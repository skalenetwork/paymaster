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
    using HeapLibrary for HeapLibrary.Iterator;

    type Value is uint256;

    struct PriorityQueue {
        HeapLibrary.Heap priorities;
        mapping (uint256 => Value[]) values;
    }

    struct Iterator {
        HeapLibrary.Iterator priorityIterator;
        Value value;
        uint256 valueIndex;
        uint256 valuesLength;
    }

    event PriorityQueueValueAdded(
        uint256 priority,
        Value value
    );

    event PriorityQueueValueRemoved(
        uint256 priority,
        Value value
    );

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function push(PriorityQueue storage queue, uint256 priority, Value value) internal {
        if (queue.values[priority].length == 0) {
            queue.priorities.add(priority);
        }
        queue.values[priority].push(value);
        emit PriorityQueueValueAdded(priority, value);
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function empty(PriorityQueue storage queue) internal view returns (bool result) {
        return queue.priorities.size() == 0;
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function front(PriorityQueue storage queue) internal view returns (Value value) {
        if (empty(queue)) {
            revert AccessToEmptyPriorityQueue();
        }
        uint256 priority = queue.priorities.get();
        return queue.values[priority][queue.values[priority].length - 1];
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function pop(PriorityQueue storage queue) internal {
        if (empty(queue)) {
            revert AccessToEmptyPriorityQueue();
        }
        uint256 priority = queue.priorities.get();
        uint256 length = queue.values[priority].length;
        emit PriorityQueueValueRemoved(priority, queue.values[priority][length - 1]);
        queue.values[priority].pop();
        if (length == 1) {
            queue.priorities.pop();
        }
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function getIterator(PriorityQueue storage queue) internal view returns (Iterator memory iterator) {
        if (empty(queue)) {
            revert AccessToEmptyPriorityQueue();
        }
        HeapLibrary.Iterator memory priorityIterator = queue.priorities.getIterator();
        return Iterator({
            priorityIterator: priorityIterator,
            value: queue.values[priorityIterator.getValue()][0],
            valueIndex: 0,
            valuesLength: queue.values[priorityIterator.getValue()].length
        });
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function hasNext(Iterator memory iterator) internal pure returns (bool exists) {
        if (iterator.valueIndex + 1 < iterator.valuesLength) {
            return true;
        } else {
            return iterator.priorityIterator.hasNext();
        }
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function step(Iterator memory iterator, PriorityQueue storage queue) internal view {
        if (iterator.valueIndex + 1 < iterator.valuesLength) {
            ++iterator.valueIndex;
            iterator.value = queue.values[iterator.priorityIterator.getValue()][iterator.valueIndex];
        } else {
            iterator.priorityIterator.step();
            iterator.valueIndex = 0;
            iterator.valuesLength = queue.values[iterator.priorityIterator.getValue()].length;
            iterator.value = queue.values[iterator.priorityIterator.getValue()][iterator.valueIndex];
        }
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function getValue(Iterator memory iterator) internal pure returns (Value value) {
        return iterator.value;
    }

    // This function is a workaround to allow slither to analyze the code
    // because current version fails on
    // PriorityQueueLibrary.Value.unwrap(value)
    // TODO: remove the function after slither fix the issue

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function unwrapValue(Value value) internal pure returns (uint256 unwrappedValue) {
        return Value.unwrap(value);
    }

    // This function is a workaround to allow slither to analyze the code
    // because current version fails on
    // PriorityQueueLibrary.Value.wrap(value)
    // TODO: remove the function after slither fix the issue

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function wrapValue(uint256 unwrappedValue) internal pure returns (Value wrappedValue) {
        return Value.wrap(unwrappedValue);
    }
}
