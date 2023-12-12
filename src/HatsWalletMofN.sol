// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console2, Test } from "forge-std/Test.sol"; // remove before deploy
import "./lib/HatsWalletErrors.sol";
import { HatsWalletBase } from "./HatsWalletBase.sol";
import { LibHatsWallet, Operation, ProposalStatus, Vote } from "./lib/LibHatsWallet.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";

/**
 * @title HatsWalletMofN
 * @author Haberdasher Labs
 * @author spengrah
 * @notice A HatsWallet implementation that requires m votes by valid signers — ie wearers of
 * the hat — to execute a transaction. The threshold is derived dynamically as a factor of the wallet's configured
 * min- and max-threshold and the current supply of the hat. Transactions are queued via onchain proposal, and valid
 * signers vote onchain to approve or reject the proposal. Valid signers can also approve messages as "signed" by the
 * wallet, which can be used to create a ERC-1271 contract signature.
 */
contract HatsWalletMofN is HatsWalletBase {
  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event ProposalSubmitted(
    Operation[] operations, uint32 expiration, bytes32 descriptionHash, bytes32 proposalId, address proposer
  );

  event VoteCast(bytes32 proposalId, address voter, Vote vote);

  event ProposalExecuted(bytes32 proposalId);

  event ProposalRejected(bytes32 proposalId);

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

  /// @notice The status of a proposal, indexed by its id
  mapping(bytes32 proposalId => ProposalStatus) public proposalStatus;

  /// @notice The votes on a proposal, indexed by its id and the voter's address
  mapping(bytes32 proposalId => mapping(address voter => Vote vote)) public votes;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(string memory _version) HatsWalletBase(_version) { }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Propose a tx to be executed by this HatsWallet. The caller must be a valid signer for this HatsWallet.
   * @dev Even though signer validity is also checked at execution time, we check it here to prevent spam and DoS
   * attacks.
   * @param _operations Array of operations to be executed by this HatsWallet. Only call and delegatecall are supported.
   * Delegatecalls are routed through the sandbox.
   * @param _expiration The timestamp after which the proposal will be expired and no longer executable. If zero, the
   * proposal will never expire.
   * @param _descriptionHash Hash of the description of the tx to be executed. Can be used to create a unique
   * proposalId when the same operations are proposed multiple times.
   * @return proposalId The unique id of the proposal
   */
  function propose(Operation[] calldata _operations, uint32 _expiration, bytes32 _descriptionHash)
    external
    returns (bytes32 proposalId)
  {
    // submit the proposal and log it, reverting if the proposal already exists
    return _propose(_operations, _expiration, _descriptionHash);
  }

  /**
   * @notice Propose a tx to be executed by this HatsWallet along with a vote to approve.
   * @dev Even though signer validity is also checked at execution time, we check it here to prevent spam and DoS
   * attacks.
   * @param _operations Array of operations to be executed by this HatsWallet. Only call and delegatecall are supported.
   * Delegatecalls are routed through the sandbox.
   * @param _expiration The timestamp after which the proposal will be expired and no longer executable. If zero, the
   * proposal will never expire.
   * @param _descriptionHash Hash of the description of the tx to be executed. Can be used to create a unique
   * proposalId when the same operations are proposed multiple times.
   * @return proposalId The unique id of the proposal
   */
  function proposeWithApproval(Operation[] calldata _operations, uint32 _expiration, bytes32 _descriptionHash)
    external
    returns (bytes32 proposalId)
  {
    // submit the proposal and log it, reverting if the proposal already exists
    proposalId = _propose(_operations, _expiration, _descriptionHash);

    // record the proposer's approval vote and log it
    _unsafeVote(proposalId, Vote.APPROVE);
  }

  /**
   * @notice Cast a vote on a pending proposal.
   * @dev Voters can change their votes by calling this function again with a different vote. Voters need not be valid
   * signers, since signer validity is checked at execution time.
   * @param _proposalId The unique id of the proposal
   * @param _vote The vote to cast. 1 = APPROVE, 2 = REJECT
   */
  function vote(bytes32 _proposalId, Vote _vote) external {
    // proposal must be pending
    if (proposalStatus[_proposalId] != ProposalStatus.PENDING) revert ProposalNotPending();

    // record and log the vote
    _unsafeVote(_proposalId, _vote);
  }

  /**
   * @notice Execute a pending proposal. If enough valid signers have voted to approve the proposal, it will be
   * executed.
   * @dev Checks signer validity.
   * @param _operations Array of operations to be executed by this HatsWallet. Only call and delegatecall are supported.
   * Delegatecalls are routed through the sandbox.
   * @param _expiration The timestamp after which the proposal will be expired and no longer executable.
   * @param _descriptionHash Hash of the description of the tx to be executed.
   * @param _voters The addresses of the voters to check for approval votes
   * @return results The results of the operations
   */
  function execute(
    Operation[] calldata _operations,
    uint32 _expiration,
    bytes32 _descriptionHash,
    address[] calldata _voters
  ) external payable returns (bytes[] memory) {
    // get the proposal hash
    bytes32 proposalId = getProposalId(_operations, _expiration, _descriptionHash);

    // validate the voters and their approvals of this proposed tx
    _checkExecutableNow(proposalId, _voters);

    // increment the state var
    _beforeExecute();

    // set the proposal status to executed
    proposalStatus[proposalId] = ProposalStatus.EXECUTED;

    // loop through the operations and execute them, storing the bubbled-up results in an array
    uint256 length = _operations.length;
    bytes[] memory results = new bytes[](length);

    for (uint256 i = 0; i < length; i++) {
      results[i] =
        LibHatsWallet._execute(_operations[i].to, _operations[i].value, _operations[i].data, _operations[i].operation);
    }

    // log the proposal execution
    emit ProposalExecuted(proposalId);

    // return the bubbled-up results
    return results;
  }

  /**
   * @notice Reject a pending proposal. If enough valid signers have voted to reject the proposal, the rejection will be
   * recorded.
   * @dev Checks signer validity.
   * @param _proposalId The unique id of the proposal
   * @param _voters The addresses of the voters to check for rejection votes
   */
  function reject(bytes32 _proposalId, address[] calldata _voters) external {
    // validate the voters and their rejections of this proposed tx
    _checkRejectableNow(_proposalId, _voters);

    // set the proposal status to rejected
    proposalStatus[_proposalId] = ProposalStatus.REJECTED;

    // log the proposal rejection
    emit ProposalRejected(_proposalId);
  }

  // TODO enable HatsWalletMOfN to create a contract signature

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Derive the proposal id as a hash of the operations and description hash
   * @param operations Array of operations to be executed by this HatsWallet.
   * @param _expiration The timestamp after which the proposal will be expired and no longer executable.
   * @param _descriptionHash Hash of the description of the tx to be executed.
   * @return proposalId The unique id of the proposal
   */
  function getProposalId(Operation[] calldata operations, uint32 _expiration, bytes32 _descriptionHash)
    public
    pure
    returns (bytes32 proposalId)
  {
    /**
     * Steps to derive the proposalId:
     *     1. Hash together the operations array and the description hash
     *     2. Shift the resulting value 32 bits to the left to truncate the most significant 8 bytes and open up the
     * least significant 8 bytes
     *     3. Insert the expiration into the empty least significant 8 bytes with bitwise OR
     *     4. Cast the resulting value to bytes32
     */
    return bytes32((uint256(keccak256(abi.encode(operations, _descriptionHash))) << 32) | uint256(_expiration));
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
   * @notice Get the expiration timestamp for a given proposalId.
   * @dev The expiration is stored in the least significant 32 bits of the proposalId.
   * @param _proposalId The unique id of the proposal
   * @return expiration The expiration timestamp, encoded as uint256 for easy comparison with block.timestamp
   */
  function getExpiration(bytes32 _proposalId) public pure returns (uint256 expiration) {
    return uint256(uint32(uint256(_proposalId)));
  }

  /**
   * @notice Derive the rejection threshold, which is the inverse of the current threshold.
   * @return rejectionThreshold The current rejection threshold.
   */
  function getRejectionThreshold() public view returns (uint256 rejectionThreshold) {
    uint256 hatSupply = HATS().hatSupply(hat());
    return hatSupply - _getThreshold(hatSupply);
  }

  /**
   * @notice Returns whether a proposal is executable now, reverts if not. A proposal is executable if:
   *   1. It is pending
   *   2. Has at least *threshold* approvals from valid signers
   * @param _proposalId The unique id of the proposal
   * @param _voters The addresses of the voters to check for approval votes
   * @return Whether the proposal is executable
   */
  function isExecutableNow(bytes32 _proposalId, address[] calldata _voters) external view returns (bool) {
    _checkExecutableNow(_proposalId, _voters);
    return true;
  }

  /**
   * @notice Returns whether a proposal is rejectable now, reverts if not. A proposal is rejectable if:
   *   1. It is pending
   *   2. Has at least *threshold* rejections from valid signers
   * @param _proposalId The unique id of the proposal
   * @param _voters The addresses of the voters to check for rejection votes
   * @return Whether the proposal is rejectable
   */
  function isRejectableNow(bytes32 _proposalId, address[] calldata _voters) external view returns (bool) {
    return _checkRejectableNow(_proposalId, _voters);
  }

  /**
   * @notice Returns the current number of approvals and rejections for a proposal as a convenience for clients.
   * @param _proposalId The unique id of the proposal
   * @param _voters The addresses of the voters to check for votes
   * @return approvals The number of valid approval votes
   * @return rejections The number of valid rejection votes
   */
  function validVoteCountsNow(bytes32 _proposalId, address[] calldata _voters)
    external
    view
    returns (uint256 approvals, uint256 rejections)
  {
    for (uint256 i; i < _voters.length;) {
      unchecked {
        if (votes[_proposalId][_voters[i]] == Vote.APPROVE && _isValidSigner(_voters[i])) {
          // Should not overflow within the gas limit
          ++approvals;
        }

        if (votes[_proposalId][_voters[i]] == Vote.REJECT && _isValidSigner(_voters[i])) {
          // Should not overflow within the gas limit
          ++rejections;
        }

        // Should not overflow given the loop condition
        ++i;
      }
    }
  }

  /// @inheritdoc HatsWalletBase
  function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
    return (interfaceId == type(IERC1271).interfaceId || super.supportsInterface(interfaceId));
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Set the status of a proposal to pending and log the proposal submission.
   * @dev Reverts if the proposal already exists or if the caller is not a valid signer. Even though signer validity is
   * also checked at execution time, we check it here to prevent spam and DoS attacks.
   * @param _operations Array of operations to be executed by this HatsWallet. Only call and delegatecall are supported.
   * Delegatecalls are routed through the sandbox.
   * @param _expiration The timestamp after which the proposal will be expired and no longer executable. If zero, the
   * proposal will never expire.
   * @param _descriptionHash Hash of the description of the tx to be executed. Can be used to create a unique
   * @return proposalId The unique id of the proposal
   */
  function _propose(Operation[] calldata _operations, uint32 _expiration, bytes32 _descriptionHash)
    internal
    returns (bytes32 proposalId)
  {
    // caller must be a valid signer
    if (!_isValidSigner(msg.sender)) revert InvalidSigner();

    // get the proposal hash
    proposalId = getProposalId(_operations, _expiration, _descriptionHash);

    // revert if the proposal already exists
    if (proposalStatus[proposalId] > ProposalStatus.NULL) revert ProposalAlreadyExists();

    // set the proposal status to pending
    proposalStatus[proposalId] = ProposalStatus.PENDING;

    // log the proposal submission
    emit ProposalSubmitted(_operations, _expiration, _descriptionHash, proposalId, msg.sender);
  }

  /**
   * @dev Records a vote on a proposal and logs it. Does not check whether the proposal is executable or rejectable.
   * @param _proposalId The unique id of the proposal
   * @param _vote The vote to record. 1 = APPROVE, 2 = REJECT
   */
  function _unsafeVote(bytes32 _proposalId, Vote _vote) internal {
    // record the vote
    votes[_proposalId][msg.sender] = _vote;

    // log the vote
    emit VoteCast(_proposalId, msg.sender, _vote);
  }

  function _isValidSignature(bytes32 _hash, bytes calldata _signature) internal view override returns (bool) {
    // TODO
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
   *   1. It has not expired
   *   2. It is pending
   *   3. Has at least [threshold] approvals from valid signers
   * @param _proposalId The unique id of the proposal
   * @param _voters The addresses of the voters to check for approval votes
   * @return executable Whether the proposal is executable now
   */
  function _checkExecutableNow(bytes32 _proposalId, address[] calldata _voters) internal view returns (bool) {
    // proposal must not be expired. If the expiration is zero, the proposal has no expiration.
    uint256 expiration = getExpiration(_proposalId);
    if (expiration > 0 && expiration < block.timestamp) revert ProposalExpired();

    // proposal must be pending
    if (proposalStatus[_proposalId] != ProposalStatus.PENDING) revert ProposalNotPending();

    // get the current threshold
    uint256 threshold = getThreshold();

    _checkValidVotes(_proposalId, _voters, Vote.APPROVE, threshold);

    return true;
  }

  /**
   * @dev Checks whether a proposal is rejectable now, and reverts if not. A proposal is rejectable if:
   *   1. It is pending
   *   2. Has at least [hatSupply - threshold] rejections from valid signers
   * @param _proposalId The unique id of the proposal
   * @param _voters The addresses of the voters to check for rejection votes
   * @return rejectable Whether the proposal is rejectable now
   */
  function _checkRejectableNow(bytes32 _proposalId, address[] calldata _voters) internal view returns (bool) {
    // proposal must be pending
    if (proposalStatus[_proposalId] != ProposalStatus.PENDING) revert ProposalNotPending();

    // proposal must not be expired

    // the number of rejections required to reject the proposal is the inverse of the current threshold
    // uint256 hatSupply = HATS().hatSupply(hat());
    uint256 rejectionThreshold = getRejectionThreshold();

    _checkValidVotes(_proposalId, _voters, Vote.REJECT, rejectionThreshold);

    return true;
  }

  function _checkValidVotes(bytes32 _proposalId, address[] calldata _voters, Vote _vote, uint256 _threshold)
    internal
    view
  {
    uint256 count;
    address currentVoter;
    address lastVoter;
    for (uint256 i; i < _voters.length;) {
      // cache the current voter
      currentVoter = _voters[i];
      // console2.log("lastVoter", lastVoter);
      // console2.log("currentVoter", currentVoter);
      // console2.log("ascending", currentVoter > lastVoter);

      /**
       * @dev To guarantee that the same voter cannot vote twice, we must ensure that the voters array has no
       * duplicates. The cheapest method is to require that the voters array is a distinctly sorted ascending array.
       * If at any point the lastVoter's address is not numerically greater than the currentVoter's address, we
       * know that the voters array has violated this condition, so we revert.
       */
      if (currentVoter <= lastVoter) revert UnsortedVotersArray();

      unchecked {
        // TODO optimize
        if (votes[_proposalId][currentVoter] == _vote && _isValidSigner(currentVoter)) {
          // Should not overflow within the gas limit
          ++count;
        }

        // once we have enough votes, we stop counting and return
        if (count >= _threshold) return;

        // prepare for the next iteration
        lastVoter = currentVoter;
        ++i; // Should not overflow given the loop condition
      }
    }

    // if we didn't get enough rejections, the proposal is not rejectable
    revert InsufficientValidVotes();
  }
}
