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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessManagedUpgradeable}
from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {IPaymaster, SchainHash, ValidatorId} from "./interfaces/IPaymaster.sol";


struct Schain {
    SchainHash hash;
    string name;
}

struct Validator {
    ValidatorId id;
    uint nodesAmount;
    uint activeNodesAmount;
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

error ValidatorNotFound(
    ValidatorId id
);

error ValidatorAddingError(
    ValidatorId id
);

error ValidatorDeletionError(
    ValidatorId id
);

contract Paymaster is AccessManagedUpgradeable, IPaymaster {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(SchainHash => Schain) public schains;
    EnumerableSet.Bytes32Set private _schainHashes;

    mapping(ValidatorId => Validator) public validators;
    EnumerableSet.UintSet private _validatorIds;

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

    function addValidator(ValidatorId id) external override restricted {
        Validator memory validator = Validator({
            id: id,
            nodesAmount: 0,
            activeNodesAmount: 0
        });
        _addValidator(validator);
    }

    function removeValidator(ValidatorId id) external override restricted {
        _removeValidator(_getValidator(id));
    }

    function setNodesAmount(ValidatorId id, uint amount) external override restricted {
        Validator storage validator = _getValidator(id);
        validator.nodesAmount = amount;
        validator.activeNodesAmount = amount;
    }

    function setActiveNodes(ValidatorId id, uint amount) external override restricted {
        Validator storage validator = _getValidator(id);
        validator.activeNodesAmount = Math.min(amount, validator.nodesAmount);
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

    function _addValidator(Validator memory validator) private {
        validators[validator.id] = validator;
        if (!_validatorIds.add(ValidatorId.unwrap(validator.id))) {
            revert ValidatorAddingError(validator.id);
        }
    }

    function _removeValidator(Validator memory validator) private {
        delete validators[validator.id];
        if(!_validatorIds.remove(ValidatorId.unwrap(validator.id))) {
            revert ValidatorDeletionError(validator.id);
        }
    }

    function _getSchain(SchainHash hash) private view returns (Schain storage schain) {
        if (_schainHashes.contains(SchainHash.unwrap(hash))) {
            return schains[hash];
        } else {
            revert SchainNotFound(hash);
        }
    }

    function _getValidator(ValidatorId id) private view returns (Validator storage validator) {
        if (_validatorIds.contains(ValidatorId.unwrap(id))) {
            return validators[id];
        } else {
            revert ValidatorNotFound(id);
        }
    }
}
