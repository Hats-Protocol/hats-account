// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2, StdUtils } from "forge-std/Test.sol";
import { HatsWalletBaseTest } from "./HatsWalletBase.t.sol";
import { HatsWalletBase, HatsWallet1ofN } from "../src/HatsWallet1ofN.sol";
import "../src/lib/HatsWalletErrors.sol";
import { Operation } from "../src/lib/LibHatsWallet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ECDSA, SignerMock, MaliciousStateChanger } from "./utils/TestContracts.sol";
import { IMulticall3 } from "multicall/interfaces/IMulticall3.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC6551Executable } from "erc6551/interfaces/IERC6551Executable.sol";
import { ISandboxExecutor } from "tokenbound/interfaces/ISandboxExecutor.sol";

contract HatsWallet1ofNTest is HatsWalletBaseTest {
  event TxExecuted(address signer);

  function setUp() public virtual override {
    super.setUp();

    // fund the wallet with eth
    vm.deal(address(instance), 100 ether);

    // fund the wallet with DAI
    deal(address(DAI), address(instance), 100 ether);
  }

  function _createSimpleOperation() internal view returns (Operation memory) {
    return Operation(target, 1 ether, EMPTY_BYTES, 0);
  }

  function _encodeSandboxCall(address to, uint256 value, bytes memory _data) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(ISandboxExecutor.extcall.selector, to, value, _data);
  }
}

contract Execute is HatsWallet1ofNTest {
  bytes public data;
  IMulticall3 public multicall = IMulticall3(MULTICALL3_ADDRESS);
  uint256 state;
  uint256 expState;

  function test_revert_implementation() public {
    // execute should revert since none if the initialization values have been set
    vm.prank(wearer1);
    vm.expectRevert();
    implementation.execute(target, 1 ether, EMPTY_BYTES, 0);

    // executeBatch should also revert for the same reason
    Operation[] memory ops = new Operation[](1);
    ops[0] = _createSimpleOperation();

    vm.prank(wearer1);
    vm.expectRevert();
    implementation.executeBatch(ops);
  }

  function test_revert_invalidSigner() public {
    state = instance.state();
    vm.expectRevert(InvalidSigner.selector);

    vm.prank(nonWearer);
    instance.execute(target, 1 ether, EMPTY_BYTES, 0);

    assertEq(target.balance, 0 ether);
    assertEq(address(instance).balance, 100 ether);
    assertEq(instance.state(), state);
  }

  function test_revert_create() public {
    state = instance.state();
    console2.log("state", state);
    vm.expectRevert(InvalidOperation.selector);

    vm.prank(wearer1);
    instance.execute(target, 1 ether, EMPTY_BYTES, 2);

    assertEq(target.balance, 0 ether);
    assertEq(address(instance).balance, 100 ether);
    assertEq(instance.state(), state);
  }

  function test_revert_create2() public {
    state = instance.state();
    vm.expectRevert(InvalidOperation.selector);

    vm.prank(wearer1);
    instance.execute(target, 1 ether, EMPTY_BYTES, 3);

    assertEq(target.balance, 0 ether);
    assertEq(address(instance).balance, 100 ether);
    assertEq(instance.state(), state);
  }

  function test_call_transfer_eth() public {
    state = instance.state();
    vm.expectEmit();
    emit TxExecuted(wearer1);
    vm.prank(wearer1);
    instance.execute(target, 1 ether, EMPTY_BYTES, 0);

    expState =
      calculateNewState(state, abi.encodeWithSelector(HatsWallet1ofN.execute.selector, target, 1 ether, EMPTY_BYTES, 0));

    assertEq(target.balance, 1 ether);
    assertEq(address(instance).balance, 99 ether);
    assertEq(instance.state(), expState);
  }

  function test_call_transfer_ERC20() public {
    state = instance.state();
    data = abi.encodeWithSelector(IERC20.transfer.selector, target, 1 ether);

    vm.expectEmit();
    emit TxExecuted(wearer1);
    vm.prank(wearer1);
    instance.execute(address(DAI), 0, data, 0);

    expState =
      calculateNewState(state, abi.encodeWithSelector(HatsWallet1ofN.execute.selector, address(DAI), 0, data, 0));

    assertEq(DAI.balanceOf(target), 1 ether);
    assertEq(DAI.balanceOf(address(instance)), 99 ether);
    assertEq(instance.state(), expState);
  }

  function test_call_bubbleUpError() public {
    state = instance.state();
    data = abi.encodeWithSelector(IERC20.transfer.selector, target, 200 ether);

    vm.expectRevert("Dai/insufficient-balance");

    vm.prank(wearer1);
    instance.execute(address(DAI), 0, data, 0);

    assertEq(DAI.balanceOf(target), 0 ether);
    assertEq(DAI.balanceOf(address(instance)), 100 ether);
    assertEq(instance.state(), state);
  }

  function test_delegatecall_multicall() public {
    state = instance.state();
    // prepare calls
    IMulticall3.Call[] memory calls = new IMulticall3.Call[](2);
    calls[0] = IMulticall3.Call(
      address(instance),
      _encodeSandboxCall(address(DAI), 0, abi.encodeWithSelector(IERC20.transfer.selector, target, 10 ether))
    );
    calls[1] = IMulticall3.Call(
      address(instance),
      _encodeSandboxCall(address(DAI), 0, abi.encodeWithSelector(IERC20.transfer.selector, target, 20 ether))
    );

    // prepare data
    data = abi.encodeWithSelector(multicall.aggregate.selector, calls);

    // execute, expecting an event
    vm.expectEmit();
    emit TxExecuted(wearer1);
    vm.prank(wearer1);
    instance.execute(address(multicall), 0, data, 1);

    expState =
      calculateNewState(state, abi.encodeWithSelector(HatsWallet1ofN.execute.selector, address(multicall), 0, data, 1));

    assertEq(DAI.balanceOf(target), 30 ether);
    assertEq(DAI.balanceOf(address(instance)), 70 ether);
    assertEq(instance.state(), expState);
  }

  function test_revert_delegatecall_bubbleUpError() public {
    state = instance.state();
    // prepare calls
    IMulticall3.Call[] memory calls = new IMulticall3.Call[](2);
    calls[0] = IMulticall3.Call(
      address(instance),
      _encodeSandboxCall(address(DAI), 0, abi.encodeWithSelector(IERC20.transfer.selector, target, 10 ether))
    );
    // this next call should fail
    calls[1] = IMulticall3.Call(
      address(instance),
      _encodeSandboxCall(address(DAI), 0, abi.encodeWithSelector(IERC20.transfer.selector, target, 100 ether))
    );

    // prepare data
    data = abi.encodeWithSelector(multicall.aggregate.selector, calls);

    // execute, expecting a revert
    // Multicall3 does not bubble up errors from its aggregated calls, so we expect the error from Multicall3 itself
    vm.expectRevert("Multicall3: call failed");

    vm.prank(wearer1);
    instance.execute(address(multicall), 0, data, 1);

    assertEq(DAI.balanceOf(target), 0 ether);
    assertEq(DAI.balanceOf(address(instance)), 100 ether);
    assertEq(instance.state(), state);
  }

  function test_revert_delegatecall_maliciousStateChange() public {
    state = instance.state();
    // set up the malicious contract
    MaliciousStateChanger baddy = new MaliciousStateChanger();
    // prepare calldata
    data = abi.encodeWithSelector(MaliciousStateChanger.decrementState.selector);

    // execute, expecting a revert
    vm.expectRevert();

    vm.prank(wearer1);
    instance.execute(address(baddy), 0, data, 1);
    assertEq(instance.state(), expState);
  }
}

contract ExecuteBatch is HatsWallet1ofNTest {
  uint256 state;
  uint256 expState;
  // one operation

  function test_singleOperation() public {
    state = instance.state();
    Operation[] memory ops = new Operation[](1);
    ops[0] = _createSimpleOperation();

    vm.expectEmit();
    emit TxExecuted(wearer1);
    vm.prank(wearer1);
    instance.executeBatch(ops);

    expState = calculateNewState(state, abi.encodeWithSelector(HatsWallet1ofN.executeBatch.selector, ops));

    // check that the operation effects were applied
    assertEq(target.balance, 1 ether);
    assertEq(address(instance).balance, 99 ether);
    assertEq(instance.state(), expState);
  }
  // n operations

  function test_multipleOperations(uint256 n) public {
    // bound n to realistic values
    n = bound(n, 1, 40);

    state = instance.state();

    Operation[] memory ops = new Operation[](n);
    for (uint256 i = 0; i < n; i++) {
      ops[i] = _createSimpleOperation();
    }

    vm.expectEmit();
    emit TxExecuted(wearer1);
    vm.prank(wearer1);
    instance.executeBatch(ops);

    expState = calculateNewState(state, abi.encodeWithSelector(HatsWallet1ofN.executeBatch.selector, ops));

    // check that the operation effects were applied
    assertEq(target.balance, n * 1 ether);
    assertEq(address(instance).balance, (100 - n) * 1 ether);
    assertEq(instance.state(), expState);
  }

  function test_revert_invalidSigner() public {
    state = instance.state();
    Operation[] memory ops = new Operation[](1);
    ops[0] = _createSimpleOperation();

    vm.expectRevert(InvalidSigner.selector);

    vm.prank(nonWearer);
    instance.executeBatch(ops);

    assertEq(target.balance, 0 ether);
    assertEq(address(instance).balance, 100 ether);
    assertEq(instance.state(), state);
  }
}

contract IsValidSignature is HatsWallet1ofNTest {
  SignerMock public wearerContract;
  SignerMock public nonWearerContract;

  string public message;
  bytes32 public messageHash;
  bytes public signature;
  bytes public mechSig;
  bytes32 public r;
  bytes32 public s;
  uint8 public v;

  function combineSig(bytes32 _r, bytes32 _s, uint8 _v) public pure returns (bytes memory) {
    return abi.encodePacked(_r, _s, _v);
  }

  function signMessage(string memory _message, uint256 _privateKey)
    public
    pure
    returns (bytes32 _messageHash, bytes memory _signature)
  {
    uint8 _v;
    bytes32 _r;
    bytes32 _s;
    _messageHash = ECDSA.toEthSignedMessageHash(abi.encodePacked(_message));
    (_v, _r, _s) = vm.sign(_privateKey, _messageHash);
    _signature = combineSig(_r, _s, _v);
  }

  function signWithContract(address _signerContract, string memory _message, uint256 _privateKey)
    public
    pure
    returns (bytes32 _messageHash, bytes memory _signature, bytes memory _mechSig)
  {
    uint8 _v;
    bytes32 _r;
    bytes32 _s;
    bytes32 _sigLength;
    _messageHash = ECDSA.toEthSignedMessageHash(abi.encodePacked(_message));
    (_v, _r, _s) = vm.sign(_privateKey, _messageHash);
    _signature = combineSig(_r, _s, _v);
    // console2.log("sig", vm.toString(_signature));
    _sigLength = bytes32(_signature.length);
    _mechSig = abi.encodePacked(
      bytes32(uint256(uint160(_signerContract))), bytes32(abi.encode(65)), uint8(0), _sigLength, _signature
    );
  }

  function setUp() public override {
    super.setUp();

    wearerContract = new SignerMock();
    nonWearerContract = new SignerMock();

    vm.prank(org);
    HATS.mintHat(hatWithWallet, address(wearerContract));
  }

  function test_true_validSigner_EOA() public {
    message = "I am an EOA and I am wearing the hat";
    (messageHash, signature) = signMessage(message, wearer1Key);

    assertEq(instance.isValidSignature(messageHash, signature), ERC1271_MAGIC_VALUE);
  }

  function test_true_validSigner_contract() public {
    // console2.log("wearerContract", address(wearerContract));
    message = "I am a contract and I am wearing the hat";
    // a nonWearer EOA can ECDSA-sign a message, make it a valid signature from a wearerContract, and that will result
    // in a valid ER1271 signature
    (messageHash, signature, mechSig) = signWithContract(address(wearerContract), message, nonWearerKey);

    // store the signature in the contract
    wearerContract.sign(message, signature);

    assertEq(instance.isValidSignature(messageHash, mechSig), ERC1271_MAGIC_VALUE);
  }

  function test_false_invalidSigner_EOA() public {
    message = "I am an EOA and I am NOT wearing the hat";
    (messageHash, signature) = signMessage(message, nonWearerKey);

    assertEq(instance.isValidSignature(messageHash, signature), bytes4(0));
  }

  function test_false_invalidSigner_contract() public {
    message = "I am a contract and I am NOT wearing the hat";

    (messageHash, signature) = signMessage(message, nonWearerKey);

    (messageHash, signature, mechSig) = signWithContract(address(wearerContract), message, nonWearerKey);

    // store the signature in the contract
    nonWearerContract.sign(message, signature);

    assertEq(instance.isValidSignature(messageHash, signature), bytes4(0));
  }
}

contract ERC165 is HatsWallet1ofNTest {
  function test_true_IERC6551Executable() public {
    assertTrue(instance.supportsInterface(type(IERC6551Executable).interfaceId));
    assertTrue(instance.supportsInterface(0x51945447));
  }

  function test_true_ERC1271() public {
    assertTrue(instance.supportsInterface(type(IERC1271).interfaceId));
  }
}
