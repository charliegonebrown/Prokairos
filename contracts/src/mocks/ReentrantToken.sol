// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Malicious ERC20 that re-enters CircuitScheduler.execute() on transfer.
contract ReentrantToken is ERC20 {
    address public target;
    uint256 public attackId;
    bool public armed;

    constructor() ERC20("Reentrant", "REENTER") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(address target_, uint256 id_) external {
        target = target_;
        attackId = id_;
        armed = true;
    }

    function disarm() external {
        armed = false;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool result = super.transfer(to, amount);
        if (armed && msg.sender == target) {
            armed = false;
            (bool ok,) = target.call(abi.encodeWithSignature("execute(uint256)", attackId));
            // We don't revert if the re-entrant call fails — that's the expected outcome
            ok;
        }
        return result;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        return super.transferFrom(from, to, amount);
    }
}
