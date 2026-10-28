// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @notice Drives PleaToken with random sequences of transfers, approvals and pulls among a fixed set of
///         actors, including calls that must fail. Every successful call is checked against an independent
///         model of balances and allowances; every failing call must revert and leave the state unchanged.
contract PleaTokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    PleaToken public immutable token;
    address[] public actors;

    // Ghost model, updated from the call's inputs only, never from the token's own return values.
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostTransfersOk;
    uint256 public ghostRevertsExpected;
    uint256 public ghostUnexpectedOutcome;

    constructor(PleaToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        // The first actor deployed the token and holds the whole supply.
        ghostBalance[actors_[0]] = SUPPLY;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        // Mostly within balance, sometimes one wei past it, so both paths are exercised.
        amount = bound(amount, 0, held + 1);

        vm.prank(from);
        if (amount > held) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
            token.transfer(to, amount);
            ++ghostRevertsExpected;
            return;
        }
        bool ok = token.transfer(to, amount);
        if (!ok) ++ghostUnexpectedOutcome;
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ++ghostTransfersOk;
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        ++ghostRevertsExpected;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        amount = infinite ? type(uint256).max : bound(amount, 0, SUPPLY + 1);
        vm.prank(owner);
        bool ok = token.approve(spender, amount);
        if (!ok) ++ghostUnexpectedOutcome;
        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 held = ghostBalance[owner];
        uint256 cap = allowed < held ? held : allowed;
        amount = bound(amount, 0, cap == type(uint256).max ? cap : cap + 1);

        vm.prank(spender);
        if (amount > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
            token.transferFrom(owner, to, amount);
            ++ghostRevertsExpected;
            return;
        }
        if (amount > held) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
            token.transferFrom(owner, to, amount);
            ++ghostRevertsExpected;
            return;
        }
        bool ok = token.transferFrom(owner, to, amount);
        if (!ok) ++ghostUnexpectedOutcome;
        if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
        ghostBalance[owner] -= amount;
        ghostBalance[to] += amount;
        ++ghostTransfersOk;
    }

    /// @dev A stranger with no balance and no allowance tries to pull from a random holder.
    function strangerPull(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address stranger = address(0xBAD);
        amount = bound(amount, 1, SUPPLY);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        token.transferFrom(owner, stranger, amount);
        ++ghostRevertsExpected;
    }
}

contract PleaTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    PleaToken internal token;
    PleaTokenHandler internal handler;
    address[] internal actors;

    function setUp() public {
        actors.push(makeAddr("deployer"));
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));

        vm.prank(actors[0]);
        token = new PleaToken();
        handler = new PleaTokenHandler(token, actors);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = PleaTokenHandler.transfer.selector;
        selectors[1] = PleaTokenHandler.transferToZero.selector;
        selectors[2] = PleaTokenHandler.approve.selector;
        selectors[3] = PleaTokenHandler.transferFrom.selector;
        selectors[4] = PleaTokenHandler.strangerPull.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY, "total supply changed");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY, "tokens leaked outside the actor set");
        assertEq(token.balanceOf(address(0)), 0, "zero address holds tokens");
        assertEq(token.balanceOf(address(0xBAD)), 0, "stranger obtained tokens");
        assertEq(token.balanceOf(address(token)), 0, "token holds itself");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]), "balance diverged from model");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.ghostAllowance(actors[i], actors[j]),
                    "allowance diverged from model"
                );
            }
            assertEq(token.allowance(actors[i], address(0xBAD)), 0, "stranger gained an allowance");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_everySuccessfulCallReturnedTrue() public view {
        assertEq(handler.ghostUnexpectedOutcome(), 0, "a successful call returned false");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_metadataIsFixed() public view {
        assertEq(token.name(), "pleaimd", "name");
        assertEq(token.symbol(), "PLEA", "symbol");
        assertEq(token.decimals(), 18, "decimals");
    }
}
