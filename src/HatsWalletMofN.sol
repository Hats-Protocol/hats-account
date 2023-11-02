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
  // bytes32 descriptionHash;
  uint128 status; // 0 = non-existent, 1 = pending, 2 = executed, 3 = cancelled
}

// TODO natspec
contract HatsWalletMOfN is HatsWalletBase {
  /*//////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @param proposer The address of the HatsWallet signer who proposed the tx and cast a yes vote.
  event ProposalSubmitted(
    address to,
    uint256 value,
    bytes data,
    uint256 operation,
    bytes32 descriptionHash,
    bytes32 proposalHash,
    address proposer
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

  enum ProposalStatus {
    NON_EXISTENT, // 0
    PENDING, // 1
    EXECUTED, // 2
    CANCELLED // 3
  }

  uint256 internal constant APPROVE = 1;
  // uint256 internal constant REJECT = 2+ ;

  /*//////////////////////////////////////////////////////////////
                          MUTABLE STORAGE
  //////////////////////////////////////////////////////////////*/

  uint128 public contractNonce;

  // proposals tracking
  mapping(bytes32 proposalHash => ProposalStatus) public proposalStatus;
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

  function propose(address _to, uint256 _value, bytes calldata _data, uint256 _operation, bytes32 _descriptionHash)
    external
    returns (bytes32 proposalHash)
  {
    // get the proposal hash
    proposalHash = getProposalHash(_to, _value, _data, _operation, _descriptionHash);

    // revert if the proposal already exists
    if (proposalStatus[proposalHash] > ProposalStatus.NON_EXISTENT) revert ProposalAlreadyExists();

    // record the proposal status in storage
    proposalStatus[proposalHash] = ProposalStatus.PENDING;
    votes[proposalHash][msg.sender] = APPROVE;

    // log the proposal
    emit ProposalSubmitted(_to, _value, _data, _operation, _descriptionHash, proposalHash, msg.sender);
  }

  function vote(bytes32 _proposalHash, uint256 _vote) external {
    // proposal must be pending
    if (proposalStatus[_proposalHash] != ProposalStatus.PENDING) revert ProposalNotPending();

    // record the vote in HatsWalletStorage
    votes[_proposalHash][msg.sender] = _vote;

    emit VoteCast(_proposalHash, msg.sender, _vote);
  }

  // TODO batch actions
  function execute(
    address _to,
    uint256 _value,
    bytes calldata _data,
    uint256 _operation,
    bytes32 _descriptionHash,
    address[] calldata _voters
  ) external payable returns (bytes memory result) {
    // validate the voters and their approvals of this proposed tx
    if (!canExecute(getProposalHash(_to, _value, _data, _operation, _descriptionHash), _voters)) {
      revert InvalidSigner();
    }

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
    // proposal must be pending
    if (proposalStatus[_proposalHash] != ProposalStatus.PENDING) revert ProposalNotPending();

    uint256 hatSupply = HATS().hatSupply(hat());
    uint256 inverseThreshold = hatSupply - _getThreshold(HATS().hatSupply(hat()));

    if (_voters.length < inverseThreshold) revert NotEnoughRejections(); // optimization: remove?

    uint256 rejections;

    for (uint256 i; i < _voters.length;) {
      unchecked {
        if (votes[_proposalHash][_voters[i]] > 1) ++rejections;

        if (rejections >= inverseThreshold) break;

        ++i;
      }
    }

    if (rejections < inverseThreshold) revert NotEnoughRejections();

    // record the cancellation in HatsWalletStorage
    proposalStatus[_proposalHash] = ProposalStatus.CANCELLED;

    emit ProposalCancelled(_proposalHash);
  }

  function canExecute(bytes32 _proposalHash, address[] calldata _voters) public view returns (bool) {
    if (proposalStatus[_proposalHash] != ProposalStatus.PENDING) return false;

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

  function getProposalHash(
    address _to,
    uint256 _value,
    bytes calldata _data,
    uint256 _operation,
    bytes32 _descriptionHash
  ) public pure returns (bytes32) {
    return keccak256(abi.encode(_to, _value, _data, _operation, _descriptionHash));
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
