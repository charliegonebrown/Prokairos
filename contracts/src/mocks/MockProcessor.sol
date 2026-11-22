// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICircuitProcessor} from "../interfaces/ICircuitProcessor.sol";

contract MockProcessor is ICircuitProcessor {
    mapping(uint256 => bytes) private _results;

    function setResult(uint256 id, bytes calldata result) external {
        _results[id] = result;
    }

    function setResultBool(uint256 id, bool value) external {
        _results[id] = value ? abi.encodePacked(uint8(1)) : abi.encodePacked(uint8(0));
    }

    function eval(uint256 id, bytes calldata) external view override returns (bytes memory) {
        return _results[id];
    }

    function step(uint256 id, bytes calldata state, bytes calldata)
        external
        view
        override
        returns (bytes memory, bytes memory)
    {
        return (state, _results[id]);
    }

    function circuitInfo(uint256)
        external
        pure
        override
        returns (uint32 nIn, uint32 nOut, uint32 nState, uint32 gateCount)
    {
        return (32, 1, 0, 50);
    }

    function netlist(uint256) external pure override returns (bytes memory) {
        return "";
    }
}
