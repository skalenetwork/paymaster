import { ethers } from "hardhat"
import { expect } from 'chai';
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";


describe("Timeline", () => {

    const deploySequenceFixture = async () => await ethers.deployContract("SequenceTester");

    describe("basic tests", () => {
        const offset = 10;
        const space = 5;
        const number = 7

        const sequenceWithSampleData = async () => {
            const sequence = await loadFixture(deploySequenceFixture);

            //                                         #####
            //                                    ###############
            //                               #########################
            //                          ###################################
            //                     #############################################
            //                #######################################################
            //           #################################################################
            // |---------|---------|---------|---------|---------|---------|---------|---------|

            for (let index = 0; index < number; index += 1) {
                await sequence.add(offset + index * space, index + 1);
            }

            for (let index = 0; index < number; index += 1) {
                await sequence.add(offset + (index + number) * space, number - index - 1);
            }

            return sequence;
        }

        it("should not allow to add to the processed part", async () => {
            const sequence = await loadFixture(sequenceWithSampleData);

            await expect(sequence.add(offset, 1))
                .to.be.revertedWithCustomError(sequence, "CannotAddToThePast");
        });
    });
});
