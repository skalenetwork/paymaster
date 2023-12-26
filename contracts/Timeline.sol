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

import {TypedDoubleEndedQueue} from "./structs/typed/TypedDoubleEndedQueue.sol";
import {TypedPriorityQueue} from "./structs/typed/TypedPriorityQueue.sol";
import {DateTimeUtils, Seconds, Timestamp} from "./DateTimeUtils.sol";


library TimelineLibrary {
    type ChangeId is uint256;
    type ValueId is bytes32;

    using TypedDoubleEndedQueue for TypedDoubleEndedQueue.ValueIdDeque;
    using TypedPriorityQueue for TypedPriorityQueue.ChangeIdPriorityQueue;
    using TypedPriorityQueue for TypedPriorityQueue.ChangeIdPriorityQueueIterator;

    error CannotSetValueInThePast();
    error TimeIntervalIsNotProcessed();
    error TimeIntervalIsAlreadyProcessed();
    error IncorrectTimeInterval();
    error TimestampIsOutOfValues();
    error ClearUnprocessed();

    struct Timeline {
        Timestamp processedUntil;

        ChangeId changesEnd;
        mapping (ChangeId => Change) futureChanges;
        TypedPriorityQueue.ChangeIdPriorityQueue changesQueue;

        ValueId valuesEnd;
        mapping (ValueId => Value) values;
        TypedDoubleEndedQueue.ValueIdDeque valuesQueue;
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

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function process(Timeline storage timeline, Timestamp until) internal {
        if (until <= timeline.processedUntil) {
            return;
        }

        while (_hasFutureChanges(timeline)) {
            Change memory nextChange = _getNextChange(timeline);
            if (nextChange.timestamp < until) {
                if (timeline.valuesQueue.empty()) {
                    _createValue(timeline, Value({
                        timestamp: nextChange.timestamp,
                        value: nextChange.add - nextChange.subtract
                    }));
                } else {
                    Value storage currentValue = _getCurrentValue(timeline);
                    if (currentValue.timestamp == nextChange.timestamp) {
                        currentValue.value = currentValue.value + nextChange.add - nextChange.subtract;
                    } else {
                        _createValue(timeline, Value({
                            timestamp: nextChange.timestamp,
                            value: currentValue.value + nextChange.add - nextChange.subtract
                        }));
                    }
                }
                _popNextChange(timeline);
            } else {
                break;
            }
        }

        timeline.processedUntil = until;
    }

    // Library internal functions should not have leading underscore
    // solhint-disable private-vars-leading-underscore

    // False positive detection of the dead code. The function is used in `Paymaster::_loadFromTimeline` function
    // slither-disable-next-line dead-code
    function getSum(Timeline storage timeline, Timestamp from, Timestamp to) internal view returns (uint256 sum) {
    // solhint-enable private-vars-leading-underscore

        if (to < from) {
            revert IncorrectTimeInterval();
        }
        Timestamp processedUntil = timeline.processedUntil;
        if (processedUntil < to) {
            if (processedUntil < from) {
                return _getSumInUnprocessedSegment(timeline, to) - _getSumInUnprocessedSegment(timeline, from);
            } else {
                return _getSumInProcessedSegment(timeline, from, timeline.processedUntil) +
                    _getSumInUnprocessedSegment(timeline, to);
            }
        }

        return _getSumInProcessedSegment(timeline, from, to);
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
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

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function clear(Timeline storage timeline, Timestamp before) internal {
        if (timeline.processedUntil < before) {
            revert ClearUnprocessed();
        }

        for (uint256 valuesAmount = timeline.valuesQueue.length(); valuesAmount > 0; --valuesAmount) {
            if (before <= _getValueByIndex(timeline, 0).timestamp) {
                break;
            }
            ValueId valueId = timeline.valuesQueue.popFront();
            _deleteValue(timeline.values[valueId]);
        }
    }

    // This function is a workaround to allow slither to analyze the code
    // because current version fails on
    // TimelineLibrary.ValueId.unwrap(value)
    // TODO: remove the function after slither fix the issue

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function unwrapValueId(ValueId value) internal pure returns (bytes32 unwrappedValue) {
        return ValueId.unwrap(value);
    }

    // This function is a workaround to allow slither to analyze the code
    // because current version fails on
    // TimelineLibrary.ValueId.wrap(value)
    // TODO: remove the function after slither fix the issue

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function wrapValueId(bytes32 unwrappedValue) internal pure returns (ValueId wrappedValue) {
        return ValueId.wrap(unwrappedValue);
    }

    // This function is a workaround to allow slither to analyze the code
    // because current version fails on
    // TimelineLibrary.ChangeId.unwrap(value)
    // TODO: remove the function after slither fix the issue

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function unwrapChangeId(ChangeId value) internal pure returns (uint256 unwrappedValue) {
        return ChangeId.unwrap(value);
    }

    // This function is a workaround to allow slither to analyze the code
    // because current version fails on
    // TimelineLibrary.ChangeId.wrap(value)
    // TODO: remove the function after slither fix the issue

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function wrapChangeId(uint256 unwrappedValue) internal pure returns (ChangeId wrappedValue) {
        return ChangeId.wrap(unwrappedValue);
    }

    // Private

    function _getSumInProcessedSegment(
        Timeline storage timeline,
        Timestamp from,
        Timestamp to
    )
        private
        view
        returns (uint256 sum)
    {
        _validateTimeInterval(timeline, from , to, true);
        if (timeline.valuesQueue.empty()) {
            return 0;
        }
        Timestamp firstValueTimestamp = _getValueByIndex(timeline, 0).timestamp;
        if (to <= firstValueTimestamp) {
            return 0;
        }
        if (from < firstValueTimestamp) {
            return _getSumInProcessedSegment(timeline, firstValueTimestamp, to);
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

            sum += _getValueByIndex(timeline, i).value * Seconds.unwrap(DateTimeUtils.duration(current, next));

            current = next;
        }
    }

    function _getSumInUnprocessedSegment(Timeline storage timeline, Timestamp to) private view returns (uint256 sum) {
        Value memory current;
        if (timeline.valuesQueue.empty()) {
            current = Value({
                timestamp: Timestamp.wrap(0),
                value: 0
            });
        } else {
            current = _getCurrentValue(timeline);
        }

        if (!timeline.changesQueue.empty()) {
            for (
                TypedPriorityQueue.ChangeIdPriorityQueueIterator memory changeIdsIterator =
                    timeline.changesQueue.getIterator();
                changeIdsIterator.hasNext();
                changeIdsIterator.step(timeline.changesQueue)
            ) {
                Change storage change = timeline.futureChanges[changeIdsIterator.getValue()];
                Value memory nextValue = Value({
                    timestamp: change.timestamp,
                    value: current.value + change.add - change.subtract
                });
                if (to < nextValue.timestamp) {
                    break;
                }

                sum += current.value * Seconds.unwrap(DateTimeUtils.duration(current.timestamp, nextValue.timestamp));
                current = nextValue;
            }
        }

        sum += current.value * Seconds.unwrap(DateTimeUtils.duration(current.timestamp, to));
    }

    function _hasFutureChanges(Timeline storage timeline) private view returns (bool hasChanges) {
        return !timeline.changesQueue.empty();
    }

    function _getNextChange(Timeline storage timeline) private view returns (Change storage change) {
        ChangeId changeId = timeline.changesQueue.front();
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
            changeId
        );
    }

    function _popNextChange(Timeline storage timeline) private {
        ChangeId changeId = timeline.changesQueue.front();
        timeline.changesQueue.pop();
        delete timeline.futureChanges[changeId];
    }

    function _deleteValue(Value storage value) private {
        value.timestamp = Timestamp.wrap(0);
        delete value.value;
    }

    function _getCurrentValue(Timeline storage timeline) private view returns (Value storage value) {
        return timeline.values[timeline.valuesQueue.back()];
    }

    function _getValueByIndex(Timeline storage timeline, uint256 index) private view returns (Value storage value) {
        return timeline.values[timeline.valuesQueue.at(index)];
    }

    // False positive detection of the dead code. The function is used in `getSum` function
    // slither-disable-next-line dead-code
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
        timeline.valuesQueue.pushBack(valuesEnd);
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
