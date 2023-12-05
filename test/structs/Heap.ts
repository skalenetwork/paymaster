import { HeapTester } from "../../typechain-types";
import { ethers } from "hardhat";
import { expect } from "chai";
import {
    loadFixture
} from "@nomicfoundation/hardhat-toolbox/network-helpers";


describe("Heap", () => {
    const deployHeapFixture = async () => await ethers.deployContract("HeapTester")

    // It's initialized in beforeEach
    // eslint-disable-next-line init-declarations
    let heap: HeapTester;

    beforeEach("when heap is deployed", async () => {
        heap = await loadFixture(deployHeapFixture);
    });

    it("should return elements in ascending order", async () => {
        const amount = 10;
        const array = [...Array(amount).keys()].reverse();

        for (const element of array) {
            await heap.add(element);
        }

        const sortedArray = array.sort();
        for (const element of sortedArray) {
            expect(await heap.get()).be.equal(element);
            await heap.pop();
        }
    });
  });
