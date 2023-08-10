// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console2, Test } from "forge-std/Test.sol"; // remove before deploy
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { IERC6551Account } from "erc6551/interfaces/IERC6551Account.sol";
import { IERC6551Executable } from "erc6551/interfaces/IERC6551Executable.sol";
import { ERC6551AccountLib } from "erc6551/lib/ERC6551AccountLib.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";

contract HatsWallet is Test, IERC165, IERC6551Account, IERC6551Executable {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  error InvalidSigner();
  error CallOnly();

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`
  bytes4 internal constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

  /// @inheritdoc IERC6551Account
  function token() external view returns (uint256 chainId, address tokenContract, uint256 tokenId) {
    return ERC6551AccountLib.token();
  }

  function salt() public view returns (uint256) {
    return ERC6551AccountLib.salt();
  }

  function hat() public view returns (uint256) {
    bytes memory footer = new bytes(0x20);
    assembly {
      // copy 0x20 bytes from final word of footer
      extcodecopy(address(), add(footer, 0x20), 0x8d, 0x20)
    }
    return abi.decode(footer, (uint256));
  }

  function HATS() public view returns (IHats) {
    bytes memory footer = new bytes(0x20);
    assembly {
      // copy 0x20 bytes from third word of footer
      extcodecopy(address(), add(footer, 0x20), 0x6d, 0x20)
    }
    return abi.decode(footer, (IHats));
  }

  // function IMPLEMENTATION() public view returns (address) {
  //   bytes memory footer = new bytes(0x20);
  //   assembly {
  //     // TODO figure out how to grab the implementation address from the middle of the bytecode
  //     extcodecopy(address(), add(footer, 0x20), 45, 0x20)
  //   }
  //   return abi.decode(footer, (address));
  // }

  /*///////////////////////////////////////////////////////////////
                          MUTABLE STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC6551Account
  uint256 public state;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  // constructor() { }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC6551Executable
  function execute(address _to, uint256 _value, bytes calldata _data, uint256 _operation)
    external
    payable
    returns (bytes memory result)
  {
    if (!_isValidSigner(msg.sender)) revert InvalidSigner();
    if (_operation != 0) revert CallOnly(); // TODO should we allow delegatecalls?

    // increment the state var
    ++state; // TODO is it safe to do this unchecked?

    bool success;
    (success, result) = _to.call{ value: _value }(_data);

    // bubble up revert error data
    if (!success) {
      assembly {
        revert(add(result, 32), mload(result))
      }
    }
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function _isValidSigner(address _signer) internal view returns (bool) {
    return HATS().isWearerOfHat(_signer, hat());
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC6551Account
  function isValidSigner(address _signer, bytes calldata) external view returns (bytes4) {
    if (_isValidSigner(_signer)) {
      return IERC6551Account.isValidSigner.selector;
    }

    return bytes4(0);
  }

  function isValidSignature(bytes32 _hash, bytes memory _signature) external view returns (bytes4 magicValue) {
    // TODO implement Mech-style recursion to support contract signatures
    address signer = ECDSA.recover(_hash, _signature);

    if (_isValidSigner(signer)) {
      return ERC1271_MAGIC_VALUE;
    }

    return bytes4(0);
  }

  /// @inheritdoc IERC165
  function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
    return (
      interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC6551Account).interfaceId
        || interfaceId == type(IERC6551Executable).interfaceId
    );
  }

  /*//////////////////////////////////////////////////////////////
                          FALLBACK FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC6551Account
  receive() external payable { }
}
