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
            // |0--------|10-------|20-------|30-------|40-------|50-------|60-------|70-------|80

            for (let index = 0; index < number; index += 1) {
                await sequence.add(offset + index * space, index + 1);
            }

            for (let index = 0; index < number; index += 1) {
                await sequence.add(offset + (index + number) * space, number - index - 1);
            }

            return sequence;
        }

        const getValue = (timestamp: number) => {
            if (timestamp < offset) {
                return 0;
            }

            let pointer = timestamp - offset;
            if (pointer < space * number) {
                return 1 + Math.floor(pointer / space);
            }

            pointer -= space * (number - 1);
            return number - Math.min(Math.floor(pointer / space), number);
        }

        it("should not allow to add to the processed part", async () => {
            const sequence = await loadFixture(sequenceWithSampleData);

            await expect(sequence.add(offset, 1))
                .to.be.revertedWithCustomError(sequence, "CannotAddToThePast");
        });

        it("should get value", async () => {
            const sequence = await loadFixture(sequenceWithSampleData);

            const maxTimestamp = 100;

            for (let timestamp = 0; timestamp < maxTimestamp; timestamp += 1) {
                expect(await sequence.getValueByTimestamp(timestamp)).to.be.equal(getValue(timestamp));
            }
        });
    });
});
