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

import {DateTime as UntypedDateTime} from "@quant-finance/solidity-datetime/contracts/DateTime.sol";


type Seconds is uint256;
type Day is uint256;
type Month is uint256;
type Months is uint256;
type Year is uint256;

type Timestamp is uint256;

using DateTimeUtils for Timestamp global;

library DateTimeUtils {
    function timestamp() internal view returns (Timestamp timestampValue) {
        return Timestamp.wrap(block.timestamp);
    }

    // Conversion functions

    function day(uint256 untypedDay) internal pure returns (Day dayValue) {
        return Day.wrap(untypedDay);
    }

    function months(uint256 untypedMonths) internal pure returns (Months monthsValue) {
        return Months.wrap(untypedMonths);
    }

    // Untyped functions wrappers

    function timestampToDate(Timestamp timestampValue) internal pure returns (Year _year, Month _month, Day dayValue) {
        (uint256 untypedYear, uint256 untypedMonth, uint256 untypedDay) =
            UntypedDateTime.timestampToDate(Timestamp.unwrap(timestampValue));
        return (Year.wrap(untypedYear), Month.wrap(untypedMonth), Day.wrap(untypedDay));
    }

    function timestampFromDate(Year year, Month month, Day dayValue) internal pure returns (Timestamp timestampValue) {
        timestampValue = Timestamp.wrap(UntypedDateTime.timestampFromDate(
            Year.unwrap(year),
            Month.unwrap(month),
            Day.unwrap(dayValue)
        ));
    }

    function addMonths(Timestamp timestampValue, Months monthsValue) internal pure returns (Timestamp newTimestamp) {
        newTimestamp = Timestamp.wrap(
            UntypedDateTime.addMonths(
                Timestamp.unwrap(timestampValue),
                Months.unwrap(monthsValue)
            )
        );
    }

    // Operations

    function add(Timestamp timestampValue, Months monthsValue) internal pure returns (Timestamp newTimestamp) {
        newTimestamp = timestampValue.addMonths(monthsValue);
    }

    // Auxiliary functions

    function firstDayOfMonth(Timestamp timestampValue) internal pure returns (Timestamp newTimestamp) {
        (Year year, Month month, ) = timestampToDate(timestampValue);
        return timestampFromDate(year, month, day(1));
    }

    function nextMonth(Timestamp timestampValue) internal pure returns (Timestamp newTimestamp) {
        return timestampValue.firstDayOfMonth().add(months(1));
    }
}
