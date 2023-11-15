// SPDX-License-Identifier: AGPL-3.0-only

/*
    Sequence.sol - Paymaster
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

import {Timestamp} from "./DateTimeUtils.sol";


library SequenceLibrary {
    type NodeId is uint256;

    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    uint256 private constant _EMPTY_ITERATOR_INDEX = type(uint256).max;

    struct Node {
        Timestamp timestamp;
        uint256 value;
    }

    struct Sequence {
        mapping (NodeId => Node) nodes;
        DoubleEndedQueue.Bytes32Deque ids;
    }

    struct Iterator {
        uint256 idIndex;
        uint256 sequenceSize;
        Timestamp nextTimestamp;
    }

    function getIterator(
        Sequence storage sequence,
        Timestamp timestamp
    )
        internal
        view
        returns (Iterator memory iterator)
    {
        if (sequence.ids.empty()) {
            return Iterator({
                idIndex: _EMPTY_ITERATOR_INDEX,
                sequenceSize: 0,
                nextTimestamp: Timestamp.wrap(0)
            });
        }
        uint256 sequenceSize = sequence.ids.length();
        Timestamp earliest = _getNodeByIndex(sequence, 0).timestamp;
        if (timestamp < earliest) {
            return Iterator({
                idIndex: _EMPTY_ITERATOR_INDEX,
                sequenceSize: sequenceSize,
                nextTimestamp: earliest
            });
        }
        uint256 left = 0;
        uint256 right = sequenceSize;
        while (left + 1 < right) {
            uint256 middle = (left + right) / 2;
            if (timestamp < _getNodeByIndex(sequence, middle).timestamp) {
                right = middle;
            } else {
                left = middle;
            }
        }

        Timestamp nextTimestamp = Timestamp.wrap(type(uint256).max);
        if (left + 1 < sequenceSize) {
            nextTimestamp = _getNodeByIndex(sequence, left + 1).timestamp;
        }

        return Iterator({
            idIndex: left,
            sequenceSize: sequenceSize,
            nextTimestamp: nextTimestamp
        });
    }

    function getValue(Sequence storage sequence, Iterator memory iterator) internal view returns (uint256 value) {
        if(iterator.idIndex == _EMPTY_ITERATOR_INDEX) {
            return 0;
        }
        if(iterator.idIndex >= iterator.sequenceSize) {
            return _getNodeByIndex(sequence, iterator.sequenceSize - 1).value;
        }
        return _getNodeByIndex(sequence, iterator.idIndex).value;
    }

    function step(Iterator memory iterator) internal pure returns (bool success) {
        success = hasNext(iterator);
        iterator.idIndex += 1;
    }

    function hasNext(Iterator memory iterator) internal pure returns (bool exist) {
        return iterator.idIndex + 1 < iterator.sequenceSize;
    }

    function clear(Sequence storage sequence) internal {
        uint256 length = sequence.ids.length();
        for (uint256 i = 0; i < length; ++i) {
            Node storage node = _getNodeByIndex(sequence, i);
            node.timestamp = Timestamp.wrap(0); // similar to operator delete
            delete node.value;
        }
        sequence.ids.clear();
    }

    // Private

    function _getNode(Sequence storage sequence, NodeId nodeId) private view returns (Node storage node) {
        return sequence.nodes[nodeId];
    }

    function _getNodeByIndex(Sequence storage sequence, uint256 index) private view returns (Node storage node) {
        return _getNode(sequence, _getNodeId(sequence, index));
    }

    function _getNodeId(Sequence storage sequence, uint256 index) private view returns (NodeId nodeId) {
        nodeId = NodeId.wrap(uint256(sequence.ids.at(index)));
    }
}
