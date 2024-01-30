// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "tokenbound/utils/Errors.sol";

/// @notice Thrown when the caller is not wearing the `hat`
error InvalidSigner();

/// @notice Thrown when the caller is not this instance of HatsWallet
error NotHatsWallet();

/// @notice The same exact proposal cannot be submitted twice. Any differences in the proposal parameters —
/// including its operations, expiration, or descriptionHash — will produce a unique proposal.
error ProposalAlreadyExists();

/// @notice Proposals must be in the PENDING state to be voted on or processed (executed or rejected)
error ProposalNotPending();

/// @notice Proposals must not have expired to be executed
error ProposalExpired();

/// @notice Thrown when attempting to process (execute or reject) a proposal with insufficient valid votes (approvals or
/// rejections) to meet the required threshold
error InsufficientValidVotes();

/// @notice Voters must be sorted in ascending order by address
error UnsortedVotersArray();
