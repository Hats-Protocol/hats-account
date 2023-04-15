// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { HatsWallet } from "./HatsWallet.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

contract HatsWalletFactory {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted if attempting to deploy a HatsWallet for a hat that already has a HatsWallet deployment
  error HatsWalletFactory_AlreadyDeployed(uint256 hatId);

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when a HatsWallet for `hatId` is deployed to address `instance`
  event HatsWalletDeployed(uint256 hatId, address instance);

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /// @notice The address of the HatsWallet implementation
  HatsWallet public immutable IMPLEMENTATION;
  /// @notice The address of the Hats Protocol contract
  IHats public immutable HATS;

  bytes internal constant emptyBytes = hex"00";

  /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /**
   * @param _implementation The address of the HatsWallet implementation
   * @param _hatsProtocol The address of the Hats Protocol contract
   */
  constructor(HatsWallet _implementation, IHats _hatsProtocol) {
    IMPLEMENTATION = _implementation;
    HATS = _hatsProtocol;
  }

  /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploys a new HatsWallet instance for a given `_hatId`
   * @param _hatId The hat for which to deploy a HatsWallet.
   * for another season. Must be <= 10,000.
   * @return _instance The address of the deployed HatsWallet instance
   */
  function createHatsWallet(uint256 _hatId) public returns (HatsWallet _instance) {
    // check if HatsWallet has already been deployed for _hatId
    if (deployed(_hatId)) revert HatsWalletFactory_AlreadyDeployed(_hatId);
    // deploy the clone to a deterministic address
    _instance = _createHatsWallet(_hatId);
    // set up the toggle with immutable values
    _instance.setUp(abi.encode(HATS, _hatId));
    // log the deployment and setUp
    emit HatsWalletDeployed(_hatId, address(_instance));
  }

  /**
   * @notice Predicts the address of a HatsWallet instance for a given hat
   * @param _hatId The hat for which to predict the HatsWallet instance address
   * @return The predicted address of the deployed instance
   */
  function getHatsWalletAddress(uint256 _hatId) public view returns (address) {
    // prepare the unique inputs
    bytes32 _salt = _calculateSalt(_hatId);
    // predict the address
    return _getHatsWalletAddress(_salt);
  }

  /**
   * @notice Checks if a HatsWallet instance has already been deployed for a given hat
   * @param _hatId The hat for which to check for an existing instance
   * @return True if an instance has already been deployed for the given hat
   */
  function deployed(uint256 _hatId) public view returns (bool) {
    // predict the address
    address instance = _getHatsWalletAddress(_calculateSalt(_hatId));
    // check for contract code at the predicted address
    return instance.code.length > 0;
  }

  /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploys a new HatsWallet contract for a given hat, to a deterministic address
   * @param _hatId The hat for which to deploy a HatsWallet
   * @return _instance The address of the deployed HatsWallet
   */
  function _createHatsWallet(uint256 _hatId) internal returns (HatsWallet _instance) {
    // calculate the determinstic address salt as the hash of the _hatId and the Hats Protocol address
    bytes32 _salt = _calculateSalt(_hatId);
    // deploy the clone to the deterministic address
    _instance = HatsWallet(payable(LibClone.cloneDeterministic(address(IMPLEMENTATION), emptyBytes, _salt)));
  }

  /**
   * @notice Predicts the address of a HatsWallet contract given the encoded arguments and salt
   * @param _salt The salt to use when deploying the clone
   * @return The predicted address of the deployed HatsWallet
   */
  function _getHatsWalletAddress(bytes32 _salt) internal view returns (address) {
    return LibClone.predictDeterministicAddress(address(IMPLEMENTATION), emptyBytes, _salt, address(this));
  }

  /**
   * @notice Calculates the salt to use when deploying the clone. The (packed) inputs are:
   *  - The address of this contract, `FACTORY`
   *  - The`_hatId`
   *  - The chain ID of the current network, to avoid confusion across networks since the same hat trees
   *    on different networks may have different wearers/admins
   * @param _hatId The hat for which to deploy a HatsWallet
   * @return The salt to use when deploying the clone
   */
  function _calculateSalt(uint256 _hatId) internal view returns (bytes32) {
    return keccak256(abi.encodePacked(address(this), _hatId, block.chainid));
  }
}
