import { MS_PER_SEC, currentTime, nextMonth, skipMonth, skipTimeToSpecificDate } from "./tools/time";
import { Paymaster, PaymasterAccessManager, Token } from "../typechain-types";
import {
    deployAccessManager,
    deployPaymaster,
    setupRoles
} from "../migrations/deploy";
import { HDNodeWallet } from "ethers";
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
    const precision = BigInt(1);

    let owner: SignerWithAddress;
    let validator: SignerWithAddress;
    let user: SignerWithAddress;
    let priceAgent: SignerWithAddress;

    const setup = async (paymaster: Paymaster, skaleToken: Token) => {
        const minute = 60;
        const MAX_REPLENISHMENT_PERIOD = 24;
        const SCHAIN_PRICE = ethers.parseEther("5000");
        const SKL_PRICE = ethers.parseEther("2");

        await skaleToken.mint(await user.getAddress(), BIG_AMOUNT);
        await skaleToken.connect(user).approve(await paymaster.getAddress(), BIG_AMOUNT);

        await paymaster.setMaxReplenishmentPeriod(MAX_REPLENISHMENT_PERIOD);
        await paymaster.setSchainPrice(SCHAIN_PRICE);
        await paymaster.setAllowedSklPriceLag(minute);
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

    describe("when 1 validator with 1 node and 1 schain exist", () => {
        const validatorId = 1;
        const nodesAmount = 1;

        const addSchainAndValidatorFixture = async () => {
            const paymaster = await loadFixture(deployPaymasterFixture);
            await paymaster.addSchain(schainName);
            await paymaster.addValidator(validatorId, await validator.getAddress());
            await paymaster.setNodesAmount(validatorId, nodesAmount);
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

        it("should remove schain", async () => {
            const paymaster = await loadFixture(addSchainAndValidatorFixture);

            await paymaster.removeSchain(schainHash);

            await expect(paymaster.getSchainExpirationTimestamp(schainHash))
                .to.be.revertedWithCustomError(paymaster, "SchainNotFound")
                .withArgs(schainHash);
        })

        it("should remove validator", async () => {
            const paymaster = await loadFixture(addSchainAndValidatorFixture);

            await paymaster.removeValidator(validatorId);

            await expect(paymaster.setNodesAmount(validatorId, nodesAmount + 1))
                .to.be.revertedWithCustomError(paymaster, "ValidatorNotFound")
                .withArgs(validatorId);
        });

        describe("when schain was paid for 1 month", () => {
            const payOneMonthFixture = async () => {
                const paymaster = await loadFixture(addSchainAndValidatorFixture);
                await paymaster.connect(user).pay(schainHash, 1);
                return paymaster;
            }

            it("should claim rewards after month end", async () => {
                const paymaster = await loadFixture(payOneMonthFixture);
                const token = await ethers.getContractAt("Token", await paymaster.skaleToken());
                const paidUntil = new Date( Number(await paymaster.getSchainExpirationTimestamp(schainHash)) * MS_PER_SEC);
                await skipTimeToSpecificDate(paidUntil);
                await paymaster.connect(validator).claim(await validator.getAddress());
                const tokensPerMonth = (await paymaster.schainPricePerMonth()) * ethers.parseEther("1") / (await paymaster.oneSklPrice());
                expect((await token.balanceOf(await validator.getAddress()))).to.be.equal(tokensPerMonth);
            })

            it("should calculate reward amount before claiming", async () => {
                const paymaster = await loadFixture(payOneMonthFixture);
                const paidUntil = new Date( Number(await paymaster.getSchainExpirationTimestamp(schainHash)) * MS_PER_SEC);
                await skipTimeToSpecificDate(paidUntil);
                const tokensPerMonth = (await paymaster.schainPricePerMonth()) * ethers.parseEther("1") / (await paymaster.oneSklPrice());
                expect(await paymaster.connect(validator).getRewardAmount()).to.be.equal(tokensPerMonth);
            });
        })
    });

    describe("when 7 validator and 7 schain exist", () => {
        const validatorsNumber = 7;
        const schainsNumber = 7;
        const defaultBalance = ethers.parseEther("100");

        const addSchainAndValidatorFixture = async () => {
            const paymaster = await loadFixture(deployPaymasterFixture);
            const token = await ethers.getContractAt("Token", await paymaster.skaleToken());
            const validators: HDNodeWallet[] = [];
            for (let index = 0; index < validatorsNumber; index += 1) {
                validators.push(ethers.Wallet.createRandom(ethers.provider));
            }

            for (const [index, validatorWallet] of validators.entries()) {
                if (await ethers.provider.getBalance(await validatorWallet.getAddress()) < defaultBalance) {
                    await owner.sendTransaction({
                        to: await validatorWallet.getAddress(),
                        value: defaultBalance
                    });
                }
                await paymaster.addValidator(index, await validatorWallet.getAddress());
                await paymaster.setNodesAmount(index, index + 1);
            }

            const schains = [];

            for (let index = 0; index < schainsNumber; index += 1) {
                const currentSchainName = `schain-${index}`;
                await paymaster.addSchain(currentSchainName);
                schains.push(ethers.solidityPackedKeccak256(["string"], [currentSchainName]));
            }

            return { paymaster, schains, token, validators };
        }

        it("should claim reward even if not all chains paid in time", async () => {
            const { paymaster, schains, token, validators } = await loadFixture(addSchainAndValidatorFixture);
            const tokensPerMonth = (await paymaster.schainPricePerMonth()) * ethers.parseEther("1") / (await paymaster.oneSklPrice());

            // Month A

            await paymaster.connect(user).pay(schains[0], 1);
            await paymaster.connect(user).pay(schains[1], 1);

            await skipMonth();

            // Month B

            // Chain does not pay for 0 (non full) month
            expect(await paymaster.getRewardAmountFor(0)).to.be.equal(0);
            await expect(paymaster.connect(validators[0]).claim(await validators[0].getAddress()))
                .to.changeTokenBalance(token, validators[0], 0);

            await paymaster.connect(priceAgent).setSklPrice(await paymaster.oneSklPrice());
            const thirdChain = 2;
            await paymaster.connect(user).pay(schains[thirdChain], 1);

            await skipMonth();

            // Month C

            let totalNodesNumber = BigInt(0);
            for (let index = 0; index < validators.length; index += 1) {
                totalNodesNumber += await paymaster.getNodesNumber(index);
            }

            // Reward for month B is available
            const amountOfPaidChains = 3;
            const monthBReward = tokensPerMonth * BigInt(amountOfPaidChains);
            expect(await paymaster.getRewardAmountFor(0)).to.be.equal(monthBReward / totalNodesNumber);
            await expect(paymaster.connect(validators[0]).claim(await validators[0].getAddress()))
                .to.changeTokenBalance(token, validators[0], monthBReward / totalNodesNumber);

            // Should not get reward one more time
            expect(await paymaster.getRewardAmountFor(0)).to.be.equal(0);
            await expect(paymaster.connect(validators[0]).claim(await validators[0].getAddress()))
                .to.changeTokenBalance(token, validators[0], 0);

            // Reward for another validator
            for (let anotherValidator = 1; anotherValidator < validators.length; anotherValidator += 1) {
                const estimated = await paymaster.getRewardAmountFor(anotherValidator);
                const calculated = monthBReward * (await paymaster.getNodesNumber(anotherValidator)) / totalNodesNumber;
                expect(estimated).be.lessThanOrEqual(calculated);
                expect(calculated - estimated).be.lessThanOrEqual(precision);
                await expect(paymaster.connect(validators[anotherValidator]).claim(await validators[anotherValidator].getAddress()))
                    .to.changeTokenBalance(
                        token,
                        validators[anotherValidator],
                        estimated
                    );
            }
        })
    });
});
