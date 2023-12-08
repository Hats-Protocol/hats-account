// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2, StdUtils } from "forge-std/Test.sol";
import { BaseTest, WithForkTest } from "./Base.t.sol";
import { HatsWalletBase, HatsWalletMofN } from "../src/HatsWalletMofN.sol";
import { Operation, ProposalStatus, Vote } from "../src/lib/LibHatsWallet.sol";
import { ERC6551Account } from "tokenbound/abstract/ERC6551Account.sol";
import "../src/lib/HatsWalletErrors.sol";
import { DeployImplementation, DeployWallet } from "../script/HatsWalletMofN.s.sol";
import { IERC6551Registry } from "erc6551/interfaces/IERC6551Registry.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ECDSA, SignerMock, MaliciousStateChanger, MofNMock } from "./utils/TestContracts.sol";

contract HatsWalletMofNTest is DeployImplementation, WithForkTest {
  // variables inhereted from DeployImplementation
  // bytes32 public constant SALT;
  // HatsWalletMofN public implementation;

  HatsWalletMofN public instance;
  DeployWallet public deployWallet;

  uint8 public minThreshold;
  uint8 public maxThreshold;

  event ProposalSubmitted(
    Operation[] operations, uint32 expiration, bytes32 descriptionHash, bytes32 proposalId, address proposer
  );
  event VoteCast(bytes32 proposalId, address voter, Vote vote);
  event ProposalExecuted(bytes32 proposalId);
  event ProposalRejected(bytes32 proposalId);

  // predetermine relevant actor addresses to make fork tests more efficient
  address public benefactor = makeAddr("benefactor");
  /**
   * @dev wearer1 (inherited from BaseTest) is generated with a private key in order to test signature functionality.
   * All other wearer addresses are numbered sequentially from 2 to 15 to make sorted voter array tests easier.
   */
  address public wearer2 = address(2);
  address public wearer3 = address(3);
  address public wearer4 = address(4);
  address public wearer5 = address(5);
  address public wearer6 = address(6);
  address public wearer7 = address(7);
  address public wearer8 = address(8);
  address public wearer9 = address(9);
  address public wearer10 = address(10);
  address public wearer11 = address(11);
  address public wearer12 = address(12);
  address public wearer13 = address(13);
  address public wearer14 = address(14);
  address public wearer15 = address(15);
  address[] public wearers;

  function _calculateSalt(uint8 _minThreshold, uint8 _maxThreshold) internal pure returns (bytes32 salt) {
    salt = bytes32(abi.encodePacked(_minThreshold, _maxThreshold));
  }

  function setUp() public virtual override {
    super.setUp();

    // deploy implementation
    DeployImplementation.prepare(false, version);
    DeployImplementation.run();

    // put wearers into an array for easy access
    wearers = new address[](15);
    wearers[0] = wearer1;
    wearers[1] = wearer2;
    wearers[2] = wearer3;
    wearers[3] = wearer4;
    wearers[4] = wearer5;
    wearers[5] = wearer6;
    wearers[6] = wearer7;
    wearers[7] = wearer8;
    wearers[8] = wearer9;
    wearers[9] = wearer10;
    wearers[10] = wearer11;
    wearers[11] = wearer12;
    wearers[12] = wearer13;
    wearers[13] = wearer14;
    wearers[14] = wearer15;

    // mint additional hat wearers hats. first wearer already has a hat
    vm.startPrank(org);
    for (uint256 i = 1; i < wearers.length; ++i) {
      HATS.mintHat(hatWithWallet, wearers[i]);
    }
    vm.stopPrank();

    // set up initial min and max threshold
    minThreshold = 2;
    maxThreshold = 3;

    // deploy wallet instance with initial min and max threshold
    deployWallet = new DeployWallet();
    instance = deployWalletWithThresholds(minThreshold, maxThreshold);
  }

  function deployWalletWithThresholds(uint256 _minThreshold, uint256 _maxThreshold)
    public
    returns (HatsWalletMofN wallet)
  {
    uint256 cap = wearers.length - 2;
    uint8 min = uint8(bound(_minThreshold, 1, cap));
    uint8 max = uint8(bound(_maxThreshold, minThreshold, cap));
    deployWallet.prepare(false, address(implementation), hatWithWallet, _calculateSalt(min, max));
    wallet = HatsWalletMofN(payable(deployWallet.run()));
    // bankroll the wallet with some ETH
    vm.deal(address(wallet), 10 ether);
  }

  function createOps(address[] memory tos, uint256[] memory values, bytes[] memory datas, uint8[] memory operations)
    public
    pure
    returns (Operation[] memory)
  {
    // assume lengths are equal
    uint256 length = tos.length;
    Operation[] memory ops = new Operation[](length);
    for (uint256 i; i < length; i++) {
      ops[i] = Operation(tos[i], values[i], datas[i], operations[i]);
    }
    return ops;
  }

  function createRandomProposal(
    uint256 actionCount,
    address toSeed,
    uint256 valueSeed,
    bytes memory dataSeed,
    uint8 operationsSeed,
    uint32 expiration,
    bytes32 description
  ) public pure returns (Operation[] memory ops, bytes32 proposalId) {
    // create random tos, values, datas, and operations of length actionCount
    address[] memory tos = new address[](actionCount);
    uint256[] memory values = new uint256[](actionCount);
    bytes[] memory datas = new bytes[](actionCount);
    uint8[] memory operations = new uint8[](actionCount);

    for (uint256 i; i < actionCount; i++) {
      tos[i] = address(uint160(uint256(keccak256(abi.encode(toSeed, i)))));
      values[i] = uint256(keccak256(abi.encode(valueSeed, i)));
      datas[i] = abi.encode(keccak256(abi.encodePacked(dataSeed, i)));
      operations[i] = uint8(uint256(keccak256(abi.encode(operationsSeed, i))));
    }
    ops = createOps(tos, values, datas, operations);
    proposalId = createProposalId(ops, expiration, description);
  }

  function createProposalId(
    address[] memory tos,
    uint256[] memory values,
    bytes[] memory datas,
    uint8[] memory operations,
    uint32 expiration,
    bytes32 description
  ) public pure returns (bytes32) {
    Operation[] memory ops = createOps(tos, values, datas, operations);
    return createProposalId(ops, expiration, description);
  }

  function createProposalId(Operation[] memory ops, uint32 expiration, bytes32 description)
    public
    pure
    returns (bytes32)
  {
    bytes32 prelimId = keccak256(abi.encode(ops, description));
    uint256 shiftedId = uint256(prelimId) << 32;
    uint256 appended = shiftedId | uint256(expiration);
    return bytes32(appended);
  }

  function createSingleOpProposal(
    address to,
    uint256 value,
    bytes memory data,
    uint8 operation,
    uint32 expiration,
    bytes32 description
  ) public pure returns (Operation[] memory ops, bytes32 proposalId) {
    ops = new Operation[](1);
    ops[0] = Operation(to, value, data, operation);
    proposalId = createProposalId(ops, expiration, description);
  }

  function createSimpleProposal()
    public
    view
    returns (Operation[] memory ops, uint32 expiration, bytes32 proposalId, bytes32 description)
  {
    uint256 value = 1 ether;
    bytes memory data = EMPTY_BYTES;
    uint8 operation = 0;
    description = bytes32("description");
    expiration = 0;
    (ops, proposalId) = createSingleOpProposal(target, value, data, operation, expiration, description);
  }

  function submitSimpleProposal(address proposer)
    public
    returns (Operation[] memory ops, uint32 expiration, bytes32 proposalId, bytes32 description)
  {
    (ops, expiration, proposalId, description) = createSimpleProposal();

    vm.expectEmit();
    emit ProposalSubmitted(ops, expiration, description, proposalId, wearer1);
    vm.prank(proposer);
    instance.propose(ops, expiration, description);
  }

  /// @dev Retrieves wearer at the given index, or the nonWearer if the index is out of bounds
  function _getActor(uint256 index) internal view returns (address) {
    if (index >= wearers.length) {
      return nonWearer;
    } else {
      return wearers[index];
    }
  }

  /// @dev Creates an array of unique voters sorted by address, ascending. Takes advantage of the fact that the
  /// wearers array is already sorted.
  function createSortedVoterArray(uint256 length) public view returns (address[] memory voters) {
    uint256 maxLength = wearers.length - 1;
    require(length < maxLength, "length must fit within the wearers array, excluding wearer1");
    /// @dev We exclude wearer1 since their address is not numerically ordered
    voters = new address[](length);
    for (uint256 i = 0; i < length; ++i) {
      // console2.log("i", i);
      voters[i] = wearers[i + 1]; // exclude wearer1
        // console2.log("voters[i]", voters[i]);
    }
  }

  /// @dev Creates an array of unique voters, but not correctly sorted by address. It accomplishes this by inserting
  /// wearer2 at a configurable location within the returned array.
  function createUnsortedVoterArray(uint256 length, uint256 outOfOrderPositionIndex)
    public
    view
    returns (address[] memory voters)
  {
    uint256 maxLength = wearers.length - 1;
    require(length < maxLength, "length must fit within the wearers array, excluding wearer1");
    require(outOfOrderPositionIndex < length, "outOfOrderPositionIndex must be within length");
    // can't be the first element, since that's wearer2
    require(outOfOrderPositionIndex != 0, "outOfOrderPositionIndex cannot be 0");

    voters = new address[](length);

    // insert wearer2 at the given index
    voters[outOfOrderPositionIndex] = wearer2;

    // fill the rest of the array with wearers, in ascending order
    for (uint256 i = 0; i < length - 1; ++i) {
      if (i != outOfOrderPositionIndex) {
        voters[i] = wearers[i + 2]; // exclude wearer1 and wearer2
      }
      // console2.log("voters[i]", voters[i]);
    }
  }

  /// @dev Creates an otherwise-correctly-sorted array that includes a duplicate voter
  function createVoterArrayWithDuplicate(uint256 length, uint256 duplicateIndex)
    public
    view
    returns (address[] memory voters)
  {
    uint256 maxLength = wearers.length - 1;
    // console2.log("maxLength", maxLength);
    // console2.log("length", length);
    // console2.log("duplicateIndex", duplicateIndex);
    require(length < maxLength, "length must fit within the wearers array, excluding wearer1");
    require(duplicateIndex < length, "duplicateIndex must be within length");

    voters = new address[](length);

    // populate a correctly-sorted array of length - 1
    for (uint256 i; i < length - 1; ++i) {
      // console2.log("i", i);
      voters[i] = wearers[i + 1]; // exclude wearer1
        // console2.log("voters[i]", voters[i]);
    }

    // append the duplicated voter to the end of the array
    voters[length - 1] = voters[duplicateIndex];
    // console2.log("voters[length - 1]", voters[length - 1]);
  }

  /*///////////////////////////////////////////////////////////////
                          CUSTOM ASSERTIONS
  //////////////////////////////////////////////////////////////*/

  function assertEq(ProposalStatus actual, ProposalStatus expected) public {
    assertEq(uint256(actual), uint256(expected));
  }

  function assertEqVote(Vote actual, Vote expected) public {
    assertEq(uint256(actual), uint256(expected));
  }
}

contract Constants is HatsWalletMofNTest {
  function test_thresholdRange() public {
    (uint256 min, uint256 max) = instance.THRESHOLD_RANGE();
    assertEq(min, minThreshold);
    assertEq(max, maxThreshold);
  }

  function test_minThreshold() public {
    assertEq(instance.MIN_THRESHOLD(), minThreshold);
  }

  function test_maxThreshold() public {
    assertEq(instance.MAX_THRESHOLD(), maxThreshold);
  }

  function test_version() public {
    assertEq(implementation.version_(), version, "wrong implementation version");
    assertEq(instance.version(), version, "wrong instance version");
  }
}

contract GetThreshold is HatsWalletMofNTest {
  uint256 public hatWithWallet2;

  function setUp() public virtual override {
    super.setUp();

    // create a new hat with supply of 0;
    vm.prank(org);
    hatWithWallet2 =
      HATS.createHat(tophat, "hatWithWallet2", 0, eligibility, toggle, true, "org.eth/hatWithWallet2.png");
  }

  function test_getThreshold(uint32 supply, uint8 min, uint8 max) public {
    supply = uint32(bound(supply, 0, 15));
    min = uint8(bound(min, 1, 14));
    max = uint8(bound(max, min + 1, 15));

    // deploy a new instance with the given min and max threshold
    deployWallet.prepare(false, address(implementation), hatWithWallet2, _calculateSalt(min, max));
    instance = HatsWalletMofN(payable(deployWallet.run()));

    vm.prank(org);
    HATS.changeHatMaxSupply(hatWithWallet2, supply);

    // mint some hats to meet the supply
    vm.startPrank(org);
    for (uint256 i; i < supply; i++) {
      // mint to random wearers
      HATS.mintHat(hatWithWallet2, wearers[i]);
    }
    vm.stopPrank();

    // ensure supply is correct
    assertEq(HATS.hatSupply(hatWithWallet2), supply);

    // calculate expected threshold
    uint256 expectedThreshold;
    if (supply < min) {
      expectedThreshold = min;
    } else if (supply > max) {
      expectedThreshold = max;
    } else {
      expectedThreshold = supply;
    }

    // ensure threshold is correct
    assertEq(instance.getThreshold(), expectedThreshold);
  }
}

contract getProposalId is HatsWalletMofNTest {
  function test_getProposalId(
    uint256 actionCount,
    address toSeed,
    uint256 valueSeed,
    bytes memory dataSeed,
    uint8 operationsSeed,
    uint32 expiration,
    bytes32 description
  ) public {
    // cap actionCount at 20
    actionCount = bound(actionCount, 1, 20);

    // create random tos, values, datas, and operations
    address[] memory tos = new address[](actionCount);
    uint256[] memory values = new uint256[](actionCount);
    bytes[] memory datas = new bytes[](actionCount);
    uint8[] memory operations = new uint8[](actionCount);

    for (uint256 i; i < actionCount; i++) {
      tos[i] = address(uint160(uint256(keccak256(abi.encode(toSeed, i)))));
      values[i] = uint256(keccak256(abi.encode(valueSeed, i)));
      datas[i] = abi.encode(keccak256(abi.encodePacked(dataSeed, i)));
      operations[i] = uint8(uint256(keccak256(abi.encode(operationsSeed, i))));
    }
    bytes32 expected = createProposalId(tos, values, datas, operations, expiration, description);

    Operation[] memory ops = createOps(tos, values, datas, operations);
    assertEq(instance.getProposalId(ops, expiration, description), expected);
  }
}

contract MockMofNTest is HatsWalletMofNTest {
  MofNMock mockImplementation;
  MofNMock mock;

  function setUp() public virtual override {
    super.setUp();

    // deploy implementation
    mockImplementation = new MofNMock(version);

    // deploy mock instance
    deployWallet.prepare(false, address(mockImplementation), hatWithWallet, _calculateSalt(minThreshold, maxThreshold));
    mock = MofNMock(payable(deployWallet.run()));
  }
}

contract _UnsafeVoting is MockMofNTest {
  address voter;
  Vote vote;

  function test_approveVote(bytes32 proposalId, uint256 voterIndex) public {
    voter = _getActor(voterIndex);
    vote = Vote.APPROVE;

    // voter casts the vote, expecting an event
    vm.prank(voter);
    vm.expectEmit();
    emit VoteCast(proposalId, voter, vote);
    mock.unsafeVote(proposalId, vote);

    // assert that the vote was cast
    assertEqVote(mock.votes(proposalId, voter), vote);
  }

  function test_rejectVote(bytes32 proposalId, uint256 voterIndex) public {
    voter = _getActor(voterIndex);
    vote = Vote.REJECT;

    // voter casts the vote, expecting an event
    vm.prank(voter);
    vm.expectEmit();
    emit VoteCast(proposalId, voter, vote);
    mock.unsafeVote(proposalId, vote);

    // assert that the vote was cast
    assertEqVote(mock.votes(proposalId, voter), vote);
  }
}

contract _getExpiration is HatsWalletMofNTest {
  function test_happy(Operation[] memory ops, uint32 expiration, bytes32 description) public {
    // create a simple proposal id
    bytes32 proposalId = createProposalId(ops, expiration, description);

    // get the expiration and ensure it's correct
    assertEq(instance.getExpiration(proposalId), expiration);
  }
}

contract Propose is HatsWalletMofNTest {
  function test_happy(
    uint256 actionCount,
    address toSeed,
    uint256 valueSeed,
    bytes memory dataSeed,
    uint8 operationsSeed,
    uint32 expiration,
    bytes32 description,
    uint256 proposerIndex
  ) public {
    // cap actionCount at 20
    actionCount = bound(actionCount, 1, 20);

    // select a random wearer to propose
    proposerIndex = bound(proposerIndex, 0, wearers.length - 1);
    address proposer = _getActor(proposerIndex);

    // create a random proposal
    (Operation[] memory ops, bytes32 proposalId) =
      createRandomProposal(actionCount, toSeed, valueSeed, dataSeed, operationsSeed, expiration, description);

    // check that the proposal doesn't yet exist
    assertEq(instance.proposalStatus(proposalId), ProposalStatus.NULL);

    // submit the proposal, expecting an event
    vm.expectEmit();
    emit ProposalSubmitted(ops, expiration, description, proposalId, proposer);
    vm.prank(proposer);
    instance.propose(ops, expiration, description);

    // ensure the proposal was stored correctly
    assertEq(instance.proposalStatus(proposalId), ProposalStatus.PENDING);
  }

  function test_revert_invalidSigner() public {
    // create a simple proposal
    (Operation[] memory ops, uint32 expiration, bytes32 proposalId, bytes32 description) = createSimpleProposal();

    // try to propose from a nonWearer, expecting revert
    vm.expectRevert(InvalidSigner.selector);
    vm.prank(nonWearer);
    instance.propose(ops, expiration, description);

    // assert that the proposal was not created
    assertEq(instance.proposalStatus(proposalId), ProposalStatus.NULL);
  }

  function test_revert_proposalAlreadyExists() public {
    // submit a simple proposal, expecting an event
    (Operation[] memory ops, uint32 expiration, bytes32 proposalId, bytes32 description) = submitSimpleProposal(wearer1);

    // assert that it exists
    assertEq(instance.proposalStatus(proposalId), ProposalStatus.PENDING);

    // try to propose again, expecting revert
    vm.expectRevert(ProposalAlreadyExists.selector);
    vm.prank(wearer1);
    instance.propose(ops, expiration, description);

    // assert that it still exists
    assertEq(instance.proposalStatus(proposalId), ProposalStatus.PENDING);
  }
}

contract Voting is HatsWalletMofNTest {
  address[] voters;

  function test_approve() public {
    address voter = wearer2;
    Vote vote = Vote.APPROVE;

    // wearer1 submits a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // vote to approve the proposal, expecting an event
    vm.expectEmit();
    emit VoteCast(proposalId, voter, vote);
    vm.prank(voter);
    instance.vote(proposalId, vote);

    // assert that the vote was cast
    assertEqVote(instance.votes(proposalId, voter), vote);
  }

  function test_reject() public {
    address voter = wearer2;
    Vote vote = Vote.REJECT;

    // wearer submits a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // vote to reject the proposal, expecting an event
    vm.expectEmit();
    emit VoteCast(proposalId, voter, vote);
    vm.prank(voter);
    instance.vote(proposalId, vote);

    // assert that the vote was cast
    assertEqVote(instance.votes(proposalId, voter), vote);
  }

  function test_changeVote() public {
    address voter = wearer2;
    Vote vote = Vote.APPROVE;

    // wearer1 submits a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // vote to approve the proposal, expecting an event
    vm.expectEmit();
    emit VoteCast(proposalId, voter, vote);
    vm.prank(voter);
    instance.vote(proposalId, vote);

    // assert that the vote was cast
    assertEqVote(instance.votes(proposalId, voter), vote);

    // change the vote to reject, expecting an event
    vote = Vote.REJECT;
    vm.expectEmit();
    emit VoteCast(proposalId, voter, vote);
    vm.prank(voter);
    instance.vote(proposalId, vote);

    // assert that the vote was changed
    assertEqVote(instance.votes(proposalId, voter), vote);
  }

  function test_revert_proposalNotCreated() public {
    address voter = wearer2;
    Vote vote = Vote.APPROVE;

    // no proposal is submitted
    bytes32 proposalId = bytes32("proposalId");

    // vote to approve the proposal, expecting a revert
    vm.expectRevert(ProposalNotPending.selector);
    vm.prank(voter);
    instance.vote(proposalId, vote);

    // assert that the vote was not cast
    assertEqVote(instance.votes(proposalId, voter), Vote.NONE);
  }

  function test_revert_proposalExecuted() public {
    address voter = wearer4;
    Vote vote = Vote.APPROVE;

    // wearer1 submits a simple proposal
    (Operation[] memory ops, uint32 expiration, bytes32 proposalId, bytes32 description) = submitSimpleProposal(wearer1);

    // get the current threshold
    uint256 threshold = instance.getThreshold();

    // build the array of voters
    voters = createSortedVoterArray(threshold);

    // voters vote to approve the proposal
    for (uint256 i; i < voters.length; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, vote);
    }

    // execute the proposal
    instance.execute(ops, expiration, description, voters);

    // vote to approve the proposal, expecting a revert
    vm.expectRevert(ProposalNotPending.selector);
    vm.prank(voter);
    instance.vote(proposalId, vote);

    // assert that the vote was not cast
    assertEqVote(instance.votes(proposalId, voter), vote);
  }

  function test_revert_proposalRejected() public {
    address voter = wearer13;
    Vote vote = Vote.APPROVE;

    // wearer1 submits a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // get the current rejection threshold
    uint256 rejectionThreshold = instance.getRejectionThreshold();

    // build the array of voters
    voters = createSortedVoterArray(rejectionThreshold);

    // voters vote to reject the proposal
    for (uint256 i; i < voters.length; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.REJECT);
    }

    // reject the proposal
    instance.reject(proposalId, voters);

    Vote expectedVote = instance.votes(proposalId, voter);

    // vote to approve the proposal, expecting a revert
    vm.expectRevert(ProposalNotPending.selector);
    vm.prank(voter);
    instance.vote(proposalId, vote);

    // assert that the vote was not cast
    assertEqVote(instance.votes(proposalId, voter), expectedVote);
  }
}

contract _CheckValidVotes is MockMofNTest {
  address voter;
  address[] voters;
  Vote vote;

  // function test_sortedArray(uint256 threshold) public view {
  //   threshold = bound(threshold, 1, wearers.length - 2);
  //   createSortedVoterArray(13);
  // }

  // function test_unsortedArray(uint256 threshold, uint256 index) public view {
  //   threshold = bound(threshold, 1, wearers.length - 2);
  //   index = bound(index, 0, threshold - 1);
  //   createUnsortedVoterArray(threshold, index);
  // }

  // function test_duplicateVoter(uint256 threshold, uint256 index) public view {
  //   threshold = bound(threshold, 1, wearers.length - 2);
  //   index = bound(index, 0, threshold - 1);
  //   createVoterArrayWithDuplicate(threshold, index);
  // }

  function test_happy(uint256 threshold, uint256 _vote) public {
    vote = Vote(bound(_vote, 1, 2)); // only APPROVE or REJECT votes
    bytes32 proposalId = bytes32("proposalId");
    threshold = bound(threshold, 1, wearers.length - 2);

    // create a sorted array of enough voters to meet the threshold
    voters = createSortedVoterArray(threshold);

    // use {unsafeVote} to have each voter cast a vote even though the proposal hasn't been created
    for (uint256 i; i < voters.length; ++i) {
      vm.prank(voters[i]);
      mock.unsafeVote(proposalId, vote);
    }

    // assert that {_checkValidVotes} doesn't revert
    assertTrue(mock.checkValidVotes(proposalId, voters, vote, threshold));
  }

  function test_revert_insufficientVotes(uint256 threshold, uint256 _vote) public {
    vote = Vote(bound(_vote, 1, 2)); // only APPROVE or REJECT votes
    bytes32 proposalId = bytes32("proposalId");
    threshold = bound(threshold, 1, wearers.length - 2);

    // create a sorted array of voters that is one less than the threshold
    voters = createSortedVoterArray(threshold - 1);

    // use {unsafeVote} to have each voter cast a vote even though the proposal hasn't been created
    for (uint256 i; i < voters.length; ++i) {
      vm.prank(voters[i]);
      mock.unsafeVote(proposalId, vote);
    }

    // assert that {_checkValidVotes} reverts
    vm.expectRevert(InsufficientValidVotes.selector);
    mock.checkValidVotes(proposalId, voters, vote, threshold);
  }

  function test_revert_insufficientValidVotes(uint256 threshold, uint256 _vote, uint256 wrongVoterCount) public {
    vote = Vote(bound(_vote, 1, 2)); // only APPROVE or REJECT votes
    Vote wrongVote = (vote == Vote.APPROVE) ? Vote.REJECT : Vote.APPROVE;
    bytes32 proposalId = bytes32("proposalId");
    threshold = bound(threshold, 1, wearers.length - 2);
    wrongVoterCount = bound(wrongVoterCount, 1, threshold);

    // create a sorted array of enough voters to meet the threshold
    voters = createSortedVoterArray(threshold);

    // use {unsafeVote} to have each voter cast a vote even though the proposal hasn't been created
    // the first wrongVoterCount voters will cast the wrong vote, and the rest will cast the correct vote
    for (uint256 i; i < voters.length; ++i) {
      vm.prank(voters[i]);
      if (i < wrongVoterCount) {
        mock.unsafeVote(proposalId, wrongVote);
      } else {
        mock.unsafeVote(proposalId, vote);
      }
    }

    // assert that {_checkValidVotes} reverts
    vm.expectRevert(InsufficientValidVotes.selector);
    mock.checkValidVotes(proposalId, voters, vote, threshold);
  }

  function test_revert_unsortedArray(uint256 threshold, uint256 _vote, uint256 outOfOrderIndex) public {
    vote = Vote(bound(_vote, 1, 2)); // only APPROVE or REJECT votes
    bytes32 proposalId = bytes32("proposalId");
    threshold = bound(threshold, 2, wearers.length - 2);
    outOfOrderIndex = bound(outOfOrderIndex, 1, threshold - 1);

    // create an unsorted array of enough voters to meet the threshold
    voters = createUnsortedVoterArray(threshold, outOfOrderIndex);

    // use {unsafeVote} to have each voter cast a vote even though the proposal hasn't been created
    for (uint256 i; i < voters.length; ++i) {
      vm.prank(voters[i]);
      mock.unsafeVote(proposalId, vote);
    }

    // assert that {_checkValidVotes} reverts
    vm.expectRevert(UnsortedVotersArray.selector);
    mock.checkValidVotes(proposalId, voters, vote, threshold);
  }

  function test_revert_duplicateVoter(uint256 threshold, uint256 _vote, uint256 duplicateIndex) public {
    vote = Vote(bound(_vote, 1, 2)); // only APPROVE or REJECT votes
    bytes32 proposalId = bytes32("proposalId");
    threshold = bound(threshold, 2, wearers.length - 2);
    duplicateIndex = bound(duplicateIndex, 1, threshold - 1);

    // create an array of enough voters to meet the threshold, but with a duplicate
    voters = createVoterArrayWithDuplicate(threshold, duplicateIndex);

    // use {unsafeVote} to have each voter cast a vote even though the proposal hasn't been created
    for (uint256 i; i < voters.length; ++i) {
      vm.prank(voters[i]);
      mock.unsafeVote(proposalId, vote);
    }

    // assert that {_checkValidVotes} reverts
    vm.expectRevert(UnsortedVotersArray.selector);
    mock.checkValidVotes(proposalId, voters, vote, threshold);
  }

  function test_revert_invalidVoter(uint256 threshold, uint256 _vote, uint256 invalidVoterCount) public {
    vote = Vote(bound(_vote, 1, 2)); // only APPROVE or REJECT votes
    bytes32 proposalId = bytes32("proposalId");
    threshold = bound(threshold, 1, wearers.length - 2);
    invalidVoterCount = bound(invalidVoterCount, 1, threshold);

    // create a sorted array of enough voters to meet the threshold
    voters = createSortedVoterArray(threshold);

    // use {unsafeVote} to have each voter cast a vote even though the proposal hasn't been created
    // the first invalidVoterCount voters will be invalidated by having their hat revoked, and the rest will be valid
    for (uint256 i; i < voters.length; ++i) {
      if (i < invalidVoterCount) {
        // revoke the voter's hat to make them invalid
        vm.prank(eligibility);
        HATS.setHatWearerStatus(hatWithWallet, voters[i], false, true);
      }
      // vote
      vm.prank(voters[i]);
      mock.unsafeVote(proposalId, vote);
    }

    // assert that {_checkValidVotes} reverts
    vm.expectRevert(InsufficientValidVotes.selector);
    mock.checkValidVotes(proposalId, voters, vote, threshold);
  }
}

contract ProposeWithApproval is HatsWalletMofNTest {
  address proposer;

  function test_happy(uint256 proposerIndex) public {
    // select a random wearer to propose
    proposerIndex = bound(proposerIndex, 0, wearers.length - 1);
    proposer = _getActor(proposerIndex);

    // craft a simple proposal
    (Operation[] memory ops, uint32 expiration, bytes32 proposalId, bytes32 description) = createSimpleProposal();

    // proposer submits the proposal with approval, expecting two events
    vm.prank(proposer);
    vm.expectEmit();
    emit ProposalSubmitted(ops, expiration, description, proposalId, proposer);
    emit VoteCast(proposalId, proposer, Vote.APPROVE);
    instance.proposeWithApproval(ops, expiration, description);

    // assert that the proposal was created
    assertEq(instance.proposalStatus(proposalId), ProposalStatus.PENDING);
    // assert that the vote was cast
    assertEqVote(instance.votes(proposalId, proposer), Vote.APPROVE);
  }

  function test_revert_invalidSigner() public {
    // craft a simple proposal
    (Operation[] memory ops, uint32 expiration, bytes32 proposalId, bytes32 description) = createSimpleProposal();

    // try to propose with approval from a nonWearer, expecting revert
    vm.expectRevert(InvalidSigner.selector);
    vm.prank(nonWearer);
    instance.proposeWithApproval(ops, expiration, description);

    // assert that the proposal was not created
    assertEq(instance.proposalStatus(proposalId), ProposalStatus.NULL);
    // assert that the vote was not cast
    assertEqVote(instance.votes(proposalId, nonWearer), Vote.NONE);
  }

  function test_revert_proposalAlreadyExists(uint256 proposerIndex) public {
    // select a random wearer to propose
    proposerIndex = bound(proposerIndex, 0, wearers.length - 1);
    proposer = _getActor(proposerIndex);

    // create and submit a simple proposal
    (Operation[] memory ops, uint32 expiration, bytes32 proposalId, bytes32 description) = createSimpleProposal();
    vm.prank(proposer);
    instance.propose(ops, expiration, description);

    // assert that it exists
    assertEq(instance.proposalStatus(proposalId), ProposalStatus.PENDING);

    // try to propose again with an approval, expecting revert
    vm.expectRevert(ProposalAlreadyExists.selector);
    vm.prank(proposer);
    instance.proposeWithApproval(ops, expiration, description);

    // assert that it still exists
    assertEq(instance.proposalStatus(proposalId), ProposalStatus.PENDING);
  }
}

contract IsExecutableNow is HatsWalletMofNTest {
  address[] voters;

  function test_true(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // create and submit a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // get the current threshold
    uint256 threshold = instance.getThreshold();

    // build the array of voters
    voters = createSortedVoterArray(threshold);

    // threshold number of voters approve the proposal
    for (uint256 i; i < threshold; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.APPROVE);
    }

    // assert that the proposal is executable
    assertTrue(instance.isExecutableNow(proposalId, voters));
  }

  function test_revert_expired(uint256 _minThreshold, uint256 _maxThreshold, uint32 _expiration) public {
    // ensure the expiration is not 0 or 2^32 - 1 (leaving room to warp past it)
    _expiration = uint32(bound(uint256(_expiration), 1, uint256(type(uint32).max - 1)));

    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // create a single op proposal with a custom expiration
    bytes32 description = bytes32("description");
    (Operation[] memory ops, bytes32 proposalId) =
      createSingleOpProposal(target, 1 ether, EMPTY_BYTES, 0, _expiration, description);

    // submit the proposal
    vm.prank(wearer1);
    instance.propose(ops, _expiration, description);

    // get the current threshold
    uint256 threshold = instance.getThreshold();

    // build the array of voters
    voters = createSortedVoterArray(threshold);

    // threshold number of voters approve the proposal
    for (uint256 i; i < threshold; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.APPROVE);
    }

    // expect a revert only if the proposal is expired
    if (_expiration <= block.timestamp) {
      vm.expectRevert(ProposalExpired.selector);
      instance.isExecutableNow(proposalId, voters);
    } else {
      assertTrue(instance.isExecutableNow(proposalId, voters));
      // fast forward past the expiration
      vm.warp(_expiration + 1);

      // assert that the proposal is not executable now
      vm.expectRevert(ProposalExpired.selector);
      instance.isExecutableNow(proposalId, voters);
    }
  }

  function test_revert_insufficientValidVotes(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // create and submit a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // get the current threshold
    uint256 threshold = instance.getThreshold();

    // build the array of voters
    voters = createSortedVoterArray(threshold);

    // threshold - 1 voters approve the proposal
    for (uint256 i; i < threshold - 1; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.APPROVE);
    }

    // assert that the proposal is not executable
    vm.expectRevert(InsufficientValidVotes.selector);
    instance.isExecutableNow(proposalId, voters);
  }

  function test_revert_unsortedVotersArray(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // create and submit a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // get the current threshold
    uint256 threshold = instance.getThreshold();

    // build the array of voters, but unsorted
    voters = createUnsortedVoterArray(threshold, 1);

    // threshold number of voters approve the proposal
    for (uint256 i; i < threshold; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.APPROVE);
    }

    // assert that the proposal is not executable
    vm.expectRevert(UnsortedVotersArray.selector);
    instance.isExecutableNow(proposalId, voters);
  }

  function test_revert_proposalNotCreated(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // don't submit a proposal
    bytes32 proposalId = bytes32("proposalId");

    // get the current threshold
    uint256 threshold = instance.getThreshold();

    // build the array of voters
    voters = createSortedVoterArray(threshold);

    // assert that the proposal is not executable
    vm.expectRevert(ProposalNotPending.selector);
    instance.isExecutableNow(proposalId, voters);
  }

  function test_revert_proposalAlreadyExecuted(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // submit a simple proposal
    (Operation[] memory ops, uint32 expiration, bytes32 proposalId, bytes32 description) = submitSimpleProposal(wearer1);

    // get the current threshold
    uint256 threshold = instance.getThreshold();

    // build the array of voters
    voters = createSortedVoterArray(threshold);

    // threshold number of voters approve the proposal
    for (uint256 i; i < threshold; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.APPROVE);
    }

    // execute the proposal
    instance.execute(ops, expiration, description, voters);

    // assert that the proposal is not executable
    vm.expectRevert(ProposalNotPending.selector);
    instance.isExecutableNow(proposalId, voters);
  }

  function test_revert_proposalRejected(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // submit a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // get the current rejection threshold
    uint256 rejectionThreshold = instance.getRejectionThreshold();

    // build the array of voters
    voters = createSortedVoterArray(rejectionThreshold);

    // threshold number of voters reject the proposal
    for (uint256 i; i < rejectionThreshold; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.REJECT);
    }

    // reject the proposal
    instance.reject(proposalId, voters);

    // assert that the proposal is not executable
    vm.expectRevert(ProposalNotPending.selector);
    instance.isExecutableNow(proposalId, voters);
  }
}

// // TODO
// contract Execute is HatsWalletMofNTest {
//   address[] voters;

//   /*
//   Assertions to make
//   - state var is appropraitely incremented
//   - instance balance changes appropriately
//   - proposal status is set correctly
//   - ProposalExecuted event is emitted correctly
//   - results are returned correctly

//   Conditions to test
//   - ETH transfer
//   - external call
//   - multiple operations
//   - insufficient votes
//   - expiration
//    */
// }

contract IsRejectableNow is HatsWalletMofNTest {
  address[] voters;

  function test_true(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // submit a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // get the current rejection threshold
    uint256 rejectionThreshold = instance.getRejectionThreshold();

    // build the array of voters
    voters = createSortedVoterArray(rejectionThreshold);

    // threshold number of voters reject the proposal
    for (uint256 i; i < rejectionThreshold; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.REJECT);
    }

    // assert that the proposal is rejectable
    assertTrue(instance.isRejectableNow(proposalId, voters));
  }

  function test_revert_insufficientValidVotes(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // submit a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // get the current rejection threshold
    uint256 rejectionThreshold = instance.getRejectionThreshold();

    // build the array of voters
    voters = createSortedVoterArray(rejectionThreshold - 1);

    // threshold - 1 number of voters reject the proposal
    for (uint256 i; i < rejectionThreshold - 1; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.REJECT);
    }

    // assert that the proposal is not rejectable
    vm.expectRevert(InsufficientValidVotes.selector);
    instance.isRejectableNow(proposalId, voters);
  }

  function test_revert_unsortedVotersArray(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // submit a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // get the current rejection threshold
    uint256 rejectionThreshold = instance.getRejectionThreshold();

    // build the array of voters, but unsorted
    voters = createUnsortedVoterArray(rejectionThreshold, 1);

    // threshold number of voters reject the proposal
    for (uint256 i; i < rejectionThreshold; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.REJECT);
    }

    // assert that the proposal is not rejectable
    vm.expectRevert(UnsortedVotersArray.selector);
    instance.isRejectableNow(proposalId, voters);
  }

  function test_revert_proposalNotCreated(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // don't submit a proposal
    bytes32 proposalId = bytes32("proposalId");

    // get the current rejection threshold
    uint256 rejectionThreshold = instance.getRejectionThreshold();

    // build the array of voters
    voters = createSortedVoterArray(rejectionThreshold);

    // assert that the proposal is not rejectable
    vm.expectRevert(ProposalNotPending.selector);
    instance.isRejectableNow(proposalId, voters);
  }

  function test_revert_proposalAlreadyExecuted(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // submit a simple proposal
    (Operation[] memory ops, uint32 expiration, bytes32 proposalId, bytes32 description) = submitSimpleProposal(wearer1);

    // get the current threshold
    uint256 threshold = instance.getThreshold();

    // build the array of voters
    voters = createSortedVoterArray(threshold);

    // threshold number of voters approve the proposal
    for (uint256 i; i < threshold; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.APPROVE);
    }

    // execute the proposal
    instance.execute(ops, expiration, description, voters);

    // assert that the proposal is not rejectable
    vm.expectRevert(ProposalNotPending.selector);
    instance.isRejectableNow(proposalId, voters);
  }

  function test_revert_proposalRejected(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // submit a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // get the current rejection threshold
    uint256 rejectionThreshold = instance.getRejectionThreshold();

    // build the array of voters
    voters = createSortedVoterArray(rejectionThreshold);

    // threshold number of voters reject the proposal
    for (uint256 i; i < rejectionThreshold; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.REJECT);
    }

    // reject the proposal
    instance.reject(proposalId, voters);

    // assert that the proposal is not rejectable
    vm.expectRevert(ProposalNotPending.selector);
    instance.isRejectableNow(proposalId, voters);
  }
}

contract Reject is HatsWalletMofNTest {
  address[] voters;

  function test_reject(uint256 _minThreshold, uint256 _maxThreshold) public {
    // deploy a new instance with bounded min and max threshold
    instance = deployWalletWithThresholds(_minThreshold, _maxThreshold);

    // submit a simple proposal
    (,, bytes32 proposalId,) = submitSimpleProposal(wearer1);

    // get the current rejection threshold
    uint256 rejectionThreshold = instance.getRejectionThreshold();

    // build the array of voters
    voters = createSortedVoterArray(rejectionThreshold);

    // threshold number of voters reject the proposal
    for (uint256 i; i < rejectionThreshold; ++i) {
      vm.prank(voters[i]);
      instance.vote(proposalId, Vote.REJECT);
    }

    // reject the proposal, expecting an event
    vm.expectEmit();
    emit ProposalRejected(proposalId);
    instance.reject(proposalId, voters);

    // assert that the proposal was rejected
    assertEq(instance.proposalStatus(proposalId), ProposalStatus.REJECTED);
  }
}

// contract ValidVoteCountsNow is HatsWalletMofNTest {
// // TODO
// }
