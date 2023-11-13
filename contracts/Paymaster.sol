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

pragma solidity ^0.8.19;

// cspell:words structs IERC20

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessManagedUpgradeable}
from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {
    SchainPriceIsNotSet,
    SkaleTokenIsNotSet,
    SklPriceIsNotSet
} from "./errors/Parameters.sol";
import {
    ReplenishmentPeriodIsTooBig,
    TooSmallAllowance,
    TransferFailure
} from "./errors/Replenishment.sol";
import {SchainNotFound, SchainAddingError, SchainDeletionError} from "./errors/Schain.sol";
import {
    ValidatorNotFound,
    ValidatorAddingError,
    ValidatorAddressAlreadyExists,
    ValidatorAddressNotFound,
    ValidatorDeletionError
} from "./errors/Validator.sol";
import {
    IPaymaster,
    SchainHash,
    USD,
    ValidatorId
} from "./interfaces/IPaymaster.sol";
import {TypedMap} from "./structs/TypedMap.sol";
import {SKL} from "./types/Skl.sol";
import {
    DateTimeUtils,
    Timestamp,
    Months
} from "./DateTimeUtils.sol";
import {TimelineLibrary} from "./Timeline.sol";


struct Schain {
    SchainHash hash;
    string name;
    Timestamp paidUntil;
}

struct Validator {
    ValidatorId id;
    uint256 nodesAmount;
    uint256 activeNodesAmount;
    Timestamp claimedUntil;
    address validatorAddress;
}

contract Paymaster is AccessManagedUpgradeable, IPaymaster {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.UintSet;
    using TimelineLibrary for TimelineLibrary.Timeline;
    using TypedMap for TypedMap.AddressToValidatorIdMap;

    mapping(SchainHash => Schain) public schains;
    EnumerableSet.Bytes32Set private _schainHashes;

    mapping(ValidatorId => Validator) public validators;
    EnumerableSet.UintSet private _validatorIds;
    TypedMap.AddressToValidatorIdMap private _addressToValidatorId;

    Months public maxReplenishmentPeriod;
    USD public schainPricePerMonth;
    USD public oneSklPrice;
    Timestamp public sklPriceTimestamp;
    IERC20 public skaleToken;

    TimelineLibrary.Timeline private _totalRewards;

    constructor(address initialAuthority) initializer {
        __AccessManaged_init(initialAuthority);
    }

    function addSchain(string calldata name) external override restricted {
        SchainHash schainHash = SchainHash.wrap(keccak256(abi.encodePacked(name)));
        Schain memory schain = Schain({
            hash: schainHash,
            name: name,
            paidUntil: DateTimeUtils.timestamp().nextMonth()
        });
        _addSchain(schain);
    }

    function removeSchain(SchainHash schainHash) external override restricted {
        _removeSchain(_getSchain(schainHash));
    }

    function addValidator(ValidatorId id, address validatorAddress) external override restricted {
        Validator memory validator = Validator({
            activeNodesAmount: 0,
            claimedUntil: DateTimeUtils.timestamp(),
            id: id,
            nodesAmount: 0,
            validatorAddress: validatorAddress
        });
        _addValidator(validator);
    }

    function removeValidator(ValidatorId id) external override restricted {
        _removeValidator(_getValidator(id));
    }

    function setNodesAmount(ValidatorId id, uint256 amount) external override restricted {
        Validator storage validator = _getValidator(id);
        validator.nodesAmount = amount;
        validator.activeNodesAmount = amount;
    }

    function setActiveNodes(ValidatorId id, uint256 amount) external override restricted {
        Validator storage validator = _getValidator(id);
        validator.activeNodesAmount = Math.min(amount, validator.nodesAmount);
    }

    function setMaxReplenishmentPeriod(Months months) external override restricted {
        maxReplenishmentPeriod = months;
    }

    function setSchainPrice(USD price) external override restricted {
        schainPricePerMonth = price;
    }

    function setSklPrice(USD price) external override restricted {
        oneSklPrice = price;
        sklPriceTimestamp = DateTimeUtils.timestamp();
    }

    function setSkaleToken(IERC20 token) external override restricted {
        skaleToken = token;
    }

    function pay(SchainHash schainHash, Months duration) external override {
        if (duration > maxReplenishmentPeriod) {
            revert ReplenishmentPeriodIsTooBig();
        }

        Schain storage schain = _getSchain(schainHash);
        SKL cost = _toSKL(_getCost(duration));

        if (address(skaleToken) == address(0)) {
            revert SkaleTokenIsNotSet();
        }
        SKL allowance = SKL.wrap(
            skaleToken.allowance(_msgSender(), address(this))
        );
        if (allowance < cost) {
            revert TooSmallAllowance({
                spender: address(this),
                required: SKL.unwrap(cost),
                allowed: SKL.unwrap(allowance)
            });
        }

        SKL costPerMonth = SKL.wrap(SKL.unwrap(cost) / Months.unwrap(duration));
        Timestamp start = schain.paidUntil;
        Months oneMonth = Months.wrap(1);
        for (Months i = Months.wrap(0); i < duration; i = i + oneMonth) {
            _totalRewards.add(start.add(i), start.add(i + oneMonth), SKL.unwrap(costPerMonth));
        }
        schain.paidUntil = start.add(duration);

        if (!skaleToken.transferFrom(_msgSender(), address(this), SKL.unwrap(cost))) {
            revert TransferFailure();
        }
    }

    function claim(address to) external restricted override {
        Validator storage validator = _getValidatorByAddress(_msgSender());
        claimFor(validator.id, to);
    }

    function claimFor(ValidatorId validatorId, address to) public restricted override {
        Validator storage validator = _getValidator(validatorId);
        Timestamp currentTime = DateTimeUtils.timestamp();
        _totalRewards.process(currentTime);
        SKL rewards = SKL.wrap(_totalRewards.getSum(validator.claimedUntil, currentTime));
        validator.claimedUntil = currentTime;

        if (!skaleToken.transfer(to, SKL.unwrap(rewards))) {
            revert TransferFailure();
        }
    }

    // Private

    function _addSchain(Schain memory schain) private {
        schains[schain.hash] = schain;
        if (!_schainHashes.add(SchainHash.unwrap(schain.hash))) {
            revert SchainAddingError(schain.hash);
        }
    }

    function _removeSchain(Schain storage schain) private {
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
        if(!_addressToValidatorId.set(validator.validatorAddress, validator.id)) {
            revert ValidatorAddressAlreadyExists(validator.validatorAddress);
        }
    }

    function _removeValidator(Validator storage validator) private {
        delete validators[validator.id];
        if(!_validatorIds.remove(ValidatorId.unwrap(validator.id))) {
            revert ValidatorDeletionError(validator.id);
        }
        if(!_addressToValidatorId.remove(validator.validatorAddress)) {
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

    function _getValidatorByAddress(address validatorAddress) private view returns (Validator storage validator) {
        (bool success, ValidatorId id) = _addressToValidatorId.tryGet(validatorAddress);
        if (success) {
            return _getValidator(id);
        } else {
            revert ValidatorAddressNotFound(validatorAddress);
        }
    }

    function _toSKL(USD amount) private view returns (SKL result) {
        if (oneSklPrice == USD.wrap(0)) {
            revert SklPriceIsNotSet();
        }
        result = SKL.wrap(
            USD.unwrap(amount) * 1e18 / USD.unwrap(oneSklPrice)
        );
    }

    function _getCost(Months period) private view returns (USD cost) {
        if (schainPricePerMonth == USD.wrap(0)) {
            revert SchainPriceIsNotSet();
        }
        cost = USD.wrap(Months.unwrap(period) * USD.unwrap(schainPricePerMonth));
    }
}
