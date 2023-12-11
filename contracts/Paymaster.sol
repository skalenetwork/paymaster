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
    Seconds,
    Timestamp,
    Months
} from "./DateTimeUtils.sol";
import {SequenceLibrary} from "./Sequence.sol";
import {TimelineLibrary} from "./Timeline.sol";


contract Paymaster is AccessManagedUpgradeable, IPaymaster {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.UintSet;
    using SequenceLibrary for SequenceLibrary.Iterator;
    using SequenceLibrary for SequenceLibrary.Sequence;
    using TimelineLibrary for TimelineLibrary.Timeline;
    using TypedMap for TypedMap.AddressToValidatorIdMap;

    type DebtId is uint256;

    struct Payment {
        Timestamp from;
        Timestamp to;
        SKL amount;
    }

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
        SequenceLibrary.Sequence nodesHistory;
        DebtId firstUnpaidDebt;
    }

    mapping(SchainHash => Schain) public schains;
    EnumerableSet.Bytes32Set private _schainHashes;

    mapping(ValidatorId => Validator) private _validators;
    EnumerableSet.UintSet private _validatorIds;
    TypedMap.AddressToValidatorIdMap private _addressToValidatorId;

    Months public maxReplenishmentPeriod;
    USD public schainPricePerMonth;
    USD public oneSklPrice;
    Timestamp public sklPriceTimestamp;
    IERC20 public skaleToken;

    TimelineLibrary.Timeline private _totalRewards;
    SequenceLibrary.Sequence private _totalNodesHistory;

    mapping (DebtId => Payment) public debts;
    DebtId public debtsBegin;
    DebtId public debtsEnd;

    error ImportantDataRemoving();

    function initialize(address initialAuthority) public virtual initializer override {
        __AccessManaged_init(initialAuthority);
    }

    function addSchain(string calldata name) external override restricted {
        SchainHash schainHash = SchainHash.wrap(keccak256(abi.encodePacked(name)));
        Schain memory schain = Schain({
            hash: schainHash,
            name: name,
            paidUntil: _getTimestamp().nextMonth()
        });
        _addSchain(schain);
    }

    function removeSchain(SchainHash schainHash) external override restricted {
        _removeSchain(_getSchain(schainHash));
    }

    function addValidator(ValidatorId id, address validatorAddress) external override restricted {
        if (!_validatorIds.add(ValidatorId.unwrap(id))) {
            revert ValidatorAddingError(id);
        }
        if(!_addressToValidatorId.set(validatorAddress, id)) {
            revert ValidatorAddressAlreadyExists(validatorAddress);
        }

        _validators[id].id = id;
        delete _validators[id].nodesAmount;
        delete _validators[id].activeNodesAmount;
        _validators[id].claimedUntil = _getTimestamp();
        _validators[id].validatorAddress = validatorAddress;
        _validators[id].nodesHistory.clear();
    }

    function removeValidator(ValidatorId id) external override restricted {
        _removeValidator(_getValidator(id));
    }

    function setNodesAmount(ValidatorId validatorId, uint256 amount) external override restricted {
        Validator storage validator = _getValidator(validatorId);
        uint256 oldActiveNodesAmount = validator.activeNodesAmount;
        validator.nodesAmount = amount;
        validator.activeNodesAmount = amount;
        _activeNodesAmountChanged(validator, oldActiveNodesAmount, amount);
    }

    function setActiveNodes(ValidatorId validatorId, uint256 amount) external override restricted {
        Validator storage validator = _getValidator(validatorId);
        uint256 oldActiveNodesAmount = validator.activeNodesAmount;
        uint256 activeNodesAmount = Math.min(amount, validator.nodesAmount);
        validator.activeNodesAmount = activeNodesAmount;
        _activeNodesAmountChanged(validator, oldActiveNodesAmount, activeNodesAmount);
    }

    function setMaxReplenishmentPeriod(Months months) external override restricted {
        maxReplenishmentPeriod = months;
    }

    function setSchainPrice(USD price) external override restricted {
        schainPricePerMonth = price;
    }

    function setSklPrice(USD price) external override restricted {
        oneSklPrice = price;
        sklPriceTimestamp = _getTimestamp();
    }

    function setSkaleToken(IERC20 token) external override restricted {
        skaleToken = token;
    }

    function clearHistory(Timestamp before) external override restricted {
        uint256 schainsAmount = _schainHashes.length();
        for (uint256 i = 0; i < schainsAmount; ++i) {
            SchainHash schainHash = SchainHash.wrap(_schainHashes.at(i));
            Schain storage schain = _getSchain(schainHash);
            if (schain.paidUntil < before) {
                revert ImportantDataRemoving();
            }
        }

        DebtId firstUnpaidDebt = debtsEnd;
        uint256 validatorsAmount = _validatorIds.length();
        for (uint256 i = 0; i < validatorsAmount; ++i) {
            ValidatorId validatorId = ValidatorId.wrap(_validatorIds.at(i));
            Validator storage validator = _getValidator(validatorId);
            if (validator.claimedUntil < before) {
                revert ImportantDataRemoving();
            }
            if (_before(validator.firstUnpaidDebt, firstUnpaidDebt)) {
                firstUnpaidDebt = validator.firstUnpaidDebt;
            }
            validator.nodesHistory.clear(before);
        }

        for (DebtId id = debtsBegin; !_equal(id, firstUnpaidDebt); id = _next(id)) {
            _clearDebt(id);
        }
        debtsBegin = firstUnpaidDebt;

        _totalRewards.process(before);
        _totalRewards.clear(before);
        _totalNodesHistory.clear(before);
    }

    function pay(SchainHash schainHash, Months duration) external override {
        Schain storage schain = _getSchain(schainHash);

        Timestamp current = _getTimestamp();
        Timestamp start = schain.paidUntil;
        Timestamp finish = start.add(duration);
        Timestamp limit = DateTimeUtils.nextMonth(current).add(maxReplenishmentPeriod);
        if (limit < finish) {
            revert ReplenishmentPeriodIsTooBig();
        }

        SKL cost = _toSKL(_getCost(duration));
        SKL costPerMonth = SKL.wrap(SKL.unwrap(cost) / Months.unwrap(duration));
        Months oneMonth = Months.wrap(1);
        DebtId end = debtsEnd;
        for (Months i = Months.wrap(0); i < duration; i = i + oneMonth) {
            Timestamp from = start.add(i);
            Timestamp to = start.add(i + oneMonth);
            if(_addPayment(
                Payment({
                    from: from,
                    to: to,
                    amount: costPerMonth
                }),
                current,
                end
            )) {
                end = _next(end);
            }
        }
        if (!_equal(debtsEnd, end)) {
            debtsEnd = end;
        }
        schain.paidUntil = start.add(duration);

        _pullTokens(cost);
    }

    function claim(address to) external override {
        Validator storage validator = _getValidatorByAddress(_msgSender());
        _claimFor(validator.id, to);
    }

    function getSchainExpirationTimestamp(SchainHash schainHash) external view override returns (Timestamp expiration) {
        return _getSchain(schainHash).paidUntil;
    }

    // Public

    function claimFor(ValidatorId validatorId, address to) public restricted override {
        _claimFor(validatorId, to);
    }

    // Internal

    function _getTimestamp() internal view virtual returns (Timestamp timestamp) {
        return DateTimeUtils.timestamp();
    }

    // Private

    function _claimFor(ValidatorId validatorId, address to) private {
        Validator storage validator = _getValidator(validatorId);
        Timestamp claimUntil = DateTimeUtils.firstDayOfMonth(_getTimestamp());
        _totalRewards.process(claimUntil);

        SKL rewards = _calculateRewards(
            validator,
            Payment({
                from: validator.claimedUntil,
                to: claimUntil,
                amount: SKL.wrap(0) // ignored by _loadFromTimeline
            }),
            _loadFromTimeline
        );
        validator.claimedUntil = claimUntil;

        DebtId end = debtsEnd;
        for (DebtId debtId = validator.firstUnpaidDebt; _before(debtId, end); debtId = _next(debtId)) {
            rewards = rewards + _calculateRewards(
                validator,
                debts[debtId],
                _proportionalRewardGetter
            );
        }
        validator.firstUnpaidDebt = end;

        if (!skaleToken.transfer(to, SKL.unwrap(rewards))) {
            revert TransferFailure();
        }
    }

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

    function _removeValidator(Validator storage validator) private {
        validator.id = ValidatorId.wrap(0);
        delete validator.nodesAmount;
        delete validator.activeNodesAmount;
        validator.claimedUntil = Timestamp.wrap(0);
        delete validator.validatorAddress;
        validator.nodesHistory.clear();

        if(!_validatorIds.remove(ValidatorId.unwrap(validator.id))) {
            revert ValidatorDeletionError(validator.id);
        }
        if(!_addressToValidatorId.remove(validator.validatorAddress)) {
            revert ValidatorDeletionError(validator.id);
        }
    }

    function _activeNodesAmountChanged(Validator storage validator, uint256 oldAmount, uint256 newAmount) private {
        Timestamp currentTime = _getTimestamp();
        validator.nodesHistory.add(currentTime, newAmount);

        uint256 totalNodes = _totalNodesHistory.getLastValue();
        _totalNodesHistory.add(currentTime, totalNodes + newAmount - oldAmount);
    }

    function _addDebt(Payment memory debt, DebtId id) private {
        debts[id] = debt;
    }

    function _addPayment(Payment memory payment, Timestamp current, DebtId end) private returns (bool debtWasCreated) {
        debtWasCreated = false;
        if (current <= payment.from) {
            // payment for the future
            _totalRewards.add(payment.from, payment.to, SKL.unwrap(payment.amount));
        } else {
            debtWasCreated = true;
            if (payment.to <= current) {
                // payment for the past
                _addDebt(
                    payment,
                    end
                );
            } else {
                // payment is partially for the future
                // and partially for the past
                _addDebt(
                    Payment({
                        from: payment.from,
                        to: current,
                        amount: SKL.wrap(
                            SKL.unwrap(payment.amount)
                                * Seconds.unwrap(DateTimeUtils.duration(payment.from, current))
                                / Seconds.unwrap(DateTimeUtils.duration(payment.from, payment.to))
                        )
                    }),
                    end
                );

                _totalRewards.add(
                    current,
                    payment.to,
                    SKL.unwrap(payment.amount)
                        * Seconds.unwrap(DateTimeUtils.duration(current, payment.to))
                        / Seconds.unwrap(DateTimeUtils.duration(payment.from, payment.to))
                );
            }
        }
    }

    function _pullTokens(SKL amount) private {
        if (address(skaleToken) == address(0)) {
            revert SkaleTokenIsNotSet();
        }
        SKL allowance = SKL.wrap(
            skaleToken.allowance(msg.sender, address(this))
        );
        if (allowance < amount) {
            revert TooSmallAllowance({
                spender: address(this),
                required: SKL.unwrap(amount),
                allowed: SKL.unwrap(allowance)
            });
        }

        if (!skaleToken.transferFrom(msg.sender, address(this), SKL.unwrap(amount))) {
            revert TransferFailure();
        }
    }

    function _clearDebt(DebtId id) private {
        debts[id].from = Timestamp.wrap(0);
        debts[id].to = Timestamp.wrap(0);
        debts[id].amount = SKL.wrap(0);
    }

    // False positive detection of the dead code. The function is used in `claim` function
    //slither-disable-next-line dead-code
    function _loadFromTimeline(Timestamp from, Timestamp to, Payment memory) private view returns (SKL reward) {
        return SKL.wrap(_totalRewards.getSum(from, to));
    }

    // False positive detection of the dead code. The function is used in `claim` function
    //slither-disable-next-line dead-code
    function _proportionalRewardGetter(
        Timestamp from,
        Timestamp to,
        Payment memory debt
    )
        private
        pure
        returns (SKL reward)
    {
        return SKL.wrap(
            SKL.unwrap(debt.amount)
                * Seconds.unwrap(DateTimeUtils.duration(from, to))
                / Seconds.unwrap(DateTimeUtils.duration(debt.from, debt.to))
        );
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
            return _validators[id];
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

    function _calculateRewards(
        Validator storage validator,
        Payment memory rewardSource,
        function (Timestamp, Timestamp, Payment memory) internal view returns (SKL) getTotalReward
    )
        private
        view
        returns (SKL rewards)
    {
        Timestamp cursor = rewardSource.from;

        SequenceLibrary.Iterator memory totalNodesHistoryIterator = _totalNodesHistory.getIterator(cursor);
        SequenceLibrary.Iterator memory nodesHistoryIterator = validator.nodesHistory.getIterator(cursor);

        rewards = SKL.wrap(0);
        uint256 activeNodes = validator.nodesHistory.getValue(nodesHistoryIterator);
        uint256 totalNodes = _totalNodesHistory.getValue(totalNodesHistoryIterator);

        while (cursor < rewardSource.to) {
            Timestamp nextCursor = _getNextCursor(rewardSource.to, totalNodesHistoryIterator, nodesHistoryIterator);

            if (totalNodes > 0) {
                rewards = rewards + SKL.wrap(
                    SKL.unwrap(getTotalReward(cursor, nextCursor, rewardSource)) * activeNodes / totalNodes
                );
            }

            cursor = nextCursor;
            while (totalNodesHistoryIterator.hasNext() && totalNodesHistoryIterator.nextTimestamp <= cursor) {
                if (totalNodesHistoryIterator.step()) {
                    totalNodes = _totalNodesHistory.getValue(totalNodesHistoryIterator);
                }
            }
            while (nodesHistoryIterator.hasNext() && nodesHistoryIterator.nextTimestamp <= cursor) {
                if (nodesHistoryIterator.step()) {
                    activeNodes = validator.nodesHistory.getValue(nodesHistoryIterator);
                }
            }
        }
    }

    function _getNextCursor(
        Timestamp currentTime,
        SequenceLibrary.Iterator memory totalNodesHistoryIterator,
        SequenceLibrary.Iterator memory nodesHistoryIterator
    ) private pure returns (Timestamp nextCursor) {
        nextCursor = currentTime;
        if (totalNodesHistoryIterator.hasNext()) {
            nextCursor = DateTimeUtils.min(nextCursor, totalNodesHistoryIterator.nextTimestamp);
        }
        if (nodesHistoryIterator.hasNext()) {
            nextCursor = DateTimeUtils.min(nextCursor, nodesHistoryIterator.nextTimestamp);
        }
    }

    function _next(DebtId id) private pure returns (DebtId nextId) {
        return DebtId.wrap(DebtId.unwrap(id) + 1);
    }

    function _equal(DebtId a, DebtId b) private pure returns (bool result) {
        return DebtId.unwrap(a) == DebtId.unwrap(b);
    }

    function _before(DebtId left, DebtId right) private pure returns (bool result) {
        return DebtId.unwrap(left) < DebtId.unwrap(right);
    }
}
