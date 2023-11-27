#!/usr/bin/env bash

set -e

yarn exec hardhat run migrations/deploy.ts
