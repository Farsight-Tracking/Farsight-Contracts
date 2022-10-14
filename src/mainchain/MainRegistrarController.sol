//SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "../lib/utils/Ownable.sol";
import "./IMainRegistrarController.sol";
import "./PaymentProviders/IPaymentProvider.sol";
import "./IMainRegistrar.sol";
import "../lib/Axelar/IAxelarGateway.sol";

contract MainRegistrarController is IMainRegistrarController, Ownable {
    /**********\
    |* Errors *|
    \**********/
    error UnexpiredCommitmentExists();
    error CommitmentTooNew();
    error CommitmentTooOld();
    error RegisterDurationTooShort(uint256 minimum, uint256 given);
    error RenewDurationTooShort(uint256 minimum, uint256 given);
    error MustBeNameOwner(address owner, address given);

    error NameTooShort(uint256 minimum, uint256 given);
    error NameTooLong(uint256 maxmimum, uint256 given);

    error DuplicateChainIdAddition(uint256 chainId);
    error UnsupportedOrInvalidChainId(uint256 chainId);
    error ChainIdNotAtGivenIndex(uint256 chainId, uint256 index);

    /**********\
    |* Events *|
    \**********/
    event PaymentProviderChanged(IPaymentProvider previous, IPaymentProvider current);
    event MinRegisterDurationChanged(uint256 previous, uint256 current);
    event MinRenewDurationChanged(uint256 previous, uint256 current);

    event MinNameLengthChanged(uint256 previous, uint256 current);
    event MaxNameLengthChanged(uint256 previous, uint256 current);

    event ChainAdded(uint256 indexed chainId, string indexed targetPropagatorAddress);
    event ChainRemoved(uint256 indexed chainId);

    /***********\
    |* Structs *|
    \***********/
    struct ChainDefinition {
        bool isValid;
        string name;
        string targetAddress;
    }
    

    uint256 public immutable minCommitmentAge;
    uint256 public immutable maxCommitmentAge;

    mapping(bytes32 => uint256) private commitments;    

    IMainRegistrar public immutable registrar;

    IPaymentProvider public paymentProvider;

    uint256 public minRegisterDuration;
    uint256 public minRenewDuration;

    uint256 public minNameLength;
    uint256 public maxNameLength;

    IAxelarGateway private immutable axelarGateway;

    uint256[] public supportedChains;
    mapping(uint256 => ChainDefinition) private chainDefinitions;

    constructor(uint256 _minCommitmentAge,
                uint256 _maxCommitmentAge, 
                IMainRegistrar _registrar,
                IPaymentProvider _paymentProvider,
                uint256 _minRegisterDuration,
                uint256 _minRenewDuration,
                uint256 _minNameLength,
                uint256 _maxNameLength,
                IAxelarGateway _axelarGateway
    ) {
        require(_minCommitmentAge < _maxCommitmentAge);
        require(_maxCommitmentAge > 0);

        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;

        registrar = _registrar;
        paymentProvider = _paymentProvider;

        minRegisterDuration = _minRegisterDuration;
        minRenewDuration = _minRenewDuration;

        minNameLength = _minNameLength;
        maxNameLength = _maxNameLength;

        axelarGateway = _axelarGateway;
    }

    /***********\
    |* Getters *|
    \***********/

    function available(uint256 name) public view returns (bool) {
        return registrar.available(name);
    }

    /***********\
    |* Setters *|
    \***********/

    function commit(bytes32 commitment) external override {
        if (commitments[commitment] + maxCommitmentAge >= block.timestamp) { revert UnexpiredCommitmentExists(); }

        commitments[commitment] = block.timestamp;
    } 
    
    function register(string calldata plainName, address owner, uint256 duration, bytes32 secret) external returns (uint256) {
        if (duration < minRegisterDuration) { revert RegisterDurationTooShort(minRegisterDuration, duration); }

        uint256 length = utfStringLength(plainName);

        if (length < minNameLength) { revert NameTooShort(minNameLength, length); }
        if (length > maxNameLength) { revert NameTooLong(maxNameLength, length); }

        uint256 name = uint256(keccak256(bytes(plainName)));

        //Payment provider should revert if payment unsuccessful
        paymentProvider.collectPayment(msg.sender, plainName, registrar.nameExpires(name), duration); 

        _consumeCommitment(name, owner, duration, secret);

        return registrar.register(name, owner, duration);
    }

    function renew(string calldata plainName, uint256 duration) external returns (uint256) {
        if (duration < minRenewDuration) { revert RenewDurationTooShort(minRenewDuration, duration); }

        uint256 name = uint256(keccak256(bytes(plainName)));

        paymentProvider.collectPayment(msg.sender, plainName, _max(block.timestamp, registrar.nameExpires(name)), duration);

        return registrar.renew(name, duration);
    }

    /***********************\
    |* Cross Chain Setters *|
    \***********************/

    function sendNameUpdate(uint256 chainId, uint256 name, string calldata owner) external {
        if (!chainDefinitions[chainId].isValid) { revert UnsupportedOrInvalidChainId(chainId); }
        if (registrar.ownerOf(name) != msg.sender) {
            revert MustBeNameOwner(registrar.ownerOf(name), msg.sender);
        }

        axelarGateway.callContract(
            chainDefinitions[chainId].name, 
            chainDefinitions[chainId].targetAddress, 
            abi.encode(name, owner, registrar.nameExpires(name), registrar.nameVersion(name))
        );
    }

    /*******************\
    |* Admin Functions *|
    \*******************/

    function setPaymentProvider(IPaymentProvider _paymentProvider) external onlyOwner {
        require(paymentProvider != _paymentProvider);

        emit PaymentProviderChanged(paymentProvider, _paymentProvider);
        paymentProvider = _paymentProvider;
    }

    function setMinRegisterDuration(uint256 _minRegisterDuration) external onlyOwner {
        require(minRegisterDuration != _minRegisterDuration);

        emit MinRegisterDurationChanged(minRegisterDuration, _minRegisterDuration);
        minRegisterDuration = _minRegisterDuration;
    }

    function setMinRenewDuration(uint256 _minRenewDuration) external onlyOwner {
        require(minRenewDuration != _minRenewDuration);

        emit MinRenewDurationChanged(minRenewDuration, _minRenewDuration);
        minRenewDuration = _minRenewDuration;
    }

    function setMinNameLength(uint256 _minNameLength) external onlyOwner {
        require(minNameLength != _minNameLength);

        emit MinNameLengthChanged(minNameLength, _minNameLength);
        minNameLength = _minNameLength;
    }

    function setMaxNameLength(uint256 _maxNameLength) external onlyOwner {
        require(maxNameLength != _maxNameLength);

        emit MinRenewDurationChanged(maxNameLength, _maxNameLength);
        maxNameLength = _maxNameLength;
    }

    function addChain(uint256 chainId, string calldata targetPropagatorAddress, string calldata chainName) external onlyOwner {
        if(chainDefinitions[chainId].isValid) { revert DuplicateChainIdAddition(chainId); }

        supportedChains.push(chainId);
        chainDefinitions[chainId] = ChainDefinition({
            isValid: true,
            name: chainName, 
            targetAddress: targetPropagatorAddress
        });

        emit ChainAdded(chainId, targetPropagatorAddress);
    }

    function removeChain(uint256 chainId, uint256 arrayIndex) external onlyOwner {
        if (!chainDefinitions[chainId].isValid) { revert UnsupportedOrInvalidChainId(chainId); }
        if (supportedChains[arrayIndex] != chainId) { revert ChainIdNotAtGivenIndex(chainId, arrayIndex); }

        supportedChains[arrayIndex] = supportedChains[supportedChains.length - 1];
        supportedChains.pop();

        emit ChainRemoved(chainId);
    }

    /**********************\
    |* Internal Functions *|
    \**********************/

    // Returns the larger of two numbers
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function _consumeCommitment(uint256 name, address owner, uint256 duration, bytes32 secret) internal {
        bytes32 commitment = keccak256(abi.encodePacked(name, owner, duration, secret));

        if (commitments[commitment] + minCommitmentAge > block.timestamp) { revert CommitmentTooNew(); }
        if (commitments[commitment] + maxCommitmentAge <= block.timestamp) { revert CommitmentTooOld(); }

        delete (commitments[commitment]);
    }

    function utfStringLength(string memory str) pure internal returns (uint256 length) {
        uint256 i = 0;
        bytes memory string_rep = bytes(str);

        while (i < string_rep.length)
        {
            if (string_rep[i]>>7==0)
                i+=1;
            else if (string_rep[i]>>5==bytes1(uint8(0x6)))
                i+=2;
            else if (string_rep[i]>>4==bytes1(uint8(0xE)))
                i+=3;
            else if (string_rep[i]>>3==bytes1(uint8(0x1E)))
                i+=4;
            else
                //For safety
                i+=1;

            length++;
        }
    }
}