// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2, StdUtils } from "forge-std/Test.sol";
import { WithForkTest } from "./Base.t.sol";
import "../src/lib/HatsWalletErrors.sol";
import { LibSandbox } from "tokenbound/lib/LibSandbox.sol";
import { MockHW } from "./utils/TestContracts.sol";
import { IMulticall3 } from "multicall/interfaces/IMulticall3.sol";

contract MockHWTest is WithForkTest {
  MockHW public mock;
  IMulticall3 public multicall = IMulticall3(MULTICALL3_ADDRESS);

  function setUp() public virtual override {
    super.setUp();
    mock = new MockHW(version);

    // bankroll the mock with some eth and DAI
    vm.deal(address(mock), 10 ether);
    deal(address(DAI), address(mock), 10 ether);
  }
}

contract _Execute is MockHWTest {
  uint8 constant OP_CALL = 0;
  uint8 constant OP_DELEGATECALL = 1;
  uint8 constant OP_CREATE = 2;
  uint8 constant OP_CREATE2 = 3;

  function test_call_transfer_ETH() public {
    // prepare call data
    address to = target;
    uint256 value = 1 ether;
    bytes memory data = EMPTY_BYTES;
    uint8 operation = OP_CALL;

    // execute call
    bytes memory results = mock.execute_(to, value, data, operation);

    // assert balances
    assertEq(address(to).balance, 1 ether);
    assertEq(address(mock).balance, 9 ether);

    // assert results
    assertEq(results, new bytes(0));
  }

  function test_call_transfer_ERC20() public {
    // prepare call data
    address to = address(DAI);
    uint256 value = 0;
    uint256 amount = 1 ether;
    bytes memory data = abi.encodeWithSelector(DAI.transfer.selector, target, amount);
    uint8 operation = OP_CALL;

    // execute call
    bytes memory results = mock.execute_(to, value, data, operation);

    // assert balances
    assertEq(DAI.balanceOf(target), 1 ether);
    assertEq(DAI.balanceOf(address(mock)), 9 ether);

    // assert results
    assertEq(results, abi.encode(true));
  }

  function test_revert_call_transfer_ERC20() public {
    // prepare call data
    address to = address(DAI);
    uint256 value = 0;
    uint256 amount = 20 ether; // too much
    bytes memory data = abi.encodeWithSelector(DAI.transfer.selector, target, amount);
    uint8 operation = OP_CALL;

    // execute call, expecting revert
    vm.expectRevert();
    mock.execute_(to, value, data, operation);
  }

  function test_delegatecall_sandboxNotDeployed() public {
    // prepare call data
    address to = target;
    uint256 value = 0;
    uint256 amount = 1 ether;
    bytes memory data;
    uint8 operation = OP_DELEGATECALL;
    // prepare calls
    IMulticall3.Call[] memory calls = new IMulticall3.Call[](1);
    calls[0] = IMulticall3.Call(
      address(mock), _encodeSandboxCall(address(DAI), 0, abi.encodeWithSelector(DAI.transfer.selector, to, amount))
    );
    // prepare data
    data = abi.encodeWithSelector(multicall.aggregate.selector, calls);

    // assert sandbox not deployed
    address sandbox = mock.getSandbox();
    assertEq(sandbox.code.length, 0, "sandbox should not be deployed");

    // execute call
    bytes memory results = mock.execute_(address(multicall), value, data, operation);

    // assert sandbox deployed
    assertGt(sandbox.code.length, 0, "sandbox should be deployed");

    // assert balances
    assertEq(DAI.balanceOf(address(target)), 1 ether);
    assertEq(DAI.balanceOf(address(mock)), 9 ether);

    // assert results length
    assertEq(results.length, 1 * 256);
  }

  function test_delegatecall_sandboxDeployed() public {
    // prepare call data
    address to = target;
    uint256 value = 0;
    uint256 amount = 1 ether;
    bytes memory data;
    uint8 operation = OP_DELEGATECALL;
    // prepare calls
    IMulticall3.Call[] memory calls = new IMulticall3.Call[](1);
    calls[0] = IMulticall3.Call(
      address(mock), _encodeSandboxCall(address(DAI), 0, abi.encodeWithSelector(DAI.transfer.selector, to, amount))
    );
    // prepare data
    data = abi.encodeWithSelector(multicall.aggregate.selector, calls);

    // deploy sandbox
    mock.deploySandbox();

    // assert sandbox deployed
    address sandbox = mock.getSandbox();
    assertGt(sandbox.code.length, 0, "sandbox should be deployed");

    // execute call
    bytes memory results = mock.execute_(address(multicall), value, data, operation);

    // assert balances
    assertEq(DAI.balanceOf(address(target)), 1 ether);
    assertEq(DAI.balanceOf(address(mock)), 9 ether);

    // assert results length
    assertEq(results.length, 1 * 256);
  }

  function test_revert_create() public {
    // prepare call data
    address to = address(0);
    uint256 value = 1 ether;
    bytes memory data = EMPTY_BYTES;
    uint8 operation = OP_CREATE;

    // execute call, expecting revert
    vm.expectRevert(InvalidOperation.selector);
    mock.execute_(to, value, data, operation);
  }

  function test_revert_create2() public {
    // prepare call data
    address to = address(0);
    uint256 value = 1 ether;
    bytes memory data = EMPTY_BYTES;
    uint8 operation = OP_CREATE2;

    // execute call, expecting revert
    vm.expectRevert(InvalidOperation.selector);
    mock.execute_(to, value, data, operation);
  }

  function test_execute_revert() public { }
}
