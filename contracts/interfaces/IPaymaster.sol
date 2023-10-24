// SPDX-License-Identifier: AGPL-3.0-only

/*
    IPaymaster.sol - Paymaster
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


type SchainHash is bytes32;
type ValidatorId is uint256;

interface IPaymaster {
    function addSchain(string calldata name) external;
    function removeSchain(SchainHash schainHash) external;
    function addValidator(ValidatorId id) external;
    function removeValidator(ValidatorId id) external;
}
