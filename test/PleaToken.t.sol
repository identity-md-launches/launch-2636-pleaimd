// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @notice Behavioural tests for PleaToken: metadata, the one-time mint, ordinary ERC-20 success and
///         failure paths, and the absence of any admin, mint, pause or freeze surface.
contract PleaTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    /// @dev Stands in for the factory: whoever deploys receives the supply.
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    PleaToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event SupplyMinted(address indexed deployer, uint256 supply);

    function setUp() public {
        vm.prank(deployer);
        token = new PleaToken();
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and constants
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "pleaimd", "name");
        assertEq(token.symbol(), "PLEA", "symbol");
        assertEq(token.decimals(), 18, "decimals");
        assertEq(token.TOKEN_NAME(), "pleaimd", "TOKEN_NAME");
        assertEq(token.TOKEN_SYMBOL(), "PLEA", "TOKEN_SYMBOL");
        assertEq(token.TOKEN_DECIMALS(), 18, "TOKEN_DECIMALS");
    }

    function test_totalSupplyConstantMatchesBrief() public view {
        // 1,000,000,000 whole tokens with 18 decimals, written out in full.
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000_000_000_000_000_000_000, "TOTAL_SUPPLY literal");
        assertEq(token.TOTAL_SUPPLY(), SUPPLY, "TOTAL_SUPPLY");
        assertEq(token.totalSupply(), SUPPLY, "totalSupply");
    }

    // ---------------------------------------------------------------------------------------------
    // Constructor: whole supply minted once to the deployer
    // ---------------------------------------------------------------------------------------------

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(deployer), SUPPLY, "deployer balance");
        assertEq(token.balanceOf(address(this)), 0, "test contract holds nothing");
        assertEq(token.balanceOf(address(token)), 0, "token holds nothing");
    }

    function test_constructorEmitsTransferFromZeroAndSupplyMinted() public {
        address other = makeAddr("other-deployer");
        // The mint shows up as an ERC-20 Transfer from the zero address, then our SupplyMinted event.
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), other, SUPPLY);
        vm.expectEmit(true, true, true, true);
        emit SupplyMinted(other, SUPPLY);
        vm.prank(other);
        new PleaToken();
    }

    function test_eachDeploymentMintsToItsOwnDeployer() public {
        address second = makeAddr("second-deployer");
        vm.prank(second);
        PleaToken another = new PleaToken();
        assertEq(another.balanceOf(second), SUPPLY, "second deployer gets its token's supply");
        assertEq(another.balanceOf(deployer), 0, "first deployer gets nothing of the second token");
        assertEq(token.balanceOf(second), 0, "second deployer gets nothing of the first token");
        assertEq(token.totalSupply(), SUPPLY, "first token supply unchanged");
    }

    function test_constructorMakesNoExternalCallsAndNeedsNoCode() public {
        // Deploying from an EOA-like address with no code anywhere else on the chain succeeds, which is
        // what the launch's empty-chain constructor check requires.
        address fresh = makeAddr("fresh");
        assertEq(fresh.code.length, 0, "fresh has no code");
        vm.prank(fresh);
        PleaToken t = new PleaToken();
        assertEq(t.balanceOf(fresh), SUPPLY, "minted to fresh");
    }

    // ---------------------------------------------------------------------------------------------
    // transfer: success paths
    // ---------------------------------------------------------------------------------------------

    function test_transferMovesExactAmount() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, alice, 1_000 ether);
        assertTrue(token.transfer(alice, 1_000 ether), "transfer returns true");
        assertEq(token.balanceOf(alice), 1_000 ether, "alice received exactly the amount");
        assertEq(token.balanceOf(deployer), SUPPLY - 1_000 ether, "deployer debited exactly the amount");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transferWholeBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY), "transfer whole supply");
        assertEq(token.balanceOf(alice), SUPPLY, "alice holds everything");
        assertEq(token.balanceOf(deployer), 0, "deployer holds nothing");
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice); // alice holds nothing, but a zero transfer is still valid ERC-20
        assertTrue(token.transfer(bob, 0), "zero transfer returns true");
        assertEq(token.balanceOf(bob), 0, "bob still holds nothing");
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, 5 ether), "self transfer");
        assertEq(token.balanceOf(deployer), SUPPLY, "balance unchanged after self transfer");
    }

    function test_chainOfTransfersConservesSupply() public {
        vm.prank(deployer);
        token.transfer(alice, 300 ether);
        vm.prank(alice);
        token.transfer(bob, 120 ether);
        vm.prank(bob);
        token.transfer(deployer, 20 ether);
        assertEq(token.balanceOf(alice), 180 ether, "alice");
        assertEq(token.balanceOf(bob), 100 ether, "bob");
        assertEq(token.balanceOf(deployer), SUPPLY - 280 ether, "deployer");
        assertEq(token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(deployer), SUPPLY, "conserved");
    }

    // ---------------------------------------------------------------------------------------------
    // transfer: failure paths
    // ---------------------------------------------------------------------------------------------

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 11 ether)
        );
        token.transfer(bob, 11 ether);
        assertEq(token.balanceOf(alice), 10 ether, "alice unchanged after failed transfer");
        assertEq(token.balanceOf(bob), 0, "bob unchanged after failed transfer");
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_transferRevertsToZeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1 ether);
        assertEq(token.totalSupply(), SUPPLY, "nothing burned by a transfer to zero");
    }

    // ---------------------------------------------------------------------------------------------
    // approve / allowance / transferFrom
    // ---------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit Approval(deployer, spender, 500 ether);
        assertTrue(token.approve(spender, 500 ether), "approve returns true");
        assertEq(token.allowance(deployer, spender), 500 ether, "allowance set");
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(deployer);
        token.approve(spender, 500 ether);
        token.approve(spender, 20 ether);
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 20 ether, "allowance overwritten, not added");
    }

    function test_approveRevertsForZeroSpender() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1 ether);
    }

    function test_transferFromWithinAllowanceMovesTokensAndDecrementsAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 500 ether);

        vm.prank(spender);
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, bob, 200 ether);
        assertTrue(token.transferFrom(deployer, bob, 200 ether), "transferFrom returns true");

        assertEq(token.balanceOf(bob), 200 ether, "bob received");
        assertEq(token.balanceOf(deployer), SUPPLY - 200 ether, "deployer debited");
        assertEq(token.balanceOf(spender), 0, "spender holds nothing itself");
        assertEq(token.allowance(deployer, spender), 300 ether, "allowance decremented");
    }

    function test_transferFromExactAllowanceSpendsItAll() public {
        vm.prank(deployer);
        token.approve(spender, 50 ether);
        vm.prank(spender);
        token.transferFrom(deployer, bob, 50 ether);
        assertEq(token.allowance(deployer, spender), 0, "allowance exhausted");
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1_000 ether);
        assertEq(token.allowance(deployer, spender), type(uint256).max, "max allowance stays max");
        assertEq(token.balanceOf(bob), 1_000 ether, "bob received");
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1 ether));
        token.transferFrom(deployer, bob, 1 ether);
        assertEq(token.balanceOf(deployer), SUPPLY, "deployer untouched");
    }

    function test_transferFromRevertsAboveAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 100 ether, 101 ether)
        );
        token.transferFrom(deployer, bob, 101 ether);
        assertEq(token.allowance(deployer, spender), 100 ether, "allowance untouched after revert");
    }

    function test_transferFromRevertsWhenOwnerBalanceTooLow() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        token.approve(spender, 100 ether); // allowance exceeds what alice actually holds
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 50 ether)
        );
        token.transferFrom(alice, bob, 50 ether);
    }

    function test_transferFromRevertsToZeroAddress() public {
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 1 ether);
    }

    function test_transferFromCannotMoveSomeoneElsesTokensWithoutApproval() public {
        // The deployer, the most trusted plausible address, cannot pull from a holder either.
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 10 ether, "alice untouched");
    }

    // ---------------------------------------------------------------------------------------------
    // No admin surface: nothing mints, pauses, freezes, burns from, or upgrades
    // ---------------------------------------------------------------------------------------------

    function test_noMintOrAdminSelectorExists() public {
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "upgradeTo(address)",
            "initialize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], deployer, type(uint128).max);
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged after every attempt");
        assertEq(token.balanceOf(deployer), SUPPLY, "deployer balance unchanged after every attempt");
    }

    function test_unknownCalldataAndPlainEtherAreRejected() public {
        (bool ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok, "unknown selector reverts: no fallback");
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "ether is refused: no receive");
        assertEq(address(token).balance, 0, "token holds no ether");
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        // Mirrors the launch floor's reachability walk: only opcodes execution can reach count, and
        // PUSH data bytes are skipped.
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0, "has runtime");
        assertLe(runtime.length, 24_576, "fits EIP-170");
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    function test_supportsIERC20Interface() public view {
        // The token is usable through the bare IERC20 interface the launch and integrators rely on.
        IERC20 erc20 = IERC20(address(token));
        assertEq(erc20.totalSupply(), SUPPLY, "IERC20.totalSupply");
        assertEq(erc20.balanceOf(deployer), SUPPLY, "IERC20.balanceOf");
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferMovesExactlyAmountAndConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != deployer);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount), "transfer ok");
        assertEq(token.balanceOf(to), amount, "recipient got exactly amount");
        assertEq(token.balanceOf(deployer), SUPPLY - amount, "sender lost exactly amount");
        assertEq(token.balanceOf(to) + token.balanceOf(deployer), SUPPLY, "conserved");
        assertEq(token.totalSupply(), SUPPLY, "supply fixed");
    }

    function testFuzz_transferAboveBalanceReverts(address from, uint256 held, uint256 amount) public {
        vm.assume(from != address(0) && from != deployer);
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        vm.prank(deployer);
        token.transfer(from, held);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        token.transfer(bob, amount);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowance_, uint256 amount) public {
        allowance_ = bound(allowance_, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, allowance_);
        vm.prank(spender);
        if (amount > allowance_) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance_, amount)
            );
            token.transferFrom(deployer, bob, amount);
            assertEq(token.balanceOf(bob), 0, "nothing moved on revert");
        } else {
            assertTrue(token.transferFrom(deployer, bob, amount), "transferFrom ok");
            assertEq(token.balanceOf(bob), amount, "bob got exactly amount");
            assertEq(token.allowance(deployer, spender), allowance_ - amount, "allowance reduced exactly");
        }
        assertEq(token.totalSupply(), SUPPLY, "supply fixed");
    }

    function testFuzz_anyDeployerReceivesWholeSupply(address who) public {
        vm.assume(who != address(0) && who.code.length == 0);
        vm.assume(uint160(who) > 0xffff); // skip precompile range
        vm.prank(who);
        PleaToken t = new PleaToken();
        assertEq(t.balanceOf(who), SUPPLY, "deployer got the supply");
        assertEq(t.totalSupply(), SUPPLY, "supply");
    }
}
