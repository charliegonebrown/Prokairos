// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CircuitScheduler} from "../src/CircuitScheduler.sol";
import {ComparatorProcessor} from "../src/mocks/ComparatorProcessor.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CircuitSchedulerIntegrationTest is Test {
    CircuitScheduler public scheduler;
    ComparatorProcessor public processor;
    MockERC20 public token;

    address payer = makeAddr("payer");
    address receiver = makeAddr("receiver");
    address submitter = makeAddr("submitter");

    uint256 constant AMOUNT = 10e6;
    uint256 constant TIP = 1e6;
    uint256 constant CIRCUIT_ID = 1;

    function setUp() public {
        scheduler = new CircuitScheduler();
        processor = new ComparatorProcessor();
        token = new MockERC20("Test USDC", "USDC", 6);

        token.mint(payer, 1000e6);
        vm.prank(payer);
        token.approve(address(scheduler), type(uint256).max);
    }

    function test_integration_oneTimePayment() public {
        uint256 targetBlock = block.number + 100;

        // circuitInputSpec = target block as uint32 big-endian
        bytes memory inputSpec = abi.encodePacked(uint32(targetBlock));

        vm.prank(payer);
        uint256 id = scheduler.createSchedule(
            receiver,
            IERC20(address(token)),
            AMOUNT,
            TIP,
            address(processor),
            CIRCUIT_ID,
            inputSpec,
            block.number + 1,
            0,
            1,
            targetBlock + 1000
        );

        // Before target block: circuit returns 0, not ready
        vm.roll(targetBlock - 1);
        assertFalse(scheduler.isReady(id));

        // At target block: circuit returns 1, ready
        vm.roll(targetBlock);
        assertTrue(scheduler.isReady(id));

        // Execute
        vm.prank(submitter);
        scheduler.execute(id);

        assertEq(token.balanceOf(receiver), AMOUNT);
        assertEq(token.balanceOf(submitter), TIP);
    }

    function test_integration_recurringPayment() public {
        // Use vm.getBlockNumber() to avoid via_ir re-reading block.number after vm.roll
        uint256 startBlock = vm.getBlockNumber() + 50;
        uint256 interval = 100;

        bytes memory inputSpec = abi.encodePacked(uint32(startBlock));

        vm.prank(payer);
        uint256 id = scheduler.createSchedule(
            receiver,
            IERC20(address(token)),
            AMOUNT,
            TIP,
            address(processor),
            CIRCUIT_ID,
            inputSpec,
            startBlock,
            interval,
            3,
            startBlock + 10000
        );

        // Not ready before start
        vm.roll(startBlock - 1);
        assertFalse(scheduler.isReady(id));

        // First run at startBlock
        vm.roll(startBlock);
        assertTrue(scheduler.isReady(id));
        vm.prank(submitter);
        scheduler.execute(id);

        // After execute, nextDue = block.number + interval
        uint256 nextDue1 = vm.getBlockNumber() + interval;

        // Not ready one block before nextDue
        vm.roll(nextDue1 - 1);
        assertFalse(scheduler.isReady(id));

        // Second run at nextDue
        vm.roll(nextDue1);
        assertTrue(scheduler.isReady(id));
        vm.prank(submitter);
        scheduler.execute(id);

        // Third run
        uint256 nextDue2 = vm.getBlockNumber() + interval;
        vm.roll(nextDue2);
        assertTrue(scheduler.isReady(id));
        vm.prank(submitter);
        scheduler.execute(id);

        // All done
        assertEq(token.balanceOf(receiver), AMOUNT * 3);
        assertEq(token.balanceOf(submitter), TIP * 3);
        assertEq(scheduler.getSchedule(id).remaining, 0);
    }

    function test_integration_cancelAndRefund() public {
        uint256 targetBlock = block.number + 100;
        bytes memory inputSpec = abi.encodePacked(uint32(targetBlock));

        vm.prank(payer);
        uint256 id = scheduler.createSchedule(
            receiver,
            IERC20(address(token)),
            AMOUNT,
            TIP,
            address(processor),
            CIRCUIT_ID,
            inputSpec,
            block.number + 1,
            0,
            1,
            targetBlock + 1000
        );

        uint256 balBefore = token.balanceOf(payer);
        vm.prank(payer);
        scheduler.cancel(id);

        assertEq(token.balanceOf(payer) - balBefore, AMOUNT + TIP);
        assertFalse(scheduler.isReady(id));
    }

    function test_integration_reclaimAfterDeadline() public {
        uint256 targetBlock = block.number + 10000;
        uint256 deadline = block.number + 500;
        bytes memory inputSpec = abi.encodePacked(uint32(targetBlock));

        vm.prank(payer);
        uint256 id = scheduler.createSchedule(
            receiver,
            IERC20(address(token)),
            AMOUNT,
            TIP,
            address(processor),
            CIRCUIT_ID,
            inputSpec,
            block.number + 1,
            0,
            1,
            deadline
        );

        // Circuit won't return 1 until block 10000, but deadline is 500
        vm.roll(deadline + 1);
        assertFalse(scheduler.isReady(id));

        uint256 balBefore = token.balanceOf(payer);
        vm.prank(payer);
        scheduler.reclaim(id);

        assertEq(token.balanceOf(payer) - balBefore, AMOUNT + TIP);
    }

    function test_integration_anyoneCanSubmit() public {
        uint256 targetBlock = block.number + 10;
        bytes memory inputSpec = abi.encodePacked(uint32(targetBlock));

        vm.prank(payer);
        uint256 id = scheduler.createSchedule(
            receiver,
            IERC20(address(token)),
            AMOUNT,
            TIP,
            address(processor),
            CIRCUIT_ID,
            inputSpec,
            block.number + 1,
            0,
            1,
            targetBlock + 1000
        );

        vm.roll(targetBlock);

        // Random wallet submits and earns the tip
        address randomWallet = makeAddr("random");
        vm.prank(randomWallet);
        scheduler.execute(id);

        assertEq(token.balanceOf(receiver), AMOUNT);
        assertEq(token.balanceOf(randomWallet), TIP);
    }
}
