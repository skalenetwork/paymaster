// SPDX-License-Identifier: AGPL-3.0-only

/*
    TypedPriorityQueue.sol - Paymaster
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

// cspell:words structs

import { TimelineLibrary } from "./../../Timeline.sol";
import { PriorityQueueLibrary } from "./../PriorityQueue.sol";


library TypedPriorityQueue {
    using PriorityQueueLibrary for PriorityQueueLibrary.Iterator;
    using PriorityQueueLibrary for PriorityQueueLibrary.PriorityQueue;

    struct ChangeIdPriorityQueue {
        PriorityQueueLibrary.PriorityQueue inner;
    }

    struct ChangeIdPriorityQueueIterator {
        PriorityQueueLibrary.Iterator inner;
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function push(
        ChangeIdPriorityQueue storage queue,
        uint256 priority,
        TimelineLibrary.ChangeId value
    )
        internal
    {
        queue.inner.push(
            priority,
            PriorityQueueLibrary.wrapValue(TimelineLibrary.unwrapChangeId(value))
        );
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function pop(ChangeIdPriorityQueue storage queue) internal {
        queue.inner.pop();
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function front(
        ChangeIdPriorityQueue storage queue
    )
        internal
        view
        returns (TimelineLibrary.ChangeId value)
    {
        return TimelineLibrary.wrapChangeId(PriorityQueueLibrary.unwrapValue(queue.inner.front()));
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function empty(ChangeIdPriorityQueue storage queue) internal view returns (bool result) {
        return queue.inner.empty();
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function getIterator(
        ChangeIdPriorityQueue storage queue
    )
        internal
        view
        returns (ChangeIdPriorityQueueIterator memory iterator)
    {
        return ChangeIdPriorityQueueIterator({
            inner: queue.inner.getIterator()
        });
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function step(
        ChangeIdPriorityQueueIterator memory iterator,
        ChangeIdPriorityQueue storage queue
    )
        internal
        view
    {
        iterator.inner.step(queue.inner);
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function hasNext(
        ChangeIdPriorityQueueIterator memory iterator
    )
        internal
        pure
        returns (bool exists)
    {
        return iterator.inner.hasNext();
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function getValue(
        ChangeIdPriorityQueueIterator memory iterator
    )
        internal
        pure
        returns (TimelineLibrary.ChangeId value)
    {
        return TimelineLibrary.wrapChangeId(
            PriorityQueueLibrary.unwrapValue(iterator.inner.getValue())
        );
    }
}
