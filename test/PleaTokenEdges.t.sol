// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @notice Edge inputs the behavioural suite does not pin: the zero address as caller, the maximum
///         uint256 amount, a spender acting on its own balance, and repeated calls.
contract PleaTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    PleaToken internal token;

    function setUp() public {
        vm.prank(deployer);
        token = new PleaToken();
    }

    function test_zeroAddressCannotSendEvenZero() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.transfer(alice, 0);
    }

    function test_zeroAddressCannotApprove() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.approve(alice, 1);
    }

    function test_transferFromZeroAddressOwnerReverts() public {
        // Nobody can hold an allowance from the zero address, so the allowance check fails first.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(address(0), alice, 1);
    }

    function test_transferMaxUintReverts() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_transferOneMoreThanSupplyReverts() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
    }

    function test_infiniteAllowanceStillBoundByBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 5 ether);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        token.transferFrom(alice, bob, 6 ether);
        assertEq(token.allowance(alice, bob), type(uint256).max, "allowance untouched");
    }

    function test_ownerNeedsAllowanceToTransferFromSelf() public {
        // transferFrom by the owner on its own balance is not exempt from the allowance.
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);

        vm.prank(deployer);
        token.approve(deployer, 3);
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 3);
        assertEq(token.balanceOf(alice), 3, "moved with self-allowance");
        assertEq(token.allowance(deployer, deployer), 0, "self-allowance spent");
    }

    function test_zeroAmountTransferFromNeedsNoAllowance() public {
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, 0), "zero pull ok");
        assertEq(token.balanceOf(deployer), SUPPLY, "nothing moved");
        assertEq(token.allowance(deployer, bob), 0, "no allowance created");
    }

    function test_approveToZeroRevokes() public {
        vm.prank(deployer);
        token.approve(alice, 10 ether);
        vm.prank(deployer);
        token.approve(alice, 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function test_sameTransferTwiceFailsWhenBalanceExhausted() public {
        vm.prank(deployer);
        token.transfer(alice, 7 ether);
        vm.prank(alice);
        token.transfer(bob, 7 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 7 ether));
        token.transfer(bob, 7 ether);
        assertEq(token.balanceOf(bob), 7 ether, "bob credited once");
    }

    function test_transferToTokenContractIsAcceptedButStuck() public {
        // Plain ERC-20: tokens sent to the token's own address are accepted and held there, and nothing
        // can move them back out. Pinned so a change in this behaviour is noticed.
        vm.prank(deployer);
        token.transfer(address(token), 1 ether);
        assertEq(token.balanceOf(address(token)), 1 ether, "held by the token");
        assertEq(token.totalSupply(), SUPPLY, "not burned");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_selfTransferNeverChangesBalance(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(deployer, amount);
        assertEq(token.balanceOf(deployer), SUPPLY, "self transfer changed balance");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_roundTripRestoresBalances(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.transfer(deployer, amount);
        assertEq(token.balanceOf(deployer), SUPPLY, "deployer restored");
        assertEq(token.balanceOf(alice), 0, "alice back to zero");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_splitPullsSpendAllowanceAdditively(uint256 allowed, uint256 first, uint256 second) public {
        allowed = bound(allowed, 0, SUPPLY);
        first = bound(first, 0, allowed);
        second = bound(second, 0, allowed - first);
        vm.prank(deployer);
        token.approve(bob, allowed);
        vm.startPrank(bob);
        token.transferFrom(deployer, alice, first);
        token.transferFrom(deployer, alice, second);
        vm.stopPrank();
        assertEq(token.allowance(deployer, bob), allowed - first - second, "allowance");
        assertEq(token.balanceOf(alice), first + second, "alice");
    }
}
