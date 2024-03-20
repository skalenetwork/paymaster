export class NetworkComposition {
    // Nodes structure
    // {
    //     validatorId: {
    //         "timestamp in increasing order": "amount of node"
    //     }
    // }
    private nodes = new Map<number, Map<number, number>>();

    clone() {
        const networkComposition = new NetworkComposition();
        for (const [validatorId, nodesHistory] of this.nodes.entries()) {
            networkComposition.nodes.set(validatorId, new Map(nodesHistory));
        }
        return networkComposition;
    }

    setNodesAmount(validatorId: number, nodesAmount: number, timestamp: number) {
        if(!this.nodes.has(validatorId)) {
            this.nodes.set(validatorId, new Map<number, number>([[0, 0]]));
        }

        const history = this.nodes.get(validatorId)!;

        if (timestamp < Array.from(history.keys())[history.size - 1]) {
            throw new Error("Can't change already set nodes amount");
        }

        history.set(timestamp, nodesAmount);
    }

    getChangePoints() {
        const points = new Set<number>();
        for (const history of this.nodes.values()) {
            for (const change of history.keys()) {
                points.add(change);
            }
        }
        return [...points].sort();
    }

    getNodesAmount(validatorId: number, timestamp: number) {
        if(!this.nodes.has(validatorId)) {
            throw new Error("Validator does not exist");
        }
        const changes = Array.from(this.nodes.get(validatorId)!.keys());
        let left = 0;
        let right = changes.length;
        while (left + 1 < right) {
            const middle = Math.floor((left + right) / 2);
            if (timestamp < changes[middle]) {
                right = middle;
            } else {
                left = middle;
            }
        }

        return this.nodes.get(validatorId)!.get(changes[left])!;
    }

    getTotalNodesAmount(timestamp: number) {
        let amount = 0;
        for (const validatorId of this.nodes.keys()) {
            amount += this.getNodesAmount(validatorId, timestamp);
        }
        return amount;
    }
}
