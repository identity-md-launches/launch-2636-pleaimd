// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title PleaToken — the pleaimd (PLEA) token
/// @notice A plain, fixed-supply ERC-20. The whole supply of 1,000,000,000 PLEA (18 decimals) is
///         minted once, in the constructor, to the deployer (`msg.sender`). Nothing can mint again,
///         there is no owner, no pause, no blacklist, no fee and no burn hook: every transfer moves
///         exactly the amount asked for.
/// @dev The deployer is the IdentityMD ProjectFactory on a launch, which receives the supply and pays
///      it out (swarm distributor, pool seed, requester remainder). The constructor takes no arguments
///      and makes no external calls, so it deploys identically on an empty chain. The Solidity name
///      `PleaToken` is the launch's record name; `name()` and `symbol()` return the token's own.
contract PleaToken is ERC20 {
    /// @notice The token name returned by `name()`.
    string public constant TOKEN_NAME = "pleaimd";

    /// @notice The token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "PLEA";

    /// @notice ERC-20 decimals. Matches OpenZeppelin's default so `decimals()` needs no override.
    uint8 public constant TOKEN_DECIMALS = 18;

    /// @notice The fixed supply in minor units: 1,000,000,000 whole tokens × 10^18.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(TOKEN_DECIMALS);

    /// @notice Emitted once, when the constructor mints the whole supply to the deployer.
    /// @param deployer The address that received the whole supply (`msg.sender` of the deployment).
    /// @param supply The amount minted, equal to `TOTAL_SUPPLY`.
    event SupplyMinted(address indexed deployer, uint256 supply);

    /// @notice Mints the whole fixed supply to the deployer. Runs exactly once; there is no other mint path.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
        emit SupplyMinted(msg.sender, TOTAL_SUPPLY);
    }
}
