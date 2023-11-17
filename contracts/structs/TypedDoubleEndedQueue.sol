// SPDX-License-Identifier: AGPL-3.0-only

/*
    TypedDoubleEndedQueue.sol - Paymaster
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

pragma solidity ^0.8.20;

// cspell:words deque structs

import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

import {SequenceLibrary} from "../Sequence.sol";
import {TimelineLibrary} from "../Timeline.sol";


library TypedDoubleEndedQueue {

    struct NodeIdDeque {
        DoubleEndedQueue.Bytes32Deque inner;
    }

    struct ValueIdDeque {
        DoubleEndedQueue.Bytes32Deque inner;
    }

    // NodeIdDeque - internal

    /**
     * @dev Inserts an item at the end of the queue.
     *
     * Reverts with {QueueFull} if the queue is full.
     */
    function pushBack(NodeIdDeque storage deque, SequenceLibrary.NodeId value) internal {
        DoubleEndedQueue.pushBack(deque.inner, bytes32(SequenceLibrary.unwrapNodeId(value)));
    }

    /**
     * @dev Removes the item at the beginning of the queue and returns it.
     *
     * Reverts with `QueueEmpty` if the queue is empty.
     */
    function popFront(NodeIdDeque storage deque) internal returns (SequenceLibrary.NodeId value) {
        return SequenceLibrary.wrapNodeId(uint256(DoubleEndedQueue.popFront(deque.inner)));
    }

    /**
     * @dev Resets the queue back to being empty.
     *
     * NOTE: The current items are left behind in storage. This does not affect the functioning of the queue, but misses
     * out on potential gas refunds.
     */
    function clear(NodeIdDeque storage deque) internal {
        DoubleEndedQueue.clear(deque.inner);
    }

    // ValueIdDeque - internal

    /**
     * @dev Inserts an item at the end of the queue.
     *
     * Reverts with {QueueFull} if the queue is full.
     */
    function pushBack(ValueIdDeque storage deque, TimelineLibrary.ValueId valueId) internal {
        DoubleEndedQueue.pushBack(deque.inner, TimelineLibrary.unwrapValueId(valueId));
    }

    /**
     * @dev Removes the item at the beginning of the queue and returns it.
     *
     * Reverts with `QueueEmpty` if the queue is empty.
     */
    function popFront(ValueIdDeque storage deque) internal returns (TimelineLibrary.ValueId valueId) {
        return TimelineLibrary.wrapValueId(DoubleEndedQueue.popFront(deque.inner));
    }

    // NodeIdDeque - internal view

    /**
     * @dev Return the item at a position in the queue given by `index`, with the first item at 0 and last item at
     * `length(deque) - 1`.
     *
     * Reverts with `QueueOutOfBounds` if the index is out of bounds.
     */
    function at(NodeIdDeque storage deque, uint256 index) internal view returns (SequenceLibrary.NodeId value) {
        return SequenceLibrary.wrapNodeId(
            uint256(
                DoubleEndedQueue.at(deque.inner, index)
            )
        );
    }

    /**
     * @dev Returns the number of items in the queue.
     */
    function length(NodeIdDeque storage deque) internal view returns (uint256 lengthValue) {
        return DoubleEndedQueue.length(deque.inner);
    }

    /**
     * @dev Returns true if the queue is empty.
     */
    function empty(NodeIdDeque storage deque) internal view returns (bool isEmpty) {
        return DoubleEndedQueue.empty(deque.inner);
    }

    // ValueIdDeque - internal view

    /**
     * @dev Returns true if the queue is empty.
     */
    function empty(ValueIdDeque storage deque) internal view returns (bool isEmpty) {
        return DoubleEndedQueue.empty(deque.inner);
    }

    /**
     * @dev Returns the number of items in the queue.
     */
    function length(ValueIdDeque storage deque) internal view returns (uint256 lengthValue) {
        return DoubleEndedQueue.length(deque.inner);
    }

    /**
     * @dev Returns the item at the end of the queue.
     *
     * Reverts with `QueueEmpty` if the queue is empty.
     */
    function back(ValueIdDeque storage deque) internal view returns (TimelineLibrary.ValueId valueId) {
        return TimelineLibrary.wrapValueId(DoubleEndedQueue.back(deque.inner));
    }

    /**
     * @dev Return the item at a position in the queue given by `index`, with the first item at 0 and last item at
     * `length(deque) - 1`.
     *
     * Reverts with `QueueOutOfBounds` if the index is out of bounds.
     */
    function at(ValueIdDeque storage deque, uint256 index) internal view returns (TimelineLibrary.ValueId valueId) {
        return TimelineLibrary.wrapValueId(
                DoubleEndedQueue.at(deque.inner, index)
        );
    }
}
