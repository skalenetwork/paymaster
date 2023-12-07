import { Paymaster, PaymasterAccessManager, Token } from "../typechain-types";
import { currentTime, nextMonth } from "./tools/time";
import {
    deployAccessManager,
    deployPaymaster,
    setupRoles
} from "../migrations/deploy";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { expect } from "chai";
import {
    loadFixture
} from "@nomicfoundation/hardhat-toolbox/network-helpers";


describe("Paymaster", () => {
    const schainName = "d2-schain";
    const schainHash = ethers.solidityPackedKeccak256(["string"], [schainName]);
    const BIG_AMOUNT = ethers.parseEther("100000");

    let owner: SignerWithAddress;
    let validator: SignerWithAddress;
    let user: SignerWithAddress;
    let priceAgent: SignerWithAddress;

    const setup = async (paymaster: Paymaster, skaleToken: Token) => {
        const MAX_REPLENISHMENT_PERIOD = 24;
        const SCHAIN_PRICE = 5000;
        const SKL_PRICE = ethers.parseEther("2");

        await skaleToken.mint(await user.getAddress(), BIG_AMOUNT);
        await skaleToken.connect(user).approve(await paymaster.getAddress(), BIG_AMOUNT);

        await paymaster.setMaxReplenishmentPeriod(MAX_REPLENISHMENT_PERIOD);
        await paymaster.setSchainPrice(SCHAIN_PRICE);
        await paymaster.connect(priceAgent).setSklPrice(SKL_PRICE);
        await paymaster.setSkaleToken(await skaleToken.getAddress());
    }

    const grantRoles = async (accessManager: PaymasterAccessManager) => {
        await accessManager.grantRole(
            // It's a constant in the contract
            // eslint-disable-next-line new-cap
            await accessManager.PRICE_SETTER_ROLE(),
            await priceAgent.getAddress(),
            0
        );
    }

    const deployPaymasterFixture = async () => {
        const accessManager = await deployAccessManager(owner);
        const paymaster = await deployPaymaster(accessManager);
        const skaleToken = await ethers.deployContract("Token");
        await setupRoles(accessManager, paymaster)
        await grantRoles(accessManager);
        await setup(paymaster, skaleToken);
        return paymaster;
    }

    before(async () => {
        [owner, validator, user, priceAgent] = await ethers.getSigners();
    })

    it("should add schain", async () => {
        const paymaster = await loadFixture(deployPaymasterFixture);
        await paymaster.addSchain(schainName);
        const schain = await paymaster.schains(schainHash);
        expect(schain.hash).to.be.equal(schainHash);
        expect(schain.name).to.be.equal(schainName);
        expect(schain.paidUntil).to.be.equal(nextMonth(await currentTime()));
    });

    describe("when 1 validator and 1 schain exist", () => {
        const validatorId = 1;

        const addSchainAndValidatorFixture = async () => {
            const paymaster = await loadFixture(deployPaymasterFixture);
            await paymaster.addSchain(schainName);
            await paymaster.addValidator(validatorId, await validator.getAddress());
            return paymaster;
        }

        it("should be able to pay for schain", async () => {
            const paymaster = await loadFixture(addSchainAndValidatorFixture);
            const numberOfMonths = 1;

            const currentExpirationTime = await paymaster.getSchainExpirationTimestamp(schainHash);
            await paymaster.connect(user).pay(schainHash, numberOfMonths);
            let extendedExpirationTime = Number(currentExpirationTime);
            for (let month = 0; month < numberOfMonths; month += 1) {
                extendedExpirationTime = nextMonth(extendedExpirationTime);
            }
            expect(await paymaster.getSchainExpirationTimestamp(schainHash)).to.be.equal(extendedExpirationTime);
        });
    });
});
