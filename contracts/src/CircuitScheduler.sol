// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ICircuitProcessor} from "./interfaces/ICircuitProcessor.sol";

contract CircuitScheduler is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Schedule {
        address payer;
        address receiver;
        IERC20 token;
        uint256 amount;
        uint256 tip;
        address processor;
        uint256 circuitId;
        bytes circuitInputSpec;
        uint256 startBlock;
        uint256 interval;
        uint256 remaining;
        uint256 deadline;
        uint256 nextDue;
        uint256 balance;
        bool cancelled;
    }

    uint256 private _nextId = 1;
    mapping(uint256 => Schedule) private _schedules;
    mapping(address => uint256[]) private _userSchedules;

    event ScheduleCreated(
        uint256 indexed id,
        address indexed payer,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 tip,
        address processor,
        uint256 circuitId,
        uint256 startBlock,
        uint256 interval,
        uint256 remaining,
        uint256 deadline
    );

    event ScheduleExecuted(
        uint256 indexed id,
        address indexed submitter,
        address indexed receiver,
        uint256 amount,
        uint256 tip,
        uint256 runsLeft
    );

    event ScheduleCancelled(uint256 indexed id, uint256 refunded);
    event ScheduleReclaimed(uint256 indexed id, uint256 refunded);

    error NotPayer();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidSchedule();
    error NotReady();
    error AlreadyCancelled();
    error NoRunsLeft();
    error DeadlinePassed();
    error DeadlineNotPassed();
    error NothingToRefund();

    function createSchedule(
        address receiver,
        IERC20 token,
        uint256 amount,
        uint256 tip,
        address processor,
        uint256 circuitId,
        bytes calldata circuitInputSpec,
        uint256 startBlock,
        uint256 interval,
        uint256 remaining,
        uint256 deadline
    ) external returns (uint256 id) {
        if (receiver == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (remaining == 0) revert InvalidSchedule();
        if (deadline <= block.number) revert InvalidSchedule();
        if (startBlock < block.number) revert InvalidSchedule();
        if (interval == 0 && remaining != 1) revert InvalidSchedule();

        uint256 total = remaining * (amount + tip);

        id = _nextId++;

        _schedules[id] = Schedule({
            payer: msg.sender,
            receiver: receiver,
            token: token,
            amount: amount,
            tip: tip,
            processor: processor,
            circuitId: circuitId,
            circuitInputSpec: circuitInputSpec,
            startBlock: startBlock,
            interval: interval,
            remaining: remaining,
            deadline: deadline,
            nextDue: startBlock,
            balance: total,
            cancelled: false
        });

        _userSchedules[msg.sender].push(id);

        token.safeTransferFrom(msg.sender, address(this), total);

        emit ScheduleCreated(
            id,
            msg.sender,
            receiver,
            address(token),
            amount,
            tip,
            processor,
            circuitId,
            startBlock,
            interval,
            remaining,
            deadline
        );
    }

    function _buildCircuitInput(Schedule storage s) internal view returns (bytes memory) {
        return abi.encodePacked(uint32(block.number), s.circuitInputSpec);
    }

    function isReady(uint256 id) public view returns (bool) {
        Schedule storage s = _schedules[id];
        if (s.payer == address(0)) return false;
        if (s.cancelled) return false;
        if (s.remaining == 0) return false;
        if (block.number < s.nextDue) return false;
        if (block.number > s.deadline) return false;
        if (s.balance < s.amount + s.tip) return false;

        bytes memory result = ICircuitProcessor(s.processor).eval(s.circuitId, _buildCircuitInput(s));
        if (result.length == 0) return false;
        return uint8(result[0]) == 1;
    }

    function execute(uint256 id) external nonReentrant {
        Schedule storage s = _schedules[id];
        if (s.cancelled) revert AlreadyCancelled();
        if (s.remaining == 0) revert NoRunsLeft();
        if (block.number < s.nextDue) revert NotReady();
        if (block.number > s.deadline) revert DeadlinePassed();

        bytes memory result = ICircuitProcessor(s.processor).eval(s.circuitId, _buildCircuitInput(s));
        if (result.length == 0 || uint8(result[0]) != 1) revert NotReady();

        s.remaining--;
        s.balance -= (s.amount + s.tip);

        if (s.remaining > 0 && s.interval > 0) {
            s.nextDue = block.number + s.interval;
        }

        s.token.safeTransfer(s.receiver, s.amount);
        if (s.tip > 0) {
            s.token.safeTransfer(msg.sender, s.tip);
        }

        emit ScheduleExecuted(id, msg.sender, s.receiver, s.amount, s.tip, s.remaining);
    }

    function cancel(uint256 id) external {
        Schedule storage s = _schedules[id];
        if (msg.sender != s.payer) revert NotPayer();
        if (s.cancelled) revert AlreadyCancelled();

        s.cancelled = true;
        uint256 refund = s.balance;
        s.balance = 0;

        if (refund > 0) {
            s.token.safeTransfer(s.payer, refund);
        }

        emit ScheduleCancelled(id, refund);
    }

    function reclaim(uint256 id) external {
        Schedule storage s = _schedules[id];
        if (msg.sender != s.payer) revert NotPayer();
        if (block.number <= s.deadline) revert DeadlineNotPassed();

        uint256 refund = s.balance;
        if (refund == 0) revert NothingToRefund();

        s.balance = 0;
        s.remaining = 0;
        s.token.safeTransfer(s.payer, refund);

        emit ScheduleReclaimed(id, refund);
    }

    function getSchedule(uint256 id) external view returns (Schedule memory) {
        return _schedules[id];
    }

    function schedulesOf(address addr) external view returns (uint256[] memory) {
        return _userSchedules[addr];
    }

    function scheduleCount() external view returns (uint256) {
        return _nextId - 1;
    }
}
