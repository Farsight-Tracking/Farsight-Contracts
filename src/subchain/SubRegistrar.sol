// SPDX-License-Identifier: MIT

pragma solidity >=0.8.17;

import "../shared/BaseRegistrar.sol";
import "./ISubRegistrar.sol";
import "./ISubNameBridge.sol";
import "../shared/INameBridge.sol";

contract SubRegistrar is BaseRegistrar, ISubRegistrar {
    /**********\
    |* Errors *|
    \**********/
    error NotTransferLocked();
    error TransferLocked();

    mapping(uint256 => bool) transferLocks;

    ISubNameBridge subNameBridge;

    constructor(ISubNameBridge _subNameBridge) 
        BaseRegistrar()
    {
        subNameBridge = _subNameBridge;
    }

    /********************\
    |* ERC721 Overrides *|
    \********************/
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
        if (from == address(0)){
            releaseTransferLock(tokenId);
        } else {
            if (transferLocks[tokenId]) { revert TransferLocked(); }
        }        

        BaseRegistrar._beforeTokenTransfer(from, to, tokenId);
    }

    /***********\
    |* Getters *|
    \***********/
    function getNameBridge() external view returns (ISubNameBridge) {
        return subNameBridge;
    }
    function isTransferLocked(uint256 name) external view returns (bool) {
        return transferLocks[name] && BaseRegistrar.isKeeper(name); 
    }

    /************************\
    |* Controller Functions *|
    \************************/
    function applyTransferLock(uint256 name) external onlyController {
        if (transferLocks[name]) { revert TransferLocked(); }
        transferLocks[name] = true;
    }

    function releaseTransferLock(uint256 name) public onlyController {
        if (!transferLocks[name]) { revert NotTransferLocked(); }
        transferLocks[name] = false;
    }

    /**********************\
    |* Internal Functions *|
    \**********************/
    function _nameBridge() internal view override returns (INameBridge) {
        return subNameBridge;
    }
}