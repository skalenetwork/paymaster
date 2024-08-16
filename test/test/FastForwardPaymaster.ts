import { currentTime, skipTime } from "../tools/time";
import { ethers, upgrades } from "hardhat";
import { PaymasterAccessManager } from "../../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { deployAccessManager } from "../../migrations/deploy";
import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";


describe("FastForwardPaymaster", () => {
    let owner: SignerWithAddress;

    const deployFastForwardPaymaster = async (accessManager: PaymasterAccessManager) => {
        const factory = await ethers.getContractFactory("FastForwardPaymaster");
        const paymaster = await upgrades.deployProxy(factory, [await accessManager.getAddress()]);
        return paymaster;
    }

    const deployFastForwardPaymasterFixture = async () => {
        const accessManager = await deployAccessManager(owner);
        const paymaster = await deployFastForwardPaymaster(accessManager);
        return paymaster;
    }

    before(async () => {
        [ owner ] = await ethers.getSigners();
    });

    it("should allow to skip time", async () => {
        const skipSec = 1000;
        const paymaster = await await loadFixture(deployFastForwardPaymasterFixture);
        expect(await paymaster.effectiveTimestamp()).to.be.equal(await currentTime());

        await paymaster.skipTime(skipSec);

        expect(await paymaster.effectiveTimestamp()).to.be.equal((await currentTime()) + skipSec);
    })

    it("should allow to speed up time", async () => {
        const coefficient = 2;
        const skipSec = 1000;
        const paymaster = await await loadFixture(deployFastForwardPaymasterFixture);

        await paymaster.setTimeMultiplier(ethers.parseEther(coefficient.toString()));

        const start = await currentTime();
        await skipTime(skipSec);

        expect(await paymaster.effectiveTimestamp()).to.be.equal(start + skipSec * coefficient);
    })
});
