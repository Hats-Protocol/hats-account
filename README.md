# HatsAccount

HatsAccount is a smart contract account for every hat in [Hats Protocol](https://github.com/Hats-Protocol/hats-protocol).

This repo contains three contracts:

1. [HatsAccountBase](#HatsAccountbase), an abstract contract designed to be inherited by various flavors of HatsAccount
2. [HatsAccount1ofN](#HatsAccount1ofn), a flavor of HatsAccount that mirrors the typical 1-of-n security model of hat-based role and permission management
3. [HatsAccountMofN](#HatsAccountmofn), a flavor of HatsAccount that supports m-of-n security models, somewhat like a multisig of hat wearers

## Overview

HatsAccount gives every Hats Protocol hat a smart contract account. Each hat can have multiple flavors of HatsAccount, each following the ERC6551 standard and designed to be deployed via the ERC6551Registry factory.

HatsAccount gives every hat the ability to do the following:

- Send ETH, ERC20, ERC721, and ERC1155 tokens
- Sign ERC1271-compatible messages, e.g. as a signer on a multisig
- Become a member of a DAO and make/vote on proposals, e.g. in a Moloch DAO
- Call functions on other contracts
- `Delegatecall` to other contracts, via [tokenbound](https://github.com/tokenbound/contracts)'s [sandbox](https://github.com/jaydenwindle/delegatecall-sandbox/) concept
- Be assigned permissions in address-based onchain access control schemes

Apart from the first and last, all of these actions are performed by the hat's wearer(s), with the security model determined by the flavor of HatsAccount.

## HatsAccountBase

HatsAccountBase is an abstract contract built with [tokenbound's library](https://github.com/tokenbound/contracts)  that provides the following common functionality for all other HatsAccount flavors:

- Ability to receive ETH (or other EVM chain-native tokens), ERC20, ERC721, and ERC1155 tokens
- Implementation of the `IERC6551Account` interface, including / as well as getter functions for the account deployment parameters
  - `salt()`
  - `HATS()` — the address of the Hats Protocol contract, aka the `IERC6551Account.token.tokenContract`
  - `hat()` — the id of the hat that this HatsAccount represents, aka the `IERC6551Account.token.tokenId`
  - `IMPLEMENTATION()` — the address of the implementation contract for the inheriting flavor of HatsAccount
- Implementation of `IERC6551Account.isValidSigner` that sets wearers of the `hat()` as valid signers
- Internal `_updateState` function adhering to the `IERC6551Account` standard
- EIP-721-compliant message-hashing function for use in signing and verifying messages by inheriting HatsAccount flavors
- [tokenbound](https://github.com/tokenbound/contracts)'s `BaseExecutor`, for use in executing transactions by inheriting HatsAccount flavors

### Delegatecalls

For safety, HatsAccountBase constrains `delegatecall`s, only executing them from a special sandbox account coupled with the HatsAccount1ofN instance. This protects the HatsAccount from storage collision and self-destruct from malicious target contracts, with the tradeoff that the target contract must know — or be told about — the sandbox pattern in order for the `delegatecall` to succeed.

See the [delegatecall-sandbox docs](https://github.com/jaydenwindle/delegatecall-sandbox/) for more details.

## HatsAccount1ofN

HatsAccount1ofN is a flavor of HatsAccount that mirrors the typical 1-of-n security model of hat-based role and permission management. Any single wearer of a HatsAccount1ofN instance's hat has full control over that HatsAccount. If a hat has multiple wearers, they each individually have full control.

### 1ofN: Executing Transactions

Any single wearer of the hat can execute transactions under the hat's authority. For individual transactions, this is done by calling the `execute()` function, which conforms to the `ERC6551Executable` interface and takes the following arguments:

- `to` — the address of the contract to call
- `value` — the amount of ETH to send with the call
- `data` — the calldata to send with the call, which encodes the target function signature and arguments
- `operation` — the type of call to make, either `call` (0), or `delegatecall` (1) — other operations are disallowed

For multiple transactions, this is done by calling the `executeBatch()` function, which takes as its sole argument an array of `Operations`. An `Operation` is a struct containing the same properties as the arguments of the `execute()` function above.

If execution succeeds, the HatsAccount's `state` is updated in compliance with the ERC6551 standard.

### 1ofN: Signing Messages

Any single wearer of the hat can also sign messages on the hat's behalf. Other applications or contracts can verify that such signatures are valid by calling the `isValidSignature()` function, which takes the following arguments:

- `hash` — the keccak256 hash of the signed message, which can optionally be calculated with the `HatsAccountBase.getMessageHash()` function for compatibility with EIP-712.
- `signature` — the signature to verify

The signature is considered valid as long as it is either...

- a valid ECDSA signature by a wearer of the hat, or
- a valid EIP-1271 signature by a wearer of the hat

This design follows [Gnosis Mech](https://github.com/gnosis/mech)'s approach, and creates flexibility for recursive validation of nested signatures. See [their docs for more details](https://github.com/gnosis/mech/tree/main#eip-1271-signatures).

## HatsAccountMofN

HatsAccountMofN is a flavor of HatsAccount that supports m-of-n security models, somewhat like a multisig of hat wearers. To take any action with HatsAccount, m of the n present wearers of the hat must approve the action.

### M of N Security Model

The specific security model of a given HatsAccountMofN instance is determined by a) the number of present wearers of the hat (ie the hat's supply), and b) the `THRESHOLD_RANGE` configured for that instance. As the supply of the hat changes, the required number of approvals to execute actions — given by `getThreshold()` — will move within the `THRESHOLD_RANGE`.

These parameters are encoded at deployment time in the `salt` parameter of the `IERC6551Registry.deployAccount` function.

- `MIN_THRESHOLD` — the first (leftmost) byte of the `salt` parameter
- `MAX_THRESHOLD` — the second byte of the `salt` parameter

For example, a `MIN_THRESHOLD` of 2 and a `MAX_THRESHOLD` of 5 would result in a `salt` value of `0x0205000000000000000000000000000000000000000000000000000000000000`. The actual threshold at any given time — the value returned by `getThreshold()` — is a function of the hat's present supply:

- When supply is less than `MIN_THRESHOLD`, the threshold is `MIN_THRESHOLD`
- When supply is greater than `MAX_THRESHOLD`, the threshold is `MAX_THRESHOLD`
- When supply is between `MIN_THRESHOLD` and `MAX_THRESHOLD`, the threshold is the supply

### MofN: Executing Transactions

M of the n wearers of the hat can execute transactions under the hat's authority. This is done with a simple onchain proposal and voting system:

- Any wearer of the hat can propose a transaction
- Any account can vote on a proposal, but only votes from wearers of the at *at execution time* count
- Like a multisig, there is no voting period — a proposal can be executed as soon as it has enough approvals
- Unlike some multisig and DAO contracts, proposals can be executed in any order

#### Proposing Transactions

Any wearer of the hat can propose a transaction by calling the `propose()` function, which takes the following arguments:

- `operations` — an array of `Operations`, the same struct used in [`HatsAccount1ofN.executeBatch()`](#1ofn-executing-transactions)
- `expiration` — a uint32 timestamp after which the proposal will be not be executable even if it has enough approvals, similar to how [MolochV3](https://github.com/HausDAO/Baal/) handles proposal expiration.
- `descriptionHash` — a bytes32 hash of the proposal description, similar to Governor's descriptionHash parameter. Beyond a commitment to a human-readable description, this can be used to make otherwise-identical proposals unique by including a small change in the description.

Proposers also have the option to submit an approval vote with their proposal, by calling the `proposeWithApproval()` function.

##### Proposal Ids and Storage

Unlike some multisig and DAO contracts, HatsAccountMofN proposals can be executed in any order. There is no voting period, proposals can be executed as soon as they have enough approvals, and proposal ids are not sequential.

Proposal ids are bytes32 values derived from the proposal's `operations`, `expiration`, and `descriptionHash` parameters.

For gas-efficiency, the only data stored in contract state for each proposal is a) a mapping between the proposal's id and its current status, and b) a mapping between the proposal's id, the accounts who have [voted](#voting-on-proposals) on it, and those votes. To ensure that the `expiration` parameter can be read without having to store it separately, the expiration timestamp is encoded in the proposal id.

Proposal ids are generated via the `getProposalId()` function, which is defined as follows:

1. Hash together the operations array and the description hash
2. Shift the resulting value 32 bits to the left to truncate the most significant 8 bytes and open up the least significant 8 bytes
3. Insert the expiration into the empty least significant 8 bytes with bitwise OR
4. Cast the resulting value to bytes32

The result is a bytes32 of the form `0x[A][B]`, where:

- `[A]` is the truncated hash of the operations array and the description hash, occupying the first 24 bytes
- `[B]` is the expiration timestamp, occupying the last 8 bytes

`[A]` has 4 more bytes of entropy than Ethereum addresses, so we can be confident that the ids of different proposals ids will not collide.

##### Proposal Status

Proposals can have one of five statuses:

0. NULL — the proposal does not exist
1. PENDING — the proposal has been created, but has not yet been executed
2. EXECUTED — the proposal has been executed
3. REJECTED — the proposal has been rejected
4. EXPIRED — the proposal has expired

Note that the statuses 0-3 are stored onchain in the `proposalStatuses` mapping, while the EXPIRED status is not. This is because the EXPIRED status is a function of the proposal's expiration timestamp, which is [encoded in the proposal id](#proposal-ids-and-storage).

A proposal can be considered EXPIRED if its stored status is PENDING and its expiration timestamp is in the past.

#### Voting on Proposals

Any account can vote on any PENDING proposal. Since signer validity — i.e. hat-wearing — is checked at execution time, there's no need to check it at voting time.

Voters can cast either APPROVE or REJECT votes, and can change their votes at any time prior to execution. Votes are cast by calling the `vote()` function, which takes the following arguments:

- `proposalId` — the id of the proposal to vote on
- `vote` — the vote to cast, either* APPROVE (1) or REJECT (2)

*Note that the `Vote` enum also includes a NULL (0) value, which is the default. To remove an existing vote, voters can cast a NULL vote.

#### Executing Proposals

Any account can execute any PENDING, non-expired proposal that has [enough approvals](#m-of-n-security-model). This is done by calling the `execute()` function, which takes the following arguments:

- `operations` — an array of `Operations`
- `expiration` — the expiration timestamp of the proposal
- `descriptionHash` — the description hash of the proposal
- `voters` — an array of addresses that have voted to approve the proposal. The array must be strictly sorted in ascending order with no duplicates to ensure that votes are not double-counted. Its length must be greater than or equal to the threshold.

The `execute()` function checks each of the voters in the `voters` array to ensure that they are wearers of the hat. If they are, and they voted to APPROVE for the proposalId derived from the other parameters, their vote is counted. If they are not, their vote is ignored. If the number of counted votes is greater than or equal to the [threshold](#m-of-n-security-model), the proposal is executed.

Since `operations` is an array of `Operations`, each operation must succeed for execution to succeed. Any reverting operation will cause the entire execution to revert. Execution can be attempted again until the proposal expires.

#### Rejecting Proposals

For a proposal to be rejectable, it must receive enough REJECT votes such that the proposal could not be executed without a rejector changing their vote to APPROVE. This is different than other multisigs — which typically enforce the same threshold for approval and rejection — since HatsAccountMofN proposals can be executed in any order.

The primary reason to reject a proposal is to clear it from the list of PENDING proposals in front end applications. Note that rejecting a proposal does not prevent the same proposal from being re-proposed and executed.

Any account can reject any PENDING, non-expired proposal that has enough rejections. This is done by calling the `reject()` function, which takes the following arguments:

- `proposalId`
- `voters` — an array of addresses that have voted to reject the proposal. The array must be strictly sorted in ascending order with no duplicates to ensure that votes are not double-counted. Its length must be greater than or equal to the rejection threshold.

The `reject()` function checks each of the voters in the `voters` array to ensure that they are wearers of the hat. If they are, and they voted to REJECT, their vote is counted. If they are not, their vote is ignored. If the number of counted votes is greater than or equal to the rejection threshold — given by `getRejectionThreshold()`, the proposal is rejected.

#### Front End Helpers

The following view functions are provided to help front end applications manage and display accurate information about proposals:

- `getProposalId()` - see [Proposal Ids and Storage](#proposal-ids-and-storage)
- `getThreshold()` - see [M of N Security Model](#m-of-n-security-model)
- `getRejectionThreshold()` - see [Rejecting Proposals](#rejecting-proposals)
- `getExpiration()` - extracts the expiration timestamp of a proposal from the last 8 bytes of its id
- `isExecutableNow()` — returns true if the proposal is PENDING and has enough valid approvals, otherwise reverts
- `isRejectableNow()` — returns true if the proposal is PENDING and has enough valid rejections, otherwise reverts
- `validVoteCountsNow()` — returns the number of valid approvals and rejections for the proposal

### MofN: Signing Messages

HatsAccount1ofN can produce valid EIP-1271 signatures on the hat's behalf, but the process is different from HatsAccount1ofN. Instead of a valid signer — i.e. hat-wearer — producing a cryptographic signature of the message, HatsAccountMofN marks a message as "signed" by adding the message's hash to a list of signed messages.

This can be done by executing a proposal which calls the `HatsAccountMofN.sign()` function. This function is only callable by the HatsAccountMofN instance itself, and takes a single argument: `message` — the bytes of the message itself, of arbitrary length.

When called, the `sign()` function gets the hash of the message and marks it as signed in the `signedMessages` mapping.

#### Message Hashing

In HatsAccount, messages are hashed following the EIP-712 standard with a design similar to [Safe's message hashing scheme](https://github.com/safe-global/safe-contracts/blob/f03dfae65fd1d085224b00a10755c509a4eaacfe/contracts/libraries/SignMessageLib.sol#L33).

When signing a message, `sign()` takes care of the hashing. When verifying a signature via `IERC1271.isValidSignature()`, the message must be hashed by the caller. For convenience, HatsAccountMofN exposes the `getMessageHash()` function.

## Development and Testing

This repo uses Foundry for development and testing. To build, test, and deploy: fork the repo and then follow these steps.

1. Install Foundry
2. Install dependencies: `forge install`
3. Build: `forge build`
4. Test: `forge test`
5. Deploy: see the [deployment script](./script/HatsAccount.s.sol)
