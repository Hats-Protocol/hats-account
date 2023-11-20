// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console2, Test } from "forge-std/Test.sol"; // remove before deploy
import "./lib/HatsWalletErrors.sol";
import { HatsWalletBase } from "./HatsWalletBase.sol";
import { LibHatsWallet, Operation, ProposalStatus, Vote } from "./lib/LibHatsWallet.sol";

// TODO natspec
contract HatsWalletMofN is HatsWalletBase {
  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event ProposalSubmitted(Operation[] operations, bytes32 descriptionHash, bytes32 proposalHash, address proposer);

  event VoteCast(bytes32 proposalHash, address voter, Vote vote);

  event ProposalExecuted(bytes32 proposalHash);

  event ProposalRejected(bytes32 proposalHash);

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The range of the dynamic threshold
   * @dev These values are extracted from the {salt}, where they were embedded when this wallet was first deployed.
   * @return min The lower bound. Extracted from the leftmost byte of the {salt}.
   * @return max The upper bound. Extracted from the second leftmost byte of the {salt}.
   */
  function THRESHOLD_RANGE() public view returns (uint256 min, uint256 max) {
    uint256 salt = uint256(salt());

    // the min is the leftmost byte of the salt
    min = salt >> 248;

    // the max is the second leftmost byte of the salt
    max = uint8(salt >> 240);
  }

  /// @notice The lower bound of the dynamic threshold
  function MIN_THRESHOLD() public view returns (uint256 min) {
    (min,) = THRESHOLD_RANGE();
  }

  /// @notice The upper bound of the dynamic threshold
  function MAX_THRESHOLD() public view returns (uint256 max) {
    (, max) = THRESHOLD_RANGE();
  }

  /*//////////////////////////////////////////////////////////////
                          MUTABLE STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @notice The status of a proposal, indexed by its hash
  mapping(bytes32 proposalHash => ProposalStatus) public proposalStatus;

  /// @notice The votes on a proposal, indexed by its hash and the voter's address
  mapping(bytes32 proposalHash => mapping(address voter => Vote vote)) public votes;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(string memory _version) HatsWalletBase(_version) { }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Propose a tx to be executed by this HatsWallet.
   * @dev The proposer need not be a valid signer for this HatsWallet. Signer validity is dynamic and therefore must be
   * checked at execution time, so there is no benefit to checking it here.
   * @param _operations Array of operations to be executed by this HatsWallet. Only call and delegatecall are supported.
   * Delegatecalls are routed through the sandbox.
   * @param _descriptionHash Hash of the description of the tx to be executed. Can be used to create a unique
   * proposalHash when the same operations are proposed multiple times.
   * @return proposalHash The hash of the proposal operations and description, used to identify the proposal
   */
  function propose(Operation[] calldata _operations, bytes32 _descriptionHash) external returns (bytes32 proposalHash) {
    // get the proposal hash
    proposalHash = getProposalHash(_operations, _descriptionHash);

    // revert if the proposal already exists
    if (proposalStatus[proposalHash] > ProposalStatus.NON_EXISTENT) revert ProposalAlreadyExists();

    // submit the proposal and log it
    _propose(_operations, _descriptionHash, proposalHash);
  }

  /**
   * @notice Propose a tx to be executed by this HatsWallet along with a vote to approve.
   * @dev The proposer need not be a valid signer for this HatsWallet. Signer validity is dynamic and therefore must be
   * checked at execution time, so there is no benefit to checking it here.
   * @param _operations Array of operations to be executed by this HatsWallet. Only call and delegatecall are supported.
   * Delegatecalls are routed through the sandbox.
   * @param _descriptionHash Hash of the description of the tx to be executed. Can be used to create a unique
   * proposalHash when the same operations are proposed multiple times.
   * @return proposalHash The hash of the proposal operations and description, used to identify the proposal
   */
  function proposeWithApproval(Operation[] calldata _operations, bytes32 _descriptionHash)
    external
    returns (bytes32 proposalHash)
  {
    // get the proposal hash
    proposalHash = getProposalHash(_operations, _descriptionHash);

    // revert if the proposal already exists
    if (proposalStatus[proposalHash] > ProposalStatus.NON_EXISTENT) revert ProposalAlreadyExists();

    // submit the proposal and log it
    _propose(_operations, _descriptionHash, proposalHash);

    // record the proposer's approval vote
    votes[proposalHash][msg.sender] = Vote.APPROVE;

    // log the vote
    emit VoteCast(proposalHash, msg.sender, Vote.APPROVE);
  }

  /**
   * @notice Cast a vote on a pending proposal.
   * @dev Voters can change their votes by calling this function again with a different vote. Voters need not be valid
   * signers, since signer validity is checked at execution time.
   * @param _proposalHash The hash of the proposal operations and description, used to identify the proposal
   * @param _vote The vote to cast. 1 = APPROVE, 2 = REJECT
   */
  function vote(bytes32 _proposalHash, Vote _vote) external {
    // proposal must be pending
    if (proposalStatus[_proposalHash] != ProposalStatus.PENDING) revert ProposalNotPending();

    // record the vote in HatsWalletStorage
    votes[_proposalHash][msg.sender] = _vote;

    // log the vote
    emit VoteCast(_proposalHash, msg.sender, _vote);
  }

  /**
   * @notice Execute a pending proposal. If enough valid signers have voted to approve the proposal, it will be
   * executed.
   * @dev Checks signer validity.
   * @param _operations Array of operations to be executed by this HatsWallet. Only call and delegatecall are supported.
   * Delegatecalls are routed through the sandbox.
   * @param _descriptionHash Hash of the description of the tx to be executed.
   * @param _voters The addresses of the voters to check for approval votes
   * @return results The results of the operations
   */
  function execute(Operation[] calldata _operations, bytes32 _descriptionHash, address[] calldata _voters)
    external
    payable
    returns (bytes[] memory)
  {
    // get the proposal hash
    bytes32 proposalHash = getProposalHash(_operations, _descriptionHash);

    // validate the voters and their approvals of this proposed tx
    _checkExecutableNow(proposalHash, _voters);

    // increment the state var
    _beforeExecute();

    // set the proposal status to executed
    proposalStatus[proposalHash] = ProposalStatus.EXECUTED;

    // loop through the operations and execute them, storing the bubbled-up results in an array
    uint256 length = _operations.length;
    bytes[] memory results = new bytes[](length);

    for (uint256 i = 0; i < length; i++) {
      results[i] =
        LibHatsWallet._execute(_operations[i].to, _operations[i].value, _operations[i].data, _operations[i].operation);
    }

    // log the proposal execution
    emit ProposalExecuted(proposalHash);

    // return the bubbled-up results
    return results;
  }

  /**
   * @notice Reject a pending proposal. If enough valid signers have voted to reject the proposal, it will be rejected.
   * @dev Checks signer validity.
   * @param _proposalHash The hash of the proposal operations and description, used to identify the proposal
   * @param _voters The addresses of the voters to check for rejection votes
   */
  function reject(bytes32 _proposalHash, address[] calldata _voters) external {
    // validate the voters and their rejections of this proposed tx
    _checkRejectableNow(_proposalHash, _voters);

    // set the proposal status to rejected
    proposalStatus[_proposalHash] = ProposalStatus.REJECTED;

    // log the proposal rejection
    emit ProposalRejected(_proposalHash);
  }

  // TODO enable HatsWalletMOfN to create a contract signature

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Derive the proposal hash from the operations and description hash
   * @param operations Array of operations to be executed by this HatsWallet
   * @param _descriptionHash Hash of the description of the tx to be executed.
   * @return proposalHash The hash of the proposal operations and description, used to identify the proposal
   */
  function getProposalHash(Operation[] calldata operations, bytes32 _descriptionHash)
    public
    pure
    returns (bytes32 proposalHash)
  {
    return keccak256(abi.encode(operations, _descriptionHash));
  }

  /**
   * @notice Derive the dynamic threshold, which is a function of the current hat supply and this HatsWallet's
   * configured threshold range.
   * @return threshold The current threshold.
   */
  function getThreshold() public view returns (uint256 threshold) {
    return _getThreshold(HATS().hatSupply(hat()));
  }

  /**
   * @notice Returns whether a proposal is executable now, reverts if not. A proposal is executable if:
   *   1. It is pending
   *   2. Has at least *threshold* approvals from valid signers
   * @param _proposalHash The hash of the proposal operations and description, used to identify the proposal
   * @param _voters The addresses of the voters to check for approval votes
   * @return Whether the proposal is executable
   */
  function isExecutableNow(bytes32 _proposalHash, address[] calldata _voters) external view returns (bool) {
    return _checkExecutableNow(_proposalHash, _voters);
  }

  /**
   * @notice Returns whether a proposal is rejectable now, reverts if not. A proposal is rejectable if:
   *   1. It is pending
   *   2. Has at least *threshold* rejections from valid signers
   * @param _proposalHash The hash of the proposal operations and description, used to identify the proposal
   * @param _voters The addresses of the voters to check for rejection votes
   * @return Whether the proposal is rejectable
   */
  function isRejectableNow(bytes32 _proposalHash, address[] calldata _voters) external view returns (bool) {
    return _checkRejectableNow(_proposalHash, _voters);
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Set the status of a proposal to pending and logs the proposal submission.
   * @param _proposalHash The hash of the proposal operations and description, used to identify the proposal
   */
  function _propose(Operation[] calldata _operations, bytes32 _descriptionHash, bytes32 _proposalHash) internal {
    // set the proposal status to pending
    proposalStatus[_proposalHash] = ProposalStatus.PENDING;

    // log the proposal submission
    emit ProposalSubmitted(_operations, _descriptionHash, _proposalHash, msg.sender);
  }

  /**
   * @dev Derive the dynamic threshold for a given hat supply.
   * @param _hatSupply The hat supply.
   * @return threshold The current threshold.
   */
  function _getThreshold(uint256 _hatSupply) internal view returns (uint256 threshold) {
    (uint256 min, uint256 max) = THRESHOLD_RANGE();

    if (_hatSupply < min) return min;
    if (_hatSupply > max) return max;
    return _hatSupply;
  }

  /**
   * @dev Checks whether a proposal is executable now, and reverts if not. A proposal is executable if:
   *   1. It is pending
   *   2. Has at least [threshold] approvals from valid signers
   * @param _proposalHash The hash of the proposal operations and description, used to identify the proposal
   * @param _voters The addresses of the voters to check for approval votes
   * @return executable Whether the proposal is executable now
   */
  function _checkExecutableNow(bytes32 _proposalHash, address[] calldata _voters)
    internal
    view
    returns (bool executable)
  {
    // proposal must be pending
    if (proposalStatus[_proposalHash] != ProposalStatus.PENDING) revert ProposalNotPending();

    // get the current threshold
    uint256 threshold = getThreshold();

    // if _voters array isn't long enough, we know there aren't enough approvals
    if (_voters.length < threshold) revert InsufficientApprovals();

    // loop through the voters, tallying the approvals from valid signers
    uint256 validApprovals;
    for (uint256 i; i < _voters.length;) {
      unchecked {
        // TODO optimize
        if (votes[_proposalHash][_voters[i]] == Vote.APPROVE && _isValidSigner(_voters[i])) {
          // Should not overflow within the gas limit
          ++validApprovals;
        }

        // once we have enough approvals, the proposal is executable
        if (validApprovals >= threshold) return true;

        // Should not overflow given the loop condition
        ++i;
      }
    }

    // if we didn't get enough approvals, the proposal is not executable
    revert InsufficientApprovals();
  }

  /**
   * @dev Checks whether a proposal is rejectable now, and reverts if not. A proposal is rejectable if:
   *   1. It is pending
   *   2. Has at least [hatSupply - threshold] rejections from valid signers
   * @param _proposalHash The hash of the proposal operations and description, used to identify the proposal
   * @param _voters The addresses of the voters to check for rejection votes
   * @return rejectable Whether the proposal is rejectable now
   */
  function _checkRejectableNow(bytes32 _proposalHash, address[] calldata _voters)
    internal
    view
    returns (bool rejectable)
  {
    // proposal must be pending
    if (proposalStatus[_proposalHash] != ProposalStatus.PENDING) revert ProposalNotPending();

    // the number of rejections required to reject the proposal is the inverse of the current threshold
    uint256 hatSupply = HATS().hatSupply(hat());
    uint256 rejectionThreshold = hatSupply - _getThreshold(hatSupply);

    // if _voters array isn't long enough, we know there aren't enough rejections
    if (_voters.length < rejectionThreshold) revert InsufficientRejections(); // optimization: remove?

    // loop through the voters, tallying the rejections from valid signers
    uint256 rejections;
    for (uint256 i; i < _voters.length;) {
      unchecked {
        if (votes[_proposalHash][_voters[i]] == Vote.REJECT && _isValidSigner(_voters[i])) {
          // Should not overflow within the gas limit
          ++rejections;
        }

        // once we have enough rejections, the proposal is rejectable
        if (rejections >= rejectionThreshold) return true;

        // Should not overflow given the loop condition
        ++i;
      }
    }

    // if we didn't get enough rejections, the proposal is not rejectable
    revert InsufficientRejections();
  }
}
