// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./HatsWalletErrors.sol";
import { LibExecutor, LibSandbox } from "tokenbound/lib/LibExecutor.sol";

library LibHatsWallet {
  function _execute(address _to, uint256 _value, bytes calldata _data, uint8 _operation)
    internal
    returns (bytes memory)
  {
    if (_operation == LibExecutor.OP_CALL) return LibExecutor._call(_to, _value, _data);

    if (_operation == LibExecutor.OP_DELEGATECALL) {
      /// @dev we route the delegatecall through the sandbox to protect against storage collision
      /// and selfdestruct attacks
      // derive the sandbox address
      address sandbox = LibSandbox.sandbox(address(this));
      // deploy the sandbox if it doesn't exist
      if (sandbox.code.length == 0) LibSandbox.deploy(address(this));
      // forward the call to the sandbox, which will delegatecall the `_to` address
      return LibExecutor._call(sandbox, _value, abi.encodePacked(_to, _data));
    }

    // create, create2, or other invalid _operation
    revert InvalidOperation();
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
}

struct Operation {
  address to;
  uint256 value;
  bytes data;
  uint8 operation;
}

enum ProposalStatus {
  NON_EXISTENT, // 0
  PENDING, // 1
  EXECUTED, // 2
  REJECTED // 3
}

enum Vote {
  NONE, // 0
  APPROVE, // 1
  REJECT // 2
}
