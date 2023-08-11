# HatsWallet

HatsWallet is a smart contract account for every hat in Hats Protocol.

## Overview

HatsWallet gives a smart contract account to every hat in Hats Protocol. The contract follows the ERC6551 standard and is designed to be deployed via the ERC6551Registry factory. 

Every hat gets its own instance of HatsWallet, which enables the hat itself — or its current wearer(s) — to receive and send assets (including funds and NFTs), call functions on other contracts, and sign ERC12721-compatible messages.

Additionally, since it gives every hat an *address*, HatsWallet also serves as an adapter between Hats Protocol's token-based role and permission management system and many other protocol's address-based permissioning.

## Development and Testing

This repo uses Foundry for development and testing. To build, test, and deploy: fork the repo and then follow these steps.

1. Install Foundry
2. Install dependencies: `forge install`
3. Build: `forge build`
4. Test: `forge test`
5. Deploy: see the [deployment script](./script/HatsWallet.s.sol)