# Paymaster

<div align="center">

[![License](https://img.shields.io/github/license/skalenetwork/paymaster.svg)](LICENSE)
[![Discord](https://img.shields.io/discord/534485763354787851.svg)](https://discord.gg/skale)
[![Build Status](https://github.com/skalenetwork/paymaster/actions/workflows/test.yml/badge.svg)](https://github.com/skalenetwork/paymaster/actions)
[![codecov](https://codecov.io/gh/skalenetwork/paymaster/branch/develop/graph/badge.svg)](https://codecov.io/gh/skalenetwork/paymaster)

<p>A smart contract system for collecting and distributing SKALE chain fees across validators</p>

</div>


## Introduction

Paymaster is a core economic component of the SKALE Network that manages the payment flow between SKALE chains and validators. It collects subscription fees from SKALE chains paid in SKL tokens and distributes these fees as rewards to validators proportional to their active node participation in the network.

The system implements a time-based payment and reward distribution mechanism, tracking validator node participation over time, managing chain subscription lifecycles, and ensuring fair reward distribution based on validator contributions. It uses advanced data structures like timelines, sequences, heaps, and priority queues to efficiently manage historical data and calculate accurate reward amounts.

The high-level architecture of the repository is described in
[./docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md).


**Core Capabilities:**

- **SKALE Chain Payment Processing:** Accepts SKL token payments from SKALE chains for monthly subscription fees based on configurable USD-denominated pricing
- **Validator Reward Distribution:** Calculates and distributes rewards to validators proportional to their active nodes and participation duration
- **Time-based Accounting:** Tracks validator node changes, chain payments, and reward obligations over time using custom timeline and sequence data structures
- **Price Oracle Integration:** Supports dynamic SKL price updates from authorized price setters with configurable staleness protection
- **Access Control Management:** Implements role-based access control for administrative functions and price updates using OpenZeppelin's AccessManager pattern

## Installation & Setup

### Prerequisites

- Node.js v20-22
- Yarn v3.6.4 or compatible package manager
- Hardhat development environment
- Slither (for static analysis only)

### Clone and Install

```bash
git clone --recurse-submodules https://github.com/skalenetwork/paymaster.git
cd paymaster
yarn install
yarn compile
```


## Running Tests

Tests run on a Hardhat network instance and do not require additional setup
beyond installation.

**All tests**

```bash
yarn test
```

**Single test / suite**

```bash
yarn test test/Paymaster.ts
```

**Coverage**

```bash
yarn hardhat coverage
```

**Type checking**

```bash
yarn tsc
```

## Deployment

1. Create a `.env` file with the following:

   ```dotenv
   PRIVATE_KEY="your_deployer_private_key"
   ENDPOINT="https://your.rpc.endpoint"
   ```

2. Run deployment:

   ```bash
   yarn hardhat run migrations/deploy.ts --network custom
   ```

### Official Deployments

**Official Paymaster on SKALE (Europa):** https://elated-tan-skat.explorer.mainnet.skalenodes.com/address/0x0d66cA00CbAD4219734D7FDF921dD7Caadc1F78D


## Security and Audits

**Static Analysis**

This project uses `slither`, `solhint`, `eslint`, and `cspell` as primary static analysis and linting tools.

```bash
# Run all checks (compile, lint, type-check, and slither)
yarn fullCheck

# Run individual tools
yarn lint        # Solhint for Solidity
yarn eslint      # ESLint for TypeScript
yarn slither     # Slither static analysis
yarn cspell      # Spell checking
```


### Bug Bounty Programs

Please see [HackerOne](https://hackerone.com/skale_network?type=team) for SKALE's
active bug bounty program **or** submit a bug directly via
[encrypted email](https://skale.space/security).


## Main Branches

- **develop** – Most up-to-date branch with latest features and ongoing work.
  May be ahead of production instances. This is where contributions should be opened.
- **stable** – Latest stable version of the project.

## Resources

- **SKALE Whitepaper** – https://skale.space/whitepaper
- **SKALE Manager Repository** - https://github.com/skalenetwork/skale-manager
- **SKALE Developer Documentation** – https://docs.skale.space/
- **SKALE Main Website** – https://www.skale.space/
- **SKALE Ecosystem Portal** – https://portal.skale.space/


## License

[![License](https://img.shields.io/github/license/skalenetwork/paymaster.svg)](LICENSE)

All contributions are made under the [GNU Affero General Public License v3](https://www.gnu.org/licenses/agpl-3.0.en.html). See [LICENSE](LICENSE).

Copyright (C) 2023-Present SKALE Labs
