// SPDX-License-Identifier: AGPL-3.0-only

/*
    Timeline.sol - Paymaster
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

// cspell:words deque structs

import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

import {PriorityQueueLibrary} from "./PriorityQueue.sol";
import {Timestamp} from "./DateTimeUtils.sol";


library TimelineLibrary {
    type ChangeId is uint256;
    type ValueId is bytes32;

    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using PriorityQueueLibrary for PriorityQueueLibrary.PriorityQueue;

    error CannotSetValueInThePast();

    struct Timeline {
        Timestamp processedUntil;

        mapping (ChangeId => Change) futureChanges;
        PriorityQueueLibrary.PriorityQueue changesQueue;

        ValueId valuesEnd;
        mapping (ValueId => Value) values;
        DoubleEndedQueue.Bytes32Deque valuesQueue;
    }
    struct Change {
        Timestamp timestamp;
        uint256 add;
        uint256 subtract;
    }
    struct Value {
        Timestamp timestamp;
        uint256 value;
    }

    function process(Timeline storage timeline, Timestamp until) internal {
        if (until <= timeline.processedUntil) {
            return;
        }

        while (_hasFutureChanges(timeline)) {
            Change memory nextChange = _getNextChange(timeline);
            if (nextChange.timestamp < until) {
                Value storage currentValue = _getCurrentValue(timeline);
                if (currentValue.timestamp == nextChange.timestamp) {
                    currentValue.value += nextChange.add - nextChange.subtract;
                } else {
                    _createValue(timeline, Value({
                        timestamp: nextChange.timestamp,
                        value: currentValue.value += nextChange.add - nextChange.subtract
                    }));
                }
                _popNextChange(timeline);
            } else {
                break;
            }
        }

        timeline.processedUntil = until;
    }

    // Private

    function _hasFutureChanges(Timeline storage timeline) private view returns (bool hasChanges) {
        return !timeline.changesQueue.empty();
    }

    function _getNextChange(Timeline storage timeline) private view returns (Change storage change) {
        ChangeId changeId = ChangeId.wrap(
            PriorityQueueLibrary.Value.unwrap(
                timeline.changesQueue.front()
            )
        );
        return timeline.futureChanges[changeId];
    }

    function _popNextChange(Timeline storage timeline) private {
        ChangeId changeId = ChangeId.wrap(
            PriorityQueueLibrary.Value.unwrap(
                timeline.changesQueue.front()
            )
        );
        timeline.changesQueue.pop();
        delete timeline.futureChanges[changeId];
    }

    function _getCurrentValue(Timeline storage timeline) private view returns (Value storage value) {
        return timeline.values[ValueId.wrap(timeline.valuesQueue.back())];
    }

    function _createValue(Timeline storage timeline, Value memory value) private {
        if(!timeline.valuesQueue.empty() && value.timestamp <= _getCurrentValue(timeline).timestamp) {
            revert CannotSetValueInThePast();
        }
        ValueId valuesEnd = timeline.valuesEnd;
        timeline.values[valuesEnd] = value;
        timeline.valuesQueue.pushBack(ValueId.unwrap(valuesEnd));
        timeline.valuesEnd = _getNextValueId(valuesEnd);
    }

    function _getNextValueId(ValueId valueId) private pure returns (ValueId nextValueId) {
        nextValueId = ValueId.wrap(
            bytes32(
                uint256(ValueId.unwrap(valueId)) + 1
            )
        );
    }
}
