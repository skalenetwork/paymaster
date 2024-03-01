import { nextMonth } from "./time";

interface Payment {
    from: number;
    to: number;
    value: bigint;
}

export class Payments {
    private paidUntil = new Map<string, number>();
    private payments = new Array<Payment>();
    private maxClaimedUntil = 0;

    clone() {
        const payments = new Payments();
        payments.paidUntil = new Map(this.paidUntil);
        payments.payments = [...this.payments];
        return payments;
    }

    updateClaimedUntil(until: number) {
        this.maxClaimedUntil = Math.max(this.maxClaimedUntil, until);
    }

    addSchain(schainHash: string, timestamp: number) {
        if (this.paidUntil.has(schainHash)) {
            throw new Error("Schain was already added");
        }
        this.paidUntil.set(schainHash, nextMonth(timestamp));
    }

    addPayment(schainHash: string, value: bigint, periodInMonths: number) {
        if (!this.paidUntil.has(schainHash)) {
            throw new Error("Schain does not exist");
        }
        let paidUntil = this.paidUntil.get(schainHash)!;
        for (let month = 0; month < periodInMonths; month += 1) {
            this.addPaymentConsideringRoundingTrick({
                from: paidUntil,
                to: nextMonth(paidUntil),
                value: value / BigInt(periodInMonths)
            });
            paidUntil = nextMonth(paidUntil);
        }
        this.paidUntil.set(schainHash, paidUntil);
    }

    getSum(fromTimestamp: number, toTimestamp: number) {
        let sum = 0n;
        for (const payment of this.payments) {
            if (! (toTimestamp <= payment.from || payment.to <= fromTimestamp) ) {
                // Intersection is not empty
                const left = Math.max(payment.from, fromTimestamp);
                const right = Math.min(payment.to, toTimestamp);

                sum += payment.value * BigInt(right - left) / BigInt(payment.to - payment.from);
            }
        }
        return sum;
    }

    private addPaymentConsideringRoundingTrick(payment: Payment) {
        if (payment.to <= this.maxClaimedUntil) {
            // Everything in the past
            this.payments.push(payment);
        } else if (this.maxClaimedUntil <= payment.from) {
            // Everything in the future
            const duration = BigInt(payment.to - payment.from);
            const rest = payment.value % duration;
            this.payments.push({...payment, value: payment.value - rest})
            if (rest > 0) {
                this.payments.push({
                    from: payment.to - 1,
                    to: payment.to,
                    value: rest
                });
            }
        } else {
            const pastPayment = {
                ...payment,
                to: this.maxClaimedUntil,
                value: payment.value * BigInt(this.maxClaimedUntil - payment.from) / BigInt(payment.to - payment.from)
            };
            const futurePayment = {
                ...payment,
                from: this.maxClaimedUntil,
                value: payment.value * BigInt(payment.to - this.maxClaimedUntil) / BigInt(payment.to - payment.from)
            };
            this.addPaymentConsideringRoundingTrick(pastPayment);
            this.addPaymentConsideringRoundingTrick(futurePayment);
        }

    }
}
