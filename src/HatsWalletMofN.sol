// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2, Test } from "forge-std/Test.sol"; // remove before deploy
import "./HatsWalletErrors.sol";
import { HatsWalletBase } from "./HatsWalletBase.sol";

/*//////////////////////////////////////////////////////////////
                              TYPES
//////////////////////////////////////////////////////////////*/

struct Proposal {
  // address to;
  // uint256 value;
  // bytes data;
  // uint256 operation;
  //
  uint128 nonce;
  // TODO how are we handling nonce?
  uint128 status; // 0 = non-existent, 1 = pending, 2 = executed, 3 = cancelled
}

// TODO natspec
contract HatsWalletMOfN is HatsWalletBase {
  /*//////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @param proposer The address of the HatsWallet signer who proposed the tx and cast a yes vote.
  event ProposalSubmitted(
    address to, uint256 value, bytes data, uint256 operation, bytes32 proposalHash, address proposer
  );

  event VoteCast(bytes32 proposalHash, address voter, uint256 vote);

  event ProposalCancelled(bytes32 proposalHash);

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  function MIN_THRESHOLD() internal view returns (uint256) {
    // derive from {salt}
  }

  function MAX_THRESHOLD() internal view returns (uint256) {
    // derive from {salt}
  }

  uint128 internal constant NON_EXISTENT = 0;
  uint128 internal constant PENDING = 1;
  uint128 internal constant EXECUTED = 2;
  uint128 internal constant CANCELLED = 3;
  uint256 internal constant APPROVE = 1;
  // uint256 internal constant REJECT = 2+ ;

  /*//////////////////////////////////////////////////////////////
                          MUTABLE STORAGE
  //////////////////////////////////////////////////////////////*/

  uint128 public contractNonce;

  // proposals tracking
  mapping(bytes32 proposalHash => Proposal) public proposals;
  mapping(bytes32 proposalHash => mapping(address voter => uint256 vote)) public votes;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(string memory _version) HatsWalletBase(_version) { }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  function setUp() public 
  /**
   * initializer
   */
  { }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function propose(address _to, uint256 _value, bytes calldata _data, uint256 _operation)
    external
    returns (bytes32 proposalHash)
  {
    // TODO what do we do about proposals that are legitimately the same? do we need a nonce of some kind?

    // get the proposal hash
    proposalHash = getProposalHash(_to, _value, _data, _operation);

    // record the proposal in HatsWalletStorage
    recordProposalWithYesVote(proposalHash, msg.sender);

    // TODO bubble up error

    // log the proposal
    emit ProposalSubmitted(_to, _value, _data, _operation, proposalHash, msg.sender);
  }

  function vote(bytes32 _proposalHash, uint256 _vote) external {
    // record the vote in HatsWalletStorage
    recordVote(_proposalHash, msg.sender, _vote);

    // TODO bubble up error

    emit VoteCast(_proposalHash, msg.sender, _vote);
  }

  function execute(address _to, uint256 _value, bytes calldata _data, uint256 _operation, address[] calldata _voters)
    external
    payable
    returns (bytes memory result)
  {
    // validate the voters and their approvals of this proposed tx
    if (!canExecute(getProposalHash(_to, _value, _data, _operation), _voters)) {
      revert InvalidSigner();
    }

    // TODO bubble up error

    // increment the state var
    ++state;

    bool success;

    if (_operation == 0) {
      // call
      (success, result) = _to.call{ value: _value }(_data);
    } else if (_operation == 1) {
      // delegatecall

      // cache a pre-image of the state var
      uint256 _state = state;

      // execute the delegatecall
      (success, result) = _to.delegatecall(_data);

      if (_state != state) {
        // a delegatecall has maliciously changed the state, so we revert
        revert MaliciousStateChange();
      }
    } else {
      // create, create2, or invalid _operation
      revert CallOrDelegatecallOnly();
    }

    // bubble up revert error data
    if (!success) {
      assembly {
        revert(add(result, 32), mload(result))
      }
    }
  }

  function cancel(bytes32 _proposalHash, address[] calldata _voters) external {
    // record the cancellation in HatsWalletStorage
    recordCancellation(_proposalHash, _voters);

    // TODO bubble up error

    emit ProposalCancelled(_proposalHash);
  }

  function recordProposalWithYesVote(bytes32 _proposalHash, address _proposer) public {
    if (proposals[_proposalHash].status > NON_EXISTENT) revert ProposalAlreadyExists();

    proposals[_proposalHash] = Proposal(++contractNonce, PENDING);
    votes[_proposalHash][_proposer] = APPROVE;
  }

  function recordCancellation(bytes32 _proposalHash, address[] calldata _voters) public {
    if (proposals[_proposalHash].status != PENDING) revert ProposalNotPending();

    uint256 hatSupply = HATS().hatSupply(hat());
    uint256 inverseThreshold = hatSupply - _getThreshold(HATS().hatSupply(hat()));

    if (_voters.length < inverseThreshold) revert NotEnoughRejections();

    uint256 rejections;

    for (uint256 i; i < _voters.length;) {
      unchecked {
        if (votes[_proposalHash][_voters[i]] > 1) ++rejections;

        if (rejections >= inverseThreshold) break;
      }
      ++i;
    }

    proposals[_proposalHash].status = CANCELLED;
  }

  function recordVote(bytes32 _proposalHash, address _voter, uint256 _vote) public {
    if (proposals[_proposalHash].status != PENDING) revert ProposalNotPending();

    votes[_proposalHash][_voter] = _vote;
  }

  function canExecute(bytes32 _proposalHash, address[] calldata _voters) public view returns (bool) {
    if (proposals[_proposalHash].status != PENDING) return false;

    uint256 threshold = getThreshold();

    if (_voters.length < threshold) return false;

    uint256 validApprovals;

    for (uint256 i; i < _voters.length;) {
      unchecked {
        // TODO optimize
        if (votes[_proposalHash][_voters[i]] == APPROVE && _isValidSigner(_voters[i])) {
          ++validApprovals;
        }

        if (validApprovals >= threshold) return true;

        ++i;
      }
    }

    return false;
  }

  // TODO add functionality enabling HatsWalletMOfN to create a contract signature

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function getProposalHash(address _to, uint256 _value, bytes calldata _data, uint256 _operation)
    public
    pure
    returns (bytes32)
  {
    return keccak256(abi.encodePacked(_to, _value, _data, _operation));
  }

  /// @notice Derive the dynamic threshold from the current hat supply
  function getThreshold() public view returns (uint256) {
    return _getThreshold(HATS().hatSupply(hat()));
  }

  // /// @inheritdoc HatsWalletBase
  // function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
  //   return super.supportsInterface(interfaceId);
  // }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  function _getThreshold(uint256 _hatSupply) internal view returns (uint256) {
    if (_hatSupply < MIN_THRESHOLD()) {
      return MIN_THRESHOLD();
    } else if (_hatSupply > MAX_THRESHOLD()) {
      return MAX_THRESHOLD();
    } else {
      return _hatSupply;
    }
  }
}
