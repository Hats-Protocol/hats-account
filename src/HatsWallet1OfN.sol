// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2, Test } from "forge-std/Test.sol"; // remove before deploy
import "./HatsWalletErrors.sol";
import { HatsWalletBase } from "./HatsWalletBase.sol";
import { IERC6551Executable } from "erc6551/interfaces/IERC6551Executable.sol";

// TODO natspec
contract HatsWallet1OfN is HatsWalletBase, IERC6551Executable {
  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /*///////////////////////////////////////////////////////////////
                          MUTABLE STORAGE
  //////////////////////////////////////////////////////////////*/

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(string memory _version) HatsWalletBase(_version) { }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC6551Executable
  function execute(address _to, uint256 _value, bytes calldata _data, uint8 _operation)
    external
    payable
    returns (bytes memory result)
  {
    if (!_isValidSigner(msg.sender)) revert InvalidSigner();

    // increment the state var
    ++state;

    bool success;

    if (_operation == 0) {
      // call
      (success, result) = _to.call{ value: _value }(_data);
    } else if (_operation == 1) {
      // delegatecall

      // cache the pre-image of the state var
      uint256 _state = state;

      // execute the delegatecall
      (success, result) = _to.delegatecall(_data);

      if (_state != state) {
        // a delegatecall has maliciously changed the state, so we revert
        revert MaliciousStateChange();
      }
    } else {
      // create, create2, or invalid _operation
      revert CallOrDelegatecallOnly();
    }

    // bubble up revert error data
    if (!success) {
      assembly {
        revert(add(result, 32), mload(result))
      }
    }
  }

  // TODO batchExecute

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsWalletBase
  function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
    return (super.supportsInterface(interfaceId) || interfaceId == type(IERC6551Executable).interfaceId);
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/
}
