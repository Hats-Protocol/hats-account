// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2, StdUtils } from "forge-std/Test.sol";
import { HatsWalletBase, HatsWallet1OfN } from "src/HatsWallet1OfN.sol";
import "src/HatsWalletErrors.sol";
import { DeployImplementation } from "script/HatsWallet.s.sol";
import { IERC6551Registry } from "erc6551/interfaces/IERC6551Registry.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
  ERC721, ERC1155, TestERC721, TestERC1155, ECDSA, SignerMock, MaliciousStateChanger
} from "./utils/TestContracts.sol";
import { IMulticall3 } from "multicall/interfaces/IMulticall3.sol";

contract HatsWalletTest is DeployImplementation, Test {
  // variables inhereted from DeployImplementation
  // bytes32 public constant SALT;
  // HatsWallet1OfN public implementation;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 18_382_900;
  IERC6551Registry public REGISTRY = IERC6551Registry(0x284be69BaC8C983a749956D7320729EB24bc75f9); // block 18382829
  IHats public constant HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137); // v1.hatsprotocol.eth
  HatsWallet1OfN public instance;
  string public version = "test";

  address public org = makeAddr("org");
  address public wearer;
  uint256 public wearerKey;
  address public nonWearer;
  uint256 public nonWearerKey;
  address public eligibility = makeAddr("eligibility");
  address public toggle = makeAddr("toggle");
  uint256 public tophat;
  uint256 public hatWithWallet;
  bytes4 public constant ERC6551_MAGIC_NUMBER = HatsWalletBase.isValidSigner.selector;
  bytes4 public constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
  bytes public constant EMPTY_BYTES = hex"00";

  address payable public target = payable(makeAddr("target"));
  address public benefactor = makeAddr("benefactor");
  IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); // mainnet DAI
  ERC721 public test721;
  ERC1155 public test1155;

  function setUp() public virtual {
    // set up accounts
    (wearer, wearerKey) = makeAddrAndKey("wearer");
    (nonWearer, nonWearerKey) = makeAddrAndKey("nonWearer");

    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // deploy implementation
    DeployImplementation.prepare(false, version);
    DeployImplementation.run();

    // set up test hats
    tophat = HATS.mintTopHat(org, "tophat", "org.eth/tophat.png");
    vm.startPrank(org);
    hatWithWallet = HATS.createHat(tophat, "hatWithWallet", 10, eligibility, toggle, true, "org.eth/hatWithWallet.png");
    HATS.mintHat(hatWithWallet, wearer);
    vm.stopPrank();

    // deploy wallet instance
    instance = HatsWallet1OfN(
      payable(REGISTRY.createAccount(address(implementation), SALT, block.chainid, address(HATS), hatWithWallet))
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
    assertEq(instance.salt(), SALT);
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

contract IsValidSigner is HatsWalletTest {
  function test_true_wearer() public {
    assertEq(instance.isValidSigner(wearer, EMPTY_BYTES), ERC6551_MAGIC_NUMBER);
  }

  function test_false_nonWearer() public {
    assertEq(instance.isValidSigner(nonWearer, EMPTY_BYTES), bytes4(0));
  }
}

contract IsValidSignature is HatsWalletTest {
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

  function signWithMech(address _signerContract, string memory _message, uint256 _privateKey)
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
    (messageHash, signature) = signMessage(message, wearerKey);

    assertEq(instance.isValidSignature(messageHash, signature), ERC1271_MAGIC_VALUE);
  }

  function test_true_validSigner_contract() public {
    // console2.log("wearerContract", address(wearerContract));
    message = "I am a contract and I am wearing the hat";
    // a nonWearer EOA can ECDSA-sign a message, make it a valid sign from a wearerContract, and that will result in a
    // valid ER1271 signature
    (messageHash, signature, mechSig) = signWithMech(address(wearerContract), message, nonWearerKey);

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

    (messageHash, signature, mechSig) = signWithMech(address(wearerContract), message, nonWearerKey);

    // store the signature in the contract
    nonWearerContract.sign(message, signature);

    assertEq(instance.isValidSignature(messageHash, signature), bytes4(0));
  }
}

contract Execute is HatsWalletTest {
  bytes public data;
  IMulticall3 public multicall = IMulticall3(MULTICALL3_ADDRESS);

  function setUp() public override {
    super.setUp();

    // fund the wallet with eth
    vm.deal(address(instance), 100 ether);

    // fund the wallet with DAI
    deal(address(DAI), address(instance), 100 ether);
  }

  function test_revert_invalidSigner() public {
    vm.expectRevert(InvalidSigner.selector);

    vm.prank(nonWearer);
    instance.execute(target, 1 ether, EMPTY_BYTES, 0);

    assertEq(target.balance, 0 ether);
    assertEq(address(instance).balance, 100 ether);
  }

  function test_revert_create() public {
    vm.expectRevert(CallOrDelegatecallOnly.selector);

    vm.prank(wearer);
    instance.execute(target, 1 ether, EMPTY_BYTES, 2);

    assertEq(target.balance, 0 ether);
    assertEq(address(instance).balance, 100 ether);
  }

  function test_revert_create2() public {
    vm.expectRevert(CallOrDelegatecallOnly.selector);

    vm.prank(wearer);
    instance.execute(target, 1 ether, EMPTY_BYTES, 3);

    assertEq(target.balance, 0 ether);
    assertEq(address(instance).balance, 100 ether);
  }

  function test_call_transfer_eth() public {
    vm.prank(wearer);
    instance.execute(target, 1 ether, EMPTY_BYTES, 0);

    assertEq(target.balance, 1 ether);
    assertEq(address(instance).balance, 99 ether);
  }

  function test_call_transfer_ERC20() public {
    data = abi.encodeWithSelector(IERC20.transfer.selector, target, 1 ether);

    vm.prank(wearer);
    instance.execute(address(DAI), 0, data, 0);

    assertEq(DAI.balanceOf(target), 1 ether);
    assertEq(DAI.balanceOf(address(instance)), 99 ether);
  }

  function test_call_bubbleUpError() public {
    data = abi.encodeWithSelector(IERC20.transfer.selector, target, 200 ether);

    vm.expectRevert("Dai/insufficient-balance");

    vm.prank(wearer);
    instance.execute(address(DAI), 0, data, 0);

    assertEq(DAI.balanceOf(target), 0 ether);
    assertEq(DAI.balanceOf(address(instance)), 100 ether);
  }

  function test_delegatecall_multicall() public {
    // prepare calls
    IMulticall3.Call[] memory calls = new IMulticall3.Call[](2);
    calls[0] = IMulticall3.Call(address(DAI), abi.encodeWithSelector(IERC20.transfer.selector, target, 10 ether));
    calls[1] = IMulticall3.Call(address(DAI), abi.encodeWithSelector(IERC20.transfer.selector, target, 20 ether));

    // prepare data
    data = abi.encodeWithSelector(multicall.aggregate.selector, calls);

    // execute
    vm.prank(wearer);
    instance.execute(address(multicall), 0, data, 1);

    assertEq(DAI.balanceOf(target), 30 ether);
    assertEq(DAI.balanceOf(address(instance)), 70 ether);
  }

  function test_delegatecall_bubbleUpError() public {
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

    vm.prank(wearer);
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
    vm.expectRevert(MaliciousStateChange.selector);

    vm.prank(wearer);
    instance.execute(address(baddy), 0, data, 1);
  }
}

contract Receive is HatsWalletTest {
  function test_receive_eth() public {
    // bankroll benefactor
    vm.deal(benefactor, 100 ether);

    // send eth to wallet
    vm.prank(benefactor);
    (bool success,) = payable(address(instance)).call{ value: 1 ether }("");

    assertTrue(success);
    assertEq(address(instance).balance, 1 ether);
    assertEq(benefactor.balance, 99 ether);
  }

  function test_receive_ERC721() public {
    // deploy new TestERC721, with benefactor as recipient
    test721 = new TestERC721("Test721", "TST", benefactor);
    assertEq(test721.ownerOf(1), benefactor);

    // send ERC721 to wallet
    vm.prank(benefactor);
    test721.safeTransferFrom(benefactor, address(instance), 1);

    assertEq(test721.ownerOf(1), address(instance));
  }

  function test_receive_ERC1155_single() public {
    // deploy new TestERC1155, with benefactor as recipient
    test1155 = new TestERC1155(benefactor);

    // send a single ERC1155 to wallet
    vm.prank(benefactor);
    test1155.safeTransferFrom(benefactor, address(instance), 1, 1, "");

    assertEq(test1155.balanceOf(benefactor, 1), 99);
    assertEq(test1155.balanceOf(address(instance), 1), 1);
  }

  function test_receive_ERC1155_batch() public {
    // deploy new TestERC1155, with benefactor as recipient
    test1155 = new TestERC1155(benefactor);

    // prepare batch arrays
    uint256[] memory ids = new uint256[](2);
    ids[0] = 1;
    ids[1] = 2;
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 10;
    amounts[1] = 20;

    // send batch ERC1155 to wallet
    vm.prank(benefactor);
    test1155.safeBatchTransferFrom(benefactor, address(instance), ids, amounts, "");

    assertEq(test1155.balanceOf(benefactor, 1), 90);
    assertEq(test1155.balanceOf(benefactor, 2), 180);
    assertEq(test1155.balanceOf(address(instance), 1), 10);
    assertEq(test1155.balanceOf(address(instance), 2), 20);
  }
}
