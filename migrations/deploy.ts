import { Paymaster, PaymasterAccessManager } from "../typechain-types";
import { ethers, upgrades } from "hardhat";
import { Addressable } from "ethers";
import { getVersion } from "@skalenetwork/upgrade-tools";


// TODO: remove fixed gas limit
// after estimateGas fix in skaled
const DEPLOY_GAS_LIMIT = 10e6;

export const deployAccessManager = async (owner: Addressable) => {
    console.log("Deploy AccessManager");
    const factory = await ethers.getContractFactory("PaymasterAccessManager");
    const accessManager = await upgrades.deployProxy(
        factory,
        [await owner.getAddress()],
        {
            txOverrides: {
                "gasLimit": DEPLOY_GAS_LIMIT
            }
        }
    ) as unknown as PaymasterAccessManager;
    await accessManager.waitForDeployment();
    return accessManager;
}

export const deployPaymaster = async (accessManager: PaymasterAccessManager) => {
    let contract = "Paymaster";
    if (process.env.TEST) {
        contract = "FastForwardPaymaster";
    }
    console.log(`Deploy ${contract}`);
    const factory = await ethers.getContractFactory(contract);
    const paymaster = await upgrades.deployProxy(
        factory,
        [await accessManager.getAddress()],
        {
            txOverrides: {
                "gasLimit": DEPLOY_GAS_LIMIT
            }
        }
    ) as unknown as Paymaster;
    await paymaster.waitForDeployment();
    return paymaster;
}

export const setupRoles = async (accessManager: PaymasterAccessManager, paymaster: Paymaster) => {
    const response = await accessManager.setTargetFunctionRole(
        await paymaster.getAddress(),
        [paymaster.interface.getFunction("setSklPrice").selector],
        // It's uppercase because it's a constant inside a contract
        // eslint-disable-next-line new-cap
        await accessManager.PRICE_SETTER_ROLE(),
        {
            "gasLimit": DEPLOY_GAS_LIMIT
        }
    );
    await response.wait();
}

export const setup = async (paymaster: Paymaster) => {
    const version = await getVersion();
    const response = await paymaster.setVersion(version);
    await response.wait();
}

const main = async () => {
    const [owner] = await ethers.getSigners();
    const accessManager = await deployAccessManager(owner);
    const paymaster = await deployPaymaster(accessManager);

    // Print paymaster address
    console.log(`Paymaster address: ${await paymaster.getAddress()}`);

    await setupRoles(accessManager, paymaster);
    await setup(paymaster);

    console.log("Done");
};

if (require.main === module) {
    main().catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
}
