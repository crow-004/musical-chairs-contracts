// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol"; // solhint-disable-line no-global-import
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title MusicalChairsGame
 * @author crow
 * @notice A smart contract for a "Musical Chairs" style game where players deposit a stake, and the last one "out" loses their stake to the winners.
 */
contract MusicalChairsGame is ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable
{
    /// @notice A random value to ensure unique bytecode for each deployment.
    uint256 public constant DEPLOYMENT_SALT = 20240804;

    enum GameState { // Simplified states managed by the contract
        WaitingForDeposits,     // Game created, players set, waiting for all players to deposit
        Finished,               // Results recorded, winnings available for claim
        Cancelled,              // Game cancelled (e.g., not enough players, not enough deposits)
        Failed,                 // An unexpected error occurred
        Active                  // Game is active, e.g., music playing (managed by backend, but contract can reflect this state if needed)
    }

    struct Game {
        uint256 id;                 // Onchain game ID
        GameState state;            // Current state of the game onchain
        address[] players;          // Fixed list of players for this game
        mapping(address => bool) isRegistered; // Efficient lookup for registered players
        mapping(address => bool) depositedPlayers; // Tracks who among the 'players' deposited
        uint256 depositCount;       // Number of players who have deposited
        uint256 createdAt;          // Timestamp when game was created onchain (WaitingForDeposits)
        // uint256 musicStartedAt;  // Backend manages music timing
        // uint256 clicksAllowedAt; // Backend manages click window timing
        // uint256 resultsReadyAt;  // Not needed with direct recordResults
        address loser;              // Address of the player who lost
        uint256 endedAt;            // Timestamp when game Finished or Cancelled/Failed
        mapping(address => bool) gameWinners; // Tracks who among the 'players' won this game
    }
    /// @notice The address of the backend service authorized to manage games.
    address public backendAddress;
    /// @notice The address that receives the accumulated commission.
    address public commissionRecipient;
    /// @notice The amount of ETH each player must stake to participate.
    uint256 public stakeAmount;
    /// @notice The fixed commission amount taken from each game's pot.
    uint256 public commissionAmount; // This is the fixed commission amount per game
    /// @notice A counter for creating unique on-chain game IDs.
    uint256 public nextGameIdToCreate; // Counter for unique onchain game IDs, initialized in initialize()
    /// @notice The number of players required for a game to start.
    uint256 public requiredPlayerCount; // Number of players required for a game
    /// @notice Mapping from game ID to the game's data.
    mapping(uint256 => Game) public games;
    // mapping(address => uint256) public lastPlayedTimestamp; // Backend will handle daily limit logic

    /// @notice The total commission collected from all games, awaiting withdrawal.
    uint256 public accumulatedCommission;
    /// @notice Mapping from game ID to the winnings amount for each winner of that game.
    mapping(uint256 => uint256) public winningsPerWinner; // gameId => amount
    // mapping(uint256 => mapping(address => bool)) public isWinnerOfGame; // Moved inside Game struct
    /// @notice Mapping to track if a winner has already claimed their winnings for a specific game.
    mapping(uint256 => mapping(address => bool)) public winningsClaimed; // gameId => player => bool
    /// @notice Mapping to track if a player has already claimed their refund for a specific game.
    mapping(uint256 => mapping(address => bool)) public refundClaimed; // gameId => player => bool

    // --- Time-lock variables ---
    /// @notice The default delay for time-locked operations like ownership transfer.
    uint256 public constant DEFAULT_TIMELOCK_DELAY = 7 days; // Default delay

    /// @notice The address of the proposed new owner, pending acceptance.
    address public proposedNewOwner;
    /// @notice The timestamp when the ownership transfer was proposed.
    uint256 public ownerChangeProposalTimestamp;

    /// @notice The address of the proposed new commission recipient.
    address public proposedNewCommissionRecipient;
    /// @notice The timestamp when the commission recipient change was proposed.
    uint256 public commissionRecipientChangeProposalTimestamp;

    /// @notice The address of the proposed new implementation for an upgrade.
    address public proposedNewImplementation;
    /// @notice The timestamp when the contract upgrade was proposed.
    uint256 public upgradeProposalTimestamp;

    // --- Time-lock Events ---
    /**
     * @notice Emitted when a new owner is proposed.
     * @param proposedOwner The address of the new owner candidate.
     * @param executionTimestamp The earliest time the transfer can be executed.
     */
    event OwnershipTransferProposed(address indexed proposedOwner, uint256 indexed executionTimestamp);
    /**
     * @notice Emitted when ownership is transferred.
     * @param oldOwner The address of the previous owner.
     * @param newOwner The address of the new owner.
     */
    event OwnershipTransferExecuted(address indexed oldOwner, address indexed newOwner);
    /**
     * @notice Emitted when a new commission recipient is proposed.
     * @param proposedRecipient The address of the new recipient candidate.
     * @param executionTimestamp The earliest time the change can be executed.
     */
    event CommissionRecipientChangeProposed(address indexed proposedRecipient, uint256 indexed executionTimestamp);
    // CommissionRecipientSet event is already used for execution
    // event CommissionRecipientChangeExecuted(address indexed oldRecipient, address indexed newRecipient); 
    /**
     * @notice Emitted when a contract upgrade is proposed.
     * @param newImplementation The address of the new logic contract.
     * @param executionTimestamp The earliest time the upgrade can be executed.
     */
    event UpgradeProposed(address indexed newImplementation, uint256 indexed executionTimestamp);
    // Event for upgrade execution is typically emitted by the proxy (Upgraded(address implementation))
    /** @notice Emitted when an upgrade proposal is cancelled. */
    event UpgradeProposalCancelled();

    // --- Events ---
    /** 
     * @notice Emitted when a new game is created and players are set.
     * @param gameId The ID of the game.
     * @param players The array of player addresses.
     */
    event GamePlayersSet(uint256 indexed gameId, address[] players);
    /** 
     * @notice Emitted when a player deposits their stake.
     * @param gameId The ID of the game.
     * @param player The address of the player who deposited.
     * @param amount The amount deposited.
     */
    event GameDeposit(uint256 indexed gameId, address indexed player, uint256 indexed amount);
    // event AllDepositsConfirmed(uint256 indexed gameId); // Removed, backend tracks this
    // event MusicPlaying(uint256 indexed gameId); // Removed, backend manages this
    // event AwaitingClicks(uint256 indexed gameId); // Removed, backend manages this // solhint-disable-line no-empty-blocks (if it was an empty block before)
    // event DistributionPrepared(uint256 indexed gameId); // Removed
    /**
     * @notice Emitted when the backend records the results of a game.
     * @param gameId The ID of the game.
     * @param winners An array of winner addresses.
     * @param loser The address of the loser.
     * @param amountPerWinner The amount of ETH each winner can claim.
     */
    event GameResultsRecorded(uint256 indexed gameId, address[] winners, address loser, uint256 amountPerWinner);
    /**
     * @notice Emitted when a winner successfully claims their winnings.
     * @param gameId The ID of the game.
     * @param winner The address of the winner.
     * @param amount The amount of ETH claimed.
     */
    event WinningsClaimed(uint256 indexed gameId, address indexed winner, uint256 indexed amount);
    /**
     * @notice Emitted when the accumulated commission is withdrawn.
     * @param recipient The address that received the commission.
     * @param amount The amount of ETH withdrawn.
     */
    event CommissionWithdrawn(address indexed recipient, uint256 indexed amount);
    /** 
     * @notice Emitted when a game is cancelled by the backend.
     * @param gameId The ID of the cancelled game.
     * @param cancelledFromState The state the game was in before cancellation.
     */
    event GameCancelledByTimeout(uint256 indexed gameId, GameState cancelledFromState);
    /** 
     * @notice Emitted when a player claims a refund from a cancelled or failed game.
     * @param gameId The ID of the game.
     * @param player The address of the player receiving the refund.
     * @param amount The amount refunded.
     */
    event RefundClaimed(uint256 indexed gameId, address indexed player, uint256 indexed amount);
    /** 
     * @notice Emitted when a game is marked as failed by the backend.
     * @param gameId The ID of the failed game.
     * @param reason A string describing the reason for failure.
     */
    event GameFailed(uint256 indexed gameId, string reason);

    /** 
     * @notice Emitted when the backend address is changed.
     * @param oldBackendAddress The previous backend address.
     * @param newBackendAddress The new backend address.
     */
    event BackendAddressSet(address indexed oldBackendAddress, address indexed newBackendAddress);
    /** 
     * @notice Emitted when the commission recipient address is changed.
     * @param oldRecipient The previous recipient address.
     * @param newRecipient The new recipient address.
     */
    event CommissionRecipientSet(address indexed oldRecipient, address indexed newRecipient);
    /** 
     * @notice Emitted when the stake amount is changed.
     * @param oldAmount The previous stake amount.
     * @param newAmount The new stake amount.
     */
    event StakeAmountSet(uint256 indexed oldAmount, uint256 indexed newAmount);
    /** 
     * @notice Emitted when the commission amount is changed.
     * @param oldAmount The previous commission amount.
     * @param newAmount The new commission amount.
     */
    event CommissionAmountSet(uint256 indexed oldAmount, uint256 indexed newAmount);
    /** 
     * @notice Emitted when the required player count is changed.
     * @param oldCount The previous required player count.
     * @param newCount The new required player count.
     */
    event RequiredPlayerCountSet(uint256 indexed oldCount, uint256 indexed newCount);

    // --- Custom Errors ---
    error CallerIsNotBackend();
    error InvalidGameIdForCreation();
    error MustSetAtLeastTwoPlayers();
    error TooManyPlayers();
    error GameAlreadyExists();
    error PlayerAddressCannotBeZero();
    error DuplicatePlayerAddressInArray();
    error GameNotFound();
    error GameCannotBeCancelledFromCurrentState();
    error GameNotReadyForResults();
    error NotEnoughActiveDepositedPlayers();
    error IncorrectNumberOfWinners();
    error LoserMustBeDepositedPlayer();
    error LoserNotInPlayerList();
    error WinnerCannotBeLoser();
    error WinnerNotDepositedPlayer();
    error WinnerNotRegisteredPlayer();
    error StakeMustBeGreaterThanCommission();
    error CalculatedWinningsCannotBeZero();
    error AmountPerWinnerLessThanStake();
    error NoCommissionToWithdraw();
    error ETHCommissionWithdrawalFailed();
    error GameAlreadyEnded();
    error GameNotWaitingForDeposits();
    error NotRegisteredPlayer();
    error AlreadyDeposited();
    error IncorrectETHAmountSent();
    error GameNotFinished();
    error NotAWinner();
    error AlreadyCurrentOwner();
    error NotOwnerOrProposed();
    error NoNewOwnerProposed();
    error TimelockNotPassed();
    error AlreadyCurrentRecipient();
    error NoNewRecipientProposed();
    error UpgradeNotProposedOrDifferent();
    // TimelockNotPassed can be reused for upgrade timelock
    error WinningsAlreadyClaimed();
    error NoWinningsRecordedOrZero();
    error ETHTransferFailed();
    error GameNotCancelledOrFailed();
    error NoDepositFoundForRefund();
    error ETHRefundFailed();
    error AlreadyRefunded();
    error InvalidAddress();
    error StakeMustBePositive();
    error CommissionMustBeLessThanStake();
    error NoETHToWithdraw();
    error ETHEmergencyWithdrawalFailed();
    error IncorrectPlayerCountForGame();
    error NewPlayerCountTooSmallOrLarge();
    error RenounceOwnershipDisabled();
    error DirectOwnershipTransferDisabled();

    // --- Modifiers ---
    modifier onlyBackend() {
        if (msg.sender != backendAddress) revert CallerIsNotBackend();
        _;
    }

    /** @notice The constructor is disabled for upgradeable contracts. */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Overridden to prevent the contract from ever being ownerless.
     * @dev This function will revert if called, ensuring an owner always exists.
     * This is a security measure to prevent accidental loss of control over the contract.
     */
    function renounceOwnership() public view override onlyOwner {
        revert RenounceOwnershipDisabled();
    }

    /**
     * @notice Overridden to enforce the two-step, time-locked ownership transfer process.
     * @dev This function will revert if called. Use `proposeNewOwner` and `executeOwnerChange` instead.
     * This prevents bypassing the timelock with a direct ownership transfer.
     * @param _newOwner The address of the new owner (unused, part of the override).
     */
    function transferOwnership(address _newOwner) public view override onlyOwner { // solhint-disable-line no-unused-vars
        revert DirectOwnershipTransferDisabled();
    }

    // --- Initializer ---
    /**
     * @notice Initializes the contract state. Can only be called once.
     * @param initialOwner The initial owner of the contract.
     * @param initialBackendAddress The initial address of the backend service.
     * @param initialCommissionRecipient The initial address for receiving commissions.
     * @param initialStakeAmount The initial stake amount for games.
     * @param initialCommissionAmount The initial commission amount per game.
     * @param initialRequiredPlayerCount The initial number of players required for a game.
     */
    function initialize(
        address initialOwner,
        address initialBackendAddress,
        address initialCommissionRecipient,
        uint256 initialStakeAmount,
        uint256 initialCommissionAmount,
        uint256 initialRequiredPlayerCount
    ) public initializer {
        __MusicalChairsGame_init_unchained(initialOwner, initialBackendAddress, initialCommissionRecipient, initialStakeAmount, initialCommissionAmount, initialRequiredPlayerCount);
    }

    /**
     * @notice Internal initializer logic for the MusicalChairsGame contract.
     * @param initialOwner The initial owner of the contract.
     * @param initialBackendAddress The initial address of the backend service.
     * @param initialCommissionRecipient The initial address for receiving commissions.
     * @param initialStakeAmount The initial stake amount for games.
     * @param initialCommissionAmount The initial commission amount per game.
     * @param initialRequiredPlayerCount The initial number of players required for a game.
     */
    function __MusicalChairsGame_init_unchained(
        address initialOwner,
        address initialBackendAddress,
        address initialCommissionRecipient,
        uint256 initialStakeAmount,
        uint256 initialCommissionAmount, 
        uint256 initialRequiredPlayerCount
    ) internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
        __Ownable_init_unchained(initialOwner);
        __UUPSUpgradeable_init_unchained();

        if (initialBackendAddress == address(0)) revert InvalidAddress();
        if (initialCommissionRecipient == address(0)) revert InvalidAddress();
        if (initialStakeAmount == 0) revert StakeMustBePositive();
        if (initialCommissionAmount > initialStakeAmount - 1) revert CommissionMustBeLessThanStake();
        if (initialRequiredPlayerCount < 2 || initialRequiredPlayerCount > 20) revert NewPlayerCountTooSmallOrLarge();

        backendAddress = initialBackendAddress;
        commissionRecipient = initialCommissionRecipient;
        stakeAmount = initialStakeAmount;
        commissionAmount = initialCommissionAmount;
        requiredPlayerCount = initialRequiredPlayerCount;
        nextGameIdToCreate = 1;
    }

    /** @notice Fallback function to accept direct ETH transfers if necessary. */
    receive() external payable { // Keep receive function
        // Optional: add logic here if needed, e.g., emit an event
    }

    // --- Backend: Game Setup and State Transitions ---

    /**
     * @notice Called by the backend to set up a new game with a list of players.
     * The backend is responsible for ensuring the correct number of players (e.g., 5) are provided.
     * @param gameId The unique ID for this game (expected to be `nextGameIdToCreate`).
     * @param playersArray Array of player addresses (must be REQUIRED_PLAYERS). Renamed from _players to avoid conflict
     */
    function createGameAndSetPlayers(uint256 gameId, address[] calldata playersArray) external onlyBackend {
        if (gameId != nextGameIdToCreate) revert InvalidGameIdForCreation();
        if (playersArray.length != requiredPlayerCount) revert IncorrectPlayerCountForGame();
        if (games[gameId].id != 0) revert GameAlreadyExists();

        Game storage newGame = games[gameId];
        newGame.id = gameId;
        newGame.state = GameState.WaitingForDeposits;
        newGame.createdAt = block.timestamp;

        // Check for player uniqueness and add players
        // Check for player uniqueness within the input array playersArray
        uint256 playerCount = playersArray.length;
        for (uint256 i = 0; i < playerCount; ++i) {
            if (playersArray[i] == address(0)) revert PlayerAddressCannotBeZero();
            for (uint256 j = i + 1; j < playerCount; ++j) {
                if (playersArray[i] == playersArray[j]) revert DuplicatePlayerAddressInArray();
            }
        } // Add validated players to the game struct
        address[] storage playersStorage = newGame.players;
        for (uint256 i = 0; i < playerCount; ++i) {
            playersStorage.push(playersArray[i]);
            newGame.isRegistered[playersArray[i]] = true;
        }
        ++nextGameIdToCreate;
        emit GamePlayersSet(gameId, playersArray);
    }

    // --- Backend: Game Cancellation ---

    /**
     * @notice Called by the backend to cancel a game.
     * @dev This is typically used if not enough players deposit their stake in time.
     * @param gameId The ID of the game to cancel.
     */
    function cancelGameByBackend(uint256 gameId) external onlyBackend {
        Game storage game = games[gameId];
        if (game.id == 0) revert GameNotFound();
        if (game.state != GameState.WaitingForDeposits) revert GameCannotBeCancelledFromCurrentState();
        // Add a check to ensure not too many players have already deposited if we want to prevent cancellation then.
        // For now, backend decides. If only 1 player deposited, backend can cancel.

        GameState previousState = game.state;
        game.state = GameState.Cancelled;
        game.endedAt = block.timestamp;
        emit GameCancelledByTimeout(gameId, previousState);
    }

    /**
     * @notice Internal function to validate the array of winners.
     * @dev Checks if they are not the loser, have deposited, and were registered players.
     * @param game The game storage object.
     * @param winnersArray The array of winner addresses to validate.
     * @param loserAddress The address of the loser.
     */
    function _validateWinnersArray(
        Game storage game,
        address[] calldata winnersArray,
        address loserAddress
    ) private view {
        for (uint256 i = 0; i < winnersArray.length; ++i) {
            address winner = winnersArray[i];
            if (winner == loserAddress) revert WinnerCannotBeLoser();
            if (!game.depositedPlayers[winner]) revert WinnerNotDepositedPlayer();
            // A more efficient check using the isRegistered mapping instead of a loop.
            if (!game.isRegistered[winner]) revert WinnerNotRegisteredPlayer();
        }
    }
    /**
     * @notice Internal function to validate all inputs for recording game results.
     * @dev This is an internal function called by recordResults.
     * @param game The game storage object.
     * @param winnersArray The array of winner addresses.
     * @param loserAddress The address of the loser.
     */
    function _validateGameResultsInput(
        Game storage game,
        address[] calldata winnersArray,
        address loserAddress
    ) private view {
        // Count actual deposited players who are part of the game.players list
        uint256 actualDepositedPlayersCount = 0;
        uint256 playerCount = game.players.length;
        for(uint256 i = 0; i < playerCount; ++i){
            address player = game.players[i];
            if(game.depositedPlayers[player]){
                ++actualDepositedPlayersCount;
            }
        }
        // Need at least 1 winner and 1 loser among deposited players
        if (actualDepositedPlayersCount < 2) revert NotEnoughActiveDepositedPlayers();

        // The number of winners should be actualDepositedPlayersCount - 1
        if (winnersArray.length != actualDepositedPlayersCount - 1) revert IncorrectNumberOfWinners();

        // Ensure the loser is one of the players who deposited. This is a critical check.
        if (!game.depositedPlayers[loserAddress]) revert LoserMustBeDepositedPlayer();

        // Ensure the loser was indeed part of the original player list for this game.
        bool loserInGamePlayers = false;
        for(uint256 i = 0; i < playerCount; ++i) { if(game.players[i] == loserAddress) { loserInGamePlayers = true; break; }}
        if (!loserInGamePlayers) revert LoserNotInPlayerList();

        // Validate each winner in the array
        _validateWinnersArray(game, winnersArray, loserAddress);
        // Basic check on stake and commission amounts before calculation
        if (stakeAmount < commissionAmount + 1) revert StakeMustBeGreaterThanCommission();

        // Note: Calculation of amountPerWinner is left in recordResults
        // Note: Checks on the calculated amountPerWinner are left in recordResults
    }



    // --- Backend: Results and Commission ---
    /**
     * @notice Backend records the game results. Winners share the loser's stake minus commission.
     * @param gameId The ID of the game.
     * @param winnersArray An array of winner addresses. Renamed from _winners
     * @param loserAddress The address of the loser. Renamed from _loser
     */
    function recordResults(uint256 gameId, address[] calldata winnersArray, address loserAddress) external onlyBackend nonReentrant {
        Game storage game = games[gameId];
        if (game.id == 0) revert GameNotFound();
        // Backend calls this when it has determined results.
        // Contract trusts backend to call this at the appropriate game phase (after "clicks").
        if (game.state != GameState.WaitingForDeposits) revert GameNotReadyForResults(); // Initial state check remains

        // Perform all detailed input validations
        _validateGameResultsInput(game, winnersArray, loserAddress);

        // Prize calculation: Winners share the loser's stake, minus the commission.
        // The commission is taken from the loser's stake.
        // The remainder of the loser's stake is distributed among the winners.
        // Each winner also gets their own stake back.
        if (stakeAmount < commissionAmount + 1) revert StakeMustBeGreaterThanCommission();
        uint256 loserStakeNetOfCommission = stakeAmount - commissionAmount;
        uint256 winningsFromLoserPerWinner = 0;
        if (winnersArray.length > 0) { // Avoid division by zero if there are no winners (e.g. 2 players, 1 loser, 1 winner)
            winningsFromLoserPerWinner = loserStakeNetOfCommission / winnersArray.length;
        }
        uint256 amountPerWinner = stakeAmount + winningsFromLoserPerWinner;
        if (amountPerWinner == 0) revert CalculatedWinningsCannotBeZero();
        // This check is important to ensure winners get at least their stake back,
        // which should always be true if stake > commission and there's at least one winner.
        // It also guards against potential underflows if stakeAmount or commissionAmount were manipulated incorrectly (though they are owner-set).
        // Given the stakeAmount > commissionAmount check in _validateGameResultsInput,
        // and winnersArray.length == actualDepositedPlayersCount - 1 >= 1,
        // winningsFromLoserPerWinner should be >= 0, making amountPerWinner > stakeAmount - 1.
        if (amountPerWinner < stakeAmount) revert AmountPerWinnerLessThanStake();

        winningsPerWinner[gameId] = amountPerWinner;
        accumulatedCommission += commissionAmount;
        game.state = GameState.Finished;
        game.loser = loserAddress; // Store the loser
        game.endedAt = block.timestamp;

        // Mark winners in the game's specific gameWinners mapping
        for (uint256 i = 0; i < winnersArray.length; ++i) {
            game.gameWinners[winnersArray[i]] = true;
        }
        emit GameResultsRecorded(gameId, winnersArray, loserAddress, amountPerWinner);
    }

    /** @notice Allows the backend to withdraw all accumulated commission. */
    function withdrawAccumulatedCommission() external onlyBackend nonReentrant {
        uint256 amountToWithdraw = accumulatedCommission;
        if (amountToWithdraw == 0) revert NoCommissionToWithdraw();

        accumulatedCommission = 0;
        // solhint-disable-next-line avoid-low-level-calls
        (bool sent, ) = commissionRecipient.call{value: amountToWithdraw}(""); // solhint-disable-line check-send-result
        if (!sent) revert ETHCommissionWithdrawalFailed();
        emit CommissionWithdrawn(commissionRecipient, amountToWithdraw);
    }

    /**
     * @notice Called by backend if an unrecoverable error occurs during game processing.
     * @param gameId The ID of the game to fail.
     * @param reason A string describing the reason for failure.
     */
    function failGame(uint256 gameId, string calldata reason) external onlyBackend {
        Game storage game = games[gameId];
        if (game.id == 0) revert GameNotFound();
        // Allow failing from most states except already Finished/Cancelled/Failed
        if (game.state == GameState.Finished || game.state == GameState.Cancelled || game.state == GameState.Failed) revert GameAlreadyEnded();
        game.state = GameState.Failed;
        game.endedAt = block.timestamp;
        // Note: If funds were deposited, they might be stuck unless a specific refund for Failed state is implemented.
        // Or, Failed state could be treated like Cancelled for refunds if appropriate.
        emit GameFailed(gameId, reason);
    }

    // --- Player Functions ---

    /**
     * @notice Allows a registered player to deposit their stake for a game.
     * @param gameId The ID of the game to deposit into.
     */
    function depositStake(uint256 gameId) external payable nonReentrant {
        Game storage game = games[gameId];
        if (game.id == 0) revert GameNotFound();
        if (game.state != GameState.WaitingForDeposits) revert GameNotWaitingForDeposits();
        if (!game.isRegistered[msg.sender]) revert NotRegisteredPlayer();
        if (game.depositedPlayers[msg.sender]) revert AlreadyDeposited();
        if (msg.value != stakeAmount) revert IncorrectETHAmountSent();
        game.depositedPlayers[msg.sender] = true;
        ++game.depositCount;
        emit GameDeposit(gameId, msg.sender, msg.value); // Emit actual amount sent

        // If this deposit makes the game full, backend will call confirmDepositsAndStartMusic
    }

    /**
     * @notice Allows a winner to claim their winnings from a finished game.
     * @param gameId The ID of the game from which to claim winnings.
     */
    function claimWinnings(uint256 gameId) external nonReentrant {
        Game storage game = games[gameId]; // Reading state, so no game.id check needed if it's 0
        if (game.state != GameState.Finished) revert GameNotFinished(); // Check game state
        if (!game.gameWinners[msg.sender]) revert NotAWinner(); // Check winner status using the mapping inside the struct
        if (winningsClaimed[gameId][msg.sender]) revert WinningsAlreadyClaimed();
        uint256 amount = winningsPerWinner[gameId];
        if (amount == 0) revert NoWinningsRecordedOrZero();
        winningsClaimed[gameId][msg.sender] = true;
        // solhint-disable-next-line avoid-low-level-calls, no-empty-blocks
        (bool sent, ) = msg.sender.call{value: amount}(""); // solhint-disable-line check-send-result
        if (!sent) revert ETHTransferFailed();
        emit WinningsClaimed(gameId, msg.sender, amount);
    }

    /**
     * @notice Allows a player to request a refund from a cancelled or failed game.
     * @param gameId The ID of the game from which to request a refund.
     */
    function requestRefund(uint256 gameId) external nonReentrant {
        Game storage game = games[gameId];
        if (game.state != GameState.Cancelled && game.state != GameState.Failed) revert GameNotCancelledOrFailed();
        if (refundClaimed[gameId][msg.sender]) revert AlreadyRefunded();
        if (!game.depositedPlayers[msg.sender]) revert NoDepositFoundForRefund();
        game.depositedPlayers[msg.sender] = false; // Mark as not deposited after refund
        refundClaimed[gameId][msg.sender] = true;
        --game.depositCount; // This is crucial for maintaining state consistency.
        // solhint-disable-next-line avoid-low-level-calls, no-empty-blocks
        (bool sent, ) = msg.sender.call{value: stakeAmount}(""); // solhint-disable-line check-send-result
        if (!sent) revert ETHRefundFailed();
        emit RefundClaimed(gameId, msg.sender, stakeAmount);
    }

    // --- View Functions ---

    /**
     * @notice Retrieves detailed information about a specific game.
     * @param gameId The ID of the game to query.
     * @return id The game's ID.
     * @return state The current state of the game.
     * @return players An array of registered player addresses.
     * @return depositCount The number of players who have deposited.
     * @return createdAt The timestamp of game creation.
     * @return endedAt The timestamp when the game ended.
     * @return loserAddress The address of the game's loser.
     */
    function getGameInfo(uint256 gameId) external view returns (
        uint256 id,
        GameState state,
        address[] memory players,
        uint256 depositCount,
        uint256 createdAt,
        // uint256 musicStartedAt, // Removed
        // uint256 clicksAllowedAt, // Removed
        // uint256 resultsReadyAt, // Removed
        uint256 endedAt,
        address loserAddress // Added loser to return values
    ) {
        Game storage game = games[gameId];
        if (game.id == 0) revert GameNotFound();
        return (
            game.id,
            game.state,
            game.players,
            game.depositCount,
            game.createdAt,
            // game.musicStartedAt, // Removed
            // game.clicksAllowedAt, // Removed
            // game.resultsReadyAt, // Removed
            game.endedAt,
            game.loser // Return the stored loser
        );
    }

    /**
     * @notice Checks if a player has deposited their stake for a specific game.
     * @param gameId The ID of the game.
     * @param playerAddress The address of the player to check.
     * @return bool True if the player has deposited, false otherwise.
     */
    function getPlayerDepositStatus(uint256 gameId, address playerAddress) external view returns (bool) {
        // No need to revert if game.id == 0 for a view function returning bool, it will just return false for depositedPlayers[playerAddress]
        // if (games[gameId].id == 0) revert GameNotFound(); // Removed revert for view function
        return games[gameId].depositedPlayers[playerAddress];
    }

    /**
     * @notice Checks if a specific player is a winner of a given game.
     * @param gameId The ID of the game.
     * @param playerAddress The address of the player to check.
     * @return True if the player is a winner of the game, false otherwise.
     */
    function isWinnerOfGame(uint256 gameId, address playerAddress) external view returns (bool) {
        if (games[gameId].id == 0) return false; // Game not found
        return games[gameId].gameWinners[playerAddress];
    }

    // --- Owner Functions ---

    // Backend address can be changed immediately by the owner as it's an operational hot key.
    // If backend key is compromised, owner needs to be able to react quickly.
    // Consider if a time-lock is needed here based on your risk assessment for the backend key.
    // For now, keeping it immediate.
    /**
     * @notice Sets the backend address. Can only be called by the owner.
     * @param newBackendAddress The new address for the backend service.
     */
    function setBackendAddress(address newBackendAddress) external virtual onlyOwner {
        if (newBackendAddress == address(0)) revert InvalidAddress();
        address oldBackendAddress = backendAddress;
        backendAddress = newBackendAddress;
        emit BackendAddressSet(oldBackendAddress, newBackendAddress);
    }

    // --- Time-locked Owner Functions ---

    /**
     * @notice Proposes a new owner for the contract.
     * @param newOwnerCandidate The address of the new owner candidate.
     */
    function proposeNewOwner(address newOwnerCandidate) external virtual onlyOwner {
        if (newOwnerCandidate == address(0)) revert InvalidAddress();
        if (newOwnerCandidate == owner()) revert AlreadyCurrentOwner();
        proposedNewOwner = newOwnerCandidate;
        ownerChangeProposalTimestamp = block.timestamp;
        emit OwnershipTransferProposed(newOwnerCandidate, block.timestamp + DEFAULT_TIMELOCK_DELAY);
    }

    /** @notice Executes a pending ownership transfer after the timelock has passed. */
    function executeOwnerChange() external virtual {
        if (msg.sender != owner() && msg.sender != proposedNewOwner) revert NotOwnerOrProposed();
        if (proposedNewOwner == address(0)) revert NoNewOwnerProposed();
        if (block.timestamp < ownerChangeProposalTimestamp + DEFAULT_TIMELOCK_DELAY) revert TimelockNotPassed();

        address oldOwner = owner();
        _transferOwnership(proposedNewOwner); // Use internal function to bypass the onlyOwner check
        proposedNewOwner = address(0);
        ownerChangeProposalTimestamp = 0;
        emit OwnershipTransferExecuted(oldOwner, owner()); // solhint-disable-line gas-custom-errors
    }

    /**
     * @notice Proposes a new commission recipient.
     * @param newRecipient The address of the new recipient candidate.
     */
    function proposeNewCommissionRecipient(address newRecipient) external virtual onlyOwner {
        if (newRecipient == address(0)) revert InvalidAddress();
        if (newRecipient == commissionRecipient) revert AlreadyCurrentRecipient();
        proposedNewCommissionRecipient = newRecipient;
        commissionRecipientChangeProposalTimestamp = block.timestamp;
        emit CommissionRecipientChangeProposed(newRecipient, block.timestamp + DEFAULT_TIMELOCK_DELAY);
    }

    /** @notice Executes a pending commission recipient change after the timelock has passed. */
    function executeCommissionRecipientChange() external virtual onlyOwner { // Or allow proposed recipient to execute? For now, owner.
        if (proposedNewCommissionRecipient == address(0)) revert NoNewRecipientProposed();
        if (block.timestamp < commissionRecipientChangeProposalTimestamp + DEFAULT_TIMELOCK_DELAY) revert TimelockNotPassed();

        address oldRecipient = commissionRecipient;
        commissionRecipient = proposedNewCommissionRecipient;
        proposedNewCommissionRecipient = address(0);
        commissionRecipientChangeProposalTimestamp = 0; // Reset timestamp
        emit CommissionRecipientSet(oldRecipient, commissionRecipient); // Use the updated commissionRecipient
    }

    /**
     * @notice Proposes a contract upgrade to a new implementation address.
     * @param newImplementation The address of the new logic contract.
     */
    function proposeUpgrade(address newImplementation) external virtual onlyOwner {
        if (newImplementation == address(0)) revert InvalidAddress();
        // Consider adding a check: if (newImplementation == address(this)) revert("Cannot upgrade to self");
        // Or if (newImplementation == implementation()) if you have a way to get current implementation address easily.
        proposedNewImplementation = newImplementation;
        upgradeProposalTimestamp = block.timestamp;
        emit UpgradeProposed(newImplementation, block.timestamp + DEFAULT_TIMELOCK_DELAY);
    }

    /** @notice Cancels a pending upgrade proposal. */
    function cancelUpgradeProposal() external virtual onlyOwner {
        proposedNewImplementation = address(0);
        upgradeProposalTimestamp = 0;
        emit UpgradeProposalCancelled();
        // Emit an event for cancellation if desired
    }
    // --- Non-Time-locked Owner Functions (Operational Parameters) ---
    // These are less critical than owner/commission recipient and can be changed faster if needed.
    // Consider if time-locks are desired for these as well.

    /**
     * @notice Sets the stake amount required for games.
     * @param newStakeAmount The new stake amount.
     */
    function setStakeAmount(uint256 newStakeAmount) external virtual onlyOwner {
        if (newStakeAmount == 0) revert StakeMustBePositive();
        if (commissionAmount > newStakeAmount - 1) revert CommissionMustBeLessThanStake();
        uint256 oldStakeAmount = stakeAmount;
        stakeAmount = newStakeAmount;
        emit StakeAmountSet(oldStakeAmount, newStakeAmount);
    }

    /**
     * @notice Sets the commission amount taken per game.
     * @param newCommissionAmount The new commission amount.
     */
    function setCommissionAmount(uint256 newCommissionAmount) external virtual onlyOwner {
        if (newCommissionAmount > stakeAmount - 1) revert CommissionMustBeLessThanStake();
        // Allow commission to be 0 if desired
        uint256 oldCommissionAmount = commissionAmount;
        commissionAmount = newCommissionAmount;
        emit CommissionAmountSet(oldCommissionAmount, newCommissionAmount);
    }

    /**
     * @notice Sets the number of players required for a game.
     * @param newCount The new required player count.
     */
    function setRequiredPlayerCount(uint256 newCount) external virtual onlyOwner {
        if (newCount < 2 || newCount > 20) revert NewPlayerCountTooSmallOrLarge(); // Consistent with initialize
        uint256 oldCount = requiredPlayerCount;
        requiredPlayerCount = newCount;
        emit RequiredPlayerCountSet(oldCount, newCount);
    }

    /** @notice Allows the owner to withdraw all ETH from the contract in an emergency. */
    function emergencyWithdrawETH() external virtual onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoETHToWithdraw();
        // solhint-disable-next-line avoid-low-level-calls, no-empty-blocks
        (bool sent, ) = owner().call{value: balance}(""); // solhint-disable-line check-send-result
        if (!sent) revert ETHEmergencyWithdrawalFailed();
        // Consider emitting an event here if desired
    }
    
    /**
     * @notice A dedicated, external function for the owner to trigger an upgrade.
     * This is more explicit and robust than relying on the inherited public `upgradeTo`.
     * @param newImplementation The address of the new logic contract.
     */
    function upgrade(address newImplementation) external payable onlyOwner {
        // Call the public function from the parent UUPSUpgradeable contract
        upgradeToAndCall(newImplementation, bytes(""));
    }

    /**
     * @notice Authorizes an upgrade. Required by UUPS.
     * @dev This internal function is called by the UUPS proxy before an upgrade. It checks for a valid, timelocked proposal.
     * @param newImplementation The address of the new logic contract.
     */
    function _authorizeUpgrade(address newImplementation) internal override {
        // The onlyOwner modifier on the `upgrade` function already protects this.
        // Check that the address of the new implementation matches the proposed one
        if (newImplementation != proposedNewImplementation) revert UpgradeNotProposedOrDifferent();
        // Check that the time lock has passed
        if (block.timestamp < upgradeProposalTimestamp + DEFAULT_TIMELOCK_DELAY) revert TimelockNotPassed(); // Reusing TimelockNotPassed
        proposedNewImplementation = address(0);
        upgradeProposalTimestamp = 0;
    }

    // Storage gap to allow adding new state variables in future versions without storage collisions
    uint256[45] private __gap; // Adjust size based on inherited contracts and future needs // solhint-disable-line var-name-mixedcase
}
