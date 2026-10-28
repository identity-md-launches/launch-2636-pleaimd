# pleaimd (PLEA)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum mainnet.

| Item | Value |
|------|-------|
| Token name (`name()`) | `pleaimd` |
| Symbol (`symbol()`) | `PLEA` |
| Decimals | 18 |
| Total supply | 1,000,000,000 PLEA = `1000000000000000000000000000` minor units |
| Solidity contract | `PleaToken` (`src/PleaToken.sol`) |
| Constructor arguments | none |
| Compiler | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"` |
| Base library | OpenZeppelin Contracts v5.4.0 `ERC20`, vendored under `lib/` |

## Behaviour

- The constructor mints the whole supply once to `msg.sender` and emits `Transfer(0, deployer, supply)`
  and `SupplyMinted(deployer, supply)`.
- There is no mint, burn, pause, blacklist, freeze, fee, tax, owner or upgrade path. The supply can
  never grow. The runtime bytecode contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`.
- `transfer` and `transferFrom` move exactly the amount asked for. `transferFrom` spends the caller's
  allowance from the token owner; the deployer has no special pull rights.
- Standard OpenZeppelin v5 custom errors are used on failure: `ERC20InsufficientBalance`,
  `ERC20InsufficientAllowance`, `ERC20InvalidReceiver`, `ERC20InvalidSpender`.
- The contract has no `receive` or `fallback`; ether sent to it is refused.

## Assumptions

- The deployer is the launch's `ProjectFactory`, which calls the constructor and so receives the whole
  supply. The factory then pays it out: 10% to the launch's MerkleDistributor, 70% to seed the Uniswap v4
  pool against IMD, and the remaining 20% to the requester's `remainderTo` address. None of this is
  encoded in the token; it is the factory's job and the token simply lets exact amounts move.
- Because transfers are untaxed and unrestricted, no address needs to be exempted, so the constructor
  takes no `$factory`, `$poolManager` or `$launchNumber` arguments.
- The constructor makes no external calls and requires no other contract to exist, so it deploys on an
  empty chain exactly as it does on mainnet.
- Nothing in the token depends on `tx.origin`, block values or the chain id.

## Deployment parameters

The launch deploys `PleaToken` from its creation code with an empty constructor argument list. The
manifest's `token` entry is expected to be:

| Manifest field | Value |
|----------------|-------|
| `contract` | `PleaToken` |
| `name` | `pleaimd` |
| `symbol` | `PLEA` |
| `decimals` | `18` |
| `constructorArgs` | `[]` |
| `totalSupply` | `1000000000000000000000000000` |

The manifest itself (`launch.json`) is written by the manifest step after this work is accepted; it is
intentionally not part of this repository.

`script/DeployPleaToken.s.sol` is a reviewable local deployment script for test networks. Its `deploy()`
function deploys the token with no configuration, and `run()` wraps it in a broadcast. It reads no
environment variables. The IdentityMD launch does not use it.

## After launch

There are no owner-settable values, no roles and no post-deployment configuration. Nothing needs to
be set after launch.

## Operational responsibilities

- **Holders**: a holder's balance can only be moved by the holder or by a spender the holder approved.
  Allowances are standard ERC-20; approving `type(uint256).max` grants an allowance that is never
  decremented. Review approvals before granting them.
- **Requester**: the 20% remainder goes to `0xee2aaa315cf7ed169f93148d30d24af9318dbb66` per the
  launch economics. Custody of that wallet is the requester's responsibility; the token has no recovery
  mechanism.
- **Explorer verification**: belongs to the launch deployer, with the pinned compiler settings in
  `foundry.toml` (0.8.26, optimizer 200 runs, `bytecode_hash = "none"`, EVM `cancun`).
- **No admin**: there is nobody who can pause or fix the contract after deployment. This is deliberate for
  a fixed-supply token and should be understood as final.

## Tests

- `test/PleaToken.t.sol`: metadata, the one-time mint, transfer / approve / transferFrom success and
  failure paths, absence of any admin selector, bytecode opcode walk, and fuzz tests for conservation,
  over-balance reverts and allowance enforcement.
- `test/PleaTokenLaunch.t.sol`: the launch flows run locally through a CREATE2 factory stand-in: supply
  minted to the factory, the 10% / 70% / 20% split arriving whole, a pool-like round trip, and the deployer
  having no power over a holder afterwards.
- `test/DeployPleaToken.t.sol`: the deploy script's `deploy()` function, called directly.

Run:

```sh
forge build
forge test
forge fmt --check
```

Fuzz tests also pass with the verifier's seed:

```sh
FOUNDRY_FUZZ_SEED=0x510c4e4a525d6125cc20550b367084da7c0066cb7ddd6385f7eff9fe330df6ca forge test
```

Tests read no environment variables and do not depend on which address runs them, so they pass in any
order and in parallel.

## Security notes

Tests passing are not an audit. The contract is a direct, unmodified use of OpenZeppelin `ERC20` v5.4.0
with a constructor mint, which keeps the attack surface to the audited library code. Slither was not run
on this machine; the design avoids its hard-fail detectors (no `selfdestruct`, no `transferFrom` from an
arbitrary address, no initializers or upgrade paths, no storage pointers, no shifts, no `abi.encodePacked`
of dynamic values). An independent adversarial review before launch remains good practice.

## Dependencies

Vendored as plain files, no git submodules:

- `lib/forge-std` — forge-std v1.9.7 (`src/`, MIT / Apache-2.0)
- `lib/openzeppelin-contracts` — OpenZeppelin Contracts v5.4.0 (`contracts/token`, `contracts/utils`,
  `contracts/interfaces`, MIT)

Remappings are in `remappings.txt`.
