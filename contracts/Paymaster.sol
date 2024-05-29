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
import {AccessManagedUpgradeable}
from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

import {
    SchainPriceIsNotSet,
    SkaleTokenIsNotSet,
    SklPriceIsNotSet,
    SklPriceIsOutdated
} from "./errors/Parameters.sol";
import {
    ReplenishmentPeriodIsTooBig,
    ReplenishmentPeriodIsTooSmall,
    TooSmallAllowance,
    TransferFailure
} from "./errors/Replenishment.sol";
import {SchainNotFound, SchainAddingError, SchainDeletionError} from "./errors/Schain.sol";
import {
    ValidatorNotFound,
    ValidatorAddingError,
    ValidatorAddressAlreadyExists,
    ValidatorAddressNotFound,
    ValidatorDeletionError,
    ValidatorHasBeenRemoved
} from "./errors/Validator.sol";
import {
    IPaymaster,
    SchainHash,
    USD,
    ValidatorId
} from "@skalenetwork/paymaster-interfaces/IPaymaster.sol";
import {TypedMap} from "./structs/typed/TypedMap.sol";
import {SKL} from "@skalenetwork/paymaster-interfaces/types/Skl.sol";
import {
    DateTimeUtils,
    Seconds,
    Timestamp,
    Months
} from "@skalenetwork/paymaster-interfaces/DateTimeUtils.sol";
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
        address validatorAddress;
        uint256 nodesAmount;
        uint256 activeNodesAmount;
        SequenceLibrary.Sequence nodesHistory;
        Timestamp claimedUntil;
        DebtId firstUnpaidDebt;
        Timestamp deleted;
    }

    struct ValidatorData {
        mapping(ValidatorId => Validator) validators;
        EnumerableSet.UintSet validatorIds;
        TypedMap.AddressToValidatorIdMap addressToValidatorId;
    }

    mapping(SchainHash => Schain) public schains;
    EnumerableSet.Bytes32Set private _schainHashes;

    ValidatorData private _validatorData;

    Months public maxReplenishmentPeriod;
    USD public schainPricePerMonth;
    USD public oneSklPrice;
    Timestamp public sklPriceTimestamp;
    Seconds public allowedSklPriceLag;
    IERC20 public skaleToken;

    TimelineLibrary.Timeline private _totalRewards;
    SequenceLibrary.Sequence private _totalNodesHistory;

    mapping (DebtId => Payment) public debts;
    DebtId public debtsBegin;
    DebtId public debtsEnd;

    string public version;

    error ImportantDataRemoving();
    error IncorrectActiveNodesAmount(
        uint256 amount,
        uint256 totalAmount
    );

    event SchainAdded(
        string name,
        SchainHash hash,
        Timestamp timestamp
    );

    event SchainRemoved(
        string name,
        SchainHash hash,
        Timestamp timestamp
    );

    event ValidatorAdded(
        ValidatorId id,
        address validatorAddress,
        Timestamp timestamp
    );

    event ValidatorMarkedAsRemoved(
        ValidatorId id,
        Timestamp timestamp
    );

    event ValidatorRemoved(
        ValidatorId id,
        Timestamp timestamp
    );

    event ActiveNodesNumberChanged(
        ValidatorId validator,
        uint256 oldNumber,
        uint256 newNumber,
        Timestamp timestamp
    );

    event MaxReplenishmentPeriodChanged(
        Months valueInMonths
    );

    event SchainPriceSet(
        USD priceInUsd,
        Timestamp timestamp
    );

    event SklPriceSet(
        USD priceInUsd,
        Timestamp timestamp
    );

    event SklPriceLagSet(
        Seconds lagInSeconds
    );

    event SkaleTokenSet(
        IERC20 tokenAddress
    );

    event HistoryCleaned(
        Timestamp until
    );

    event SchainPaid(
        SchainHash hash,
        Months period,
        SKL amount,
        Timestamp newLifetime,
        Timestamp timestamp
    );

    event RewardClaimed(
        ValidatorId validator,
        address receiver,
        SKL amount,
        Timestamp until,
        Timestamp timestamp
    );

    event VersionSet(
        string newVersion
    );

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
        if (!_validatorData.validatorIds.add(ValidatorId.unwrap(id))) {
            revert ValidatorAddingError(id);
        }
        if(!_validatorData.addressToValidatorId.set(validatorAddress, id)) {
            revert ValidatorAddressAlreadyExists(validatorAddress);
        }

        Timestamp currentTimestamp = _getTimestamp();

        _validatorData.validators[id].id = id;
        delete _validatorData.validators[id].nodesAmount;
        delete _validatorData.validators[id].activeNodesAmount;
        _validatorData.validators[id].claimedUntil = currentTimestamp;
        _validatorData.validators[id].validatorAddress = validatorAddress;
        _validatorData.validators[id].nodesHistory.clear();

        emit ValidatorAdded(id, validatorAddress, currentTimestamp);
    }

    function removeValidator(ValidatorId id) external override restricted {
        Timestamp currentTimestamp = _getTimestamp();
        Validator storage validator = _getValidator(id);
        setNodesAmount(id, 0);
        validator.deleted = currentTimestamp;

        emit ValidatorMarkedAsRemoved(id, currentTimestamp);
    }

    function setActiveNodes(ValidatorId validatorId, uint256 amount) external override restricted {
        Validator storage validator = _getValidator(validatorId);
        if (amount > validator.nodesAmount) {
            revert IncorrectActiveNodesAmount(amount, validator.nodesAmount);
        }
        uint256 oldActiveNodesAmount = validator.activeNodesAmount;
        validator.activeNodesAmount = amount;
        _activeNodesAmountChanged(validator, oldActiveNodesAmount, amount);
    }

    function setMaxReplenishmentPeriod(Months months) external override restricted {
        maxReplenishmentPeriod = months;

        emit MaxReplenishmentPeriodChanged(months);
    }

    function setSchainPrice(USD price) external override restricted {
        schainPricePerMonth = price;

        emit SchainPriceSet(price, _getTimestamp());
    }

    function setSklPrice(USD price) external override restricted {
        Timestamp currentTimestamp = _getTimestamp();
        oneSklPrice = price;
        sklPriceTimestamp = currentTimestamp;

        emit SklPriceSet(price, currentTimestamp);
    }

    function setAllowedSklPriceLag(Seconds lagSeconds) external override restricted {
        allowedSklPriceLag = lagSeconds;

        emit SklPriceLagSet(lagSeconds);
    }

    function setSkaleToken(IERC20 token) external override restricted {
        skaleToken = token;

        emit SkaleTokenSet(token);
    }

    function clearHistory(Timestamp before) external override restricted {
        _clearSchainsHistory(before);
        _clearValidatorsHistory(before);

        emit HistoryCleaned(before);
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
        if (duration == DateTimeUtils.months(0)) {
            revert ReplenishmentPeriodIsTooSmall();
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
                _totalRewards.processedUntil,
                end
            )) {
                end = _next(end);
            }
        }
        if (!_equal(debtsEnd, end)) {
            debtsEnd = end;
        }
        schain.paidUntil = start.add(duration);

        emit SchainPaid({
            hash: schainHash,
            period: duration,
            amount: cost,
            newLifetime: schain.paidUntil,
            timestamp: current
        });

        _pullTokens(cost);
    }

    function claim(address to) external override {
        Validator storage validator = _getValidatorByAddress(_msgSender());
        _claimFor(validator.id, to);
    }

    function setVersion(string calldata newVersion) external override restricted {
        version = newVersion;

        emit VersionSet(newVersion);
    }

    function getSchainExpirationTimestamp(
        SchainHash schainHash
    )
        external
        view
        override
        returns (Timestamp expiration)
    {
        return _getSchain(schainHash).paidUntil;
    }

    function getRewardAmount(ValidatorId validatorId) external view override returns (SKL reward) {
        Validator storage validator = _getValidator(validatorId);
        return _getRewardAmount(
            validator,
            DateTimeUtils.firstDayOfMonth(_getTimestamp())
        );
    }

    function getNodesNumber(
        ValidatorId validatorId
    )
        external
        view
        override
        returns (uint256 number)
    {
        return _getValidator(validatorId).nodesAmount;
    }

    function getActiveNodesNumber(
        ValidatorId validatorId
    )
        external
        view
        override
        returns (uint256 number)
    {
        return _getValidator(validatorId).activeNodesAmount;
    }

    function getHistoricalActiveNodesNumber(
        ValidatorId validatorId,
        Timestamp when
    )
        external
        view
        override
        returns (uint256 number)
    {
        return _getValidator(validatorId).nodesHistory.getValueByTimestamp(when);
    }

    function getHistoricalTotalActiveNodesNumber(
        Timestamp when
    )
        external
        view
        override
        returns (uint256 number)
    {
        return _totalNodesHistory.getValueByTimestamp(when);
    }

    function getValidatorsNumber() external view override returns (uint256 number) {
        return _validatorData.validatorIds.length();
    }

    function getSchainsNames() external view override returns (string[] memory names) {
        names = new string[](getSchainsNumber());
        for (uint256 i = 0; i < names.length; ++i) {
            names[i] = _getSchain(SchainHash.wrap(_schainHashes.at(i))).name;
        }
    }

    function getTotalReward(
        Timestamp from,
        Timestamp to
    )
        external
        view
        override
        returns (SKL reward)
    {
        return SKL.wrap(_totalRewards.getSum(from, to));
    }

    // Public

    function setNodesAmount(ValidatorId validatorId, uint256 amount) public override restricted {
        Validator storage validator = _getValidator(validatorId);
        if (validator.deleted != Timestamp.wrap(0)) {
            revert ValidatorHasBeenRemoved(validatorId, validator.deleted);
        }
        uint256 oldActiveNodesAmount = validator.activeNodesAmount;
        validator.nodesAmount = amount;
        validator.activeNodesAmount = amount;
        _activeNodesAmountChanged(validator, oldActiveNodesAmount, amount);
    }

    function claimFor(ValidatorId validatorId, address to) public restricted override {
        _claimFor(validatorId, to);
    }

    function getSchainsNumber() public view override returns (uint256 number) {
        return _schainHashes.length();
    }

    // Internal

    function _getTimestamp() internal view virtual returns (Timestamp timestamp) {
        return DateTimeUtils.timestamp();
    }

    // Private

    function _clearSchainsHistory(Timestamp before) private {
        uint256 schainsAmount = _schainHashes.length();
        for (uint256 i = 0; i < schainsAmount; ++i) {
            SchainHash schainHash = SchainHash.wrap(_schainHashes.at(i));
            Schain storage schain = _getSchain(schainHash);
            if (schain.paidUntil < before) {
                revert ImportantDataRemoving();
            }
        }
        _clearPaymentsHistory(before);
    }

    function _clearValidatorsHistory(Timestamp before) private {
        DebtId firstUnpaidDebt = debtsEnd;
        uint256 validatorsAmount = _validatorData.validatorIds.length();
        for (uint256 i = 0; i < validatorsAmount; ++i) {
            ValidatorId validatorId = ValidatorId.wrap(_validatorData.validatorIds.at(i));
            Validator storage validator = _getValidator(validatorId);
            if (validator.claimedUntil < before) {
                revert ImportantDataRemoving();
            }
            if (_before(validator.firstUnpaidDebt, firstUnpaidDebt)) {
                firstUnpaidDebt = validator.firstUnpaidDebt;
            }
            validator.nodesHistory.clear(before);
            if (Timestamp.wrap(0) != validator.deleted && validator.deleted <= before) {
                _removeValidator(validator);
            }
        }
        if (_before(firstUnpaidDebt, debtsEnd) && debts[firstUnpaidDebt].from < before) {
            revert ImportantDataRemoving();
        }

        for (DebtId id = debtsBegin; !_equal(id, firstUnpaidDebt); id = _next(id)) {
            _clearDebt(id);
        }
        debtsBegin = firstUnpaidDebt;

        _totalNodesHistory.clear(before);
    }

    function _clearPaymentsHistory(Timestamp before) private {
        _totalRewards.process(before);
        _totalRewards.clear(before);
    }

    function _claimFor(ValidatorId validatorId, address to) private {
        Validator storage validator = _getValidator(validatorId);
        Timestamp currentTimestamp = _getTimestamp();
        Timestamp claimUntil = DateTimeUtils.firstDayOfMonth(currentTimestamp);
        _totalRewards.process(claimUntil);

        SKL rewards = _getRewardAmount(validator, claimUntil);
        validator.claimedUntil = claimUntil;
        validator.firstUnpaidDebt = debtsEnd;

        emit RewardClaimed({
            validator: validatorId,
            receiver: to,
            amount: rewards,
            until: claimUntil,
            timestamp: currentTimestamp
        });

        if (!skaleToken.transfer(to, SKL.unwrap(rewards))) {
            revert TransferFailure();
        }
    }

    function _addSchain(Schain memory schain) private {
        schains[schain.hash] = schain;
        if (!_schainHashes.add(SchainHash.unwrap(schain.hash))) {
            revert SchainAddingError(schain.hash);
        }
        emit SchainAdded(schain.name, schain.hash, _getTimestamp());
    }

    function _removeSchain(Schain storage schain) private {
        if(!_schainHashes.remove(SchainHash.unwrap(schain.hash))) {
            revert SchainDeletionError(schain.hash);
        }
        emit SchainRemoved(schain.name, schain.hash, _getTimestamp());
        delete schains[schain.hash];
    }

    function _removeValidator(Validator storage validator) private {
        if(!_validatorData.validatorIds.remove(ValidatorId.unwrap(validator.id))) {
            revert ValidatorDeletionError(validator.id);
        }
        if(!_validatorData.addressToValidatorId.remove(validator.validatorAddress)) {
            revert ValidatorDeletionError(validator.id);
        }

        emit ValidatorRemoved(validator.id, _getTimestamp());

        validator.id = ValidatorId.wrap(0);
        delete validator.nodesAmount;
        delete validator.activeNodesAmount;
        validator.claimedUntil = Timestamp.wrap(0);
        delete validator.validatorAddress;
        validator.nodesHistory.clear();
        validator.deleted = Timestamp.wrap(0);
    }

    function _activeNodesAmountChanged(
        Validator storage validator,
        uint256 oldAmount,
        uint256 newAmount
    )
        private
    {
        Timestamp currentTime = _getTimestamp();
        validator.nodesHistory.add(currentTime, newAmount);

        uint256 totalNodes = _totalNodesHistory.getLastValue();
        _totalNodesHistory.add(currentTime, totalNodes + newAmount - oldAmount);

        emit ActiveNodesNumberChanged(validator.id, oldAmount, newAmount, currentTime);
    }

    function _addDebt(Payment memory debt, DebtId id) private {
        debts[id] = debt;
    }

    function _addPayment(
        Payment memory payment,
        Timestamp current,
        DebtId end
    )
        private
        returns (bool debtWasCreated)
    {
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
                SKL pastPart = SKL.wrap(
                    SKL.unwrap(payment.amount)
                        * Seconds.unwrap(DateTimeUtils.duration(payment.from, current))
                        / Seconds.unwrap(DateTimeUtils.duration(payment.from, payment.to)
                ));
                SKL futurePart = payment.amount - pastPart;
                _addDebt(
                    Payment({
                        from: payment.from,
                        to: current,
                        amount: pastPart
                    }),
                    end
                );

                _totalRewards.add(
                    current,
                    payment.to,
                    SKL.unwrap(futurePart)
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

    function _getRewardAmount(
        Validator storage validator,
        Timestamp claimUntil
    )
        private
        view
        returns (SKL rewards)
    {
        rewards = _calculateRewards(
            validator,
            Payment({
                from: validator.claimedUntil,
                to: claimUntil,
                amount: SKL.wrap(0) // ignored by _loadFromTimeline
            }),
            _loadFromTimeline
        );

        DebtId end = debtsEnd;
        for (
            DebtId debtId = validator.firstUnpaidDebt;
            _before(debtId, end);
            debtId = _next(debtId)
        ) {
            rewards = rewards + _calculateRewards(
                validator,
                debts[debtId],
                _proportionalRewardGetter
            );
        }
    }

    // False positive detection of the dead code. The function is used in `claim` function
    //slither-disable-next-line dead-code
    function _loadFromTimeline(
        Timestamp from,
        Timestamp to,
        Payment memory
    )
        private
        view
        returns (SKL reward)
    {
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
        if (_validatorData.validatorIds.contains(ValidatorId.unwrap(id))) {
            return _validatorData.validators[id];
        } else {
            revert ValidatorNotFound(id);
        }
    }

    function _getValidatorByAddress(
        address validatorAddress
    )
        private
        view
        returns (Validator storage validator)
    {
        (bool success, ValidatorId id) =
            _validatorData.addressToValidatorId.tryGet(validatorAddress);
        if (success) {
            return _getValidator(id);
        } else {
            revert ValidatorAddressNotFound(validatorAddress);
        }
    }

    function _toSKL(USD amount) private view returns (SKL result) {
        USD price = oneSklPrice;
        if (price == USD.wrap(0)) {
            revert SklPriceIsNotSet();
        }
        if (allowedSklPriceLag < DateTimeUtils.duration(sklPriceTimestamp, _getTimestamp())) {
            revert SklPriceIsOutdated();
        }
        result = SKL.wrap(
            USD.unwrap(amount) * 1e18 / USD.unwrap(price)
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
        function (
            Timestamp,
            Timestamp,
            Payment memory
        ) internal view returns (SKL) getTotalRewardFunction
    )
        private
        view
        returns (SKL rewards)
    {
        Timestamp cursor = rewardSource.from;
        SequenceLibrary.Iterator memory totalNodesHistoryIterator =
            _totalNodesHistory.getIterator(cursor);
        SequenceLibrary.Iterator memory nodesHistoryIterator =
            validator.nodesHistory.getIterator(cursor);
        rewards = SKL.wrap(0);
        uint256 activeNodes = validator.nodesHistory.getValue(nodesHistoryIterator);
        uint256 totalNodes = _totalNodesHistory.getValue(totalNodesHistoryIterator);

        while (cursor < rewardSource.to) {
            Timestamp nextCursor = _getNextCursor(
                rewardSource.to,
                totalNodesHistoryIterator,
                nodesHistoryIterator
            );

            if (totalNodes > 0) {
                rewards = rewards + SKL.wrap(
                    SKL.unwrap(
                        getTotalRewardFunction(cursor, nextCursor, rewardSource)
                    ) * activeNodes / totalNodes
                );
            }

            cursor = nextCursor;
            totalNodes = _updateNodesAmount(
                totalNodesHistoryIterator,
                _totalNodesHistory,
                cursor,
                totalNodes
            );
            activeNodes = _updateNodesAmount(
                nodesHistoryIterator,
                validator.nodesHistory,
                cursor,
                activeNodes
            );
        }
    }

    function _updateNodesAmount(
        SequenceLibrary.Iterator memory nodesIterator,
        SequenceLibrary.Sequence storage nodesHistory,
        Timestamp cursor,
        uint256 currentNodesNumber
    )
        private
        view
        returns (uint256 newNodesNumber)
    {
        newNodesNumber = currentNodesNumber;
        while (nodesIterator.hasNext() && nodesIterator.nextTimestamp <= cursor) {
            if (nodesIterator.step(nodesHistory)) {
                newNodesNumber = nodesHistory.getValue(nodesIterator);
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
