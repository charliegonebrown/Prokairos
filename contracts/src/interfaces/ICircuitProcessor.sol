// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICircuitProcessor {
    function eval(uint256 id, bytes calldata inputs) external view returns (bytes memory);

    function step(
        uint256 id,
        bytes calldata state,
        bytes calldata inputs
    ) external view returns (bytes memory newState, bytes memory outputs);

    function circuitInfo(uint256 id)
        external
        view
        returns (uint32 nIn, uint32 nOut, uint32 nState, uint32 gateCount);

    function netlist(uint256 id) external view returns (bytes memory);
}
