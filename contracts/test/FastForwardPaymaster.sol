// SPDX-License-Identifier: AGPL-3.0-only

/*
    FastForwardPaymaster.sol - Paymaster
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

import {DateTimeUtils, Paymaster, Seconds, Timestamp} from "../Paymaster.sol";
import {IFastForwardPaymaster} from "../interfaces/test/IFastForwardPaymaster.sol";


contract FastForwardPaymaster is Paymaster, IFastForwardPaymaster {
    using DateTimeUtils for Timestamp;

    struct CheckPoint {
        Timestamp realTime;
        Timestamp effectiveTime;
    }

    CheckPoint public checkPoint;
    uint256 public timeMultiplier = 1e18;

    function skipTime(Seconds sec) external override {
        checkPoint.realTime = super._getTimestamp();
        checkPoint.effectiveTime = _getTimestamp().add(sec);
    }

    function setTimeMultiplier(uint256 multiplier) external override {
        checkPoint.realTime = super._getTimestamp();
        checkPoint.effectiveTime = _getTimestamp();
        timeMultiplier = multiplier;
    }

    function effectiveTimestamp() external view override returns (Timestamp timestamp) {
        return _getTimestamp();
    }

    // Internal

    function _getTimestamp() internal view override returns (Timestamp timestamp) {
        Seconds passed = DateTimeUtils.duration(checkPoint.realTime, super._getTimestamp());
        Seconds diff = Seconds.wrap(Seconds.unwrap(passed) * timeMultiplier / 1e18);
        return checkPoint.effectiveTime.add(diff);
    }

    // Private
}
