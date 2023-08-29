// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Script, console2 } from "forge-std/Script.sol";
import { HatsWallet } from "src/HatsWallet.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

contract DeployImplementation is Script {
  HatsWallet public implementation;
  bool private _verbose;
  string private _version;

  //   string public version = "0.1.0"; // increment with each deploy
  bytes32 public constant SALT = bytes32(abi.encode(0x4a75)); // ~ H(4) A(a) T(7) S(5)

  function prepare(bool verbose_, string memory version_) public {
    _verbose = verbose_;
    _version = version_;
  }

  function run() public {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);

    vm.startBroadcast(deployer);
    // deploy the implementation
    implementation = new HatsWallet{ salt: SALT }(_version);

    vm.stopBroadcast();

    if (_verbose) {
      console2.log("implementation", address(implementation));
    }
  }
  // forge script script/HatsWallet.s.sol:DeployFactory -f mainnet --broadcast --verify
}
