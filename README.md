# HatsWallet

This is an ETH Tokyo hackathon repo for HatsWallet, a smart contract wallet for Hats in Hats Protocol.

## Overview

HatsWallet creates a smart contract wallet for any/each Hat in Hats Protocol. The wallet is a flavor of [Gnosis Mech](https://github.com/gnosis/mech), which defines a valid `operator` as an account that "wears" the Hat for which the HatsWallet has been configured.

Such operators can then, via the wallet, execute transactions — via `HatsWallet.exec()` — as well as sign EIP1271-compatible messages.

### Factory

HatsWallets for each Hat are created via a factory contract, `HatsWalletFactory`, which deploys a new HatsWallet for each Hat at a deterministic address based on the Hat id and chain id. This allows for counterfactual usage of HatsWallets.

## Usage

The main repo for Gnosis Mech uses hardhat, while Hats Protocol and other contracts are typically built with Foundry. We ran into import challenges when initially trying to use these two tools together, so we forked the contracts directory in the Mech repo to create a [Foundry-based version](https://github.com/hats-protocol/foundry-mech) that was more easily compatible with Foundry.

To build, test, and deploy: fork the repo and then follow these steps.

1. Install Foundry
2. Install dependencies: `forge install`
3. Build: `forge build`
4. Test: `forge test`
5. Deploy: see the [deployment script](./script/HatsWallet.s.sol)

## Current Deployments

The hackathon version of HatsWallet is deployed to Gnosis Chain, Polygon, and the Alfajores Celo testnet at the following addresses...

- implementation: `0x761417B02a5406Ff4e692bC9aB04A7e66C2f5d0a`
- factory: `0x6FE23eEe15eB5aB6Cb6c4D1C6A769e49368cE739`
