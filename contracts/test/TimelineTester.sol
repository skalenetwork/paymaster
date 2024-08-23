// SPDX-License-Identifier: AGPL-3.0-only

/*
    TimelineTester.sol - Paymaster
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

// cspell:words structs

import { Timestamp } from "@skalenetwork/paymaster-interfaces/DateTimeUtils.sol";
import { ITimelineTester } from "./../interfaces/test/ITimelineTester.sol";
import { TimelineLibrary } from "./../Timeline.sol";


contract TimelineTester is ITimelineTester {
    using TimelineLibrary for TimelineLibrary.Timeline;

    TimelineLibrary.Timeline private _timeline;

    function process(Timestamp until) external override {
        _timeline.process(until);
    }

    function add(Timestamp from, Timestamp to, uint256 value) external override {
        _timeline.add(from, to, value);
    }

    function clear(Timestamp before) external override {
        _timeline.clear(before);
    }

    function getSum(Timestamp from, Timestamp to) external view override returns (uint256 sum) {
        return _timeline.getSum(from, to);
    }
}
