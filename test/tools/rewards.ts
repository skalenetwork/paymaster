import { NetworkComposition } from "./network-composition";
import { Payments } from "./payments";
import { Withdrawals } from "./withdrawals";
import { MS_PER_SEC, monthBegin } from "./time";

export class Rewards {
    private payments = new Payments();
    private networkComposition = new NetworkComposition();
    private withdrawals = new Withdrawals();

    clone() {
        const rewards = new Rewards();
        rewards.payments = this.payments.clone();
        rewards.networkComposition = this.networkComposition.clone();
        rewards.withdrawals = this.withdrawals.clone();
        return rewards;
    }

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
        const until = monthBegin(timestamp);
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

            // if (income > 0) {
            //     console.log(`[${new Date(from * MS_PER_SEC).toISOString()}, ${new Date(to * MS_PER_SEC).toISOString()})`)
            //     console.log("Income:", income);
            //     const reward = income * nodeAmount / totalNodesAmount - withdrawn;
            //     console.log("Reward:", reward);
            //     console.log();
            // }

            if (totalNodesAmount > 0) {
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
        }

        return totalReward;
    }
}
