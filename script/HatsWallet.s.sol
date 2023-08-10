// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Script, console2 } from "forge-std/Script.sol";
import { HatsWallet } from "src/HatsWallet.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

contract DeployImplementation is Script {
  HatsWallet implementation;
  bool internal verbose;
  IHats public constant HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137); // v1.hatsprotocol.eth
  //   string public version = "0.1.0"; // increment with each deploy
  bytes32 internal constant SALT = bytes32(abi.encode(0x4a75)); // ~ H(4) A(a) T(7) S(5)

  function prepare(bool _verbose, string memory _version) public {
    verbose = _verbose;
    version = _version;
  }

  function run() public {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);

    vm.startBroadcast(deployer);
    // deploy the implementation
    implementation = new HatsWallet{ salt: SALT }(address(0), 0);

    if (verbose) {
      console2.log("implementation", address(implementation));
    }
  }
  // forge script script/HatsWallet.s.sol:DeployFactory -f mainnet --broadcast --verify
}
