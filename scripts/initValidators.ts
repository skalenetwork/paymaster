import { ethers } from "hardhat";
import { Instance, skaleContracts } from "@skalenetwork/skale-contracts-ethers-v6";
import { deployAccessManager, deployPaymaster } from "../migrations/deploy";
import { Paymaster } from "../typechain-types";
import { promises as fs } from "fs";


interface ValidatorNodes {
    [key: string]: {
      numberOfNodes: number;
      numberOfActiveNodes: number;
    };
  }

async function getContract(contractName: string, instance: Instance | undefined) {
    let contract;
    if (process.env.ABI) {
        const abi = JSON.parse(await fs.readFile(process.env.ABI, "utf-8"));
        const provider = new ethers.JsonRpcProvider(process.env.MAINNET_ENDPOINT);
        const contractAddress = abi[getContractKeyInAbiFile(contractName) + "_address"];
        const contractAbi = abi[getContractKeyInAbiFile(contractName) + "_abi"];
        contract = new ethers.Contract(contractAddress, contractAbi, provider);
    } else if (instance !== undefined) {
        contract = await instance.getContract(contractName) as any;
    } else {
        throw new Error("Set path to file with ABI and addresses to ABI environment variables")
    }
    return contract;
}

function getContractKeyInAbiFile(contract: string) {
    return contract.replace(/([a-zA-Z])(?=[A-Z])/g, '$1_').toLowerCase();
}

async function addValidators(instance: Instance | undefined, paymaster: Paymaster) {
    console.log("Adding validators");
    const validatorService = await getContract("ValidatorService", instance) as any;
    const numberOfValidators = await validatorService.numberOfValidators();
    for (let validatorId = 1; validatorId <= numberOfValidators; ++validatorId) {
        const validator = await validatorService.getValidator(validatorId);
        const validatorAddress = validator[1];
        await paymaster.addValidator(validatorId, validatorAddress);
        const percentageComplete = (validatorId * 100 / Number(numberOfValidators)).toFixed(1)
        process.stdout.write(`\rPercentage complete: ${percentageComplete}`);
    }
}

async function getNodes(instance: Instance | undefined) {
    console.log("\nParsing nodes");
    const nodes =await getContract("Nodes", instance) as any;
    const numberOfNodes = await nodes.getNumberOfNodes();
    const validatorNodes: ValidatorNodes = {};
    for (let nodeId = 0; nodeId < numberOfNodes; ++nodeId) {
        const validatorId = await nodes.getValidatorId(nodeId) as number;
        const isNodeLeft = await nodes.isNodeLeft(nodeId);
        if (!(validatorId in validatorNodes)) {
            validatorNodes[validatorId] = {
                numberOfNodes: 0,
                numberOfActiveNodes: 0,
            };
        }   
        if (!isNodeLeft) {
            validatorNodes[validatorId].numberOfNodes++;
            validatorNodes[validatorId].numberOfActiveNodes++;
        } else {
            validatorNodes[validatorId].numberOfNodes++;
        }
        const percentageComplete = ((nodeId + 1) * 100 / Number(numberOfNodes)).toFixed(1)
        process.stdout.write(`\rPercentage complete: ${percentageComplete}`);
    }
    return validatorNodes;
}

async function setNodes(paymaster: Paymaster, validatorNodes: ValidatorNodes) {
    console.log("\nSetting nodes");
    let it = 0;
    for (const validatorId in validatorNodes) {
        const numberOfNodes = validatorNodes[validatorId].numberOfNodes;
        const numberOfActiveNodes = validatorNodes[validatorId].numberOfActiveNodes;
        await paymaster.setNodesAmount(validatorId, numberOfNodes);
        await paymaster.setActiveNodes(validatorId, numberOfActiveNodes);
        const percentageComplete = (++it * 100 / Object.keys(validatorNodes).length).toFixed(1);
        process.stdout.write(`\rPercentage complete: ${percentageComplete}`);
    }
}

const main = async () => {
    const [ signer ] = await ethers.getSigners();
    let paymaster: Paymaster;
    let instance: Instance | undefined;

    if (process.env.TEST) {
        const accessManager = await deployAccessManager(signer);
        paymaster = await deployPaymaster(accessManager);
    } else if (process.env.PAYMASTER_ADDRESS) {
        const paymasterAddress = process.env.PAYMASTER_ADDRESS;
        const paymasterFactory = await ethers.getContractFactory("Paymaster");
        paymaster = paymasterFactory.attach(paymasterAddress) as Paymaster;
    } else {
        throw new Error("Set Paymaster address");
    }

    if (process.env.MAINNET_ENDPOINT) {
        const provider = new ethers.JsonRpcProvider(process.env.MAINNET_ENDPOINT);
        const network = await provider.getNetwork();
        if (network.chainId.toString() == "1") {
            const skaleNetwork = await skaleContracts.getNetworkByProvider(provider);
            const project = skaleNetwork.getProject("skale-manager");
            instance = await project.getInstance("production");
        }
    } else {
        throw new Error("Set MAINNET_ENDPOINT");
    }
    
    
    await addValidators(instance, paymaster);
    const validatorNodes = await getNodes(instance);
    await setNodes(paymaster, validatorNodes);

};

if (require.main === module) {
    main().catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
}