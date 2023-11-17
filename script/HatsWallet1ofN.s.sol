// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Script, console2 } from "forge-std/Script.sol";
import { HatsWallet1ofN } from "src/HatsWallet1ofN.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { IERC6551Registry } from "erc6551/interfaces/IERC6551Registry.sol";

contract DeployImplementation is Script {
  HatsWallet1ofN public implementation;
  bool private _verbose = true;
  string private _version = "test1";

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
    implementation = new HatsWallet1ofN{ salt: SALT }(_version);

    vm.stopBroadcast();

    if (_verbose) {
      console2.log("implementation", address(implementation));
    }
  }
  // forge script script/HatsWallet.s.sol:DeployImplementation -f mainnet --broadcast --verify

  /*
  forge verify-contract --chain-id 5 --num-of-optimizations 1000000 --watch --constructor-args $(cast abi-encode \
  "constructor(string)" "test1" ) \ 
  --compiler-version v0.8.21 0xEA95A8Da1746897343c56f5468489a36BbC5e0Bc \
  src/HatsWallet1ofN.sol:HatsWallet1ofN --etherscan-api-key $ETHERSCAN_KEY
  */
}

contract DeployWallet is Script {
  // default values
  address public implementation = 0xEA95A8Da1746897343c56f5468489a36BbC5e0Bc;
  address public wallet;
  IERC6551Registry public constant REGISTRY = IERC6551Registry(0x000000006551c19487814612e58FE06813775758);
  address public constant HATS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;
  uint256 public hatId = 1_806_318_072_216_204_486_700_476_831_445_223_038_727_298_188_772_612_676_873_928_440_807_424;
  bytes32 public salt = bytes32(abi.encode(0x4a75));
  bool internal verbose = true;

  /// @dev Overrides default values
  function prepare(bool _verbose, address _implementation, uint256 _hat, bytes32 _salt) public {
    verbose = _verbose;
    implementation = _implementation;
    hatId = _hat;
    salt = _salt;
  }

  function run() public returns (address) {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);

    console2.log("implementation", implementation);

    vm.startBroadcast(deployer);

    wallet = REGISTRY.createAccount(implementation, salt, block.chainid, HATS, hatId);

    vm.stopBroadcast();

    if (verbose) {
      console2.log("wallet", wallet);
    }

    return wallet;
  }

  // forge script script/HatsWallet.s.sol:DeployWallet -f goerli
}
