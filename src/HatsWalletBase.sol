// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2, Test } from "forge-std/Test.sol"; // remove before deploy
import "./lib/HatsWalletErrors.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { LibHatsWallet, Operation } from "./lib/LibHatsWallet.sol";
import { ERC6551Account, IERC165, IERC6551Account, ERC6551AccountLib } from "tokenbound/abstract/ERC6551Account.sol";
import { BaseExecutor } from "tokenbound/abstract/execution/BaseExecutor.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";

/**
 * @title HatsWalletBase
 * @author Haberdasher Labs
 * @author spengrah
 * @notice The base contract for all HatsWallet implementations. HatsWallet is a flavor of token-bound account for Hats
 * Protocol hats.
 * @dev This contract is built with ERC6551, using the tokenbound library.
 */
abstract contract HatsWalletBase is ERC6551Account, BaseExecutor, IERC721Receiver, IERC1155Receiver {
  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /// @notice The salt used to create this HatsWallet instance
  function salt() public view returns (bytes32) {
    return ERC6551AccountLib.salt();
  }

  /// @notice The Hats Protocol hat whose wearer controls this HatsWallet
  function hat() public view returns (uint256) {
    bytes memory footer = new bytes(0x20);
    assembly {
      // copy 0x20 bytes from final word of footer
      extcodecopy(address(), add(footer, 0x20), 0x8d, 0x20)
    }
    return abi.decode(footer, (uint256));
  }

  /// @notice The address of Hats Protocol
  function HATS() public view returns (IHats) {
    bytes memory footer = new bytes(0x20);
    assembly {
      // copy 0x20 bytes from third word of footer
      extcodecopy(address(), add(footer, 0x20), 0x6d, 0x20)
    }
    return abi.decode(footer, (IHats));
  }

  /// @notice The address of this HatsWallet implementation
  function IMPLEMENTATION() public view returns (address) {
    bytes memory addr = new bytes(0x20);
    assembly {
      // copy 0x20 bytes from the middle of the bytecode
      // the implementation address starts at the 10th byte of the bytecode
      extcodecopy(address(), add(addr, 0x20), 10, 0x20)
    }
    // addr contains the implementation in its right-most bits, so we shift right 96 bits before casting to address
    return address(uint160(abi.decode(addr, (uint256)) >> 96));
  }

  /// @notice The version of this HatsWallet instance (clone)
  function version() public view returns (string memory) {
    return HatsWalletBase(payable(IMPLEMENTATION())).version_();
  }

  /*//////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  string public version_;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(string memory _version) {
    version_ = _version;
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC165
  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC6551Account, IERC165) returns (bool) {
    return (
      interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
        || super.supportsInterface(interfaceId)
    );
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ERC6551Account
  function _isValidSigner(address _signer, bytes memory /* context */ ) internal view override returns (bool) {
    return _isValidSigner(_signer);
  }

  /**
   * @dev Internal function to check if a given address is a valid signer for this HatsWallet. A signer is valid if they
   * are wearing the `hat` of this HatsWallet.
   * @param _signer The address to check
   */
  function _isValidSigner(address _signer) internal view returns (bool) {
    return HATS().isWearerOfHat(_signer, hat());
  }

  /// @inheritdoc BaseExecutor
  function _beforeExecute() internal override {
    _updateState();
  }

  /// @dev Updates the state var
  /// See tokenbound implementation
  /// https://github.com/tokenbound/contracts/blob/b7d93e00f6ea46abae253fc16c8517aa4665b9ff/src/AccountV3.sol#L259-L260
  function _updateState() internal virtual {
    uint256(keccak256(abi.encode(_state, msg.data)));
  }

  /// @inheritdoc BaseExecutor
  function _isValidExecutor(address _executor) internal view override returns (bool) {
    return _isValidSigner(_executor);
  }

  /*//////////////////////////////////////////////////////////////
                          RECEIVER FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC721Receiver
  function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }

  /// @inheritdoc IERC1155Receiver
  function onERC1155Received(address, address, uint256, uint256, bytes memory) external pure returns (bytes4) {
    return IERC1155Receiver.onERC1155Received.selector;
  }

  /// @inheritdoc IERC1155Receiver
  function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory)
    external
    pure
    returns (bytes4)
  {
    return IERC1155Receiver.onERC1155BatchReceived.selector;
  }
}
