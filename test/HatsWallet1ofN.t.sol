// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2, StdUtils } from "forge-std/Test.sol";
import { HatsWalletBaseTest } from "./HatsWalletBase.t.sol";
import { HatsWalletBase, HatsWallet1ofN } from "../src/HatsWallet1ofN.sol";
import "../src/lib/HatsWalletErrors.sol";
import { Operation } from "../src/lib/LibHatsWallet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MaliciousStateChanger } from "./utils/TestContracts.sol";
import { IMulticall3 } from "multicall/interfaces/IMulticall3.sol";

contract HatsWallet1ofNTest is HatsWalletBaseTest { }

contract Execute is HatsWallet1ofNTest {
  bytes public data;
  IMulticall3 public multicall = IMulticall3(MULTICALL3_ADDRESS);

  function setUp() public override {
    super.setUp();

    // fund the wallet with eth
    vm.deal(address(instance), 100 ether);

    // fund the wallet with DAI
    deal(address(DAI), address(instance), 100 ether);
  }

  function test_revert_implementation() public {
    // execute should revert since none if the initialization values have been set
    vm.prank(wearer1);
    vm.expectRevert();
    implementation.execute(target, 1 ether, EMPTY_BYTES, 0);

    // executeBatch should also revert for the same reason
    Operation[] memory ops = new Operation[](1);
    ops[0] = Operation(target, 1 ether, EMPTY_BYTES, 0);

    vm.prank(wearer1);
    vm.expectRevert();
    implementation.executeBatch(ops);
  }

  function test_revert_invalidSigner() public {
    vm.expectRevert(InvalidSigner.selector);

    vm.prank(nonWearer);
    instance.execute(target, 1 ether, EMPTY_BYTES, 0);

    assertEq(target.balance, 0 ether);
    assertEq(address(instance).balance, 100 ether);
  }

  function test_revert_create() public {
    vm.expectRevert(InvalidOperation.selector);

    vm.prank(wearer1);
    instance.execute(target, 1 ether, EMPTY_BYTES, 2);

    assertEq(target.balance, 0 ether);
    assertEq(address(instance).balance, 100 ether);
  }

  function test_revert_create2() public {
    vm.expectRevert(InvalidOperation.selector);

    vm.prank(wearer1);
    instance.execute(target, 1 ether, EMPTY_BYTES, 3);

    assertEq(target.balance, 0 ether);
    assertEq(address(instance).balance, 100 ether);
  }

  function test_call_transfer_eth() public {
    vm.prank(wearer1);
    instance.execute(target, 1 ether, EMPTY_BYTES, 0);

    assertEq(target.balance, 1 ether);
    assertEq(address(instance).balance, 99 ether);
  }

  function test_call_transfer_ERC20() public {
    data = abi.encodeWithSelector(IERC20.transfer.selector, target, 1 ether);

    vm.prank(wearer1);
    instance.execute(address(DAI), 0, data, 0);

    assertEq(DAI.balanceOf(target), 1 ether);
    assertEq(DAI.balanceOf(address(instance)), 99 ether);
  }

  function test_call_bubbleUpError() public {
    data = abi.encodeWithSelector(IERC20.transfer.selector, target, 200 ether);

    vm.expectRevert("Dai/insufficient-balance");

    vm.prank(wearer1);
    instance.execute(address(DAI), 0, data, 0);

    assertEq(DAI.balanceOf(target), 0 ether);
    assertEq(DAI.balanceOf(address(instance)), 100 ether);
  }

  // TODO fix this test for the sandbox
  function delegatecall_multicall() public {
    // prepare calls
    IMulticall3.Call[] memory calls = new IMulticall3.Call[](2);
    calls[0] = IMulticall3.Call(address(DAI), abi.encodeWithSelector(IERC20.transfer.selector, target, 10 ether));
    calls[1] = IMulticall3.Call(address(DAI), abi.encodeWithSelector(IERC20.transfer.selector, target, 20 ether));

    // prepare data
    data = abi.encodeWithSelector(multicall.aggregate.selector, calls);

    // execute
    vm.prank(wearer1);
    instance.execute(address(multicall), 0, data, 1);

    assertEq(DAI.balanceOf(target), 30 ether);
    assertEq(DAI.balanceOf(address(instance)), 70 ether);
  }

  // TODO fix this test for the sandbox
  function delegatecall_bubbleUpError() public {
    // prepare calls
    IMulticall3.Call[] memory calls = new IMulticall3.Call[](2);
    calls[0] = IMulticall3.Call(address(DAI), abi.encodeWithSelector(IERC20.transfer.selector, target, 10 ether));
    // this next call should fail
    calls[1] = IMulticall3.Call(address(DAI), abi.encodeWithSelector(IERC20.transfer.selector, target, 100 ether));

    // prepare data
    data = abi.encodeWithSelector(multicall.aggregate.selector, calls);

    // execute, expecting a revert
    // Multicall3 does not bubble up errors from its aggregated calls, so we expect the error from Multicall3 itself
    vm.expectRevert("Multicall3: call failed");

    vm.prank(wearer1);
    instance.execute(address(multicall), 0, data, 1);

    assertEq(DAI.balanceOf(target), 0 ether);
    assertEq(DAI.balanceOf(address(instance)), 100 ether);
  }

  function test_revert_delegatecall_maliciousStateChange() public {
    // set up the malicious contract
    MaliciousStateChanger baddy = new MaliciousStateChanger();
    // prepare calldata
    data = abi.encodeWithSelector(MaliciousStateChanger.decrementState.selector);

    // execute, expecting a revert
    vm.expectRevert();

    vm.prank(wearer1);
    instance.execute(address(baddy), 0, data, 1);
  }
}

// TODO
contract ExecuteBatch is HatsWallet1ofNTest { }

// TODO
contract ERC165 is HatsWallet1ofNTest { }
