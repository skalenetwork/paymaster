// SPDX-License-Identifier: AGPL-3.0-only

/*
    PriorityQueue.sol - Paymaster
    Copyright (C) 2023-Present SKALE Labs
    @author Dmytro Stebaiev

    Paymaster is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Paymaster is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with Paymaster.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity ^0.8.19;

import {HeapLibrary} from "./Heap.sol";


error AccessToEmptyPriorityQueue();

library PriorityQueueLibrary {
    using HeapLibrary for HeapLibrary.Heap;

    type Value is uint256;

    struct PriorityQueue {
        HeapLibrary.Heap priorities;
        mapping (uint256 => Value[]) values;
    }

    function push(PriorityQueue storage queue, uint256 priority, Value value) public {
        if (queue.values[priority].length == 0) {
            queue.priorities.add(priority);
        }
        queue.values[priority].push(value);
    }

    function empty(PriorityQueue storage queue) public view returns (bool result) {
        return queue.priorities.size == 0;
    }

    function front(PriorityQueue storage queue) public view returns (Value value) {
        if (empty(queue)) {
            revert AccessToEmptyPriorityQueue();
        }
        uint256 priority = queue.priorities.get();
        return queue.values[priority][queue.values[priority].length - 1];
    }

    function pop(PriorityQueue storage queue) public {
        if (empty(queue)) {
            revert AccessToEmptyPriorityQueue();
        }
        uint256 priority = queue.priorities.get();
        uint256 length = queue.values[priority].length;
        queue.values[priority].pop();
        if (length == 1) {
            queue.priorities.pop();
        }
    }

    // This function is a workaround to allow slither to analyze the code
    // because current version fails on
    // PriorityQueueLibrary.Value.unwrap(value)
    // TODO: remove the function after slither fix the issue
    function unwrapValue(Value value) public pure returns (uint256 unwrappedValue) {
        return Value.unwrap(value);
    }

    // This function is a workaround to allow slither to analyze the code
    // because current version fails on
    // PriorityQueueLibrary.Value.wrap(value)
    // TODO: remove the function after slither fix the issue
    function wrapValue(uint256 unwrappedValue) public pure returns (Value wrappedValue) {
        return Value.wrap(unwrappedValue);
    }
}
