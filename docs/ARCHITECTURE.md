# Paymaster Architecture

This document describes the architecture and structure of the Paymaster repository.

## Repository Structure

```
paymaster/
├── contracts/           # Smart contract source files
├── test/               # Test suites
├── migrations/         # Deployment and upgrade scripts
├── scripts/            # Utility scripts
└── docs/              # Documentation
```

## Directory Details

### `/contracts/` - Smart Contract Source Code

The core smart contracts written in Solidity.

**Main Contracts:**
- **`Paymaster.sol`** - The primary contract managing chain payments, validator rewards, and fee distribution
- **`PaymasterAccessManager.sol`** - Access control manager implementing role-based permissions
- **`Timeline.sol`** - Library for managing time-based value changes with efficient queries
- **`Sequence.sol`** - Library for tracking chronological numeric value sequences

### `/test/` - Test Suites

Comprehensive test suites written in TypeScript using Hardhat and Chai.

**Test Files:**
- **`Paymaster.ts`** - Main contract functionality tests
- **`Sequence.ts`** - Sequence library unit tests
- **`Timeline.ts`** - Timeline library unit tests

- **`test/structs/**`** - Data structure tests

- **`test/test/`** - Additional test utilities
  - `FastForwardPaymaster.ts` - Tests for time manipulation features

- **`test/tools/**`** - Testing utilities and helpers


### `/migrations/` - Deployment Scripts

Scripts for deploying and upgrading contracts.

- **`deploy.ts`** - Initial deployment logic for Paymaster and AccessManager
- **`upgrade.ts`** - Upgrade logic for existing deployments

### `/scripts/` - Utility Scripts

Helper scripts for development and maintenance.

### Configuration Files (Root)

- **`hardhat.config.ts`** - Hardhat configuration (network, compiler settings)
- **`package.json`** - Node.js dependencies and scripts
- **`tsconfig.json`** - TypeScript compiler configuration
- **`slither.config.json`** - Slither static analyzer configuration
- **`cspell.json`** - Spell checker configuration
- **`LICENSE`** - AGPL-3.0 license
- **`README.md`** - Project documentation
