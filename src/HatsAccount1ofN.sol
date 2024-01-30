// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2, Test } from "forge-std/Test.sol"; // comment out before deploy
import "./lib/HatsAccountErrors.sol";
import { HatsAccountBase } from "./HatsAccountBase.sol";
import { LibHatsAccount, Operation } from "./lib/LibHatsAccount.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { IERC6551Executable } from "erc6551/interfaces/IERC6551Executable.sol";

/**
 * @title HatsAccount1ofN
 * @author Haberdasher Labs
 * @author spengrah
 * @notice A HatsAccount implementation that requires a single signature from a valid signer — ie a single wearer of
 * the hat — to execute a transaction. It supports execution of single operations, batch operations, and EIP-1271
 * contract signatures.
 */
contract HatsAccount1ofN is HatsAccountBase, IERC6551Executable {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when a transaction is executed. Enables tracking of which signer executed a transaction.
  event TxExecuted(address signer);

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(string memory version) {
    // set the implementation version
    _version = version;
  }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @inheritdoc IERC6551Executable
   * @param _operation The operation to execute. Only call and delegatecall are supported. Delegatecalls are routed
   * through the sandbox.
   */
  function execute(address _to, uint256 _value, bytes calldata _data, uint8 _operation)
    external
    payable
    returns (bytes memory result)
  {
    if (!_isValidSigner(msg.sender)) revert InvalidSigner();

    // increment the state var
    _beforeExecute();

    // execute the call, routing delegatecalls through the sandbox, and bubble up the result
    result = LibHatsAccount._execute(_to, _value, _data, _operation);

    // log the executor
    emit TxExecuted(msg.sender);
  }

  /**
   * @notice Executes a batch of operations. Must be called by a valid signer.
   * @param operations The operations to execute. Only call and delegatecall are supported. Delegatecalls are routed
   * through the sandbox.
   * @return results The results of each operation
   */
  function executeBatch(Operation[] calldata operations) external payable returns (bytes[] memory) {
    if (!_isValidSigner(msg.sender)) revert InvalidSigner();

    // increment the state var
    _beforeExecute();

    uint256 length = operations.length;
    bytes[] memory results = new bytes[](length);

    for (uint256 i; i < length; ++i) {
      /// @dev compile with solc ^0.8.23 to use unchecked incremenation
      // execute the call, routing delegatecalls through the sandbox, and bubble up the result
      results[i] =
        LibHatsAccount._execute(operations[i].to, operations[i].value, operations[i].data, operations[i].operation);
    }

    // log the executor
    emit TxExecuted(msg.sender);

    return results;
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Checks whether the signature provided is valid for the provided hash, complies with EIP-1271. A signature
   * is valid if either:
   *  - It's a valid ECDSA signature by a valid HatsAccount signer
   *  - It's a valid EIP-1271 signature by a valid HatsAccount signer
   * @dev Implementation borrowed from https://github.com/gnosis/mech/blob/main/contracts/base/Mech.sol
   * @param _hash Hash of the data (could be either a message hash or transaction hash)
   * @param _signature Signature to validate. Can be an EIP-1271 contract signature (identified by v=0) or an ECDSA
   * signature
   */
  function _isValidSignature(bytes32 _hash, bytes calldata _signature) internal view override returns (bool) {
    bytes memory signature = _signature; //
    bytes32 r;
    bytes32 s;
    uint8 v;
    (v, r, s) = LibHatsAccount._splitSignature(signature);

    if (v == 0) {
      // This is an EIP-1271 contract signature
      // The address of the contract is encoded into r
      address signingContract = address(uint160(uint256(r)));

      // The signature data to pass for validation to the contract is appended to the signature and the offset is stored
      // in s
      bytes memory contractSignature;
      // solhint-disable-next-line no-inline-assembly
      assembly {
        contractSignature := add(add(signature, s), 0x20) // add 0x20 to skip over the length of the bytes array
      }

      // If the contract is a valid signer, we defer to its implementation of EIP-1271
      if (_isValidSigner(signingContract)) {
        return
          IERC1271(signingContract).isValidSignature(_hash, contractSignature) == IERC1271.isValidSignature.selector;
      }
    } else {
      // This is an ECDSA signature
      if (_isValidSigner(ECDSA.recover(_hash, v, r, s))) {
        return true;
      }
    }

    return false;
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsAccountBase
  function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
    return (
      interfaceId == type(IERC6551Executable).interfaceId || interfaceId == type(IERC1271).interfaceId
        || super.supportsInterface(interfaceId)
    );
  }
}
