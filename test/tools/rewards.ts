import { NetworkComposition } from "./network-composition";
import { Payments } from "./payments";
import { Withdrawals } from "./withdrawals";

export class Rewards {
    private payments = new Payments();
    private networkComposition = new NetworkComposition();
    private withdrawals = new Withdrawals();

    // Payments

    addSchain(schainHash: string, timestamp: number) {
        this.payments.addSchain(schainHash, timestamp);
    }

    addPayment(schainHash: string, value: bigint, periodInMonths: number) {
        this.payments.addPayment(schainHash, value, periodInMonths);
    }

    // Composition

    setNodesAmount(validatorId: number, nodesAmount: number, timestamp: number) {
        this.networkComposition.setNodesAmount(validatorId, nodesAmount, timestamp);
    }

    // Rewards

    calculateRewards(validatorId: number, timestamp: number) {
        throw new Error("calculateRewards is not implemented");
    }
}
