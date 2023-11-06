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
import {DateTimeUtils, Seconds, Timestamp} from "./DateTimeUtils.sol";


library TimelineLibrary {
    type ChangeId is uint256;
    type ValueId is bytes32;

    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using PriorityQueueLibrary for PriorityQueueLibrary.PriorityQueue;

    error CannotSetValueInThePast();
    error TimeIntervalIsNotProcessed();
    error TimeIntervalIsAlreadyProcessed();
    error IncorrectTimeInterval();
    error TimestampIsOutOfValues();

    struct Timeline {
        Timestamp processedUntil;

        ChangeId changesEnd;
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

    function getSum(Timeline storage timeline, Timestamp from, Timestamp to) internal view returns (uint256 sum) {
        _validateTimeInterval(timeline, from , to, true);
        if (timeline.valuesQueue.empty()) {
            return 0;
        }
        if (from < _getValueByIndex(timeline, 0).timestamp) {
            return getSum(timeline, _getValueByIndex(timeline, 0).timestamp, to);
        }

        sum = 0;
        uint256 queueLength = timeline.valuesQueue.length();
        Timestamp current = from;
        for (uint256 i = _getLowerBoundIndex(timeline, from); i < queueLength && current < to; ++i) {
            Timestamp next = to;
            if (i + 1 < queueLength) {
                Timestamp nextInterval = _getValueByIndex(timeline, i+1).timestamp;
                if (nextInterval < to) {
                    next = nextInterval;
                }
            }

            sum += _getValueByIndex(timeline, i+1).value * Seconds.unwrap(DateTimeUtils.duration(current, next));

            current = next;
        }
    }

    function add(Timeline storage timeline, Timestamp from, Timestamp to, uint256 value) internal {
        _validateTimeInterval(timeline, from , to, false);
        Seconds duration = DateTimeUtils.duration(from, to);
        uint256 rate = value / Seconds.unwrap(duration);
        _addChange(timeline, from, rate, 0);
        uint256 reminder = value % Seconds.unwrap(duration);
        if (reminder > 0) {
            _addChange(timeline, to.sub(Seconds.wrap(1)), reminder, 0);
        }
        _addChange(timeline, to, 0, rate + reminder);
    }

    // Private

    function _hasFutureChanges(Timeline storage timeline) private view returns (bool hasChanges) {
        return !timeline.changesQueue.empty();
    }

    function _getNextChange(Timeline storage timeline) private view returns (Change storage change) {
        ChangeId changeId = ChangeId.wrap(
            PriorityQueueLibrary.unwrapValue(
                timeline.changesQueue.front()
            )
        );
        return timeline.futureChanges[changeId];
    }

    function _addChange(
        Timeline storage timeline,
        Timestamp timestamp,
        uint256 addValue,
        uint256 subtractValue
    )
        private
    {
        ChangeId changeId = timeline.changesEnd;
        timeline.changesEnd = _getNextChangeId(changeId);
        timeline.futureChanges[changeId] = Change({
            timestamp: timestamp,
            add: addValue,
            subtract: subtractValue
        });
        timeline.changesQueue.push(
            Timestamp.unwrap(timestamp),
            PriorityQueueLibrary.wrapValue(ChangeId.unwrap(changeId))
        );
    }

    function _popNextChange(Timeline storage timeline) private {
        ChangeId changeId = ChangeId.wrap(
            PriorityQueueLibrary.unwrapValue(
                timeline.changesQueue.front()
            )
        );
        timeline.changesQueue.pop();
        delete timeline.futureChanges[changeId];
    }

    function _getCurrentValue(Timeline storage timeline) private view returns (Value storage value) {
        return timeline.values[ValueId.wrap(timeline.valuesQueue.back())];
    }

    function _getValueByIndex(Timeline storage timeline, uint256 index) private view returns (Value storage value) {
        return timeline.values[ValueId.wrap(timeline.valuesQueue.at(index))];
    }

    function _getLowerBoundIndex(Timeline storage timeline, Timestamp timestamp) private view returns (uint256 index) {
        if (timestamp < _getValueByIndex(timeline, 0).timestamp) {
            revert TimestampIsOutOfValues();
        }
        if (_getCurrentValue(timeline).timestamp <= timestamp) {
            return timeline.valuesQueue.length() - 1;
        }
        uint256 left = 0;
        uint256 right = timeline.valuesQueue.length() - 1;
        while (left + 1 < right) {
            uint256 middle = (left + right) / 2;
            if (_getValueByIndex(timeline, middle).timestamp <= timestamp) {
                left = middle;
            } else {
                right = middle;
            }
        }
        return left;
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

    function _getNextChangeId(ChangeId changeId) private pure returns (ChangeId nextChangeId) {
        nextChangeId = ChangeId.wrap(ChangeId.unwrap(changeId) + 1);
    }

    function _validateTimeInterval(
        Timeline storage timeline,
        Timestamp from,
        Timestamp to,
        bool processed) private view {
        if (to < from) {
            revert IncorrectTimeInterval();
        }
        if (processed) {
            if (timeline.processedUntil < to) {
                revert TimeIntervalIsNotProcessed();
            }
        } else {
            if (from < timeline.processedUntil) {
                revert TimeIntervalIsAlreadyProcessed();
            }
        }
    }
}
