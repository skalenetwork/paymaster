import { NetworkComposition } from "./network-composition";
import { Payments } from "./payments";
import { previousMonth } from "./time";
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

    claim(validatorId: number, timestamp: number) {
        const changePoints = this.networkComposition.getChangePoints();
        const until = previousMonth(timestamp);
        let totalReward = 0n;
        for (let index = 0; index < changePoints.length && changePoints[index] < until; index += 1) {
            const from = changePoints[index];
            let to = from;
            if (index + 1 >= changePoints.length) {
                to = until;
            } else {
                to = Math.min(until, changePoints[index + 1]);
            }

            const income = this.payments.getSum(from, to);
            const nodeAmount = BigInt(this.networkComposition.getNodesAmount(validatorId, from));
            const totalNodesAmount = BigInt(this.networkComposition.getTotalNodesAmount(from));
            const withdrawn = this.withdrawals.getWithdrawal(validatorId, from, to);

            const reward = income * nodeAmount / totalNodesAmount - withdrawn;
            totalReward += reward;

            this.withdrawals.addWithdrawal(
                validatorId,
                {
                    from,
                    to,
                    value: reward
                }
            );
        }

        return totalReward;
    }
}
