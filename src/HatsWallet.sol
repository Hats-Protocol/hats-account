// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2, Test } from "forge-std/Test.sol"; // remove before deploy
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { IERC6551Account } from "erc6551/interfaces/IERC6551Account.sol";
import { IERC6551Executable } from "erc6551/interfaces/IERC6551Executable.sol";
import { ERC6551AccountLib } from "erc6551/lib/ERC6551AccountLib.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";

/*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
//////////////////////////////////////////////////////////////*/

error InvalidSigner();
error CallOnly();

contract HatsWallet is IERC165, IERC721Receiver, IERC1155Receiver, IERC6551Account, IERC6551Executable {
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

  function IMPLEMENTATION() public view returns (address) {
    bytes memory addy = new bytes(0x20);
    assembly {
      // copy 0x20 bytes from the middle of the bytecode
      // the implementation address starts at the 10th byte of the bytecode
      extcodecopy(address(), add(addy, 0x20), 10, 0x20)
    }
    // addy contains the implementation in its right-most bits, so we shift right 96 bits before casting to address
    return address(uint160(abi.decode(addy, (uint256)) >> 96));
  }

  /// @notice The version of this HatsWallet implementation
  string public version_;

  /// @notice The version of this HatsWallet instance
  function version() public view returns (string memory) {
    return HatsWallet(payable(IMPLEMENTATION())).version_();
  }

  /*///////////////////////////////////////////////////////////////
                          MUTABLE STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC6551Account
  uint256 public state;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(string memory _version) {
    version_ = _version;
  }

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
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC6551Account
  function isValidSigner(address _signer, bytes calldata) external view returns (bytes4) {
    if (_isValidSigner(_signer)) {
      return IERC6551Account.isValidSigner.selector;
    }

    return bytes4(0);
  }

  /// @dev Borrowed from https://github.com/gnosis/mech/blob/main/contracts/base/Mech.sol
  function isValidSignature(bytes32 _hash, bytes memory _signature) external view returns (bytes4 magicValue) {
    bytes32 r;
    bytes32 s;
    uint8 v;
    (v, r, s) = _splitSignature(_signature);

    if (v == 0) {
      // This is an EIP-1271 contract signature
      // The address of the contract is encoded into r
      address signingContract = address(uint160(uint256(r)));

      // The signature data to pass for validation to the contract is appended to the signature and the offset is stored
      // in s
      bytes memory contractSignature;
      // solhint-disable-next-line no-inline-assembly
      assembly {
        contractSignature := add(add(_signature, s), 0x20) // add 0x20 to skip over the length of the bytes array
      }

      // if it's our own signature, we recursively check if it's valid
      if (!_isValidSigner(signingContract) && signingContract != address(this)) {
        return bytes4(0);
      }

      return IERC1271(signingContract).isValidSignature(_hash, contractSignature);
    } else {
      // This is an ECDSA signature
      if (_isValidSigner(ECDSA.recover(_hash, v, r, s))) {
        return ERC1271_MAGIC_VALUE;
      }
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
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function _isValidSigner(address _signer) internal view returns (bool) {
    return HATS().isWearerOfHat(_signer, hat());
  }

  /**
   * @dev Divides bytes signature into `uint8 v, bytes32 r, bytes32 s`.
   * Borrowed from https://github.com/gnosis/mech/blob/main/contracts/base/Mech.sol
   * @param signature The signature bytes
   */
  function _splitSignature(bytes memory signature) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
    // The signature format is a compact form of:
    //   {bytes32 r}{bytes32 s}{uint8 v}
    // Compact means, uint8 is not padded to 32 bytes.
    // solhint-disable-next-line no-inline-assembly
    assembly {
      r := mload(add(signature, 0x20))
      s := mload(add(signature, 0x40))
      v := byte(0, mload(add(signature, 0x60)))
    }
  }

  /*//////////////////////////////////////////////////////////////
                          RECEIVER FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC6551Account
  receive() external payable { }

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
