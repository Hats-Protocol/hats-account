// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice Thrown when the caller is not wearing the `hat`
error InvalidSigner();

/// @notice Thrown when the {execute} operation is something other than a call or delegatecall
error CallOrDelegatecallOnly();

/// @notice External contracts are not allowed to change the `state` of a HatsWallet
error MaliciousStateChange();

error NotHatsWallet();
error ProposalAlreadyExists();
error ProposalNotPending();
error NotEnoughRejections();
