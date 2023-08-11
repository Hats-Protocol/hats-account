// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { HatsWallet } from "src/HatsWallet.sol";
import { DeployImplementation } from "script/HatsWallet.s.sol";
import { ERC6551Registry } from "erc6551/ERC6551Registry.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
// import { HatsErrors } from "hats-protocol/Interfaces/HatsErrors.sol";

contract HatsWalletTest is DeployImplementation, Test {
  // variables inhereted from DeployImplementation
  // bytes32 public constant SALT;
  // HatsWallet public implementation;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 17_671_864;
  ERC6551Registry public registry;
  IHats public constant HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137); // v1.hatsprotocol.eth
  HatsWallet public instance;
  string public version = "0.0.1";

  address public org = makeAddr("org");
  address public wearer = makeAddr("wearer");
  address public nonWearer = makeAddr("nonWearer");
  address public eligibility = makeAddr("eligibility");
  address public toggle = makeAddr("toggle");
  uint256 public tophat;
  uint256 public hatWithWallet;
  uint256 public salt = 8;
  bytes public initData;

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // deploy ERC6551 registry
    registry = new ERC6551Registry();

    // deploy implementation
    DeployImplementation.prepare(false, version);
    DeployImplementation.run();

    // set up test hats
    tophat = HATS.mintTopHat(org, "tophat", "org.eth/tophat.png");
    vm.prank(org);
    hatWithWallet = HATS.createHat(tophat, "hatWithWallet", 1, eligibility, toggle, true, "org.eth/hatWithWallet.png");

    // deploy wallet instance
    instance = HatsWallet(
      payable(
        registry.createAccount(address(implementation), block.chainid, address(HATS), hatWithWallet, salt, initData)
      )
    );
  }
}

contract Constants is HatsWalletTest {
  function test_hat() public {
    // console2.log("hat()", instance.hat());
    assertEq(instance.hat(), hatWithWallet);
  }

  function test_salt() public {
    // console2.log("salt()", instance.salt());
    assertEq(instance.salt(), salt);
  }

  function test_hats() public {
    // console2.log("HATS()", instance.HATS());
    assertEq(address(instance.HATS()), address(HATS));
  }

  function test_implementation() public {
    // console2.log("IMPLEMENTATION()", instance.IMPLEMENTATION());
    assertEq(address(instance.IMPLEMENTATION()), address(implementation));
  }

  function test_version() public {
    assertEq(implementation.version_(), version, "wrong implementation version");
    assertEq(instance.version(), version, "wrong instance version");
  }
}

contract IsValidSigner is HatsWalletTest { }

contract IsValidSignature is HatsWalletTest { }

contract Execute is HatsWalletTest { }
