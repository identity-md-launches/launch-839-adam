// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ADAM} from "../src/ADAM.sol";

contract FactoryProbe {
    function deploy(bytes32 salt) external returns (ADAM) {
        return new ADAM{salt: salt}();
    }

    function send(ADAM token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract RejectingReceiver {
    fallback() external {
        revert("ERC-20 transfers must not call the recipient");
    }
}

contract ADAMTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant DEPLOYER = address(0xD0);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    ADAM private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new ADAM();
    }

    function test_metadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "ADAM");
        assertEq(token.symbol(), "ADAM");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        ADAM another = new ADAM();
        assertEq(another.balanceOf(ALICE), SUPPLY);
    }

    function test_factoryCreate2OwnsSupplyAndLaunchTransfersArriveWhole() public {
        FactoryProbe factory = new FactoryProbe();
        vm.prank(ALICE, ALICE);
        ADAM launched = factory.deploy(bytes32(uint256(1)));
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(ALICE), 0);

        uint256 swarm = SUPPLY / 10;
        assertTrue(factory.send(launched, SPENDER, swarm));
        assertEq(launched.balanceOf(SPENDER), swarm);
        vm.prank(SPENDER);
        assertTrue(launched.transfer(BOB, swarm));
        assertEq(launched.balanceOf(SPENDER), 0);
        assertEq(launched.balanceOf(BOB), swarm);
        assertTrue(factory.send(launched, ALICE, SUPPLY - swarm));
        assertEq(launched.balanceOf(ALICE), SUPPLY - swarm);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(DEPLOYER, ALICE, 123 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 123 ether));
        assertEq(token.balanceOf(ALICE), 123 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanMoveAndReturn() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(DEPLOYER, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_selfTransferPreservesBalance() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(DEPLOYER, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferStillRequiresBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(ALICE, 1);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.startPrank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.stopPrank();
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferDoesNotInvokeRecipient() public {
        RejectingReceiver recipient = new RejectingReceiver();
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(address(recipient), 1 ether));
        assertEq(token.balanceOf(address(recipient)), 1 ether);
    }

    function test_approveEmitsEventThenReplacesAndRevokesAllowance() public {
        vm.startPrank(DEPLOYER);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(DEPLOYER, SPENDER, 100 ether);
        assertTrue(token.approve(SPENDER, 100 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 100 ether);
        assertTrue(token.approve(SPENDER, 30 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 30 ether);
        assertTrue(token.approve(SPENDER, 0));
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, BOB, 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_approvalDoesNotRequireTokensOrMoveTokens() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(DEPLOYER);
        token.approve(address(0), 1);
        assertEq(token.allowance(DEPLOYER, address(0)), 0);
    }

    function test_transferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(DEPLOYER, ALICE, 40 ether);
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 40 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 60 ether);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 60 ether));
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 100 ether);
        assertEq(token.balanceOf(ALICE), 40 ether);
        assertEq(token.balanceOf(BOB), 60 ether);
    }

    function test_transferFromKeepsMaximumAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, SUPPLY));
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_transferFromToSameHolderConsumesAllowanceWithoutChangingBalance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, DEPLOYER, 10));
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_zeroTransferFromWithoutApprovalSucceeds() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_zeroTransferFromZeroSenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_holderNeedsAllowanceWhenUsingTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(DEPLOYER, ALICE, 1);
    }

    function test_deployerCannotTakeAnotherHoldersTokens() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(ALICE, DEPLOYER, 1);
        assertEq(token.balanceOf(ALICE), 1 ether);
    }

    function test_transferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, SPENDER), 10);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromZeroRecipientRollsBackAllowanceAndBalances() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, address(0), 10);
        assertEq(token.allowance(DEPLOYER, SPENDER), 10);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noMintBurnFreezeSeizeOrUpgradeEntryPoints() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100);
        bytes[] memory calls = new bytes[](15);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[7] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[8] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[10] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[11] = abi.encodeWithSignature("setMinter(address)", BOB);
        calls[12] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[13] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[14] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(DEPLOYER);
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess);
            vm.prank(BOB);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess);
        }
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_runtimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }

    function test_directEtherPaymentReverts() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
    }

    function testFuzz_transferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, amount)
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testFuzz_transferFromTracksAllowance(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, amount));
        assertEq(token.allowance(DEPLOYER, SPENDER), approved - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromAboveAllowanceReverts(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, amount);
        assertEq(token.allowance(DEPLOYER, SPENDER), approved);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
