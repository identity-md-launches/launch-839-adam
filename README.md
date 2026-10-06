ADAM is a fixed-supply ERC-20. Its constructor mints **1,000,000,000 ADAM**
with **18 decimals** to the immediate deployer. Name and symbol are both `ADAM`.
The supply in minor units is `1000000000000000000000000000` (`10^27`).

The production contract is `src/ADAM.sol:ADAM`. It inherits the vendored
OpenZeppelin ERC-20 implementation and adds only the initial-supply constant
and constructor mint. There is no owner, later mint, public burn, pause,
blacklist, confiscation, tax, rebase, proxy, upgrade, or initialization step.
Transfers deliver the exact requested amount. The token makes no external calls.

Build and check with Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files under `lib/`.
No dependency installation, network connection, RPC, environment variables,
wallet, FFI, or filesystem cheatcode permissions are needed to build or test.
The compiler itself is supplied by the build environment, not this repository.
`DEPENDENCIES.json` records the upstream tags, commits, and SHA-256 hashes:

| Dependency | Version | Vendored content |
| --- | --- | --- |
| OpenZeppelin Contracts | v5.1.0 | ERC-20 and its complete import closure, MIT license |
| forge-std | v1.9.7 | Test library source, MIT and Apache-2.0 licenses |

Deployment parameters are fixed and reviewable:

| Parameter | Value |
| --- | --- |
| Artifact | `out/ADAM.sol/ADAM.json` |
| Contract identifier | `src/ADAM.sol:ADAM` |
| Constructor arguments | None (`[]`; append no ABI arguments to creation bytecode) |
| Deployment value | `0` |
| Initial recipient | Immediate constructor caller (`msg.sender`) |
| Name / symbol / decimals | `ADAM` / `ADAM` / `18` |
| Total supply in minor units | `1000000000000000000000000000` |
| Solidity | `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, 200 runs |
| Metadata hash | `none` |

Use `forge inspect src/ADAM.sol:ADAM bytecode` to obtain creation bytecode and
`forge inspect src/ADAM.sol:ADAM deployedBytecode` to obtain expected runtime
bytecode. The authorized deployer must select a chain compatible with the
configured EVM target, confirm the artifact and supply, and deploy through the
intended account or factory. A factory using CREATE or CREATE2 receives the
entire supply itself; the originating account does not. A helper contract that
cannot transfer tokens would trap the supply. There is no special factory or
pool address baked into ADAM, and no exemptions are needed for its exact transfers.

For the contributor-network launch, the factory is responsible for distributing
the swarm share, seeding liquidity, and forwarding the remainder after deployment.
The token constructor performs none of those distributions. The network's
manifest/deployment step must use the identifier, empty constructor arguments,
metadata, and exact supply above, together with its separately supplied chain,
factory, paired currency, pool, and economic parameters. Those parameters were
not provided here. This project does not invent a launch manifest or perform
transactions. No application contracts are required for this token.

Standard ERC-20 behavior is assumed: zero-value transfers to a nonzero address
succeed and emit `Transfer`; transfers to the zero address and approvals for the
zero spender revert. `approve` replaces the caller's existing allowance.
Finite allowances decrease on `transferFrom`; the maximum `uint256` allowance
remains unchanged. OpenZeppelin v5 emits `Approval` for `approve`, but does not
emit it when spending an allowance. Integrations should query `allowance` for
current values. Holders should grant only needed allowances, revoke unused
approvals, and account for the standard allowance replacement race (a spender
can spend an old allowance before a replacement is confirmed).

Custody and distribution remain the deployer's operational responsibility.
After distribution, holders control transfers and spender authorizations; the
deployer has no authority over their balances. There is no recovery mechanism
for tokens sent to an inaccessible address or for assets sent to the token
contract. Ordinary native-currency payments revert, but forcibly sent native
currency cannot be recovered either. Operators must verify deployed source and
runtime, initial balance, and metadata, and arrange an independent security
review before release. Tests do not constitute an audit.

The tests cover metadata, mint and transfer events, contract deployment through
CREATE2, exact factory/distributor/holder transfers, full-supply and zero/self
transfers, finite and unlimited allowances, revocation, invalid addresses,
insufficient balances and allowances, atomic rollback, forbidden administrative
entry points, runtime opcode restrictions, and recipient contracts that reject
calls. Four fuzz tests run 256 cases each. Two stateful invariants run 128
sequences of 64 actions each over four holders, checking balances, supply, and
allowances against an independent model. Each test initializes its own state.

The supplied protected launch harness was read as an integration specification.
Its real Uniswap v4 seed/swap tests require network launch infrastructure and
parameters absent from this standalone token project, so that harness is not
executed by the local suite. The factory/distributor test checks exact token
flows, not a real pool swap. Local verification uses Foundry; Slither, Mythril,
live deployment, and explorer verification are not performed here.
