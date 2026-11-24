// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CircuitScheduler} from "../src/CircuitScheduler.sol";
import {MockProcessor} from "../src/mocks/MockProcessor.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {ReentrantToken} from "../src/mocks/ReentrantToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CircuitSchedulerTest is Test {
    CircuitScheduler public scheduler;
    MockProcessor public processor;
    MockERC20 public token;

    address payer = makeAddr("payer");
    address receiver = makeAddr("receiver");
    address submitter = makeAddr("submitter");

    uint256 constant AMOUNT = 10e6;
    uint256 constant TIP = 1e6;
    uint256 constant CIRCUIT_ID = 1;

    function setUp() public {
        scheduler = new CircuitScheduler();
        processor = new MockProcessor();
        token = new MockERC20("Test USDC", "USDC", 6);

        token.mint(payer, 1000e6);
        vm.prank(payer);
        token.approve(address(scheduler), type(uint256).max);

        processor.setResultBool(CIRCUIT_ID, true);
    }

    function _createOneTime(uint256 startBlock, uint256 deadline) internal returns (uint256) {
        vm.prank(payer);
        return scheduler.createSchedule(
            receiver,
            IERC20(address(token)),
            AMOUNT,
            TIP,
            address(processor),
            CIRCUIT_ID,
            "",
            startBlock,
            0,
            1,
            deadline
        );
    }

    function _createRecurring(uint256 startBlock, uint256 interval, uint256 count, uint256 deadline)
        internal
        returns (uint256)
    {
        vm.prank(payer);
        return scheduler.createSchedule(
            receiver,
            IERC20(address(token)),
            AMOUNT,
            TIP,
            address(processor),
            CIRCUIT_ID,
            "",
            startBlock,
            interval,
            count,
            deadline
        );
    }

    // --- Creation tests ---

    function test_createSchedule_oneTime() public {
        uint256 startBlock = block.number + 10;
        uint256 deadline = block.number + 100;

        uint256 id = _createOneTime(startBlock, deadline);
        assertEq(id, 1);

        CircuitScheduler.Schedule memory s = scheduler.getSchedule(id);
        assertEq(s.payer, payer);
        assertEq(s.receiver, receiver);
        assertEq(s.amount, AMOUNT);
        assertEq(s.tip, TIP);
        assertEq(s.remaining, 1);
        assertEq(s.interval, 0);
        assertEq(s.nextDue, startBlock);
        assertEq(s.balance, AMOUNT + TIP);
        assertFalse(s.cancelled);
    }

    function test_createSchedule_recurring() public {
        uint256 startBlock = block.number + 10;
        uint256 deadline = block.number + 1000;

        uint256 id = _createRecurring(startBlock, 50, 3, deadline);

        CircuitScheduler.Schedule memory s = scheduler.getSchedule(id);
        assertEq(s.remaining, 3);
        assertEq(s.interval, 50);
        assertEq(s.balance, 3 * (AMOUNT + TIP));
    }

    function test_createSchedule_pullsFunds() public {
        uint256 balBefore = token.balanceOf(payer);
        _createOneTime(block.number + 10, block.number + 100);
        uint256 balAfter = token.balanceOf(payer);
        assertEq(balBefore - balAfter, AMOUNT + TIP);
    }

    function test_createSchedule_tracksUser() public {
        _createOneTime(block.number + 10, block.number + 100);
        _createOneTime(block.number + 20, block.number + 200);

        uint256[] memory ids = scheduler.schedulesOf(payer);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
    }

    function test_createSchedule_revertsZeroReceiver() public {
        vm.prank(payer);
        vm.expectRevert(CircuitScheduler.ZeroAddress.selector);
        scheduler.createSchedule(
            address(0), IERC20(address(token)), AMOUNT, TIP,
            address(processor), CIRCUIT_ID, "", block.number + 10, 0, 1, block.number + 100
        );
    }

    function test_createSchedule_revertsZeroAmount() public {
        vm.prank(payer);
        vm.expectRevert(CircuitScheduler.ZeroAmount.selector);
        scheduler.createSchedule(
            receiver, IERC20(address(token)), 0, TIP,
            address(processor), CIRCUIT_ID, "", block.number + 10, 0, 1, block.number + 100
        );
    }

    function test_createSchedule_revertsZeroRemaining() public {
        vm.prank(payer);
        vm.expectRevert(CircuitScheduler.InvalidSchedule.selector);
        scheduler.createSchedule(
            receiver, IERC20(address(token)), AMOUNT, TIP,
            address(processor), CIRCUIT_ID, "", block.number + 10, 0, 0, block.number + 100
        );
    }

    function test_createSchedule_revertsIntervalZeroWithMultipleRuns() public {
        vm.prank(payer);
        vm.expectRevert(CircuitScheduler.InvalidSchedule.selector);
        scheduler.createSchedule(
            receiver, IERC20(address(token)), AMOUNT, TIP,
            address(processor), CIRCUIT_ID, "", block.number + 10, 0, 3, block.number + 100
        );
    }

    function test_createSchedule_revertsDeadlineInPast() public {
        vm.prank(payer);
        vm.expectRevert(CircuitScheduler.InvalidSchedule.selector);
        scheduler.createSchedule(
            receiver, IERC20(address(token)), AMOUNT, TIP,
            address(processor), CIRCUIT_ID, "", block.number + 10, 0, 1, block.number
        );
    }

    // --- isReady tests ---

    function test_isReady_trueWhenDue() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        assertFalse(scheduler.isReady(id));

        vm.roll(block.number + 10);
        assertTrue(scheduler.isReady(id));
    }

    function test_isReady_falseWhenCircuitReturnsZero() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        processor.setResultBool(CIRCUIT_ID, false);

        vm.roll(block.number + 10);
        assertFalse(scheduler.isReady(id));
    }

    function test_isReady_falseBeforeStartBlock() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        assertFalse(scheduler.isReady(id));
    }

    function test_isReady_falseAfterDeadline() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        vm.roll(block.number + 101);
        assertFalse(scheduler.isReady(id));
    }

    function test_isReady_falseWhenCancelled() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        vm.prank(payer);
        scheduler.cancel(id);

        vm.roll(block.number + 10);
        assertFalse(scheduler.isReady(id));
    }

    // --- Execute tests ---

    function test_execute_paysReceiverAndTip() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        vm.roll(block.number + 10);

        vm.prank(submitter);
        scheduler.execute(id);

        assertEq(token.balanceOf(receiver), AMOUNT);
        assertEq(token.balanceOf(submitter), TIP);
    }

    function test_execute_decrementsRemaining() public {
        uint256 id = _createRecurring(block.number + 10, 50, 3, block.number + 1000);
        vm.roll(block.number + 10);

        vm.prank(submitter);
        scheduler.execute(id);

        CircuitScheduler.Schedule memory s = scheduler.getSchedule(id);
        assertEq(s.remaining, 2);
        assertEq(s.balance, 2 * (AMOUNT + TIP));
    }

    function test_execute_advancesNextDue() public {
        uint256 startBlock = block.number + 10;
        uint256 id = _createRecurring(startBlock, 50, 3, block.number + 1000);
        vm.roll(startBlock);

        vm.prank(submitter);
        scheduler.execute(id);

        CircuitScheduler.Schedule memory s = scheduler.getSchedule(id);
        assertEq(s.nextDue, block.number + 50);
    }

    function test_execute_revertsBeforeNextDue() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);

        vm.prank(submitter);
        vm.expectRevert(CircuitScheduler.NotReady.selector);
        scheduler.execute(id);
    }

    function test_execute_revertsAfterDeadline() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        vm.roll(block.number + 101);

        vm.prank(submitter);
        vm.expectRevert(CircuitScheduler.DeadlinePassed.selector);
        scheduler.execute(id);
    }

    function test_execute_revertsWhenCircuitReturnsFalse() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        processor.setResultBool(CIRCUIT_ID, false);
        vm.roll(block.number + 10);

        vm.prank(submitter);
        vm.expectRevert(CircuitScheduler.NotReady.selector);
        scheduler.execute(id);
    }

    function test_execute_revertsDoubleExecute() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        vm.roll(block.number + 10);

        vm.prank(submitter);
        scheduler.execute(id);

        vm.prank(submitter);
        vm.expectRevert(CircuitScheduler.NoRunsLeft.selector);
        scheduler.execute(id);
    }

    function test_execute_revertsWhenCancelled() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        vm.prank(payer);
        scheduler.cancel(id);

        vm.roll(block.number + 10);
        vm.prank(submitter);
        vm.expectRevert(CircuitScheduler.AlreadyCancelled.selector);
        scheduler.execute(id);
    }

    function test_execute_recurringFullCycle() public {
        uint256 startBlock = block.number + 10;
        uint256 id = _createRecurring(startBlock, 50, 3, block.number + 1000);

        for (uint256 i = 0; i < 3; i++) {
            vm.roll(startBlock + i * 50);
            vm.prank(submitter);
            scheduler.execute(id);
        }

        assertEq(token.balanceOf(receiver), AMOUNT * 3);
        assertEq(token.balanceOf(submitter), TIP * 3);

        CircuitScheduler.Schedule memory s = scheduler.getSchedule(id);
        assertEq(s.remaining, 0);
        assertEq(s.balance, 0);
    }

    function test_execute_noTip() public {
        vm.prank(payer);
        uint256 id = scheduler.createSchedule(
            receiver, IERC20(address(token)), AMOUNT, 0,
            address(processor), CIRCUIT_ID, "", block.number + 10, 0, 1, block.number + 100
        );

        vm.roll(block.number + 10);
        vm.prank(submitter);
        scheduler.execute(id);

        assertEq(token.balanceOf(receiver), AMOUNT);
        assertEq(token.balanceOf(submitter), 0);
    }

    // --- Cancel tests ---

    function test_cancel_refundsBalance() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        uint256 balBefore = token.balanceOf(payer);

        vm.prank(payer);
        scheduler.cancel(id);

        assertEq(token.balanceOf(payer) - balBefore, AMOUNT + TIP);
        assertTrue(scheduler.getSchedule(id).cancelled);
    }

    function test_cancel_partialRecurring() public {
        uint256 startBlock = block.number + 10;
        uint256 id = _createRecurring(startBlock, 50, 3, block.number + 1000);

        vm.roll(startBlock);
        vm.prank(submitter);
        scheduler.execute(id);

        uint256 balBefore = token.balanceOf(payer);
        vm.prank(payer);
        scheduler.cancel(id);

        assertEq(token.balanceOf(payer) - balBefore, 2 * (AMOUNT + TIP));
    }

    function test_cancel_revertsNotPayer() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);

        vm.prank(submitter);
        vm.expectRevert(CircuitScheduler.NotPayer.selector);
        scheduler.cancel(id);
    }

    function test_cancel_revertsDoubleCancellation() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);

        vm.prank(payer);
        scheduler.cancel(id);

        vm.prank(payer);
        vm.expectRevert(CircuitScheduler.AlreadyCancelled.selector);
        scheduler.cancel(id);
    }

    // --- Reclaim tests ---

    function test_reclaim_afterDeadline() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        processor.setResultBool(CIRCUIT_ID, false);

        vm.roll(block.number + 101);
        uint256 balBefore = token.balanceOf(payer);

        vm.prank(payer);
        scheduler.reclaim(id);

        assertEq(token.balanceOf(payer) - balBefore, AMOUNT + TIP);
    }

    function test_reclaim_revertsBeforeDeadline() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);

        vm.prank(payer);
        vm.expectRevert(CircuitScheduler.DeadlineNotPassed.selector);
        scheduler.reclaim(id);
    }

    function test_reclaim_revertsNotPayer() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        vm.roll(block.number + 101);

        vm.prank(submitter);
        vm.expectRevert(CircuitScheduler.NotPayer.selector);
        scheduler.reclaim(id);
    }

    function test_reclaim_revertsNothingToRefund() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        vm.roll(block.number + 10);

        vm.prank(submitter);
        scheduler.execute(id);

        vm.roll(block.number + 101);
        vm.prank(payer);
        vm.expectRevert(CircuitScheduler.NothingToRefund.selector);
        scheduler.reclaim(id);
    }

    // --- View tests ---

    function test_scheduleCount() public {
        assertEq(scheduler.scheduleCount(), 0);
        _createOneTime(block.number + 10, block.number + 100);
        assertEq(scheduler.scheduleCount(), 1);
        _createOneTime(block.number + 20, block.number + 200);
        assertEq(scheduler.scheduleCount(), 2);
    }

    // --- Reentrancy tests ---

    function test_execute_reentrancyBlocked() public {
        ReentrantToken malicious = new ReentrantToken();
        malicious.mint(payer, 1000e6);
        vm.prank(payer);
        malicious.approve(address(scheduler), type(uint256).max);

        processor.setResultBool(CIRCUIT_ID, true);

        vm.prank(payer);
        uint256 id = scheduler.createSchedule(
            receiver,
            IERC20(address(malicious)),
            AMOUNT,
            TIP,
            address(processor),
            CIRCUIT_ID,
            "",
            block.number + 10,
            50,
            3,
            block.number + 1000
        );

        malicious.arm(address(scheduler), id);
        vm.roll(block.number + 10);

        vm.prank(submitter);
        scheduler.execute(id);

        // Only one run should have executed despite reentrancy attempt
        CircuitScheduler.Schedule memory s = scheduler.getSchedule(id);
        assertEq(s.remaining, 2);
        assertEq(malicious.balanceOf(receiver), AMOUNT);
    }

    // --- Event tests ---

    event ScheduleCreated(
        uint256 indexed id, address indexed payer, address indexed receiver,
        address token, uint256 amount, uint256 tip, address processor,
        uint256 circuitId, uint256 startBlock, uint256 interval, uint256 remaining, uint256 deadline
    );
    event ScheduleExecuted(
        uint256 indexed id, address indexed submitter, address indexed receiver,
        uint256 amount, uint256 tip, uint256 runsLeft
    );
    event ScheduleCancelled(uint256 indexed id, uint256 refunded);
    event ScheduleReclaimed(uint256 indexed id, uint256 refunded);

    function test_event_scheduleCreated() public {
        uint256 startBlock = block.number + 10;
        uint256 deadline = block.number + 100;

        vm.expectEmit(true, true, true, true);
        emit ScheduleCreated(
            1, payer, receiver, address(token), AMOUNT, TIP,
            address(processor), CIRCUIT_ID, startBlock, 0, 1, deadline
        );

        _createOneTime(startBlock, deadline);
    }

    function test_event_scheduleExecuted() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        vm.roll(block.number + 10);

        vm.expectEmit(true, true, true, true);
        emit ScheduleExecuted(id, submitter, receiver, AMOUNT, TIP, 0);

        vm.prank(submitter);
        scheduler.execute(id);
    }

    function test_event_scheduleCancelled() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);

        vm.expectEmit(true, false, false, true);
        emit ScheduleCancelled(id, AMOUNT + TIP);

        vm.prank(payer);
        scheduler.cancel(id);
    }

    function test_event_scheduleReclaimed() public {
        uint256 id = _createOneTime(block.number + 10, block.number + 100);
        processor.setResultBool(CIRCUIT_ID, false);
        vm.roll(block.number + 101);

        vm.expectEmit(true, false, false, true);
        emit ScheduleReclaimed(id, AMOUNT + TIP);

        vm.prank(payer);
        scheduler.reclaim(id);
    }

    // --- startBlock in past ---

    function test_createSchedule_revertsStartBlockInPast() public {
        vm.roll(100);
        vm.prank(payer);
        vm.expectRevert(CircuitScheduler.InvalidSchedule.selector);
        scheduler.createSchedule(
            receiver, IERC20(address(token)), AMOUNT, TIP,
            address(processor), CIRCUIT_ID, "", block.number - 1, 0, 1, block.number + 100
        );
    }
}
