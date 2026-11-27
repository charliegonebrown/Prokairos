// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CircuitScheduler} from "../src/CircuitScheduler.sol";
import {MockProcessor} from "../src/mocks/MockProcessor.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Full E2E on an X Layer mainnet fork.
/// Run: forge test --fork-url https://rpc.xlayer.tech -vv --match-contract MainnetForkTest
contract MainnetForkTest is Test {
    CircuitScheduler scheduler;
    MockProcessor processor;
    MockERC20 usdc;

    address deployer = address(0xA11CE);
    address submitter = address(0xB0B);
    address receiver = address(0xBEEF);

    function setUp() public {
        vm.startPrank(deployer);

        processor = new MockProcessor();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        scheduler = new CircuitScheduler();

        usdc.mint(deployer, 1000e6);
        usdc.approve(address(scheduler), type(uint256).max);

        vm.stopPrank();
    }

    function test_fullE2E_mainnetFork() public {
        console.log("=== Prokairos Mainnet Fork E2E ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block:", block.number);
        console.log("");

        // --- Circuit starts as NOT ready ---
        processor.setResultBool(1, false);
        console.log("[1] Circuit set to WAIT (output=0)");

        // --- Create recurring schedule: 10 USDC x3, 0.5 tip ---
        vm.startPrank(deployer);
        uint256 startBlock = block.number + 1;
        uint256 schedId = scheduler.createSchedule(
            receiver,
            IERC20(address(usdc)),
            10e6, 0.5e6,
            address(processor), 1,
            abi.encodePacked(uint32(startBlock)),
            startBlock, 100, 3,
            block.number + 100000
        );
        vm.stopPrank();

        console.log("[2] Created recurring schedule ID:", schedId);
        console.log("    Locked: 31.5 USDC (3 x 10.5)");
        assertEq(usdc.balanceOf(address(scheduler)), 31.5e6);

        // --- isReady should be false (circuit = 0) ---
        vm.roll(startBlock);
        assertFalse(scheduler.isReady(schedId));
        console.log("[3] isReady = false while circuit=0: PASS");

        // --- Flip circuit to GO ---
        processor.setResultBool(1, true);
        assertTrue(scheduler.isReady(schedId));
        console.log("[4] Circuit flipped to GO. isReady = true: PASS");

        // --- Submitter executes run #1, earns tip ---
        vm.prank(submitter);
        scheduler.execute(schedId);

        assertEq(usdc.balanceOf(receiver), 10e6);
        assertEq(usdc.balanceOf(submitter), 0.5e6);
        console.log("[5] Execute #1: receiver got 10 USDC, submitter got 0.5 tip: PASS");

        // --- Double-execute should revert ---
        vm.prank(submitter);
        vm.expectRevert(CircuitScheduler.NotReady.selector);
        scheduler.execute(schedId);
        console.log("[6] Double-execute reverted (NotReady): PASS");

        // --- Roll to next interval, execute run #2 ---
        vm.roll(block.number + 100);
        vm.prank(submitter);
        scheduler.execute(schedId);

        assertEq(usdc.balanceOf(receiver), 20e6);
        assertEq(usdc.balanceOf(submitter), 1e6);
        console.log("[7] Execute #2 after interval: receiver=20, tips=1 USDC: PASS");

        // --- Payer cancels, gets refund for remaining 1 run ---
        uint256 balBefore = usdc.balanceOf(deployer);
        vm.prank(deployer);
        scheduler.cancel(schedId);

        uint256 refunded = usdc.balanceOf(deployer) - balBefore;
        assertEq(refunded, 10.5e6);
        console.log("[8] Cancel: refunded 10.5 USDC (1 remaining run): PASS");

        // --- Create one-time schedule, then reclaim after deadline ---
        vm.startPrank(deployer);
        uint256 deadline = block.number + 50;
        uint256 id2 = scheduler.createSchedule(
            receiver, IERC20(address(usdc)),
            5e6, 0.25e6,
            address(processor), 1,
            abi.encodePacked(uint32(block.number + 1)),
            block.number + 1, 0, 1, deadline
        );
        vm.stopPrank();
        console.log("[9] Created one-time schedule ID:", id2);

        vm.roll(deadline + 1);
        balBefore = usdc.balanceOf(deployer);
        vm.prank(deployer);
        scheduler.reclaim(id2);
        refunded = usdc.balanceOf(deployer) - balBefore;
        assertEq(refunded, 5.25e6);
        console.log("[9] Reclaimed after deadline: 5.25 USDC returned: PASS");

        console.log("");
        console.log("=========================================");
        console.log("  ALL TESTS PASSED ON X LAYER MAINNET FORK");
        console.log("=========================================");
        console.log("  - Contract deploys on mainnet EVM");
        console.log("  - Schedule creation + fund locking");
        console.log("  - Circuit gating (wait -> go)");
        console.log("  - Execute pays receiver + tip to submitter");
        console.log("  - Double-execute prevented");
        console.log("  - Recurring payments with intervals");
        console.log("  - Cancel + refund");
        console.log("  - Reclaim after deadline");
    }
}
