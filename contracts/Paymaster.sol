// SPDX-License-Identifier: AGPL-3.0-only

/*
    Paymaster.sol - Paymaster
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

pragma solidity ^0.8.18;

// cspell:words structs

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {AccessManagedUpgradeable}
from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {IPaymaster, SchainHash} from "./interfaces/IPaymaster.sol";


type ValidatorId is uint256;

struct Schain {
    SchainHash hash;
    string name;
}

struct Validator {
    ValidatorId id;
}

error SchainNotFound(
    SchainHash hash
);

error SchainAddingError(
    SchainHash hash
);

error SchainDeletionError(
    SchainHash hash
);

contract Paymaster is AccessManagedUpgradeable, IPaymaster {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    mapping(SchainHash => Schain) public schains;
    EnumerableSet.Bytes32Set private _schainHashes;

    function addSchain(string calldata name) external override restricted {
        SchainHash schainHash = SchainHash.wrap(keccak256(abi.encodePacked(name)));
        Schain memory schain = Schain({
            hash: schainHash,
            name: name
        });
        _addSchain(schain);
    }

    function removeSchain(SchainHash schainHash) external override restricted {
        _removeSchain(_getSchain(schainHash));
    }

    // Private

    function _addSchain(Schain memory schain) private {
        schains[schain.hash] = schain;
        if (!_schainHashes.add(SchainHash.unwrap(schain.hash))) {
            revert SchainAddingError(schain.hash);
        }
    }

    function _removeSchain(Schain memory schain) private {
        delete schains[schain.hash];
        if(!_schainHashes.remove(SchainHash.unwrap(schain.hash))) {
            revert SchainDeletionError(schain.hash);
        }
    }

    function _getSchain(SchainHash hash) private view returns (Schain storage schain) {
        if (_schainHashes.contains(SchainHash.unwrap(hash))) {
            return schains[hash];
        } else {
            revert SchainNotFound(hash);
        }
    }
}
