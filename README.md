# HatsWallet

HatsWallet is a smart contract account for every hat in Hats Protocol.

## Overview

HatsWallet gives every Hats Protocol hat a smart contract account. The contract follows the ERC6551 standard and is designed to be deployed via the ERC6551Registry factory.

Every hat gets its own instance of HatsWallet, which enables the hat itself — or its current wearer(s) — to receive and send assets (including funds and NFTs), call functions on other contracts, and sign ERC12721-compatible messages.

Additionally, since it gives every hat an *address*, HatsWallet also serves as an adapter between Hats Protocol's token-based role and permission management system and many other protocol's address-based permissioning.

### Functionality

With HatsWallet, a hat can do the following:

- Receive ETH, ERC20, ERC721, and ERC1155 tokens
- Send ETH, ERC20, ERC721, and ERC1155 tokens
- Sign ERC1271-compatible messages, e.g. as a signer on a multisig
- Become a member of a DAO and make/vote on proposals, e.g. in a Moloch DAO
- Call functions on other contracts
- `Delegatecall` to other contracts

Apart from the first, all of these actions are performed by the hat's wearer(s).

#### Executing Transactions

Wearer(s) of the hat can execute transactions under the hat's authority. This is done by calling the `execute()` function, which takes the following arguments:

- `_to` — the address of the contract to call
- `_value` — the amount of ETH to send with the call
- `_data` — the calldata to send with the call, which encodes the target function signature and arguments
- `_operation` — the type of call to make, either `call` (0), or `delegatecall` (1)

#### Signing Messages

Wearer(s) of the hat can sign messages on the hat's behalf. Other applications or contracts can verify that such signatures are valid by calling the `isValidSignature()` function, which takes the following arguments:

- `_hash` — the keccak256 hash of the signed message, which could be a transaction hash or a message hash
- `_signature` — the signature to verify

The signature is considered valid if it is a...

- valid ECDSA signature by a wearer of the hat
- valid EIP-1271 signature by a wearer of the hat
- valid EIP-1271 signature by the HatsWallet itself

This design follows [Gnosis Mech](https://github.com/gnosis/mech)'s approach, and creates flexibility for recursive validation of nested signatures. See [their docs for more details](https://github.com/gnosis/mech/tree/main#eip-1271-signatures).

#### Receiving Tokens

HatsWallet implements the ERC721Receiver and ERC1155Receiver interfaces, which allows it to receive ERC721 and ERC1155 tokens sent with SafeTransfer-style functions.

HatsWallet receives ETH via the `receive()` function.

In both cases, HatsWallet simply receives the assets. It performs no additional logic.

### Security Model

Any single wearer of a HatsWallet instance's hat has full control over the HatsWallet. This is a 1-of-n security model. If a hat has multiple wearers, they each individually have full control.

Future versions of HatsWallet may support more complex security models, such as m-of-n.


## Development and Testing

This repo uses Foundry for development and testing. To build, test, and deploy: fork the repo and then follow these steps.

1. Install Foundry
2. Install dependencies: `forge install`
3. Build: `forge build`
4. Test: `forge test`
5. Deploy: see the [deployment script](./script/HatsWallet.s.sol)