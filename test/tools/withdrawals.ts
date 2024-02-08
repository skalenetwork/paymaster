interface Withdrawal {
    from: number,
    to: number,
    value: bigint
}


export class Withdrawals {
    private withdrawals = new Map<number, Map<number, Map<number, bigint>>>();

    addWithdrawal(validatorId: number, withdrawal: Withdrawal) {
        if (this.withdrawals.has(validatorId)) {
            if (this.withdrawals.get(validatorId)!.has(withdrawal.from)) {
                if (this.withdrawals.get(validatorId)!.get(withdrawal.from)!.has(withdrawal.to)) {
                    this.withdrawals.get(validatorId)!.get(withdrawal.from)!.set(
                        withdrawal.to,
                        this.withdrawals.get(validatorId)!.get(withdrawal.from)!.get(withdrawal.to)! + withdrawal.value
                    );
                } else {
                    this.withdrawals.get(validatorId)!.get(withdrawal.from)!.set(withdrawal.to, withdrawal.value);
                }
            } else {
                this.withdrawals.get(validatorId)!.set(withdrawal.from, new Map<number, bigint>([
                    [withdrawal.to, withdrawal.value]
                ]))
            }
        } else {
            this.withdrawals.set(
                validatorId,
                new Map<number, Map<number, bigint>>([
                    [withdrawal.from, new Map<number, bigint>([
                        [withdrawal.to, withdrawal.value]
                    ])]
                ]))
        }
    }

    getWithdrawal(validatorId: number, fromTimestamp: number, toTimestamp: number): bigint {
        throw new Error("getWithdrawal is not implemented");
    }
}
