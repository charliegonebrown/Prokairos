// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {CircuitScheduler} from "../src/CircuitScheduler.sol";
import {MockProcessor} from "../src/mocks/MockProcessor.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract DeployTestnet is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        MockProcessor processor = new MockProcessor();
        console.log("MockProcessor:", address(processor));

        MockERC20 usdc = new MockERC20("Test USDC", "USDC", 6);
        console.log("MockERC20 (USDC):", address(usdc));

        CircuitScheduler scheduler = new CircuitScheduler();
        console.log("CircuitScheduler:", address(scheduler));

        processor.setResultBool(1, true);

        vm.stopBroadcast();
    }
}

contract DeployMainnet is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        CircuitScheduler scheduler = new CircuitScheduler();
        console.log("CircuitScheduler:", address(scheduler));

        vm.stopBroadcast();
    }
}
