// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IIdentityRegistryStorage} from "../interfaces/IIdentityRegistryStorage.sol";

/**
 * @title IdentityRegistryStorage
 * @notice Stores identity mappings for the Identity Registry
 * @dev Separated storage pattern for upgradeability
 */
contract IdentityRegistryStorage is IIdentityRegistryStorage, AccessControl {
    // ==================== ROLES ====================
    bytes32 public constant REGISTRY_ROLE = keccak256("REGISTRY_ROLE");

    // ==================== STATE VARIABLES ====================

    // Mapping from user address to identity contract
    mapping(address => address) private identities;

    // Mapping from user address to country code
    mapping(address => uint16) private investorCountries;

    // Array of all registered addresses
    address[] private registeredAddresses;

    // Mapping to track if address is registered (for O(1) lookup)
    mapping(address => bool) private registered;

    // Mapping from address to index in registeredAddresses array
    mapping(address => uint256) private addressIndex;

    // ==================== EVENTS ====================

    event IdentityStored(address indexed userAddress, address indexed identity);
    event IdentityRemoved(address indexed userAddress, address indexed identity);
    event IdentityModified(address indexed userAddress, address indexed oldIdentity, address indexed newIdentity);
    event CountryModified(address indexed userAddress, uint16 indexed oldCountry, uint16 indexed newCountry);

    // ==================== CONSTRUCTOR ====================

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REGISTRY_ROLE, msg.sender);
    }

    // ==================== STORAGE MANAGEMENT ====================

    /**
     * @notice Add identity to storage
     * @dev Only callable by authorized registry contracts
     */
    function addIdentityToStorage(address _userAddress, address _identity, uint16 _country)
        external
        override
        onlyRole(REGISTRY_ROLE)
    {
        require(_userAddress != address(0), "Invalid user address");
        require(_identity != address(0), "Invalid identity address");
        require(!registered[_userAddress], "Address already registered");

        identities[_userAddress] = _identity;
        investorCountries[_userAddress] = _country;
        registered[_userAddress] = true;

        addressIndex[_userAddress] = registeredAddresses.length;
        registeredAddresses.push(_userAddress);

        emit IdentityStored(_userAddress, _identity);
    }

    /**
     * @notice Remove identity from storage
     */
    function removeIdentityFromStorage(address _userAddress) external override onlyRole(REGISTRY_ROLE) {
        require(registered[_userAddress], "Address not registered");

        address identity = identities[_userAddress];

        // Remove from mappings
        delete identities[_userAddress];
        delete investorCountries[_userAddress];
        delete registered[_userAddress];

        // Remove from array (swap with last element and pop)
        uint256 index = addressIndex[_userAddress];
        uint256 lastIndex = registeredAddresses.length - 1;

        if (index != lastIndex) {
            address lastAddress = registeredAddresses[lastIndex];
            registeredAddresses[index] = lastAddress;
            addressIndex[lastAddress] = index;
        }

        registeredAddresses.pop();
        delete addressIndex[_userAddress];

        emit IdentityRemoved(_userAddress, identity);
    }

    /**
     * @notice Modify stored identity
     */
    function modifyStoredIdentity(address _userAddress, address _identity) external override onlyRole(REGISTRY_ROLE) {
        require(registered[_userAddress], "Address not registered");
        require(_identity != address(0), "Invalid identity address");

        address oldIdentity = identities[_userAddress];
        identities[_userAddress] = _identity;

        emit IdentityModified(_userAddress, oldIdentity, _identity);
    }

    /**
     * @notice Modify stored investor country
     */
    function modifyStoredInvestorCountry(address _userAddress, uint16 _country)
        external
        override
        onlyRole(REGISTRY_ROLE)
    {
        require(registered[_userAddress], "Address not registered");

        uint16 oldCountry = investorCountries[_userAddress];
        investorCountries[_userAddress] = _country;

        emit CountryModified(_userAddress, oldCountry, _country);
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get stored identity for user
     */
    function storedIdentity(address _userAddress) external view override returns (address) {
        return identities[_userAddress];
    }

    /**
     * @notice Get stored country for user
     */
    function storedInvestorCountry(address _userAddress) external view override returns (uint16) {
        return investorCountries[_userAddress];
    }

    /**
     * @notice Check if address is registered
     */
    function contains(address _userAddress) external view override returns (bool) {
        return registered[_userAddress];
    }

    /**
     * @notice Get all registered addresses
     */
    function getRegisteredAddresses() external view returns (address[] memory) {
        return registeredAddresses;
    }

    /**
     * @notice Get count of registered addresses
     */
    function getRegisteredAddressCount() external view returns (uint256) {
        return registeredAddresses.length;
    }

    /**
     * @notice Get registered address at index
     */
    function getRegisteredAddressAtIndex(uint256 _index) external view returns (address) {
        require(_index < registeredAddresses.length, "Index out of bounds");
        return registeredAddresses[_index];
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @notice Grant registry role to address
     */
    function addRegistryRole(address _registry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(REGISTRY_ROLE, _registry);
    }

    /**
     * @notice Revoke registry role from address
     */
    function removeRegistryRole(address _registry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(REGISTRY_ROLE, _registry);
    }
}
