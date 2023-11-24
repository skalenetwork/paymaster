import { Paymaster, PaymasterAccessManager } from "../typechain-types";
import { Addressable } from "ethers";
import { ethers } from "hardhat";


// TODO: remove fixed gas limit
// after estimateGas fix in skaled
const DEPLOY_GAS_LIMIT = 10e6;

const deployAccessManager = async (owner: Addressable) => {
    console.log("Deploy AccessManager");
    const accessManager = await ethers.deployContract(
        "PaymasterAccessManager",
        [await owner.getAddress()],
        {
            "gasLimit": DEPLOY_GAS_LIMIT
        }
    );
    await accessManager.waitForDeployment();
    return accessManager;
}

const deployPaymaster = async (accessManager: PaymasterAccessManager) => {
    console.log("Deploy Paymaster");
    const paymaster = await ethers.deployContract(
        "Paymaster",
        [await accessManager.getAddress()],
        {
            "gasLimit": DEPLOY_GAS_LIMIT
        }
    );
    await paymaster.waitForDeployment();
    return paymaster;
}

const setupRoles = async (accessManager: PaymasterAccessManager, paymaster: Paymaster) => {
    await accessManager.setTargetFunctionRole(
        await paymaster.getAddress(),
        [paymaster.interface.getFunction("setSklPrice").selector],
        // It's uppercase because it's a constant inside a contract
        // eslint-disable-next-line new-cap
        await accessManager.PRICE_SETTER_ROLE()
    );
}

const main = async () => {
    const [owner] = await ethers.getSigners();
    const accessManager = await deployAccessManager(owner);
    const paymaster = await deployPaymaster(accessManager);

    // Print paymaster address
    console.log(`Paymaster address: ${await paymaster.getAddress()}`);

    await setupRoles(accessManager, paymaster);

    console.log("Done");
};

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
