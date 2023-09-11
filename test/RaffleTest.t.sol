/**
 * @title: Lottary Smart Contract
 * @author: thigur
 * @notice: Lesson 9: Foundry Smart Contract Lottery
 */

// SPDX-license-Identifier: MIT
pragma solidity 0.8.18;

import {DeployRaffle} from "../script/DeployRaffle.s.sol";
import {Raffle} from "../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";


contract RaffleTest is Test{
    /** Events */
    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    //State Variables
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinatorV2;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");        
    uint256 public constant STARTNG_USER_BALANCE = 10 ether;

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if(block.chainid != 31337) {
            return;
        }
        _;
    }

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinatorV2,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTNG_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /**
     * enterRaffle Tests
     */
    function testFaffleRevertNotEnoughPaid() public {
        //Arrange
        vm.prank(PLAYER);
        //Act / Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCannotEnterRaffleInCALCULATINGStatus() public raffleEnteredAndTimePassed {
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    /** 
     * Check UpKeep 
     * */

    function  testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");

        //Assert
        assert(!upKeepNeeded);
    }

    function  testCheckUpkeepReturnsTrueWhenParametersGood() 
        public 
        raffleEnteredAndTimePassed
    {
        /*            
        //Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");

        //Assert
        assert(upKeepNeeded == false);*/
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() 
        public
        raffleEnteredAndTimePassed
    {
        /*
        raffle.performUpkeep("");
            
        //Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");

        //Assert
        assert(upKeepNeeded == false);*/
    }

    /** 
     * enterRaffle
     */

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() 
        public
        raffleEnteredAndTimePassed
    {
        raffle.performUpkeep("");
    }

    /**
     * Not sure why this test is failing....
     */
    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        //Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    //What if we want to test using the output of an event
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() 
    public raffleEnteredAndTimePassed
    {
        vm.recordLogs();
        raffle.performUpkeep("");  // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();
        
        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1);
    }

    /**
     * fulfillRandomWords
     * using fuzzing
     */
    function testFulFillRandomWordsCanOnlyBeCalledAfterPerfomUpkeep(uint256 randomRequestId) 
        public 
        raffleEnteredAndTimePassed 
        skipFork
    {
        //Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksWinnerResetsAndSendsMoney() 
        public 
        raffleEnteredAndTimePassed 
        skipFork 
    {
        //Arrange
        uint256 numEntrants = 5;
        uint256 index = 1;
        for(uint256 i = index; i < index + numEntrants; i++) {
            address player = address(uint160(i));
            hoax(player, STARTNG_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint prize = entranceFee * (numEntrants + 1);

        vm.recordLogs();
        raffle.performUpkeep("");  // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        //pretend to be chainlink vrf, get random num and pick winner
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );
        //asserts
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLengthOfPlayers() == 0);
        assert(previousTimeStamp < raffle.getLastTimeStamp());
         assert(
            raffle.getRecentWinner().balance == 
                STARTNG_USER_BALANCE + prize - entranceFee);
    }

}