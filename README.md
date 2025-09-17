# Musical Chairs Smart Contracts

![Game Banner](https://raw.githubusercontent.com/crow-004/musical-chairs-game/main/docs/images/banner.png)

This repository contains the official smart contract source code for the on-chain game "Musical Chairs".

Our commitment is to full transparency and security for our players. By making this code public, we allow anyone to audit and verify the logic that governs the game and handles user funds.

## Repository Structure

*   `/contracts/v1/`: Source code for the initial version of the game.
*   `/contracts/v2/`: Source code for the second version.
*   `/contracts/v3/`: Source code for the third and current version, which includes the referral system.
*   `/contracts/nft/`: Source code for the "Founding Player" NFT contract.

## Verification and Code Integrity

We believe in verifiable builds. You can use this source code to compile and compare the resulting bytecode with the contracts deployed on the Arbitrum network.

For automated verification on platforms like Sourcify, use the `metadata.json` file provided for each version where available.

**A Note on SPDX License Identifiers:** To ensure a perfect bytecode match for verification, the source files are provided exactly as they were at deployment, which may include an `UNLICENSED` identifier in the comments. However, all code in this repository is officially released to the public under the terms of the **MIT License** (see the `LICENSE` file).

*   **V1 & NFT Contract:** The source code and metadata in this repository are the exact versions that were deployed. They will compile to matching bytecode and can be fully verified.

*   **V2 Contract:** The source code provided is the exact version deployed. We are in the process of locating the corresponding `metadata.json` for easy verification.

*   **V3 Contract:** **Important Note:** The source code for V3 provided here includes minor, non-critical modifications (e.g., making some functions `virtual` for future upgradeability) that were made *after* the initial deployment. As a result, a direct compilation of this code **will not produce matching bytecode**. We are publishing it for full transparency of the core logic. The fundamental game mechanics and fund handling logic remain identical to what is on-chain. We have learned from this and all future upgrades will be deployed from a version-controlled, tagged commit.

## License

The smart contracts in this repository are released under the **MIT License**. See the `LICENSE` file for more details.
