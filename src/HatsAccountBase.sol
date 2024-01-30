// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2, Test } from "forge-std/Test.sol"; // remove before deploy
import "./lib/HatsAccountErrors.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { LibHatsAccount, Operation } from "./lib/LibHatsAccount.sol";
import { ERC6551Account, IERC165, IERC6551Account, ERC6551AccountLib } from "tokenbound/abstract/ERC6551Account.sol";
import { BaseExecutor } from "tokenbound/abstract/execution/BaseExecutor.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";

/**
 * @title HatsAccountBase
 * @author Haberdasher Labs
 * @author spengrah
 * @notice The base contract for all HatsAccount implementations. As an abstract contract, this contract will only work
 * when inherited by a full implementation of HatsAccount. HatsAccount is a flavor of ERC6551-compatible token-bound
 * account for Hats Protocol hats.
 * @dev This contract implements ERC6551 with the use of the tokenbound library.
 */
abstract contract HatsAccountBase is ERC6551Account, BaseExecutor, IERC721Receiver, IERC1155Receiver {
  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /// @notice EIP-712 domain separator typehash for this contract
  bytes32 internal constant DOMAIN_SEPARATOR_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  /// @notice EIP-712 message typehash for this contract
  bytes32 internal constant HatsAccount_MSG_TYPEHASH = keccak256("HatsAccount(bytes message)");

  /// @notice The salt used to create this HatsAccount instance
  function salt() public view returns (bytes32) {
    return ERC6551AccountLib.salt();
  }

  /// @notice The Hats Protocol hat whose wearer controls this HatsAccount
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

  /// @notice The address of this HatsAccount implementation
  function IMPLEMENTATION() public view returns (address) {
    return ERC6551AccountLib.implementation();
  }

  /// @notice The version of the HatsAccount implementation contract
  /// @dev Will return an empty string when called on a HatsAccount instance (clone)
  function version_() public view returns (string memory) {
    return _version;
  }

  /// @notice The version of this HatsAccount instance (clone)
  function version() public view returns (string memory) {
    return HatsAccountBase(payable(IMPLEMENTATION())).version_();
  }

  /*//////////////////////////////////////////////////////////////
                        NON-CONSTANT STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @dev The version of this HatsAccount implementation contract. Must be set in the constructor of the inheriting
  /// contract. Will be empty for HatsAccount instances (clones).
  string internal _version;

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Generates an EIP712-compatible hash of a message, eg for use as an EIP1271 contract signature
   * @param _message Arbitrary-length message data to hash
   * @return messageHash EIP712-compatible hash of the message
   */
  function getMessageHash(bytes calldata _message) public view virtual returns (bytes32 messageHash) {
    return keccak256(
      abi.encodePacked(
        bytes1(0x19),
        bytes1(0x01),
        domainSeparator(),
        keccak256(abi.encode(HatsAccount_MSG_TYPEHASH, keccak256(_message))) // HatsAccountMessageHash
      )
    );
  }

  /**
   * @dev Returns the domain separator for this contract, as defined in the EIP-712 standard.
   * @return bytes32 The domain separator hash.
   */
  function domainSeparator() public view virtual returns (bytes32) { }

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
  /// @dev HatsAccount signer validation does not require additional context data
  function _isValidSigner(address _signer, bytes memory /* context */ ) internal view override returns (bool) {
    return _isValidSigner(_signer);
  }

  /**
   * @dev Internal function to check if a given address is a valid signer for this HatsAccount. A signer is valid if and
   * only if they are wearing the `hat` of this HatsAccount instance.
   * @param _signer The address to check
   */
  function _isValidSigner(address _signer) internal view returns (bool) {
    return HATS().isWearerOfHat(_signer, hat());
  }

  /// @inheritdoc BaseExecutor
  function _beforeExecute() internal virtual override {
    _updateState();
  }

  /// @dev Updates the state var
  /// See tokenbound implementation
  /// https://github.com/tokenbound/contracts/blob/b7d93e00f6ea46abae253fc16c8517aa4665b9ff/src/AccountV3.sol#L259-L260
  function _updateState() internal virtual {
    _state = uint256(keccak256(abi.encode(_state, msg.data)));
  }

  /// @inheritdoc BaseExecutor
  function _isValidExecutor(address _executor) internal view virtual override returns (bool) {
    // return _isValidSigner(_executor);
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
