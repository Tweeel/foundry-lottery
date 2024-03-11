// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

/**
 * @title Raffle
 * @author Houssam Eddine
 * @notice This contract is for creating a sample raflle
 * @dev Implements chainlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    /** Errors */
    error Raffle__NotEnoughETHSent();
    error Raffle__TransferFailed();
    error Raffle_RaffleNotOpen();
    error Raffle_UpkeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        RaffleState state,
        uint256 timeDiff
    );

    /** Type declarations */
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }

    /** State Variables */
    // @dev VRF requests confirmation parameters
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    // @dev VRF The number of random words requested
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    // @dev Duration of the lottery in seconds
    uint256 private immutable i_interval;

    // @dev VRF request parameters
    // @dev VRF
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    // @dev VRF The key hash
    bytes32 private immutable i_gasLane;
    // @dev VRF The subscription id
    uint64 private immutable i_subscriptionId;
    // @dev VRF The gas limit for the callback
    uint32 private immutable i_callbackGasLimit;

    uint256 private s_lastTimeStamp;
    address payable[] private s_players;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event RequestedRaffleWinner(uint256 indexed requestId);
    event EnteredRaffle(address indexed player);
    event WinnerPick(address indexed winner);

    /** Functions */
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        s_raffleState = RaffleState.OPEN;
        i_callbackGasLimit = callbackGasLimit;
    }

    function enterRaffle() external payable {
        // Checks
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughETHSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_RaffleNotOpen();
        }
        // Effects (our logic)
        s_players.push(payable(msg.sender));
        // Interactions (other contracts or external transactions)
        emit EnteredRaffle(msg.sender);
    }

    // When is the winner supposed to be picked?
    /**
     * @dev This is the function that the Chainlink Automation nodes call
     * to see if it's time to perform an upkeep.
     * the following should be true for this to return true;
     * 1. The time interval has passed between raffle runs
     * 2. the raffle is in an open STATE
     * 3. The contract has ETH (aka, players)
     * 4. (Implicit) the subscription is funded with LINK
     * @return upkeepNeeded : for us the upkeep is needed when the lottery duration has passed and it's really to pick a winner
     * @return performData : not used in our case, it used if there is any additional data that needs to be passed to performUpkeep function
     */
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        // Checks
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) > i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasPlayers && hasBalance);
        return (upkeepNeeded, "0x0");
    }

    // This function is called by the Chainlink Automation nodes to perform the upkeep
    // this is the pick the winner function
    // 1. Get a random number ✅
    // 2. use the random number to pick a winner ✅
    // 3. Be automatically called after the lottery duration
    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                s_raffleState,
                block.timestamp - s_lastTimeStamp
            );
        }

        // Effects (our logic)
        // 1. request the RNG
        // 2. Get the random number
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, // keyHash
            i_subscriptionId, // the id that you funded with LINK
            REQUEST_CONFIRMATIONS, // the number of block confirmations for your random number to be considered good
            i_callbackGasLimit, // to make sure we don't over spend on this call
            NUM_WORDS // number of random words requested
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        // Effects (our logic)
        uint256 randomNumber = randomWords[0] % s_players.length;
        address payable winner = s_players[randomNumber];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;

        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        // Interactions (other contracts or external transactions)
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPick(winner);
    }

    /** Getters Functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getPlayersLenght() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
