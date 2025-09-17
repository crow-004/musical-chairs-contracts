// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { MusicalChairsGameV2 } from "contracts/MusicalChairsV2.sol";

/**
 * @title MusicalChairsGameV3
 * @author crow
 * @notice This contract represents version 3 of the game.
 * It introduces a fully on-chain referral system to reward users for bringing new players.
 */
contract MusicalChairsGameV3 is MusicalChairsGameV2 {
    // --- V3 State Variables ---

    /// @notice A special address used to signify that a player has no referrer and cannot have one set in the future.
    address public constant NO_REFERRER_SENTINEL = 0x000000000000000000000000000000000000dEaD;

    /// @notice Maps a player to their referrer. Set only once on their first game with a referrer.
    mapping(address => address) public playerReferrer;

    /// @notice Maps a referrer to their accumulated earnings in ETH.
    mapping(address => uint256) public referralEarnings;

    /// @notice The percentage of the platform's commission that goes to the referrer, in basis points (e.g., 500 = 5%).
    uint256 public referralCommissionBps;

    // --- V3 Events ---

    /**
     * @notice Emitted when a player's referrer is set for the first time.
     * @param player The address of the player being referred.
     * @param referrer The address of the referrer, or a sentinel value if the player has no referrer.
     */
    event ReferrerSet(address indexed player, address indexed referrer);
    /**
     * @notice Emitted when a referrer earns a commission from a referred player's game.
     * @param referrer The address of the referrer receiving the commission.
     * @param gameId The ID of the game that generated the commission.
     * @param amount The commission amount earned.
     */
    event ReferralCommissionPaid(address indexed referrer, uint256 indexed gameId, uint256 amount); // solhint-disable-line gas-indexed-events
    /**
     * @notice Emitted when a referrer withdraws their accumulated earnings.
     * @param referrer The address of the referrer claiming their earnings.
     * @param amount The amount of ETH claimed.
     */
    event ReferralEarningsClaimed(address indexed referrer, uint256 amount); // solhint-disable-line gas-indexed-events
    /**
     * @notice Emitted when the owner changes the referral commission rate.
     * @param newBps The new referral commission rate in basis points.
     */
    event ReferralCommissionBpsSet(uint256 newBps); // solhint-disable-line gas-indexed-events

    // --- V3 Custom Errors ---

    error InvalidReferrer();
    error NoReferralEarningsToClaim();
    error ReferralPayoutFailed();
    error InvalidReferralCommissionBps();
    error ReferrerArrayLengthMismatch();
    error InvalidSignature();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializer for V3. Sets the referral commission rate.
     * @dev The `reinitializer(3)` modifier ensures this can only be called during an upgrade to version 3.
     * @param _initialReferralCommissionBps The initial referral commission in basis points (e.g., 500 for 5%).
     * @custom:oz-upgrades-validate-as-initializer
     */
    function initializeV3(uint256 _initialReferralCommissionBps) public reinitializer(3) {
        if (_initialReferralCommissionBps > 10000) revert InvalidReferralCommissionBps();
        referralCommissionBps = _initialReferralCommissionBps;
    }

    // --- V3 Owner Functions ---

    /**
     * @notice Allows the owner to set a new referral commission rate.
     * @param _newReferralCommissionBps The new rate in basis points (e.g., 500 for 5%).
     */
    function setReferralCommissionBps(uint256 _newReferralCommissionBps) external onlyOwner {
        if (_newReferralCommissionBps > 10000) revert InvalidReferralCommissionBps();
        referralCommissionBps = _newReferralCommissionBps;
        emit ReferralCommissionBpsSet(_newReferralCommissionBps);
    }

    // --- V3 Referrer Functions ---

    /**
     * @notice Allows a referrer to withdraw their accumulated earnings.
     */
    function claimReferralEarnings() external nonReentrant {
        uint256 earnings = referralEarnings[msg.sender];
        if (earnings == 0) revert NoReferralEarningsToClaim();

        // Checks-Effects-Interactions pattern
        referralEarnings[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: earnings}("");
        if (!success) revert ReferralPayoutFailed();

        emit ReferralEarningsClaimed(msg.sender, earnings);
    }

    // --- V3 Overridden Core Logic ---

    /**
     * @notice Overrides V2 to accept an array of referrer addresses alongside the players.
     * @dev The backend is responsible for providing the referrer for each player.
     * @param gameId The unique ID for this game.
     * @param playersArray Array of player addresses.
     * @param referrersArray Array of potential referrer addresses, parallel to playersArray.
     * @param signaturesArray Array of signatures, parallel to playersArray. A signature proves that the referrer approved the referral.
     */
    function createGameAndSetPlayers(
        uint256 gameId,
        address[] calldata playersArray,
        address[] calldata referrersArray,
        bytes[] calldata signaturesArray
    ) external virtual onlyBackend {
        if (playersArray.length != referrersArray.length || playersArray.length != signaturesArray.length) {
            revert ReferrerArrayLengthMismatch();
        }

        // Call the parent function to set up the game with players
        _createGameAndSetPlayers(gameId, playersArray);

        // Now, verify signatures and set the referrers
        for (uint256 i = 0; i < playersArray.length; ++i) {
            address player = playersArray[i];
            address referrer = referrersArray[i];
            bytes calldata signature = signaturesArray[i];

            // A referrer record can only be set if one does not already exist.
            if (playerReferrer[player] == address(0)) {
                // Case 1: Set a real, valid referrer.
                if (referrer != address(0) && referrer != NO_REFERRER_SENTINEL && referrer != player && signature.length > 0) {
                    bytes32 messageHash = keccak256(abi.encodePacked(player));
                    bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
                    if (ECDSA.recover(ethSignedMessageHash, signature) != referrer) revert InvalidSignature();
                    playerReferrer[player] = referrer;
                    emit ReferrerSet(player, referrer);
                }
                // Case 2: Permanently block a referrer from being set by using the sentinel value.
                else if (referrer == NO_REFERRER_SENTINEL) {
                    playerReferrer[player] = NO_REFERRER_SENTINEL;
                    emit ReferrerSet(player, NO_REFERRER_SENTINEL);
                }
                // Case 3: referrer is address(0) or a self-referral. Do nothing, leave as address(0) for a future game.
            }
        }
    }

    /**
     * @notice Overrides the parent `recordResults` to include referral commission distribution.
     * @dev This function is copied and modified because it was not `virtual` in the parent.
     * @param gameId The ID of the game to record results for.
     * @param winnersArray An array of winner addresses.
     * @param loserAddress The address of the loser.
     */
    function recordResults(uint256 gameId, address[] calldata winnersArray, address loserAddress) external override onlyBackend nonReentrant {
        Game storage game = games[gameId];
        if (game.id == 0) revert GameNotFound();
        if (game.state != GameState.WaitingForDeposits) revert GameNotReadyForResults();
        _validateGameResultsInput(game, winnersArray, loserAddress);

        // --- V3 Referral Logic ---
        uint256 totalPlatformCommission = commissionAmount;
        uint256 totalReferralBonus = 0;

        if (referralCommissionBps > 0 && game.depositCount > 0) {
            for (uint256 i = 0; i < game.players.length; ++i) {
                address player = game.players[i];
                if (game.depositedPlayers[player]) {
                    address referrer = playerReferrer[player];
                    // A real referrer is not the zero address and not the sentinel address.
                    if (referrer != address(0) && referrer != NO_REFERRER_SENTINEL) {
                        // Reordered calculation to multiply before dividing to maintain precision.
                        uint256 referralBonus = (totalPlatformCommission * referralCommissionBps) / game.depositCount / 10000;
                        if (referralBonus > 0) {
                            referralEarnings[referrer] += referralBonus;
                            totalReferralBonus += referralBonus;
                            emit ReferralCommissionPaid(referrer, gameId, referralBonus);
                        }
                    }
                }
            }
        }

        // --- Original Logic (with updated commission) ---
        uint256 netPlatformCommission = totalPlatformCommission - totalReferralBonus;
        accumulatedCommission += netPlatformCommission;

        uint256 loserStakeNetOfCommission = stakeAmount - totalPlatformCommission; // Commission is taken from the pot
        uint256 winningsFromLoserPerWinner = 0;
        if (winnersArray.length > 0) {
            winningsFromLoserPerWinner = loserStakeNetOfCommission / winnersArray.length;
        }
        uint256 amountPerWinner = stakeAmount + winningsFromLoserPerWinner;

        winningsPerWinner[gameId] = amountPerWinner;
        game.state = GameState.Finished;
        game.loser = loserAddress;
        game.endedAt = block.timestamp;

        for (uint256 i = 0; i < winnersArray.length; ++i) {
            game.gameWinners[winnersArray[i]] = true;
        }
        emit GameResultsRecorded(gameId, winnersArray, loserAddress, amountPerWinner);
    }

    /// @notice A simple function to confirm that the contract is V3.
    /// @return bool True if the contract is V3.
    function isVersionThree() public pure returns (bool) {
        return true;
    }
}
