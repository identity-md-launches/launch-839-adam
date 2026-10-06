// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ADAM} from "../src/ADAM.sol";

/// @dev Independent balance/allowance model over a closed set of holders.
contract ADAMHandler is Test {
    ADAM private immutable token;
    address[4] public actors = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(ADAM token_, uint256 supply) {
        token = token_;
        expectedBalance[actors[0]] = supply;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        amount = bound(amount, 0, approved < available ? approved : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (approved != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
    }

    // Explicit edges keep maximum approvals and revocations reachable in every campaign.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = unlimited ? type(uint256).max : 0;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    // Rejected calls leave the ghost model unchanged. The invariants then check every
    // holder and approval, including accounts unrelated to the rejected operation.
    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function revokeAndRejectSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function rejectTransferFromAboveBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amount,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectTransferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        if (delegated) {
            vm.prank(owner);
            assertTrue(token.approve(spender, amount));
            expectedAllowance[owner][spender] = amount;
        }
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract ADAMInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    ADAM private token;
    ADAMHandler private handler;

    function setUp() public {
        vm.prank(address(0x1001));
        token = new ADAM();
        handler = new ADAMHandler(token, SUPPLY);
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = ADAMHandler.transfer.selector;
        selectors[1] = ADAMHandler.approve.selector;
        selectors[2] = ADAMHandler.transferFrom.selector;
        selectors[3] = ADAMHandler.approveBoundary.selector;
        selectors[4] = ADAMHandler.transferFullBalance.selector;
        selectors[5] = ADAMHandler.rejectTransferAboveBalance.selector;
        selectors[6] = ADAMHandler.revokeAndRejectSpend.selector;
        selectors[7] = ADAMHandler.rejectTransferFromAboveBalance.selector;
        selectors[8] = ADAMHandler.rejectTransferToZero.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_allowancesMatchAuthorizations() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function test_handlerSequenceWithFailuresAndReauthorization() public {
        handler.transferFullBalance(0, 1);
        handler.approveBoundary(1, 2, true);
        handler.transferFrom(1, 2, 3, SUPPLY / 2);
        handler.rejectTransferAboveBalance(1, 1, type(uint256).max);
        handler.rejectTransferFromAboveBalance(1, 2, 3, SUPPLY, false);
        handler.rejectTransferToZero(1, 2, SUPPLY / 2, true);
        handler.revokeAndRejectSpend(1, 2, 3);
        handler.approveBoundary(1, 2, true);
        handler.transferFrom(1, 2, 3, SUPPLY / 2);
        handler.transferFullBalance(3, 0);
        invariant_supplyAndBalancesAreConserved();
        invariant_allowancesMatchAuthorizations();
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), type(uint256).max);
    }
}
