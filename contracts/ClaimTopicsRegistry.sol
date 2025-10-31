// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IClaimTopicsRegistry} from "../interfaces/IClaimTopicsRegistry.sol";

/**
 * @title ClaimTopicsRegistry
 * @notice Manages required claim topics for KYC/AML verification
 * @dev Claim topics are uint256 identifiers for different types of claims
 *
 * COMMON CLAIM TOPICS:
 * - 1: KYC (Know Your Customer)
 * - 2: AML (Anti-Money Laundering)
 * - 3: Accredited Investor
 * - 4: Country of Residence
 * - 5: Identity Verification
 */
contract ClaimTopicsRegistry is IClaimTopicsRegistry, AccessControl {
    // ==================== ROLES ====================
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // ==================== STATE VARIABLES ====================

    // Array of claim topics
    uint256[] private claimTopics;

    // Mapping for O(1) lookup
    mapping(uint256 => bool) private claimTopicExists;

    // Mapping from topic to index in array
    mapping(uint256 => uint256) private claimTopicIndex;

    // ==================== EVENTS ====================

    event ClaimTopicAdded(uint256 indexed claimTopic);
    event ClaimTopicRemoved(uint256 indexed claimTopic);

    // ==================== CONSTRUCTOR ====================

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    // ==================== CLAIM TOPIC MANAGEMENT ====================

    /**
     * @notice Add a claim topic
     * @param _claimTopic Topic identifier to add
     */
    function addClaimTopic(uint256 _claimTopic) external override onlyRole(MANAGER_ROLE) {
        require(!claimTopicExists[_claimTopic], "Claim topic already exists");

        claimTopicIndex[_claimTopic] = claimTopics.length;
        claimTopics.push(_claimTopic);
        claimTopicExists[_claimTopic] = true;

        emit ClaimTopicAdded(_claimTopic);
    }

    /**
     * @notice Remove a claim topic
     * @param _claimTopic Topic identifier to remove
     */
    function removeClaimTopic(uint256 _claimTopic) external override onlyRole(MANAGER_ROLE) {
        require(claimTopicExists[_claimTopic], "Claim topic does not exist");

        uint256 index = claimTopicIndex[_claimTopic];
        uint256 lastIndex = claimTopics.length - 1;

        // Swap with last element and pop
        if (index != lastIndex) {
            uint256 lastTopic = claimTopics[lastIndex];
            claimTopics[index] = lastTopic;
            claimTopicIndex[lastTopic] = index;
        }

        claimTopics.pop();
        delete claimTopicIndex[_claimTopic];
        delete claimTopicExists[_claimTopic];

        emit ClaimTopicRemoved(_claimTopic);
    }

    /**
     * @notice Batch add claim topics
     */
    function batchAddClaimTopics(uint256[] calldata _claimTopics) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < _claimTopics.length; i++) {
            if (!claimTopicExists[_claimTopics[i]]) {
                claimTopicIndex[_claimTopics[i]] = claimTopics.length;
                claimTopics.push(_claimTopics[i]);
                claimTopicExists[_claimTopics[i]] = true;

                emit ClaimTopicAdded(_claimTopics[i]);
            }
        }
    }

    /**
     * @notice Batch remove claim topics
     */
    function batchRemoveClaimTopics(uint256[] calldata _claimTopics) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < _claimTopics.length; i++) {
            if (claimTopicExists[_claimTopics[i]]) {
                uint256 index = claimTopicIndex[_claimTopics[i]];
                uint256 lastIndex = claimTopics.length - 1;

                if (index != lastIndex) {
                    uint256 lastTopic = claimTopics[lastIndex];
                    claimTopics[index] = lastTopic;
                    claimTopicIndex[lastTopic] = index;
                }

                claimTopics.pop();
                delete claimTopicIndex[_claimTopics[i]];
                delete claimTopicExists[_claimTopics[i]];

                emit ClaimTopicRemoved(_claimTopics[i]);
            }
        }
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get all claim topics
     */
    function getClaimTopics() external view override returns (uint256[] memory) {
        return claimTopics;
    }

    /**
     * @notice Check if claim topic exists
     */
    function isClaimTopic(uint256 _claimTopic) external view returns (bool) {
        return claimTopicExists[_claimTopic];
    }

    /**
     * @notice Get number of claim topics
     */
    function getClaimTopicCount() external view returns (uint256) {
        return claimTopics.length;
    }

    /**
     * @notice Get claim topic at index
     */
    function getClaimTopicAtIndex(uint256 _index) external view returns (uint256) {
        require(_index < claimTopics.length, "Index out of bounds");
        return claimTopics[_index];
    }
}
