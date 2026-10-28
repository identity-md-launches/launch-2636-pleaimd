// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @notice A stand-in for the launch factory: deploys the token through CREATE2 so the token's
///         `msg.sender` is this contract, holds the supply, and pays it out the way the factory does.
contract FactoryProbe {
    function deploy(bytes memory code, bytes32 salt) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0) && deployed.code.length > 0, "constructor failed");
    }

    function move(PleaToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

/// @notice The launch flows the factory performs, run locally: deploy from a contract, split the supply
///         into the swarm's 10%, the pool's 70% and the requester's 20%, and check every leg arrives whole.
contract PleaTokenLaunchTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    uint256 internal constant SWARM_BPS = 1_000;
    uint256 internal constant POOL_BPS = 7_000;

    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant POOL = address(0x9001);
    address internal constant REQUESTER = 0xEE2aaA315cf7eD169f93148D30D24Af9318dBb66;
    address internal constant CLAIMANT = address(0xC1A1);

    FactoryProbe internal factory;
    PleaToken internal token;

    function setUp() public {
        factory = new FactoryProbe();
        address deployed = factory.deploy(type(PleaToken).creationCode, bytes32(uint256(1)));
        token = PleaToken(deployed);
    }

    function test_create2DeploymentMintsToTheFactory() public view {
        assertEq(token.totalSupply(), SUPPLY, "supply");
        assertEq(token.balanceOf(address(factory)), SUPPLY, "factory holds the whole supply");
        assertEq(token.balanceOf(address(this)), 0, "test holds nothing");
    }

    function test_deploymentAddressIsDeterministic() public {
        bytes32 salt = bytes32(uint256(42));
        bytes32 codeHash = keccak256(type(PleaToken).creationCode);
        address predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, codeHash)))));
        address actual = factory.deploy(type(PleaToken).creationCode, salt);
        assertEq(actual, predicted, "CREATE2 address matches prediction");
        assertEq(PleaToken(actual).balanceOf(address(factory)), SUPPLY, "second deployment mints to the factory too");
    }

    function test_creationCodeHasNoConstructorArguments() public {
        // The manifest lists no constructorArgs: appending any would still deploy but is not what the
        // launch does, so the plain creation code must be enough on its own.
        address deployed = factory.deploy(type(PleaToken).creationCode, bytes32(uint256(7)));
        assertEq(PleaToken(deployed).name(), "pleaimd", "name");
        assertEq(PleaToken(deployed).symbol(), "PLEA", "symbol");
    }

    function test_swarmShareArrivesWholeAndIsClaimableWhole() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / 10_000;
        assertTrue(factory.move(token, DISTRIBUTOR, swarm), "transfer to the distributor returned false");
        assertEq(token.balanceOf(DISTRIBUTOR), swarm, "swarm share arrived short");

        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(CLAIMANT, swarm), "claim transfer returned false");
        assertEq(token.balanceOf(CLAIMANT), swarm, "claim arrived short");
        assertEq(token.balanceOf(DISTRIBUTOR), 0, "distributor kept something back");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged by the launch flows");
    }

    function test_fullLaunchSplitLeavesTheFactoryEmpty() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / 10_000;
        uint256 pool = (SUPPLY * POOL_BPS) / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        assertTrue(factory.move(token, DISTRIBUTOR, swarm), "swarm leg");
        assertTrue(factory.move(token, POOL, pool), "pool leg");
        assertTrue(factory.move(token, REQUESTER, remainder), "requester leg");

        assertEq(token.balanceOf(DISTRIBUTOR), 100_000_000 ether, "10% to the distributor");
        assertEq(token.balanceOf(POOL), 700_000_000 ether, "70% to the pool");
        assertEq(token.balanceOf(REQUESTER), 200_000_000 ether, "20% to the requester");
        assertEq(token.balanceOf(address(factory)), 0, "factory paid everything out");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_poolLikeRoundTripMovesExactAmounts() public {
        // A buyer takes tokens from the pool address and sells them back: both legs move exactly what
        // they say, as a pool manager settling deltas requires.
        address trader = makeAddr("trader");
        factory.move(token, POOL, (SUPPLY * POOL_BPS) / 10_000);
        uint256 poolBefore = token.balanceOf(POOL);

        vm.prank(POOL);
        token.transfer(trader, 12_345 ether);
        assertEq(token.balanceOf(trader), 12_345 ether, "bought exactly");
        assertEq(token.balanceOf(POOL), poolBefore - 12_345 ether, "pool debited exactly");

        vm.prank(trader);
        token.transfer(POOL, 12_345 ether);
        assertEq(token.balanceOf(trader), 0, "sold everything back");
        assertEq(token.balanceOf(POOL), poolBefore, "pool whole again");
    }

    function test_factoryCannotMoveOrFreezeAHolderAfterwards() public {
        address holder = makeAddr("holder");
        factory.move(token, holder, SUPPLY / 1_000);
        uint256 held = token.balanceOf(holder);

        // The factory, the token's deployer, has no allowance and no privileged path.
        vm.prank(address(factory));
        (bool moved,) =
            address(token).call(abi.encodeWithSelector(token.transferFrom.selector, holder, address(factory), 1));
        assertFalse(moved, "deployer pulled from a holder");
        assertEq(token.balanceOf(holder), held, "holder balance intact");

        vm.prank(holder);
        assertTrue(token.transfer(CLAIMANT, held / 2), "holder can still transfer");
        assertEq(token.balanceOf(CLAIMANT), held / 2, "transfer delivered in full");
    }

    function testFuzz_launchSplitConservesSupply(uint16 swarmBps, uint16 poolBps) public {
        swarmBps = uint16(bound(swarmBps, 0, 10_000));
        poolBps = uint16(bound(poolBps, 0, 10_000 - swarmBps));
        uint256 swarm = (SUPPLY * swarmBps) / 10_000;
        uint256 pool = (SUPPLY * poolBps) / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        factory.move(token, DISTRIBUTOR, swarm);
        factory.move(token, POOL, pool);
        factory.move(token, REQUESTER, remainder);

        assertEq(token.balanceOf(DISTRIBUTOR), swarm, "swarm");
        assertEq(token.balanceOf(POOL), pool, "pool");
        assertEq(token.balanceOf(REQUESTER), remainder, "requester");
        assertEq(token.balanceOf(address(factory)), 0, "factory empty");
        assertEq(token.balanceOf(DISTRIBUTOR) + token.balanceOf(POOL) + token.balanceOf(REQUESTER), SUPPLY, "conserved");
    }
}
