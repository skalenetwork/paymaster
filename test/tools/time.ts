import { ethers } from "hardhat";

export const MS_PER_SEC = 1000;

export const skipTime = async (seconds: bigint | number) => {
    await ethers.provider.send("evm_increaseTime", [seconds]);
    await ethers.provider.send("evm_mine", []);
}

export const currentTime = async () => {
    const latestBlock = await ethers.provider.getBlock("latest");
    if (latestBlock) {
        return latestBlock.timestamp;
    }
    throw new Error("Can't fetch latest block");
}

export const skipTimeToSpecificDate = async (date: Date) => {
    const timestamp = await currentTime();
    const diffInSeconds = Math.round(date.getTime() / MS_PER_SEC) - timestamp;
    await skipTime(diffInSeconds);
}

export const skipTimeToDate = async (day: number, monthIndex: number) => {
    const timestamp = await currentTime();
    const now = new Date(timestamp * MS_PER_SEC);
    const targetTime = new Date(Date.UTC(now.getFullYear(), monthIndex, day));
    // False positive: targetTime is modified by setFullYear method
    // eslint-disable-next-line no-unmodified-loop-condition
    while (targetTime < now) {
        targetTime.setFullYear(now.getFullYear() + 1);
    }
    await skipTimeToSpecificDate(targetTime);
}

export const months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];

export const nextMonth = (timestamp: number | bigint) => {
    const timestampNumber = Number(timestamp) * MS_PER_SEC;
    const date = new Date(timestampNumber);
    let month = date.getMonth();
    let year = date.getFullYear();

    month += 1;

    if (month >= months.length) {
        month = 0;
        year += 1;
    }

    return new Date(Date.UTC(year, month, 1)).getTime() / MS_PER_SEC;
}

export const monthBegin = (timestamp: number | bigint) => {
    const timestampNumber = Number(timestamp) * MS_PER_SEC;
    const date = new Date(timestampNumber);
    const month = date.getMonth();
    const year = date.getFullYear();
    return new Date(Date.UTC(year, month, 1)).getTime() / MS_PER_SEC;
}

export const skipMonth = async () => {
    const timestamp = await currentTime();
    await skipTime(nextMonth(timestamp) - timestamp);
}
