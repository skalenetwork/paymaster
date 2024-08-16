import {AutoSubmitter, Upgrader} from "@skalenetwork/upgrade-tools";
import {Instance, skaleContracts} from "@skalenetwork/skale-contracts-ethers-v6";
import {Paymaster} from "../typechain-types";
import {Transaction} from "ethers";
import chalk from "chalk";
import {contracts} from "./deploy";
import {ethers} from "hardhat";

enum ExitCodes {
    OK,
    TARGET_IS_NOT_SET
}

const getPaymasterInstance = async () => {
    if (process.env.ABI) {
        console.log("This version of the upgrade script ignores manually provided ABI");
        console.log("Do not set ABI environment variable");
    }
    if (!process.env.TARGET) {
        console.log(chalk.red("Specify desired paymaster instance"));
        console.log(chalk.red("Set instance alias or paymaster address to TARGET environment variable"));
        process.exit(ExitCodes.TARGET_IS_NOT_SET);
    }
    const network = await skaleContracts.getNetworkByProvider(ethers.provider);
    const project = network.getProject("paymaster");
    return await project.getInstance(process.env.TARGET);
}

interface UpgradeContext {
    targetVersion: string,
    instance: Instance,
    contractNamesToUpgrade: string[],
}

class PaymasterUpgrader extends Upgrader {
    constructor(
        context: UpgradeContext,
        submitter = new AutoSubmitter()
    ) {
        super(
            {
                contractNamesToUpgrade: context.contractNamesToUpgrade,
                instance: context.instance,
                name: "paymaster",
                version: context.targetVersion
            },
            submitter);
    }

    async getPaymaster() {
        return await this.instance.getContract("Paymaster") as unknown as Paymaster;
    }

    getDeployedVersion = async () => {
        const paymaster = await this.getPaymaster();
        try {
            return await paymaster.version();
        } catch {
            console.log(chalk.red("Can't read deployed version"));
        }
        return "";
    }

    setVersion = async (newVersion: string) => {
        const paymaster = await this.getPaymaster();
        this.transactions.push(Transaction.from({
            data: paymaster.interface.encodeFunctionData("setVersion", [newVersion]),
            to: await ethers.resolveAddress(paymaster)
        }));
    }

    // Uncomment when new contracts are deployed
    // deployNewContracts = async () => { };

    // Uncomment when initialization is required
    // initialize = async () => { };
}

const main = async () => {
    const paymaster = await getPaymasterInstance();
    const upgrader = new PaymasterUpgrader({
        contractNamesToUpgrade: contracts,
        instance: paymaster,
        targetVersion: "1.0.0"
    });
    await upgrader.upgrade();
}

if (require.main === module) {
    main().catch(error => {
            console.error(error);
            process.exitCode = 1;
        });
}
