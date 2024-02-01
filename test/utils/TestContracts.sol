// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2 } from "forge-std/Test.sol";
import { HatsAccount1ofN } from "../../src/HatsAccount1ofN.sol";
import { HatsAccountMofN } from "../../src/HatsAccountMofN.sol";
import { LibHatsAccount, LibSandbox } from "../../src/lib/LibHatsAccount.sol";
import { HatsAccountStorage } from "../../src/lib/HatsAccountStorage.sol";
import { Operation, Vote } from "../../src/lib/LibHatsAccount.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";

contract SignerMock {
  // bytes4(keccak256("isValidSignature(bytes32,bytes)")
  bytes4 internal constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

  mapping(bytes32 => bytes) public signed;

  function sign(string calldata message, bytes calldata signature) public {
    bytes32 messageHash = ECDSA.toEthSignedMessageHash(abi.encodePacked(message));

    signed[messageHash] = signature;

    // console2.log("signed[messageHash]", vm.toString(signed[messageHash]));
  }

  function isValidSignature(bytes32 messageHash, bytes calldata signature) public view returns (bytes4) {
    // console2.log("SignerMock.isValidSignature: 1");
    if (keccak256(signed[messageHash]) == keccak256(signature)) {
      // console2.log("SignerMock.isValidSignature: 2");
      return ERC1271_MAGIC_VALUE;
    } else {
      // console2.log("SignerMock.isValidSignature: 3");
      return 0xffffffff;
    }
  }
}

contract MaliciousStateChanger is HatsAccountStorage {
  function decrementState() public {
    --_state;
  }
}

contract MockERC721 is ERC721 {
  constructor(string memory name, string memory symbol, address recipient) ERC721(name, symbol) {
    _mint(recipient, 1);
  }
}

contract MockERC1155 is ERC1155 {
  constructor(address recipient) ERC1155("") {
    _mint(recipient, 1, 100, "");
    _mint(recipient, 2, 200, "");
  }
}

contract MockHW is HatsAccount1ofN {
  constructor(string memory _version) HatsAccount1ofN(_version) { }

  /// @dev exposes the internal {LibHatsAccount._execute} function for testing
  function execute_(address _to, uint256 _value, bytes calldata _data, uint8 _operation)
    external
    payable
    returns (bytes memory result)
  {
    return LibHatsAccount._execute(_to, _value, _data, _operation);
  }

  function getSandbox() public view returns (address) {
    return LibSandbox.sandbox(address(this));
  }

  function deploySandbox() public {
    LibSandbox.deploy(address(this));
  }
}

contract MofNMock is HatsAccountMofN {
  constructor(string memory _version) HatsAccountMofN(_version) { }

  /// @dev exposes the internal {_unsafeVote} function for testing
  function unsafeVote(bytes32 _proposalId, Vote _vote) public {
    _unsafeVote(_proposalId, _vote);
  }

  /// @dev exposes the internal {_checkValidVotes} function for testing
  function checkValidVotes(bytes32 _proposalId, address[] calldata _voters, Vote _vote, uint256 _threshold)
    public
    view
    returns (bool)
  {
    _checkValidVotes(_proposalId, _voters, _vote, _threshold);

    // return true if no revert
    return true;
  }
}
