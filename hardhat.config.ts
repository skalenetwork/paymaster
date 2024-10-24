import "@typechain/hardhat"
import "@nomicfoundation/hardhat-chai-matchers"
import "@nomicfoundation/hardhat-ethers"
import "@openzeppelin/hardhat-upgrades";
import "solidity-coverage";
import * as dotenv from "dotenv";
import {HardhatUserConfig, task} from "hardhat/config";


dotenv.config();

const getCustomUrl = (url: string | undefined) => {
    if (url) {
        return url;
    }
    return "http://127.0.0.1:8545";
};

const getCustomPrivateKey = (privateKey: string | undefined) => {
    if (privateKey) {
        return [privateKey];
    }
    return [];
};

const config: HardhatUserConfig = {
    "mocha": {
        "timeout": 120000
    },
    "networks": {
        "custom": {
            "accounts": getCustomPrivateKey(process.env.PRIVATE_KEY),
            "url": getCustomUrl(process.env.ENDPOINT)
        },
        "hardhat": {
            "allowUnlimitedContractSize": true
        }
    },
    "solidity": "0.8.20"
};

export default config;

task(
    "grantAccess",
    "Grant admin access to Paymaster"
).
    addPositionalParam("paymasterAddress").
    addPositionalParam("accountAddress").
    setAction(async (taskArgs, hre) => {
        const paymaster = await hre.ethers.getContractAt(
            "Paymaster",
            taskArgs.paymasterAddress
        );

        console.log(await paymaster.getAddress());
        console.log(await paymaster.authority());

        const accessManager = await hre.ethers.getContractAt(
            "AccessManager",
            await paymaster.authority()
        );

        const zeroDelay = 0;
        await accessManager.grantRole(
            // Can't rename ADMIN_ROLE because
            // it's imported from openzeppelin library
            // eslint-disable-next-line new-cap
            await accessManager.ADMIN_ROLE(),
            taskArgs.accountAddress,
            zeroDelay
        );

        console.log("Done");
    });
