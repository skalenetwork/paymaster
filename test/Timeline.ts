import Prando from 'prando';
import { ethers } from "hardhat";
import { expect } from 'chai';
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";


describe("Timeline", () => {
    const deployTimelineFixture = async () => await ethers.deployContract("TimelineTester")

    describe("basic tests", () => {
        it("should calculate an entire segment", async () => {
            const timeline = await loadFixture(deployTimelineFixture);
            const from = 10;
            const to = 20;
            const value = 10;
            await timeline.add(from, to, value);
            expect(await timeline.getSum(from, to + 1)).to.be.equal(value);
        })

        it("should calculate part of a segment", async () => {
            const timeline = await loadFixture(deployTimelineFixture);
            const from = 0;
            const to = 10;
            const value = 60;
            const testFrom = 0;
            const testTo = 2;
            const testAnswer = 12;
            await timeline.add(from, to, value);
            await timeline.process(1);
            expect(await timeline.getSum(testFrom, testTo)).to.be.equal(testAnswer);
        });
    });

    it("random test", async () => {
        const rnd = new Prando("D2");
        const timeline = await loadFixture(deployTimelineFixture);

        interface Segment {
            from: number,
            to: number,
            value: number
        }

        const segmentsNumber = 5;
        const minTime = 0;
        const maxTime = 7;
        const maxValue = 11;
        const segments: Segment[] = []

        for (let index = 0; index < segmentsNumber; index+=1) {
            const from = rnd.nextInt(minTime, maxTime);
            const to = rnd.nextInt(from + 1, maxTime + 1)
            segments.push({
                from,
                to,
                value: rnd.nextInt(1, maxValue) * (to - from)
            })
        }

        for (const segment of segments) {
            await timeline.add(segment.from, segment.to, segment.value);
        }

        for (let processedTimestamp = 0; processedTimestamp <= maxTime; processedTimestamp += 1) {
            await timeline.process(processedTimestamp);
            for (let fromTimestamp = 0; fromTimestamp <= maxTime; fromTimestamp += 1) {
                for (let toTimestamp = fromTimestamp; toTimestamp <= maxTime; toTimestamp += 1) {
                    const calculatedValue = await timeline.getSum(fromTimestamp, toTimestamp);

                    let correctValue = 0;
                    for (const segment of segments) {
                        if (!(segment.to < fromTimestamp || toTimestamp <= segment.from)) {
                            const from = Math.max(segment.from, fromTimestamp);
                            const to = Math.min(segment.to, toTimestamp);
                            correctValue += Math.floor(segment.value * (to - from) / (segment.to - segment.from));
                        }
                    }

                    expect(calculatedValue, `Value in interval [${fromTimestamp}, ${toTimestamp}) is incorrect` +
                        ` (when processed till ${processedTimestamp})`).to.be.equal(correctValue);
                }
            }
        }
    });
});
