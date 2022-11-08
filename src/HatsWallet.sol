// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "hats-auth/HatsOwned.sol";

contract HatsWallet is HatsOwned {
    error CallFailed();
    error CannotChangeHat();
    constructor(address _hats, uint256 _hatId) HatsOwned(_hatId, _hats) {}
        
    function execute(address _target, bytes calldata _data) onlyOwner external payable {
        (bool success, bytes memory data) = _target.call{value: msg.value}(_data);

        if (!success) revert CallFailed();
    }

    receive() external payable {}

    function setOwnerHat(uint256 _ownerHat, address _hatsContract)
        public
        override
        onlyOwner {
            revert CannotChangeHat();
        }
}
