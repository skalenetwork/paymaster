import { currentTime, nextMonth } from "./tools/time";
import {
    deployAccessManager,
    deployPaymaster,
    setupRoles
} from "../migrations/deploy";
import { Paymaster } from "../typechain-types";
import { ethers } from "hardhat";
import { expect } from "chai";
import {
    loadFixture
} from "@nomicfoundation/hardhat-toolbox/network-helpers";


describe("Paymaster", () => {
    const setup = async (paymaster: Paymaster) => {
        const MAX_REPLENISHMENT_PERIOD = 24
        await paymaster.setMaxReplenishmentPeriod(MAX_REPLENISHMENT_PERIOD);
    }

    const deployPaymasterFixture = async () => {
        const [owner] = await ethers.getSigners();
        const accessManager = await deployAccessManager(owner);
        const paymaster = await deployPaymaster(accessManager);
        await setupRoles(accessManager, paymaster)
        await setup(paymaster);
        return paymaster;
    }

    const schainName = "d2-schain";
    const schainHash = ethers.solidityPackedKeccak256(["string"], [schainName]);

    // It's initialized in beforeEach
    // eslint-disable-next-line init-declarations
    let paymaster: Paymaster;

    beforeEach(async () => {
        paymaster = await loadFixture(deployPaymasterFixture);
    });

    it("should add schain", async () => {
        await paymaster.addSchain(schainName);
        const schain = await paymaster.schains(schainHash);
        expect(schain.hash).to.be.equal(schainHash);
        expect(schain.name).to.be.equal(schainName);
        const blockChainTime = await currentTime();
        console.log(new Date(blockChainTime));
        console.log(new Date(nextMonth(blockChainTime)));
        console.log(new Date(Number(schain.paidUntil)));
        expect(schain.paidUntil).to.be.equal(nextMonth(await currentTime()));
    });
});
