// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ProposalStatus, Vote } from "./LibHatsAccount.sol";

contract HatsAccountStorage {
  // HatsAccountBase
  uint256 _state;
  string public version_;

  // HatsAccount1ofN has no additional storage!

  // HatsAccountMofN
  mapping(bytes32 proposalId => ProposalStatus) public proposalStatus;
  mapping(bytes32 proposalId => mapping(address voter => Vote vote)) public votes;
  mapping(bytes32 messageHash => bool signed) public signedMessages;
}
