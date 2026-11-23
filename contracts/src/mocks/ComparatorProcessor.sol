// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICircuitProcessor} from "../interfaces/ICircuitProcessor.sol";

/// @notice Simulates the real TapeOut time-comparator circuit.
/// Input: 8 bytes — uint32 currentBlock (bytes 0-3) + uint32 targetBlock (bytes 4-7).
/// Output: 0x01 if currentBlock >= targetBlock, 0x00 otherwise.
contract ComparatorProcessor is ICircuitProcessor {
    function eval(uint256, bytes calldata inputs) external pure override returns (bytes memory) {
        if (inputs.length < 8) return abi.encodePacked(uint8(0));
        uint32 current = uint32(bytes4(inputs[0:4]));
        uint32 target = uint32(bytes4(inputs[4:8]));
        return abi.encodePacked(current >= target ? uint8(1) : uint8(0));
    }

    function step(uint256, bytes calldata state, bytes calldata inputs)
        external
        pure
        override
        returns (bytes memory, bytes memory)
    {
        uint8 out = 0;
        if (inputs.length >= 8) {
            uint32 current = uint32(bytes4(inputs[0:4]));
            uint32 target = uint32(bytes4(inputs[4:8]));
            out = current >= target ? uint8(1) : uint8(0);
        }
        return (state, abi.encodePacked(out));
    }

    function circuitInfo(uint256)
        external
        pure
        override
        returns (uint32 nIn, uint32 nOut, uint32 nState, uint32 gateCount)
    {
        return (64, 1, 0, 352);
    }

    function netlist(uint256) external pure override returns (bytes memory) {
        return "";
    }
}
