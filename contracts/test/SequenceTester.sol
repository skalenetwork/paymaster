// SPDX-License-Identifier: AGPL-3.0-only

/*
    SequenceTester.sol - Paymaster
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

import {ISequenceTester} from "../interfaces/test/ISequenceTester.sol";
import {SequenceLibrary} from "../Sequence.sol";
import {Timestamp} from "../DateTimeUtils.sol";


contract SequenceTester is ISequenceTester {
    using SequenceLibrary for SequenceLibrary.Sequence;

    SequenceLibrary.Sequence private _sequence;

    function add(Timestamp timestamp, uint256 value) external override {
        _sequence.add(timestamp, value);
    }

    function getValueByTimestamp(Timestamp timestamp)
        external
        view
        override
        returns (uint256 value)
    {
        return _sequence.getValueByTimestamp(timestamp);
    }
}
