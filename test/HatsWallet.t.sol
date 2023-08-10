// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { HatsWallet } from "src/HatsWallet.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { HatsErrors } from "hats-protocol/Interfaces/HatsErrors.sol";

contract HatsWalletTest is Test {
  HatsWallet wallet;
  address wearer = makeAddr("wearer");
  address receiver = makeAddr("receiver");

  function setUp() public virtual override {
    super.setUp();
  }

  function mockIsWearerCall(address wearer, uint256 hat, bool result) public {
    bytes memory data = abi.encodeWithSignature("isWearerOfHat(address,uint256)", wearer, hat);
    vm.mockCall(address(hats), data, abi.encode(result));
  }
}

contract Exec is HatsWalletTest {
  function setUp() public virtual override {
    super.setUp();
    vm.deal(address(wallet), 3 ether);
  }

  function test_wearer_canSendEth() public { }

  function test_nonWearer_cannotExec() public { }
}
