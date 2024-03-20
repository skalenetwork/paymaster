// SPDX-License-Identifier: AGPL-3.0-only

/*
    TypedMap.sol - Paymaster
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

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {ValidatorId} from "../../interfaces/IPaymaster.sol";


library TypedMap {
    struct AddressToValidatorIdMap {
        EnumerableMap.AddressToUintMap inner;
    }

    /**
     * @dev Adds a key-value pair to a map, or updates the value for an existing
     * key. O(1).
     *
     * Returns true if the key was added to the map, that is if it was not
     * already present.
     */
    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function set(
        AddressToValidatorIdMap storage map,
        address key,
        ValidatorId value
    )
        internal
        returns (bool added)
    {
        return EnumerableMap.set(map.inner, key, ValidatorId.unwrap(value));
    }

    /**
     * @dev Removes a value from a map. O(1).
     *
     * Returns true if the key was removed from the map, that is if it was present.
     */
    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function remove(
        AddressToValidatorIdMap storage map,
        address key
    )
        internal
        returns (bool removed)
    {
        return EnumerableMap.remove(map.inner, key);
    }

    /**
     * @dev Tries to returns the value associated with `key`. O(1).
     * Does not revert if `key` is not in the map.
     */
    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function tryGet(
        AddressToValidatorIdMap storage map,
        address key
    )
        internal
        view
        returns (bool exist, ValidatorId validatorId)
    {
        (bool success, uint256 value) = EnumerableMap.tryGet(map.inner, key);
        return (success, ValidatorId.wrap(value));
    }
}
