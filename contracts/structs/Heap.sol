// SPDX-License-Identifier: AGPL-3.0-only

/*
    Heap.sol - Paymaster
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


error RootDoesNotHaveParent();
error AccessToEmptyHeap();

library HeapLibrary {
    type NodeId is uint256;

    NodeId private constant _ROOT = NodeId.wrap(1);

    struct Heap {
        uint256 size;
        uint256[] values;
    }

    function add(Heap storage heap, uint256 value) internal {
        if(heap.values.length == 0) {
            heap.values.push(0);
        }
        heap.values.push(value);
        heap.size += 1;
        _fixUp(heap, NodeId.wrap(heap.values.length - 1), value);
    }

    function get(Heap storage heap) internal view returns (uint256 minimum) {
        if (heap.size > 0) {
            return _getValue(heap, _ROOT);
        } else {
            revert AccessToEmptyHeap();
        }
    }

    function pop(Heap storage heap) internal {
        if (heap.size > 0) {
            uint256 lastValue = _getValue(heap, _getLastNode(heap));
            --heap.size;
            if (heap.size > 0) {
                _fixDown(heap, _ROOT, _getLastNode(heap), lastValue);
            }
        } else {
            revert AccessToEmptyHeap();
        }
    }

    // Private

    function _getParentNode(NodeId node) private pure returns (NodeId parent) {
        if (_equals(node, _ROOT)) {
            revert RootDoesNotHaveParent();
        }
        parent = NodeId.wrap(NodeId.unwrap(node) / 2);
    }

    function _getLeftChild(NodeId node) private pure returns (NodeId left) {
        left = NodeId.wrap(NodeId.unwrap(node) * 2);
    }

    function _getRightChild(NodeId node) private pure returns (NodeId right) {
        right = NodeId.wrap(NodeId.unwrap(node) * 2 + 1);
    }

    function _getLastNode(Heap storage heap) private view returns (NodeId last) {
        last = NodeId.wrap(heap.size);
    }

    function _fixUp(Heap storage heap, NodeId node, uint256 value) private {
        if (_equals(node, _ROOT)) {
            return;
        }
        NodeId parent = _getParentNode(node);
        uint256 parentValue = _getValue(heap, parent);
        if (parentValue <= value) {
            _setValue(heap, node, value);
        } else {
            _setValue(heap, node, parentValue);
            _fixUp(heap, parent, parentValue);
        }
    }

    function _fixDown(Heap storage heap, NodeId node, NodeId lastNode, uint256 value) private {
        NodeId left = _getLeftChild(node);
        NodeId right = _getRightChild(node);

        if (_exists(left, lastNode)) {
            uint256 leftValue = _getValue(heap, left);
            uint256 minValue = leftValue;
            NodeId minNode = left;
            if (_exists(right, lastNode)) {
                // left and right child exist
                uint256 rightValue = _getValue(heap, right);
                if (rightValue < leftValue) {
                    minNode = right;
                    minValue = rightValue;
                }
            }
            if (minValue < value) {
                _setValue(heap, node, minValue);
                _fixDown(heap, minNode, lastNode, value);
            } else {
                _setValue(heap, node, value);
            }
        } else {
            // no children
            _setValue(heap, node, value);
        }
    }

    function _equals(NodeId a, NodeId b) private pure returns (bool result) {
        return NodeId.unwrap(a) == NodeId.unwrap(b);
    }

    function _exists(NodeId node, NodeId lastNode) private pure returns (bool result) {
        return NodeId.unwrap(node) <= NodeId.unwrap(lastNode);
    }

    function _getValue(Heap storage heap, NodeId node) private view returns (uint256 value) {
        value = heap.values[NodeId.unwrap(node)];
    }

    function _setValue(Heap storage heap, NodeId node, uint256 value) private {
        heap.values[NodeId.unwrap(node)] = value;
    }
}
