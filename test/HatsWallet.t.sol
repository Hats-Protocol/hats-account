// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { HatsWallet } from "src/HatsWallet.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { HatsErrors } from "hats-protocol/Interfaces/HatsErrors.sol";
import { HatsWalletFactoryTest } from "test/HatsWalletFactory.t.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { Enum } from "foundry-mech/base/Mech.sol";

contract HatsWalletTest is HatsWalletFactoryTest {
  HatsWallet wallet;
  address wearer = makeAddr("wearer");
  address receiver = makeAddr("receiver");

  enum Operation {
    Call,
    DelegateCall
  }

  function setUp() public virtual override {
    super.setUp();

    // deploy a wallet for hat1
    wallet = factory.createHatsWallet(hat1);
  }

  function mockIsWearerCall(address wearer, uint256 hat, bool result) public {
    bytes memory data = abi.encodeWithSignature("isWearerOfHat(address,uint256)", wearer, hat);
    vm.mockCall(address(hats), data, abi.encode(result));
  }
}

contract IsOperator is HatsWalletTest {
  function test_isOperator() public {
    // mock the isWearerOfHat call
    mockIsWearerCall(wearer, hat1, true);
    // check that the wallet is an operator
    assertTrue(wallet.isOperator(wearer), "is operator");
  }

  function test_isNotOperator() public {
    // mock the isWearerOfHat call
    mockIsWearerCall(wearer, hat1, false);
    // check that the wallet is not an operator
    assertFalse(wallet.isOperator(wearer), "is not operator");
  }
}

contract Exec is HatsWalletTest {
  function setUp() public virtual override {
    super.setUp();
    vm.deal(address(wallet), 3 ether);
  }

  function test_wearer_canSendEth() public {
    // mock the isWearerOfHat call
    mockIsWearerCall(wearer, hat1, true);
    // wearer calls exec
    vm.prank(wearer);
    wallet.exec(receiver, 1 ether, hex"00", Enum.Operation.Call, 0);
    // check that the call was made
    assertEq(receiver.balance, 1 ether, "this balance");
    assertEq(address(wallet).balance, 2 ether, "wallet balance");
  }

  function test_nonWearer_cannotExec() public {
    // mock the isWearerOfHat call
    mockIsWearerCall(wearer, hat1, false);
    // wearer calls exec, expecting a revert
    vm.expectRevert();
    vm.prank(wearer);
    wallet.exec(receiver, 1 ether, hex"00", Enum.Operation.Call, 0);
    // check that the eth was not transferred
    assertEq(receiver.balance, 0 ether, "this balance");
    assertEq(address(wallet).balance, 3 ether, "wallet balance");
  }
}
