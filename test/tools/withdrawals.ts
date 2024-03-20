interface Withdrawal {
    from: number,
    to: number,
    value: bigint
}


export class Withdrawals {
    private withdrawals = new Map<number, Array<Withdrawal>>();

    clone () {
        const withdrawals = new Withdrawals();
        for (const [validatorId, claims] of this.withdrawals) {
            withdrawals.withdrawals.set(validatorId, [...claims]);
        }
        return withdrawals;
    }

    addWithdrawal(validatorId: number, withdrawal: Withdrawal) {
        if (!this.withdrawals.has(validatorId)) {
            this.withdrawals.set(validatorId, new Array<Withdrawal>());
        }
        this.withdrawals.get(validatorId)!.push(withdrawal);
    }

    getWithdrawal(validatorId: number, fromTimestamp: number, toTimestamp: number): bigint {
        let totalWithdrawal = 0n;
        if (this.withdrawals.has(validatorId)) {
            for (const withdrawal of this.withdrawals.get(validatorId)!) {
                if (! (toTimestamp <= withdrawal.from || withdrawal.to <= fromTimestamp) ) {
                    // Intersection is not empty
                    const left = Math.max(withdrawal.from, fromTimestamp);
                    const right = Math.min(withdrawal.to, toTimestamp);

                    totalWithdrawal += withdrawal.value * BigInt(right - left) / BigInt(withdrawal.to - withdrawal.from);
                }
            }
        }
        return totalWithdrawal;
    }
}
