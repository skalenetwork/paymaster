export class Payments {
    addSchain(schainHash: string, timestamp: number) {
        throw new Error("addSchain is not implemented");
    }

    addPayment(schainHash: string, value: bigint, periodInMonths: number) {
        throw new Error("addPayment is not implemented");
    }

    getSum(fromTimestamp: number, toTimestamp: number) {
        throw new Error("getTotalRewards is not implemented");
    }
}
