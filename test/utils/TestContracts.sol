// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2 } from "forge-std/Test.sol";
import { HatsWalletMofN } from "../../src/HatsWalletMofN.sol";
import { HatsWalletStorage } from "../../src/lib/HatsWalletStorage.sol";
import { Operation } from "../../src/lib/LibHatsWallet.sol";
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

contract MaliciousStateChanger is HatsWalletStorage {
  function decrementState() public {
    --_state;
  }
}

contract TestERC721 is ERC721 {
  constructor(string memory name, string memory symbol, address recipient) ERC721(name, symbol) {
    _mint(recipient, 1);
  }
}

contract TestERC1155 is ERC1155 {
  constructor(address recipient) ERC1155("") {
    _mint(recipient, 1, 100, "");
    _mint(recipient, 2, 200, "");
  }
}

contract MofNMock is HatsWalletMofN {
  constructor(string memory _version) HatsWalletMofN(_version) {

   }

  /// @dev exposes the internal {_propose} function
  function proposeInternal(Operation[] calldata _operations, bytes32 _descriptionHash, bytes32 _proposalHash) public {
    _propose(_operations, _descriptionHash, _proposalHash);
  }
}
