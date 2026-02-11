# Musical Chairs Smart Contracts

![Game Banner](https://raw.githubusercontent.com/crow-004/musical-chairs-game/main/docs/images/banner.png)

This repository contains the official smart contract source code for the on-chain game "Musical Chairs".

Our commitment is to full transparency and security for our players. By making this code public, we allow anyone to audit and verify the logic that governs the game and handles user funds.

> For Whitepaper, Roadmap, and Project Overview, visit our main Documentation Repository: **[github.com/crow-004/musical-chairs-game](https://github.com/crow-004/musical-chairs-game)**

## Repository Structure

*   `/contracts/v1/`: Source code for the initial version of the game.
*   `/contracts/v2/`: Source code for the second version, where the time lock system for emergencyWithdrawal functions was implemented
*   `/contracts/v3/`: Source code for the third version, which includes the referral system.
*   `/contracts/v4/`: Source code for the forth and current version, where the platform commission began to be calculated as a percentage.
*   `/contracts/nft/`: Source code for the "OG Member" NFT contract.

## Deployed Contracts & Verification

The current active version of the contract is **V4**.

### Key Role Addresses

These addresses are consistent across most network deployments for administrative and operational roles.

*   **Deployment Address:** `0xAE8EF7088985991bF975284264fc44044275c725`
*   **Owner Address:** `0xD0fe7416Dd4Fa719fB104894644F9C3586660325`
*   **Backend Address:** `0x85a6FaF0Ae7f9464267E1461Bc290024D807F886`
*   **Commission Recipient Address:** `0x38543a0967cF3027b6750E55E75658e096546572`

### Addresses by Network

*   **Arbitrum One**
    *   Proxy: `0xEDA164585a5FF8c53c48907bD102A1B593bd17eF`
    *   Implementation: `0x314dc2BDC74E2CbB1cDB09515a4968Dea4F51508`
*   **Base Mainnet**
    *   Proxy: `0xEDA164585a5FF8c53c48907bD102A1B593bd17eF`
    *   Implementation: `0x314dc2BDC74E2CbB1cDB09515a4968Dea4F51508`
*   **Binance Smart Chain Mainnet**
    *   Proxy: `0xEDA164585a5FF8c53c48907bD102A1B593bd17eF`
    *   Implementation: `0x314dc2BDC74E2CbB1cDB09515a4968Dea4F51508`
*   **Ethereum Mainnet**
    *   Proxy: `0x7c01A2a7e9012A98760984F2715A4517AD2c549A`
    *   Implementation: `0x4b2D727C00939ae962037F9E78e7Cb81112767B2`
*   **Optimism Mainnet**
    *   Proxy: `0xEDA164585a5FF8c53c48907bD102A1B593bd17eF`
    *   Implementation: `0x314dc2BDC74E2CbB1cDB09515a4968Dea4F51508`
*   **Polygon Mainnet**
    *   Proxy: `0x9880A2fcb9BE91051e337596a2b1a3091bF6d69C`
    *   Implementation: `0x7c01A2a7e9012A98760984F2715A4517AD2c549A`
*   **zkSync Mainnet**
    *   Proxy: `0xEDA164585a5FF8c53c48907bD102A1B593bd17eF`
    *   Implementation: `0x314dc2BDC74E2CbB1cDB09515a4968Dea4F51508`
*   **Arbitrum Sepolia (Testnet)**
    *   Proxy: `0x5Af9Ed30A64DB9ED1AE31e9c6D4215A9ED173040`
    *   Implementation: `0xEDA164585a5FF8c53c48907bD102A1B593bd17eF`

### Verification Status

All deployed mainnet contracts are verified on their respective block explorers, with the exception of zkSync.

**zkSync Verification Note:** The verification process on zkSync Era currently requires a manual source code upload. Attempts to verify using a flattened source file resulted in a bytecode mismatch. We have decided to postpone official verification on this network until a more reliable method is available, such as verification via Hardhat plugin, metadata, or by matching the bytecode of an already-verified contract on another EVM chain.

## Verification and Code Integrity

We believe in verifiable builds. You can use this source code to compile and compare the resulting bytecode with the contracts deployed on the Arbitrum network.

For automated verification on platforms like Sourcify, use the `metadata.json` file provided for each version where available.

**A Note on SPDX License Identifiers:** To ensure a perfect bytecode match for verification, the source files are provided exactly as they were at deployment, which may include an `UNLICENSED` identifier in the comments. However, all code in this repository is officially released to the public under the terms of the **MIT License** (see the `LICENSE` file).

*   **V1 & NFT Contract:** The source code and metadata in this repository are the exact versions that were deployed. They will compile to matching bytecode and can be fully verified.

*   **V2 Contract:** **Important Note:** The exact `.sol` source file for the deployed V2 contract has unfortunately been lost due to a version control oversight. The core logic of V2 is inherited by V3, whose source code is available for review. We have learned from this mistake and have since implemented stricter version control for all future deployments.

*   **V3 Contract:** **Important Note:** The source code for V3 provided here includes minor, non-critical modifications (e.g., making some functions `virtual` for future upgradeability) that were made *after* the initial deployment. As a result, a direct compilation of this code **will not produce matching bytecode**. We are publishing it for full transparency of the core logic. The fundamental game mechanics and fund handling logic remain identical to what is on-chain. We have learned from this and all future upgrades will be deployed from a version-controlled, tagged commit.

## License

The smart contracts in this repository are released under the **MIT License**. See the `LICENSE` file for more details.
