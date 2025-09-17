// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { MusicalChairsGame } from "contracts/MusicalChairs.sol";

/**
 * @title MusicalChairsGameV2
 * @author crow
 * @notice This contract represents version 2 of the game.
 * It introduces a time-locked emergency withdrawal mechanism to enhance security and user trust,
 * while deprecating the instant withdrawal function from V1.
 */
contract MusicalChairsGameV2 is MusicalChairsGame {

    // --- V2 State Variables ---
    /// @notice The amount of ETH proposed for emergency withdrawal, subject to a timelock.
    uint256 public proposedEmergencyWithdrawalAmount;
    /// @notice The timestamp when the emergency withdrawal was proposed.
    uint256 public emergencyWithdrawalProposalTimestamp;

    // --- V2 Events ---
    /**
     * @notice Emitted when an emergency withdrawal is proposed.
     * @param amount The amount of ETH proposed for withdrawal.
     * @param executionTimestamp The earliest time the withdrawal can be executed.
     */
    event EmergencyWithdrawalProposed(uint256 indexed amount, uint256 indexed executionTimestamp);
    /**
     * @notice Emitted when a proposed emergency withdrawal is cancelled.
     */
    event EmergencyWithdrawalCancelled();
    /**
     * @notice Emitted when an emergency withdrawal is successfully executed.
     * @param recipient The address that received the funds.
     * @param amount The amount of ETH withdrawn.
     */
    event EmergencyWithdrawalExecuted(address indexed recipient, uint256 indexed amount);

    // --- V2 Custom Errors ---
    error NoEmergencyWithdrawalProposed();
    error EmergencyWithdrawalDeprecated();
    error EmergencyWithdrawalAlreadyProposed();
    error InvalidPlayerCount(uint256 count);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializer for V2. It is empty as no new state needs to be set during the upgrade.
     * @dev The `reinitializer(2)` modifier ensures this can only be called during an upgrade to version 2.
     */
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() public reinitializer(2) {
        // solhint-disable-previous-line no-empty-blocks
        // No new state to initialize in this version.
    }

    // --- V2 Owner Functions ---

    /**
     * @notice Overrides the dangerous V1 function to disable it permanently.
     * @dev This function will always revert, forcing the use of the new time-locked mechanism.
     */
    function emergencyWithdrawETH() public pure override {
        revert EmergencyWithdrawalDeprecated();
    }

    /** @notice Proposes an emergency withdrawal of all funds from the contract, subject to a timelock. */
    function proposeEmergencyWithdrawal() external virtual onlyOwner {
        uint256 balance = address(this).balance;
        if (emergencyWithdrawalProposalTimestamp != 0) revert EmergencyWithdrawalAlreadyProposed();
        if (balance == 0) revert NoETHToWithdraw();
        proposedEmergencyWithdrawalAmount = balance;
        emergencyWithdrawalProposalTimestamp = block.timestamp;
        emit EmergencyWithdrawalProposed(balance, block.timestamp + DEFAULT_TIMELOCK_DELAY);
    }

    /** @notice Cancels a pending emergency withdrawal proposal. */
    function cancelEmergencyWithdrawal() external virtual onlyOwner {
        if (emergencyWithdrawalProposalTimestamp == 0) revert NoEmergencyWithdrawalProposed();
        proposedEmergencyWithdrawalAmount = 0;
        emergencyWithdrawalProposalTimestamp = 0;
        emit EmergencyWithdrawalCancelled();
    }

    /** @notice Executes a pending emergency withdrawal after the timelock has passed. */
    function executeEmergencyWithdrawal() external virtual onlyOwner nonReentrant {
        if (emergencyWithdrawalProposalTimestamp == 0) revert NoEmergencyWithdrawalProposed();
        if (block.timestamp < emergencyWithdrawalProposalTimestamp + DEFAULT_TIMELOCK_DELAY) revert TimelockNotPassed();

        uint256 amountToWithdraw = proposedEmergencyWithdrawalAmount;
        proposedEmergencyWithdrawalAmount = 0;
        emergencyWithdrawalProposalTimestamp = 0;

        (bool sent, ) = owner().call{value: amountToWithdraw}("");
        if (!sent) revert ETHEmergencyWithdrawalFailed();
        emit EmergencyWithdrawalExecuted(owner(), amountToWithdraw);
    }

    /**
     * @notice Called by the backend to set up a new game with a variable number of players.
     * @dev Overrides the V1 function to allow a player count between 2 and 20,
     * aligning with the flexible backend logic. The `requiredPlayerCount` state variable
     * is no longer used for this check but may still be used by the backend for matchmaking.
     * @param gameId The unique ID for this game (expected to be `nextGameIdToCreate`).
     * @param playersArray Array of player addresses.
     */
    function createGameAndSetPlayers(uint256 gameId, address[] calldata playersArray) external virtual override onlyBackend {
        _createGameAndSetPlayers(gameId, playersArray);
    }

    /**
     * @notice Internal logic for creating a game, refactored to be extensible by child contracts.
     * @dev This function contains the core logic from the V2 `createGameAndSetPlayers`.
     * @param gameId The unique ID for this game.
     * @param playersArray Array of player addresses.
     */
    function _createGameAndSetPlayers(
        uint256 gameId,
        address[] calldata playersArray
    ) internal virtual {
        uint256 playerCount = playersArray.length;
        if (playerCount < 2 || playerCount > 20) {
            revert InvalidPlayerCount(playerCount);
        }
        if (gameId != nextGameIdToCreate) revert InvalidGameIdForCreation();
        if (games[gameId].id != 0) revert GameAlreadyExists();

        Game storage newGame = games[gameId];
        newGame.id = gameId;
        newGame.state = GameState.WaitingForDeposits;
        newGame.createdAt = block.timestamp;

        // Check for player uniqueness and add players
        for (uint256 i = 0; i < playerCount; ++i) {
            if (playersArray[i] == address(0)) revert PlayerAddressCannotBeZero();
            for (uint256 j = i + 1; j < playerCount; ++j) {
                if (playersArray[i] == playersArray[j]) revert DuplicatePlayerAddressInArray();
            }
        }
        
        address[] storage playersStorage = newGame.players;
        for (uint256 i = 0; i < playerCount; ++i) {
            playersStorage.push(playersArray[i]);
            newGame.isRegistered[playersArray[i]] = true;
        }
        
        ++nextGameIdToCreate;
        emit GamePlayersSet(gameId, playersArray);
    }

    /// @notice A simple function to confirm that the contract is V2.
    /// @return bool True if the contract is V2.
    function isVersionTwo() public pure returns (bool) {
        return true;
    }
}
