// SPDX-License-Identifier: MIT

pragma solidity >=0.8.17;

interface IMainRegistrarController {
    function commit(bytes32 commitment) external; 
    function register(string calldata plainName, address owner, uint256 duration, bytes32 secret) external returns (uint256);
    function renew(string calldata plainName, uint256 duration) external returns (uint256);

    function addChain(uint256 chainId, string calldata targetPropagatorAddress, string calldata chainName) external;
    function removeChain(uint256 chainId, uint256 arrayIndex) external;

    function sendNameUpdate(uint256 chainId, uint256 name, string calldata owner) external payable;
}