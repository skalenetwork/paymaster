import { MS_PER_SEC, currentTime, getResponseTimestamp, monthBegin, nextMonth, skipMonth, skipTime, skipTimeToSpecificDate } from "./tools/time";
import { Paymaster, PaymasterAccessManager, Token } from "../typechain-types";
import {
    deployAccessManager,
    deployPaymaster,
    setupRoles
} from "../migrations/deploy";
import { expect, use } from "chai";
import { HDNodeWallet } from "ethers";
import Prando from 'prando';
import { Rewards } from "./tools/rewards";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { d2ChaiMatchers } from "./tools/matchers";
import { ethers } from "hardhat";
import {
    loadFixture
} from "@nomicfoundation/hardhat-toolbox/network-helpers";

use(d2ChaiMatchers);


describe("Paymaster", () => {
    const schainName = "d2-schain";
    const schainHash = ethers.solidityPackedKeccak256(["string"], [schainName]);
    const BIG_AMOUNT = ethers.parseEther("1000000");
    const MAX_REPLENISHMENT_PERIOD = 24;
    const precision = 5n;
    const decimalPlacePrecision = 12n;

    let owner: SignerWithAddress;
    let validator: SignerWithAddress;
    let user: SignerWithAddress;
    let priceAgent: SignerWithAddress;

    const setup = async (paymaster: Paymaster, skaleToken: Token) => {
        const minute = 60;
        const SCHAIN_PRICE = ethers.parseEther("5000");
        const SKL_PRICE = ethers.parseEther("0.5");

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
        const baseRewards = new Rewards();
        return {baseRewards, paymaster};
    }

    before(async () => {
        [owner, validator, user, priceAgent] = await ethers.getSigners();
    })

    it("should add schain", async () => {
        const { paymaster } = await loadFixture(deployPaymasterFixture);
        await paymaster.addSchain(schainName);
        const schain = await paymaster.schains(schainHash);
        expect(schain.hash).to.be.equal(schainHash);
        expect(schain.name).to.be.equal(schainName);
        expect(schain.paidUntil).to.be.equal(nextMonth(await currentTime()));
    });

    it("should set version", async () => {
        const { paymaster } = await loadFixture(deployPaymasterFixture);
        const version = "version";
        await expect(paymaster.setVersion(version))
            .to.emit(paymaster, "VersionSet")
            .withArgs(version);

        expect(await paymaster.version()).to.be.equal(version);
    })

    describe("when 1 validator with 1 node and 1 schain exist", () => {
        const validatorId = 1;
        const nodesAmount = 1;

        const addSchainAndValidatorFixture = async () => {
            const { baseRewards, paymaster } = await loadFixture(deployPaymasterFixture);
            const rewards = baseRewards.clone();
            const token = await ethers.getContractAt("Token", await paymaster.skaleToken());
            rewards.addSchain(
                schainHash,
                await getResponseTimestamp(await paymaster.addSchain(schainName))
            );
            await paymaster.addValidator(validatorId, await validator.getAddress());
            rewards.setNodesAmount(
                validatorId,
                nodesAmount,
                await getResponseTimestamp(await paymaster.setNodesAmount(validatorId, nodesAmount))
            );
            return { baseRewards: rewards, paymaster, token };
        }

        it("should be able to pay for schain", async () => {
            const { paymaster } = await loadFixture(addSchainAndValidatorFixture);
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
            const { paymaster } = await loadFixture(addSchainAndValidatorFixture);

            await paymaster.removeSchain(schainHash);

            await expect(paymaster.getSchainExpirationTimestamp(schainHash))
                .to.be.revertedWithCustomError(paymaster, "SchainNotFound")
                .withArgs(schainHash);
        })

        it("should remove validator", async () => {
            const { baseRewards, paymaster } = await loadFixture(addSchainAndValidatorFixture);
            const rewards = baseRewards.clone();

            const removeValidator = await paymaster.removeValidator(validatorId);
            expect(removeValidator).to.emit(paymaster, "ValidatorMarkedAsRemoved");
            rewards.setNodesAmount(validatorId, 0, await getResponseTimestamp(removeValidator));

            await expect(paymaster.setNodesAmount(validatorId, nodesAmount + 1))
                .to.be.revertedWithCustomError(paymaster, "ValidatorHasBeenRemoved")
                .withArgs(validatorId, await currentTime());

            await expect(paymaster.clearHistory(await currentTime() + 1))
                .to.be.revertedWithCustomError(paymaster, "ImportantDataRemoving");

            const deletedTimestamp = await currentTime();
            await skipMonth();
            const claim = await paymaster.connect(validator).claim(await validator.getAddress());
            await expect(claim).to.changeTokenBalance(
                await ethers.getContractAt("Token", await paymaster.skaleToken()),
                await validator.getAddress(),
                rewards.claim(validatorId, await getResponseTimestamp(claim))
            );

            await expect(paymaster.clearHistory(deletedTimestamp))
                .to.emit(paymaster, "ValidatorRemoved");
        });

        it("should not add validator with the same id", async () => {
            const { paymaster } = await loadFixture(addSchainAndValidatorFixture);

            await expect(paymaster.addValidator(validatorId, await user.getAddress()))
                .to.be.revertedWithCustomError(paymaster, "ValidatorAddingError")
                .withArgs(validatorId);
        })

        it("should not add validator with the same address", async () => {
            const { paymaster } = await loadFixture(addSchainAndValidatorFixture);

            await expect(paymaster.addValidator(validatorId + 1, await validator.getAddress()))
                .to.be.revertedWithCustomError(paymaster, "ValidatorAddressAlreadyExists")
                .withArgs(await validator.getAddress());
        })

        it("should not allow to top up more than max replenishment period", async () => {
            const { paymaster } = await loadFixture(addSchainAndValidatorFixture);
            const fiveMonths = 5;

            await expect(paymaster.connect(user).pay(schainHash, MAX_REPLENISHMENT_PERIOD + 1))
                .to.be.revertedWithCustomError(paymaster, "ReplenishmentPeriodIsTooBig")

            for (let index = 0; index < fiveMonths; index += 1) {
                await skipMonth();
            }

            await paymaster.connect(priceAgent).setSklPrice(await paymaster.oneSklPrice());
            await expect(paymaster.connect(user).pay(schainHash, MAX_REPLENISHMENT_PERIOD + fiveMonths + 1))
                .to.be.revertedWithCustomError(paymaster, "ReplenishmentPeriodIsTooBig")

            await expect(paymaster.connect(user).pay(schainHash, MAX_REPLENISHMENT_PERIOD + fiveMonths))
                .to.emit(paymaster, "SchainPaid");
        });

        it("should allow to blacklist nodes", async () => {
            const { paymaster } = await loadFixture(addSchainAndValidatorFixture);

            const nodesNumber = 7;
            const blacklistedNodesNumber = 3;

            await paymaster.setNodesAmount(validatorId, nodesNumber);
            expect(await paymaster.getNodesNumber(validatorId)).to.be.equal(nodesNumber);
            expect(await paymaster.getActiveNodesNumber(validatorId)).to.be.equal(nodesNumber);

            // Blacklist
            await paymaster.setActiveNodes(validatorId, nodesNumber - blacklistedNodesNumber);

            expect(await paymaster.getNodesNumber(validatorId)).to.be.equal(nodesNumber);
            expect(await paymaster.getActiveNodesNumber(validatorId)).to.be.equal(nodesNumber - blacklistedNodesNumber);
        })

        it("should not pay debt before month end", async () => {
            const { paymaster, token } = await loadFixture(addSchainAndValidatorFixture);

            await skipMonth();

            await paymaster.connect(priceAgent).setSklPrice(await paymaster.oneSklPrice());
            await paymaster.connect(user).pay(schainHash, 1);

            const claim = await paymaster.connect(validator).claim(await validator.getAddress());
            await expect(claim).to.changeTokenBalance(
                token,
                await validator.getAddress(),
                0
            );
        });

        describe("when schain was paid for 1 month", () => {
            const payOneMonthFixture = async () => {
                const { baseRewards, paymaster } = await loadFixture(addSchainAndValidatorFixture);
                const rewards = baseRewards.clone();

                await paymaster.connect(user).pay(schainHash, 1);
                rewards.addPayment(
                    schainHash,
                    (await paymaster.schainPricePerMonth()) * ethers.parseEther("1") / (await paymaster.oneSklPrice()),
                    1
                );
                const token = await ethers.getContractAt("Token", await paymaster.skaleToken());
                return { baseRewards: rewards, paymaster, token };
            }

            it("should claim rewards after month end", async () => {
                const { baseRewards, paymaster, token } = await loadFixture(payOneMonthFixture);
                const rewards = baseRewards.clone();
                const paidUntil = new Date( Number(await paymaster.getSchainExpirationTimestamp(schainHash)) * MS_PER_SEC);
                await skipTimeToSpecificDate(paidUntil);
                const claim = await paymaster.connect(validator).claim(await validator.getAddress());
                await expect(claim).to.changeTokenBalance(
                    token,
                    await validator.getAddress(),
                    rewards.claim(validatorId, await getResponseTimestamp(claim))
                );
            })

            it("should allow admin to claim rewards for the validator", async () => {
                const { paymaster } = await loadFixture(payOneMonthFixture);
                const token = await ethers.getContractAt("Token", await paymaster.skaleToken());
                const paidUntil = new Date( Number(await paymaster.getSchainExpirationTimestamp(schainHash)) * MS_PER_SEC);
                await skipTimeToSpecificDate(paidUntil);
                const tokensPerMonth = (await paymaster.schainPricePerMonth()) * ethers.parseEther("1") / (await paymaster.oneSklPrice());
                await expect(paymaster.claimFor(validatorId, await validator.getAddress()))
                    .to.changeTokenBalance(token, validator, tokensPerMonth);
            })

            it("should calculate reward amount before claiming", async () => {
                const { paymaster } = await loadFixture(payOneMonthFixture);
                const paidUntil = new Date( Number(await paymaster.getSchainExpirationTimestamp(schainHash)) * MS_PER_SEC);
                await skipTimeToSpecificDate(paidUntil);
                const tokensPerMonth = (await paymaster.schainPricePerMonth()) * ethers.parseEther("1") / (await paymaster.oneSklPrice());
                expect(await paymaster.getRewardAmount(validatorId)).to.be.equal(tokensPerMonth);
            });

            it("should be able to clear history", async () => {
                const { baseRewards, paymaster, token } = await loadFixture(payOneMonthFixture);
                const rewards = baseRewards.clone();

                // Paid:    [^         |##########]
                // Claimed: [^         |          ]

                await skipMonth();
                await skipMonth();

                // Paid:    [          |##########|^]
                // Claimed: [          |          |^]

                let claim = await paymaster.connect(validator).claim(await validator.getAddress());
                await expect(claim).to.changeTokenBalance(
                    token,
                    await validator.getAddress(),
                    rewards.claim(validatorId, await getResponseTimestamp(claim))
                );

                // Paid:    [          |##########|^]
                // Claimed: [##########|##########|^]

                await skipMonth();

                // Paid:    [          |##########|          |^]
                // Claimed: [##########|##########|          |^]

                claim = await paymaster.connect(validator).claim(await validator.getAddress());
                await expect(claim).to.changeTokenBalance(
                    token,
                    await validator.getAddress(),
                    rewards.claim(validatorId, await getResponseTimestamp(claim))
                );
                let claimedUntil = (await paymaster.queryFilter(paymaster.filters.RewardClaimed, "latest"))[0].args.until;

                // Paid:    [          |##########|          |^]
                // Claimed: [##########|##########|##########|^]

                await expect(paymaster.clearHistory(claimedUntil))
                    .to.be.revertedWithCustomError(paymaster, "ImportantDataRemoving");

                await paymaster.connect(priceAgent).setSklPrice(await paymaster.oneSklPrice());
                await paymaster.connect(user).pay(schainHash, 1);
                const tokensPerMonth = (await paymaster.schainPricePerMonth()) * ethers.parseEther("1") / (await paymaster.oneSklPrice());
                rewards.addPayment(schainHash, tokensPerMonth, 1);

                // Paid:    [          |##########|**********|^]
                // Claimed: [##########|##########|##########|^]

                await expect(paymaster.clearHistory(claimedUntil))
                    .to.be.revertedWithCustomError(paymaster, "ImportantDataRemoving");

                claim = await paymaster.connect(validator).claim(await validator.getAddress());
                await expect(claim).to.changeTokenBalance(
                    token,
                    await validator.getAddress(),
                    rewards.claim(validatorId, await getResponseTimestamp(claim))
                );

                // Paid:    [          |##########|##########|^]
                // Claimed: [##########|##########|##########|^]

                claimedUntil = (await paymaster.queryFilter(paymaster.filters.RewardClaimed, "latest"))[0].args.until;
                await paymaster.clearHistory(claimedUntil);

                // Paid:    [          |          |          |^]
                // Claimed: [          |          |          |^]

                expect(await paymaster.getTotalReward(0, claimedUntil)).to.be.equal(0);
                expect(await paymaster.getHistoricalActiveNodesNumber(validatorId, claimedUntil - 1n)).to.be.equal(0);
                expect(await paymaster.getHistoricalTotalActiveNodesNumber(claimedUntil - 1n)).to.be.equal(0);
                expect(await paymaster.debtsBegin()).to.be.equal(1);
                expect(await paymaster.debtsEnd()).to.be.equal(1);

                await paymaster.connect(priceAgent).setSklPrice(await paymaster.oneSklPrice());
                await paymaster.connect(user).pay(schainHash, 1);
                rewards.addPayment(schainHash, tokensPerMonth, 1);

                // Paid:    [          |          |          |^#########]
                // Claimed: [          |          |          |^         ]

                await skipMonth();

                // Paid:    [          |          |          |##########|^]
                // Claimed: [          |          |          |          |^]

                const estimated = await paymaster.getRewardAmount(validatorId);
                const calculated = tokensPerMonth;
                expect(estimated).be.lessThanOrEqual(calculated);
                expect(calculated - estimated).be.lessThanOrEqual(precision);
                claim = await paymaster.connect(validator).claim(await validator.getAddress());
                await expect(claim).to.changeTokenBalance(
                    token,
                    validator,
                    rewards.claim(validatorId, await getResponseTimestamp(claim))
                );
                await expect(claim).to.changeTokenBalance(
                    token,
                    validator,
                    estimated
                );

                // Paid:    [          |          |          |##########|^]
                // Claimed: [          |          |          |##########|^]

                claimedUntil = (await paymaster.queryFilter(paymaster.filters.RewardClaimed, "latest"))[0].args.until;
                await paymaster.clearHistory(claimedUntil);

                // Paid:    [          |          |          |          |^]
                // Claimed: [          |          |          |          |^]

                expect(await paymaster.getTotalReward(0, claimedUntil)).to.be.equal(0);
                expect(await paymaster.getHistoricalActiveNodesNumber(validatorId, claimedUntil - 1n)).to.be.equal(0);
                expect(await paymaster.getHistoricalTotalActiveNodesNumber(claimedUntil - 1n)).to.be.equal(0);
                expect(await paymaster.debtsBegin()).to.be.equal(1);
                expect(await paymaster.debtsEnd()).to.be.equal(1);
            })
        })
    });

    describe("when 7 validators and 7 schains exist", () => {
        const validatorsNumber = 7;
        const schainsNumber = 7;
        const defaultBalance = ethers.parseEther("100");

        const addSchainAndValidatorFixture = async () => {
            const { baseRewards, paymaster } = await loadFixture(deployPaymasterFixture);
            const rewards = baseRewards.clone();
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
                const response = await paymaster.setNodesAmount(index, index + 1);
                rewards.setNodesAmount(index, index + 1, await getResponseTimestamp(response));
            }

            const schains = [];

            for (let index = 0; index < schainsNumber; index += 1) {
                const currentSchainName = `schain-${index}`;
                const response = await paymaster.addSchain(currentSchainName);
                const sHash = ethers.solidityPackedKeccak256(["string"], [currentSchainName]);
                schains.push(sHash);
                rewards.addSchain(sHash, await getResponseTimestamp(response));
            }

            return { baseRewards: rewards, paymaster, schains, token, validators };
        }

        it("should claim reward even if not all chains paid in time", async () => {
            const { baseRewards, paymaster, schains, token, validators } = await loadFixture(addSchainAndValidatorFixture);
            const rewards = baseRewards.clone();
            const tokensPerMonth = (await paymaster.schainPricePerMonth()) * ethers.parseEther("1") / (await paymaster.oneSklPrice());

            // Month A

            await paymaster.connect(user).pay(schains[0], 1);
            await paymaster.connect(user).pay(schains[1], 1);

            rewards.addPayment(schains[0], tokensPerMonth, 1);
            rewards.addPayment(schains[1], tokensPerMonth, 1);

            await skipMonth();

            // Month B

            // Chain does not pay for 0 (non full) month
            expect(await paymaster.getRewardAmount(0)).to.be.equal(0);
            let claim = await paymaster.connect(validators[0]).claim(await validators[0].getAddress());
            await expect(claim).to.changeTokenBalance(token, validators[0], 0);
            await expect(claim).to.changeTokenBalance(
                token,
                await validators[0].getAddress(),
                rewards.claim(0, await getResponseTimestamp(claim))
            );

            await paymaster.connect(priceAgent).setSklPrice(await paymaster.oneSklPrice());
            const thirdChain = 2;
            await paymaster.connect(user).pay(schains[thirdChain], 1);
            rewards.addPayment(schains[thirdChain], tokensPerMonth, 1);

            await skipMonth();

            // Month C

            let totalNodesNumber = BigInt(0);
            for (let index = 0; index < validators.length; index += 1) {
                totalNodesNumber += await paymaster.getNodesNumber(index);
            }

            // Reward for month B is available
            const amountOfPaidChains = 3;
            const monthBReward = tokensPerMonth * BigInt(amountOfPaidChains);
            let estimated = await paymaster.getRewardAmount(0);
            let calculated = monthBReward / totalNodesNumber;
            expect(estimated).be.lessThanOrEqual(calculated);
            expect(calculated - estimated).be.lessThanOrEqual(precision);
            claim = await paymaster.connect(validators[0]).claim(await validators[0].getAddress());
            await expect(claim).to.changeTokenBalance(token, validators[0], estimated);
            await expect(claim).to.approximatelyChangeTokenBalance(
                token,
                validators[0],
                rewards.claim(0, await getResponseTimestamp(claim)),
                precision
            );

            // Should not get reward one more time
            expect(await paymaster.getRewardAmount(0)).to.be.equal(0);
            claim = await paymaster.connect(validators[0]).claim(await validators[0].getAddress());
            await expect(claim).to.changeTokenBalance(token, validators[0], 0);
            await expect(claim).to.changeTokenBalance(
                token,
                validators[0],
                rewards.claim(0, await getResponseTimestamp(claim))
            );

            // Reward for another validator
            for (let anotherValidator = 1; anotherValidator < validators.length; anotherValidator += 1) {
                estimated = await paymaster.getRewardAmount(anotherValidator);
                calculated = monthBReward * (await paymaster.getNodesNumber(anotherValidator)) / totalNodesNumber;
                expect(estimated).be.lessThanOrEqual(calculated);
                expect(calculated - estimated).be.lessThanOrEqual(precision);
                claim = await paymaster.connect(validators[anotherValidator]).claim(await validators[anotherValidator].getAddress());
                await expect(claim).to.changeTokenBalance(
                    token,
                    validators[anotherValidator],
                    estimated
                );
                await expect(claim).to.approximatelyChangeTokenBalance(
                    token,
                    validators[anotherValidator],
                    rewards.claim(anotherValidator, await getResponseTimestamp(claim)),
                    precision
                );
            }
        })

        it("should claim reward after other validators were removed", async () => {
            const { baseRewards, paymaster, schains, token, validators } = await loadFixture(addSchainAndValidatorFixture);
            const rewards = baseRewards.clone();
            const tokensPerMonth = (await paymaster.schainPricePerMonth()) * ethers.parseEther("1") / (await paymaster.oneSklPrice());
            const twoYears = 24;

            let totalNodesNumber = BigInt(0);
            for (let index = 0; index < validators.length; index += 1) {
                totalNodesNumber += await paymaster.getNodesNumber(index);
            }

            // Month A

            await paymaster.connect(user).pay(schains[0], twoYears);
            rewards.addPayment(schains[0], tokensPerMonth * BigInt(twoYears), twoYears);

            await paymaster.connect(user).pay(schains[1], 1);
            rewards.addPayment(schains[1], tokensPerMonth, 1);

            await skipMonth();
            await skipMonth();

            // Month C

            // Reward for month B is available
            const amountOfPaidChains = 2;
            const monthBReward = tokensPerMonth * BigInt(amountOfPaidChains);

            // All validators except the last one claim reward
            for (let validatorId = 0; validatorId < validators.length - 1; validatorId += 1) {
                const estimated = await paymaster.getRewardAmount(validatorId);
                const calculated = monthBReward * (await paymaster.getNodesNumber(validatorId)) / totalNodesNumber;
                expect(estimated).be.lessThanOrEqual(calculated);
                expect(calculated - estimated).be.lessThanOrEqual(precision);
                const claim = await paymaster.connect(validators[validatorId]).claim(await validators[validatorId].getAddress());
                await expect(claim).to.changeTokenBalance(
                    token,
                    validators[validatorId],
                    estimated
                );
                await expect(claim).to.changeTokenBalance(
                    token,
                    validators[validatorId],
                    rewards.claim(validatorId, await getResponseTimestamp(claim))
                );
            }

            // Remove all validator except the first one
            for (let validatorId = 1; validatorId < validators.length; validatorId += 1) {
                const response = await paymaster.removeValidator(validatorId);
                rewards.setNodesAmount(validatorId, 0, await getResponseTimestamp(response));
            }

            await skipMonth();

            // Month D

            // Reward for month C is available
            const amountOfChainsPaidForMonthC = 1;
            const monthCReward = tokensPerMonth * BigInt(amountOfChainsPaidForMonthC);

            const validatorId = 0;
            const removedValidatorsReward = ethers.parseEther("1");
            const estimated = await paymaster.getRewardAmount(validatorId);
            const calculated = monthCReward
            expect(estimated).be.lessThanOrEqual(calculated);
            expect(calculated - estimated).be.lessThanOrEqual(removedValidatorsReward);
            const claim = await paymaster.connect(validators[validatorId]).claim(await validators[validatorId].getAddress());
            await expect(claim).to.changeTokenBalance(
                token,
                validators[validatorId],
                estimated
            );
            await expect(claim).to.changeTokenBalance(
                token,
                validators[validatorId],
                rewards.claim(validatorId, await getResponseTimestamp(claim))
            );
        });

        it("should claim reward after removing", async () => {
            const { baseRewards, paymaster, schains, token, validators } = await loadFixture(addSchainAndValidatorFixture);
            const rewards = baseRewards.clone();
            const twoMonths = 2;
            const tokensPerMonth = (await paymaster.schainPricePerMonth()) * ethers.parseEther("1") / (await paymaster.oneSklPrice());

            let totalNodesNumber = BigInt(0);
            for (let index = 0; index < validators.length; index += 1) {
                totalNodesNumber += await paymaster.getNodesNumber(index);
            }

            // Month A

            // Pay for month B and C
            await paymaster.connect(user).pay(schains[0], twoMonths);
            rewards.addPayment(schains[0], tokensPerMonth * BigInt(twoMonths), twoMonths);

            await skipMonth();
            await skipMonth();

            // Month C

            // Reward for month B is available
            const amountOfPaidChains = 1;
            const monthBReward = tokensPerMonth * BigInt(amountOfPaidChains);

            // All validators except the last one claim reward
            for (let validatorId = 0; validatorId < validators.length; validatorId += 1) {
                const estimated = await paymaster.getRewardAmount(validatorId);
                const calculated = monthBReward * (await paymaster.getNodesNumber(validatorId)) / totalNodesNumber;
                expect(estimated).be.lessThanOrEqual(calculated);
                expect(calculated - estimated).be.lessThanOrEqual(precision);
                if (validatorId < validators.length - 1) {
                    const claim = await paymaster.connect(validators[validatorId]).claim(await validators[validatorId].getAddress());
                    await expect(claim).to.changeTokenBalance(
                        token,
                        validators[validatorId],
                        estimated
                    );
                    await expect(claim).to.changeTokenBalance(
                        token,
                        validators[validatorId],
                        rewards.claim(validatorId, await getResponseTimestamp(claim))
                    );
                }
            }

            // Remove all validator except the first one
            for (let validatorId = 1; validatorId < validators.length; validatorId += 1) {
                const removeValidator = await paymaster.removeValidator(validatorId);
                rewards.setNodesAmount(validatorId, 0, await getResponseTimestamp(removeValidator));
            }

            await skipMonth();

            // Month D

            const validatorId = validators.length - 1;
            const estimated = await paymaster.getRewardAmount(validatorId);
            const claim = await paymaster.connect(validators[validatorId]).claim(await validators[validatorId].getAddress());
            await expect(claim).to.changeTokenBalance(
                token,
                validators[validatorId],
                estimated
            );
            await expect(claim).to.changeTokenBalance(
                token,
                validators[validatorId],
                rewards.claim(validatorId, await getResponseTimestamp(claim))
            );
        });

        it("should not pay reward for inactive nodes", async () => {
            const { paymaster, schains, token, validators } = await loadFixture(addSchainAndValidatorFixture);
            const tokensPerMonth = (await paymaster.schainPricePerMonth()) * ethers.parseEther("1") / (await paymaster.oneSklPrice());
            const twoYears = 24;
            const validatorId = 0;

            let totalNodesNumber = BigInt(0);
            for (let index = 0; index < validators.length; index += 1) {
                totalNodesNumber += await paymaster.getNodesNumber(index);
            }

            // Month A

            await paymaster.connect(user).pay(schains[0], twoYears);

            await skipMonth();

            // Month B

            expect(await paymaster.getRewardAmount(validatorId)).to.be.equal(0);

            // Fast forward to the middle of the month

            const currentTimestamp = await currentTime();
            await skipTime((nextMonth(currentTimestamp) + monthBegin(currentTimestamp)) / 2 - currentTimestamp);
            const secondsInMonthB = BigInt(nextMonth(currentTimestamp) - monthBegin(currentTimestamp));

            await paymaster.setActiveNodes(validatorId, 0);
            const blacklistedTimestamp = (await paymaster.queryFilter(paymaster.filters.ActiveNodesNumberChanged, "latest"))[0].args.timestamp;

            await skipMonth();

            // Month C

            const monthBReward = tokensPerMonth;
            const rewardRate = monthBReward / secondsInMonthB;
            const estimated = await paymaster.getRewardAmount(validatorId);
            const calculated = rewardRate * (blacklistedTimestamp - BigInt(monthBegin(blacklistedTimestamp))) / totalNodesNumber;
            expect(estimated).be.lessThanOrEqual(calculated);
            expect(calculated - estimated).be.lessThanOrEqual(precision);
            await expect(paymaster.connect(validators[validatorId]).claim(await validators[validatorId].getAddress()))
                .to.changeTokenBalance(
                    token,
                    validators[validatorId],
                    estimated
                );
        });

        it("should allow to get information about validators and schains", async () => {
            const { paymaster, schains, validators } = await loadFixture(addSchainAndValidatorFixture);

            expect(await paymaster.getValidatorsNumber()).to.be.equal(validators.length);
            expect(await paymaster.getSchainsNumber()).to.be.equal(schains.length);
            expect((await paymaster.getSchainsNames()).map(
                (name) => ethers.solidityPackedKeccak256(["string"], [name])
            )).to.have.same.members(schains);
        });

        it("random test", async () => {
            const timelimit = 1500;
            const maxTopUpMonths = 7;
            const maxNodesAmount = 5;

            const start = new Date().getTime();
            const rnd = new Prando("D2");
            const week = 604800;
            const averageMonth = 2628288;

            enum Event {
                CHANGE_NODES_NUMBER,
                CLAIM,
                TOP_UP_SCHAIN
            }

            const { baseRewards, paymaster, schains, token, validators } = await loadFixture(addSchainAndValidatorFixture);
            const rewards = baseRewards.clone();
            const pricePerMonth = (await paymaster.schainPricePerMonth()) * ethers.parseEther("1") / (await paymaster.oneSklPrice());

            // // DEBUG
            // while (schains.length > 1) {
            //     schains.pop();
            // }
            // while (validators.length > 3) {
            //     validators.pop();
            // }

            // // DEBUG END

            await skipMonth();

            while (new Date().getTime() - start < timelimit * MS_PER_SEC) {
                console.log(
                    `Time: ${new Date(await currentTime() * MS_PER_SEC).toISOString()}`,
                    `(${await currentTime()})`
                );
                const event = rnd.nextArrayItem(Object.values(Event).filter((value) => typeof value !== "string"));

                if (event === Event.TOP_UP_SCHAIN) {
                    const sHash = rnd.nextArrayItem(schains);
                    const months = rnd.nextInt(0, maxTopUpMonths + 1);

                    const paidUntil = Number(await paymaster.getSchainExpirationTimestamp(sHash));
                    const target = nextMonth(await currentTime()) + months * averageMonth;

                    if (target > paidUntil) {
                        const period = Math.round((target - paidUntil) / averageMonth);
                        await paymaster.connect(priceAgent).setSklPrice(await paymaster.oneSklPrice());
                        console.log(`\tTop up ${sHash} for ${period} months`);

                        if (period > 0) {
                            await expect(paymaster.connect(user).pay(sHash, period))
                                .to.changeTokenBalance(
                                    token,
                                    await paymaster.getAddress(),
                                    BigInt(period) * pricePerMonth);
                            rewards.addPayment(sHash, BigInt(period) * pricePerMonth, period);
                        } else {
                            await expect(paymaster.connect(user).pay(sHash, period))
                                .to.revertedWithCustomError(paymaster, "ReplenishmentPeriodIsTooSmall");
                        }
                    }
                } else if (event === Event.CLAIM) {
                    const vId = rnd.nextInt(0, validators.length - 1);

                    const estimated = await paymaster.getRewardAmount(vId);
                    console.log(`\tValidator ${vId} claimed ${estimated} SKL`);

                    const claim = await paymaster.connect(validators[vId]).claim(await validators[vId].getAddress());
                    await expect(claim).to.changeTokenBalance(
                        token,
                        validators[vId],
                        estimated
                    );
                    const decimalBase = 10n;
                    await expect(claim).to.approximatelyChangeTokenBalance(
                        token,
                        validators[vId],
                        rewards.claim(vId, await getResponseTimestamp(claim)),
                        decimalBase ** (await token.decimals() - decimalPlacePrecision)
                    );
                } else if (event === Event.CHANGE_NODES_NUMBER) {
                    const vId = rnd.nextInt(0, validators.length - 1);
                    const nodesAmount = rnd.nextInt(0, maxNodesAmount);

                    const response = await paymaster.setNodesAmount(vId, nodesAmount);
                    rewards.setNodesAmount(vId, nodesAmount, await getResponseTimestamp(response));

                    console.log(`\tValidator ${vId} has ${nodesAmount} nodes (${await getResponseTimestamp(response)})`);
                }

                await skipTime(week);
            }
        });
    });
});
