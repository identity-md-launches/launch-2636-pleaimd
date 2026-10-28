// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @title DeployPleaToken
/// @notice Reviewable deployment script for PleaToken. The IdentityMD launch deploys the token itself
///         through its factory from the built bytecode, so this script is for local or test deployments
///         only. It needs no configuration: the token takes no constructor arguments and mints its
///         supply to whichever account broadcasts.
/// @dev `deploy()` is the unit the tests call directly; `run()` only wraps it in a broadcast. Nothing
///      here reads environment variables.
contract DeployPleaToken is Script {
    /// @notice Deploys a fresh PleaToken. The caller of this function's creation frame receives the supply.
    /// @return token The deployed token.
    function deploy() public returns (PleaToken token) {
        token = new PleaToken();
    }

    /// @notice Broadcast entry point: `forge script script/DeployPleaToken.s.sol --broadcast`.
    function run() external returns (PleaToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
