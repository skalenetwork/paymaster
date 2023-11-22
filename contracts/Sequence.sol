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

import {Timestamp} from "./DateTimeUtils.sol";
import {TypedDoubleEndedQueue} from "./structs/TypedDoubleEndedQueue.sol";


library SequenceLibrary {
    type NodeId is uint256;

    using TypedDoubleEndedQueue for TypedDoubleEndedQueue.NodeIdDeque;

    error CannotAddToThePast();

    uint256 private constant _EMPTY_ITERATOR_INDEX = type(uint256).max;

    struct Node {
        Timestamp timestamp;
        uint256 value;
    }

    struct Sequence {
        mapping (NodeId => Node) nodes;
        TypedDoubleEndedQueue.NodeIdDeque ids;
        NodeId freeNodeId;
    }

    struct Iterator {
        uint256 idIndex;
        uint256 sequenceSize;
        Timestamp nextTimestamp;
    }

    function add(Sequence storage sequence, Timestamp timestamp, uint256 value) public {
        uint256 length = sequence.ids.length();
        if (length > 0) {
            if (timestamp <= _getNodeByIndex(sequence, length - 1).timestamp) {
                revert CannotAddToThePast();
            }
        }
        NodeId nodeId = _assignId(sequence);
        sequence.nodes[nodeId] = Node({
            timestamp: timestamp,
            value: value
        });
        sequence.ids.pushBack(nodeId);
    }

    function getIterator(
        Sequence storage sequence,
        Timestamp timestamp
    )
        public
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

    function getValue(Sequence storage sequence, Iterator memory iterator) public view returns (uint256 value) {
        if(iterator.idIndex == _EMPTY_ITERATOR_INDEX) {
            return 0;
        }
        if(iterator.idIndex >= iterator.sequenceSize) {
            return _getNodeByIndex(sequence, iterator.sequenceSize - 1).value;
        }
        return _getNodeByIndex(sequence, iterator.idIndex).value;
    }

    function getLastValue(Sequence storage sequence) public view returns (uint256 lastValue) {
        uint256 length = sequence.ids.length();
        if (length > 0) {
            return _getNodeByIndex(sequence, length - 1).value;
        } else {
            return 0;
        }
    }

    function step(Iterator memory iterator) public pure returns (bool success) {
        success = hasNext(iterator);
        iterator.idIndex += 1;
    }

    function hasNext(Iterator memory iterator) public pure returns (bool exist) {
        return iterator.idIndex + 1 < iterator.sequenceSize;
    }

    function clear(Sequence storage sequence) public {
        uint256 length = sequence.ids.length();
        for (uint256 i = 0; i < length; ++i) {
            Node storage node = _getNodeByIndex(sequence, i);
            _deleteNode(node);
        }
        sequence.ids.clear();
        sequence.freeNodeId = NodeId.wrap(0);
    }

    function clear(Sequence storage sequence, Timestamp before) public {
        // It's important to store the most right value
        for (uint256 nodesAmount = sequence.ids.length(); nodesAmount > 1; --nodesAmount) {
            if (before <= _getNodeByIndex(sequence, 0).timestamp) {
                break;
            }
            NodeId nodeId = sequence.ids.popFront();
            _deleteNode(sequence.nodes[nodeId]);
        }
    }

    // This function is a workaround to allow slither to analyze the code
    // because current version fails on
    // SequenceLibrary.NodeId.unwrap(value)
    // TODO: remove the function after slither fix the issue
    function unwrapNodeId(NodeId value) public pure returns (uint256 unwrappedValue) {
        return NodeId.unwrap(value);
    }

    // This function is a workaround to allow slither to analyze the code
    // because current version fails on
    // SequenceLibrary.NodeId.wrap(value)
    // TODO: remove the function after slither fix the issue
    function wrapNodeId(uint256 unwrappedValue) public pure returns (NodeId wrappedValue) {
        return NodeId.wrap(unwrappedValue);
    }

    // Private

    function _assignId(Sequence storage sequence) private returns (NodeId newNodeId) {
        newNodeId = sequence.freeNodeId;
        sequence.freeNodeId = NodeId.wrap(NodeId.unwrap(newNodeId) + 1);
    }

    function _deleteNode(Node storage node) private {
        node.timestamp = Timestamp.wrap(0); // similar to operator delete
        delete node.value;
    }

    function _getNode(Sequence storage sequence, NodeId nodeId) private view returns (Node storage node) {
        return sequence.nodes[nodeId];
    }

    function _getNodeByIndex(Sequence storage sequence, uint256 index) private view returns (Node storage node) {
        return _getNode(sequence, sequence.ids.at(index));
    }
}
