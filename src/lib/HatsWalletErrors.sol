// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "tokenbound/utils/Errors.sol";

/// @notice Thrown when the caller is not wearing the `hat`
error InvalidSigner();
error NotHatsWallet();
error ProposalAlreadyExists();
error ProposalNotPending();
error ProposalExpired();
error InsufficientValidVotes();
error UnsortedVotersArray();
