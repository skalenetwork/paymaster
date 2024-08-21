#!/usr/bin/env bash

# cspell:words realpath

set -e

if [ -z $GITHUB_WORKSPACE ]
then
    GITHUB_WORKSPACE="$(dirname "$(dirname "$(realpath "$0")")")"
fi

if [ -z $GITHUB_REPOSITORY ]
then
    GITHUB_REPOSITORY="skalenetwork/paymaster"
fi

export NVM_DIR=~/.nvm;
source $NVM_DIR/nvm.sh;

DEPLOYED_TAG=$(cat $GITHUB_WORKSPACE/DEPLOYED)
DEPLOYED_VERSION=$(echo $DEPLOYED_TAG | xargs ) # trim
DEPLOYED_DIR=$GITHUB_WORKSPACE/deployed-paymaster/

DEPLOYED_WITH_NODE_VERSION="lts/iron"
CURRENT_NODE_VERSION=$(nvm current)

git clone --branch $DEPLOYED_TAG https://github.com/$GITHUB_REPOSITORY.git $DEPLOYED_DIR

GANACHE_SESSION=$(yarn exec ganache --😈 --miner.blockGasLimit 25000000 --chain.allowUnlimitedContractSize)

cd $DEPLOYED_DIR
nvm install $DEPLOYED_WITH_NODE_VERSION
nvm use $DEPLOYED_WITH_NODE_VERSION
yarn install

echo "Deploy previous version"
DEPLOY_OUTPUT_FILE="$GITHUB_WORKSPACE/data/deploy.txt"
VERSION=$DEPLOYED_VERSION yarn exec hardhat run migrations/deploy.ts --network localhost > $DEPLOY_OUTPUT_FILE
rm $GITHUB_WORKSPACE/.openzeppelin/unknown-*.json || true
cp .openzeppelin/unknown-*.json $GITHUB_WORKSPACE/.openzeppelin
PAYMASTER_ADDRESS=$(cat $DEPLOY_OUTPUT_FILE | grep "Paymaster address" | awk '{print $NF}')

cd $GITHUB_WORKSPACE
nvm use $CURRENT_NODE_VERSION
rm -r --interactive=never $DEPLOYED_DIR

export ALLOW_NOT_ATOMIC_UPGRADE="OK"
export TARGET="$PAYMASTER_ADDRESS"
yarn exec hardhat run migrations/upgrade.ts --network localhost

yarn exec ganache instances stop $GANACHE_SESSION
