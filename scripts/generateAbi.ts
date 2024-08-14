import {getAbi, getVersion} from '@skalenetwork/upgrade-tools';
import {contracts} from "../migrations/deploy";
import {ethers} from "hardhat";
import {promises as fs} from 'fs';

type ABI = {[name: string]: []}

const saveToFile = async (abi: ABI) => {
    const version = await getVersion();
    const filename = `data/paymaster-${version}-abi.json`;
    console.log(`Save to ${filename}`)
    const indent = 4;
    await fs.writeFile(filename, JSON.stringify(abi, null, indent));
}

const main = async () => {
    const allContracts = contracts.concat(["FastForwardPaymaster"]);
    const abi: ABI = {};
    const factories = Object.fromEntries(await Promise.all(
        allContracts.map(
            async (contractName) => {
                console.log(`Compile ${contractName}`);
                return [contractName, await ethers.getContractFactory(contractName)]
            }
        )
    ));
    for (const contractName of allContracts) {
        console.log(`Load ABI of ${contractName}`);
        abi[contractName] = getAbi(factories[contractName].interface);
    }
    await saveToFile(abi);
}

if (require.main === module) {
    const successCode = 0;
    const failureCode = 1;
    main()
        .then(() => process.exit(successCode))
        .catch(error => {
            console.error(error);
            process.exit(failureCode);
        });
}
