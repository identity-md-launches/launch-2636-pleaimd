// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployPleaToken} from "../script/DeployPleaToken.s.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @notice Calls the deploy script's `deploy()` directly, without a broadcast or any environment.
contract DeployPleaTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    function test_deployMintsSupplyToTheScriptAsDeployer() public {
        DeployPleaToken script = new DeployPleaToken();
        PleaToken token = script.deploy();
        // `new PleaToken()` runs inside the script contract, so the script is `msg.sender` of the constructor.
        assertEq(token.balanceOf(address(script)), SUPPLY, "script received the supply");
        assertEq(token.totalSupply(), SUPPLY, "supply");
        assertEq(token.name(), "pleaimd", "name");
        assertEq(token.symbol(), "PLEA", "symbol");
        assertEq(token.decimals(), 18, "decimals");
    }

    function test_deployTwiceGivesTwoIndependentTokens() public {
        DeployPleaToken script = new DeployPleaToken();
        PleaToken a = script.deploy();
        PleaToken b = script.deploy();
        assertTrue(address(a) != address(b), "distinct addresses");
        assertEq(a.totalSupply(), SUPPLY, "a supply");
        assertEq(b.totalSupply(), SUPPLY, "b supply");
    }
}
