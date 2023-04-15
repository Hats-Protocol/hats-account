// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Mech } from "foundry-mech/base/Mech.sol";
import { ImmutableStorage } from "foundry-mech/base/ImmutableStorage.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

contract HatsWallet is Mech, ImmutableStorage {
  /// @param _hatsProtocol Address of the Hats Protocol contract
  /// @param _hatId The token ID of the hat that will control this contract
  constructor(address _hatsProtocol, uint256 _hatId) {
    bytes memory initParams = abi.encode(_hatsProtocol, _hatId);
    setUp(initParams);
  }
  
  function setUp(bytes memory initParams) public override {
    require(readImmutable().length == 0, "Already initialized");
    // write params as immutables in storage
    writeImmutable(initParams);
  }

  /// @notice The address of the Hats Protocol contract
  function HATS() public view returns (IHats) {
    address _hats = abi.decode(readImmutable(), (address));
    return IHats(_hats);
  }

  /// @notice The hat Id of the hat who's wearer can use this wallet
  function hat() public view returns (uint256) {
    (, uint256 _hatId) = abi.decode(readImmutable(), (address, uint256));
    return _hatId;
  }

  /// @notice Checks if `signer` is a valid operator of this wallet, ie if they are a wearer of the {hat()}
  function isOperator(address signer) public view override returns (bool) {
    (address _hats, uint256 _hatId) = abi.decode(readImmutable(), (address, uint256));
    return IHats(_hats).isWearerOfHat(signer, _hatId);
  }
}
