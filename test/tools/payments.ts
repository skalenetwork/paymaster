import { nextMonth } from "./time";

interface Payment {
    from: number;
    to: number;
    value: bigint;
}

export class Payments {
    private paidUntil = new Map<string, number>();
    private payments = new Array<Payment>();

    clone() {
        const payments = new Payments();
        payments.paidUntil = new Map(this.paidUntil);
        payments.payments = [...this.payments];
        return payments;
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
            this.payments.push({
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

                // console.log(`+ ${payment.value} * (${right} - ${left}) / (${payment.to} - ${payment.from}) = ${payment.value * BigInt(right - left) / BigInt(payment.to - payment.from)}`);
            }
        }
        return sum;
    }
}
