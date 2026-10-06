// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title ADAM
/// @notice Fixed-supply ERC-20: one billion ADAM, with 18 decimals.
/// @dev The immediate constructor caller receives the entire supply, including when deployed by a factory.
contract ADAM is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("ADAM", "ADAM") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
