// SPDX-License-Identifier: AGPL-3.0-only

/*
    ISequenceTester.sol - Paymaster
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

import {Timestamp} from "../../DateTimeUtils.sol";


interface ISequenceTester {
    function add(Timestamp timestamp, uint256 value) external;
    function clear(Timestamp before) external;
    function getValueByTimestamp(Timestamp timestamp) external view returns (uint256 value);
}
