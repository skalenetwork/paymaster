// SPDX-License-Identifier: AGPL-3.0-only

/*
    DateTimeUtils.sol - Paymaster
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

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DateTime as UntypedDateTime} from "@quant-finance/solidity-datetime/contracts/DateTime.sol";


type Seconds is uint256;
type Day is uint256;
type Month is uint256;
type Months is uint256;
type Year is uint256;

type Timestamp is uint256;

using DateTimeUtils for Timestamp global;
using {
    _secondsAdd as +
} for Seconds global;
using {
    _monthsLess as <,
    _monthsEqual as ==,
    _monthsGreater as >,
    _monthsAdd as +
} for Months global;
using {
    _timestampLess as <,
    _timestampLessOrEqual as <=,
    _timestampEqual as ==
} for Timestamp global;

function _secondsAdd(Seconds a, Seconds b) pure returns (Seconds result) {
    return Seconds.wrap(Seconds.unwrap(a) + Seconds.unwrap(b));
}

function _monthsLess(Months left, Months right) pure returns (bool result) {
    return Months.unwrap(left) < Months.unwrap(right);
}

function _monthsEqual(Months a, Months b) pure returns (bool result) {
    return !(a < b) && !(b < a);
}

function _monthsGreater(Months left, Months right) pure returns (bool result) {
    return !(left < right) && !(left == right);
}

function _monthsAdd(Months a, Months b) pure returns (Months sum) {
    sum = Months.wrap(Months.unwrap(a) + Months.unwrap(b));
}

function _timestampLessOrEqual(Timestamp left, Timestamp right) pure returns (bool result) {
    return Timestamp.unwrap(left) <= Timestamp.unwrap(right);
}

function _timestampLess(Timestamp left, Timestamp right) pure returns (bool result) {
    return Timestamp.unwrap(left) < Timestamp.unwrap(right);
}

function _timestampEqual(Timestamp left, Timestamp right) pure returns (bool result) {
    return Timestamp.unwrap(left) == Timestamp.unwrap(right);
}

library DateTimeUtils {
    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function timestamp() internal view returns (Timestamp timestampValue) {
        return Timestamp.wrap(block.timestamp);
    }

    // Conversion functions

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function day(uint256 untypedDay) internal pure returns (Day dayValue) {
        return Day.wrap(untypedDay);
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function months(uint256 untypedMonths) internal pure returns (Months monthsValue) {
        return Months.wrap(untypedMonths);
    }

    // Untyped functions wrappers

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function timestampToDate(Timestamp timestampValue) internal pure returns (Year _year, Month _month, Day dayValue) {
        (uint256 untypedYear, uint256 untypedMonth, uint256 untypedDay) =
            UntypedDateTime.timestampToDate(Timestamp.unwrap(timestampValue));
        return (Year.wrap(untypedYear), Month.wrap(untypedMonth), Day.wrap(untypedDay));
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function timestampFromDate(Year year, Month month, Day dayValue) internal pure returns (Timestamp timestampValue) {
        timestampValue = Timestamp.wrap(UntypedDateTime.timestampFromDate(
            Year.unwrap(year),
            Month.unwrap(month),
            Day.unwrap(dayValue)
        ));
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function addSeconds(Timestamp timestampValue, Seconds secondsValue) internal pure returns (Timestamp newTimestamp) {
        newTimestamp = Timestamp.wrap(
            UntypedDateTime.addSeconds(
                Timestamp.unwrap(timestampValue),
                Seconds.unwrap(secondsValue)
            )
        );
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function addMonths(Timestamp timestampValue, Months monthsValue) internal pure returns (Timestamp newTimestamp) {
        newTimestamp = Timestamp.wrap(
            UntypedDateTime.addMonths(
                Timestamp.unwrap(timestampValue),
                Months.unwrap(monthsValue)
            )
        );
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function subSeconds(Timestamp timestampValue, Seconds secondsValue) internal pure returns (Timestamp newTimestamp) {
        newTimestamp = Timestamp.wrap(
            UntypedDateTime.subSeconds(
                Timestamp.unwrap(timestampValue),
                Seconds.unwrap(secondsValue)
            )
        );
    }

    // Operations

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function add(Timestamp timestampValue, Seconds secondsValue) internal pure returns (Timestamp newTimestamp) {
        newTimestamp = addSeconds(timestampValue, secondsValue);
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function add(Timestamp timestampValue, Months monthsValue) internal pure returns (Timestamp newTimestamp) {
        newTimestamp = addMonths(timestampValue, monthsValue);
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function sub(Timestamp timestampValue, Seconds secondsValue) internal pure returns (Timestamp newTimestamp) {
        newTimestamp = subSeconds(timestampValue, secondsValue);
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function duration(Timestamp from, Timestamp to) internal pure returns (Seconds difference) {
        difference = Seconds.wrap(Timestamp.unwrap(to) - Timestamp.unwrap(from));
    }

    // Auxiliary functions

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function firstDayOfMonth(Timestamp timestampValue) internal pure returns (Timestamp newTimestamp) {
        (Year year, Month month, ) = timestampToDate(timestampValue);
        return timestampFromDate(year, month, day(1));
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function nextMonth(Timestamp timestampValue) internal pure returns (Timestamp newTimestamp) {
        return add(
            firstDayOfMonth(timestampValue),
            months(1)
        );
    }

    // Library internal functions should not have leading underscore
    // solhint-disable-next-line private-vars-leading-underscore
    function min(Timestamp a, Timestamp b) internal pure returns (Timestamp minimum) {
        minimum = Timestamp.wrap(Math.min(Timestamp.unwrap(a), Timestamp.unwrap(b)));
    }
}
