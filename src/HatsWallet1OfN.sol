// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2, Test } from "forge-std/Test.sol"; // remove before deploy
import "./lib/HatsWalletErrors.sol";
import { HatsWalletBase } from "./HatsWalletBase.sol";
import { LibHatsWallet, Operation } from "./lib/LibHatsWallet.sol";
import { IERC6551Executable } from "erc6551/interfaces/IERC6551Executable.sol";

// TODO natspec
contract HatsWallet1ofN is HatsWalletBase, IERC6551Executable {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event TxExecuted(address signer);

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(string memory _version) HatsWalletBase(_version) { }

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

    // execute the call
    result = LibHatsWallet._execute(_to, _value, _data, _operation);

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

    for (uint256 i = 0; i < length; i++) {
      results[i] =
        LibHatsWallet._execute(operations[i].to, operations[i].value, operations[i].data, operations[i].operation);
    }

    emit TxExecuted(msg.sender);

    return results;
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsWalletBase
  function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
    return (interfaceId == type(IERC6551Executable).interfaceId || super.supportsInterface(interfaceId));
  }
}
