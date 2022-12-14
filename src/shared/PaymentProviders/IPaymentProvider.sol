//SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IPaymentProvider {
    /**
     * @dev Collects the payment for a name registration / renewal
     * @param name The name being registered or renewed.
     * @param expires When the name presently expires (0 if this is a new registration).
     * @param duration How long the name is being registered or extended for, in seconds.
     */
    function collectPayment(
        address buyer,
        string calldata name,
        uint256 expires,
        uint256 duration
    ) external;
}
