// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ITrustedIssuersRegistry, IIdentity} from "../interfaces/ITrustedIssuersRegistry.sol";

/**
 * @title TrustedIssuersRegistry
 * @notice Manages trusted claim issuers for identity verification
 * @dev Issuers can issue claims for specific topics (KYC, AML, etc.)
 */
contract TrustedIssuersRegistry is ITrustedIssuersRegistry, AccessControl {
    // ==================== ROLES ====================
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // ==================== STATE VARIABLES ====================

    // Issuer data structure
    struct IssuerData {
        IIdentity identity; // ONCHAINID of the issuer
        uint256[] claimTopics; // Topics this issuer can certify
        bool exists; // Flag for existence check
        uint256 index; // Index in trustedIssuers array
    }

    // Array of trusted issuer addresses
    address[] private trustedIssuers;

    // Mapping from issuer address to issuer data
    mapping(address => IssuerData) private issuerData;

    // Mapping: claimTopic => array of issuers authorized for that topic
    mapping(uint256 => address[]) private issuersByTopic;

    // Mapping: claimTopic => issuer => index in issuersByTopic array
    mapping(uint256 => mapping(address => uint256)) private issuerTopicIndex;

    // Mapping: claimTopic => issuer => exists flag
    mapping(uint256 => mapping(address => bool)) private issuerHasTopic;

    // ==================== EVENTS ====================

    event TrustedIssuerAdded(address indexed trustedIssuer, address indexed identity, uint256[] claimTopics);
    event TrustedIssuerRemoved(address indexed trustedIssuer);
    event ClaimTopicsUpdated(address indexed trustedIssuer, uint256[] claimTopics);

    // ==================== CONSTRUCTOR ====================

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    // ==================== ISSUER MANAGEMENT ====================

    /**
     * @notice Add a trusted issuer
     * @param _trustedIssuer Address of the issuer
     * @param _claimTopics Array of claim topics the issuer can certify
     */
    function addTrustedIssuer(address _trustedIssuer, address _issuerIdentity, uint256[] calldata _claimTopics)
        external
        override
        onlyRole(MANAGER_ROLE)
    {
        require(_trustedIssuer != address(0), "Invalid issuer address");
        require(_issuerIdentity != address(0), "Invalid identity address");
        require(!issuerData[_trustedIssuer].exists, "Issuer already exists");
        require(_claimTopics.length > 0, "Must specify at least one claim topic");

        IssuerData storage data = issuerData[_trustedIssuer];
        data.identity = IIdentity(_issuerIdentity);
        data.claimTopics = _claimTopics;
        data.exists = true;
        data.index = trustedIssuers.length;

        trustedIssuers.push(_trustedIssuer);

        for (uint256 i = 0; i < _claimTopics.length; i++) {
            uint256 topic = _claimTopics[i];
            if (!issuerHasTopic[topic][_trustedIssuer]) {
                issuerTopicIndex[topic][_trustedIssuer] = issuersByTopic[topic].length;
                issuersByTopic[topic].push(_trustedIssuer);
                issuerHasTopic[topic][_trustedIssuer] = true;
            }
        }

        emit TrustedIssuerAdded(_trustedIssuer, _issuerIdentity, _claimTopics);
    }

    /**
     * @notice Remove a trusted issuer
     * @param _trustedIssuer Address of the issuer to remove
     */
    function removeTrustedIssuer(address _trustedIssuer) external override onlyRole(MANAGER_ROLE) {
        require(issuerData[_trustedIssuer].exists, "Issuer does not exist");

        IssuerData storage data = issuerData[_trustedIssuer];

        // Remove from topic mappings
        for (uint256 i = 0; i < data.claimTopics.length; i++) {
            uint256 topic = data.claimTopics[i];

            if (issuerHasTopic[topic][_trustedIssuer]) {
                uint256 topicIndex = issuerTopicIndex[topic][_trustedIssuer];
                uint256 lastTopicIndex = issuersByTopic[topic].length - 1;

                if (topicIndex != lastTopicIndex) {
                    address lastIssuer = issuersByTopic[topic][lastTopicIndex];
                    issuersByTopic[topic][topicIndex] = lastIssuer;
                    issuerTopicIndex[topic][lastIssuer] = topicIndex;
                }

                issuersByTopic[topic].pop();
                delete issuerTopicIndex[topic][_trustedIssuer];
                delete issuerHasTopic[topic][_trustedIssuer];
            }
        }

        // Remove from trustedIssuers array
        uint256 index = data.index;
        uint256 lastIndex = trustedIssuers.length - 1;

        if (index != lastIndex) {
            address lastIssuer = trustedIssuers[lastIndex];
            trustedIssuers[index] = lastIssuer;
            issuerData[lastIssuer].index = index;
        }

        trustedIssuers.pop();
        delete issuerData[_trustedIssuer];

        emit TrustedIssuerRemoved(_trustedIssuer);
    }

    /**
     * @notice Update claim topics for an issuer
     * @param _trustedIssuer Address of the issuer
     * @param _claimTopics New array of claim topics
     */
    function updateIssuerClaimTopics(address _trustedIssuer, uint256[] calldata _claimTopics)
        external
        override
        onlyRole(MANAGER_ROLE)
    {
        require(issuerData[_trustedIssuer].exists, "Issuer does not exist");
        require(_claimTopics.length > 0, "Must specify at least one claim topic");

        IssuerData storage data = issuerData[_trustedIssuer];

        // Remove old topics
        for (uint256 i = 0; i < data.claimTopics.length; i++) {
            uint256 topic = data.claimTopics[i];

            if (issuerHasTopic[topic][_trustedIssuer]) {
                uint256 topicIndex = issuerTopicIndex[topic][_trustedIssuer];
                uint256 lastTopicIndex = issuersByTopic[topic].length - 1;

                if (topicIndex != lastTopicIndex) {
                    address lastIssuer = issuersByTopic[topic][lastTopicIndex];
                    issuersByTopic[topic][topicIndex] = lastIssuer;
                    issuerTopicIndex[topic][lastIssuer] = topicIndex;
                }

                issuersByTopic[topic].pop();
                delete issuerTopicIndex[topic][_trustedIssuer];
                delete issuerHasTopic[topic][_trustedIssuer];
            }
        }

        // Add new topics
        data.claimTopics = _claimTopics;

        for (uint256 i = 0; i < _claimTopics.length; i++) {
            uint256 topic = _claimTopics[i];

            if (!issuerHasTopic[topic][_trustedIssuer]) {
                issuerTopicIndex[topic][_trustedIssuer] = issuersByTopic[topic].length;
                issuersByTopic[topic].push(_trustedIssuer);
                issuerHasTopic[topic][_trustedIssuer] = true;
            }
        }

        emit ClaimTopicsUpdated(_trustedIssuer, _claimTopics);
    }

    /**
     * @notice Batch add trusted issuers
     */
    function batchAddTrustedIssuers(
        address[] calldata _trustedIssuers,
        address[] calldata _issuerIdentities,
        uint256[][] calldata _claimTopicsArray
    ) external onlyRole(MANAGER_ROLE) {
        require(
            _trustedIssuers.length == _issuerIdentities.length && _trustedIssuers.length == _claimTopicsArray.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < _trustedIssuers.length; i++) {
            address issuer = _trustedIssuers[i];
            address issuerIdentity = _issuerIdentities[i];
            uint256[] memory topics = _claimTopicsArray[i];

            if (!issuerData[issuer].exists && issuer != address(0) && issuerIdentity != address(0) && topics.length > 0)
            {
                IssuerData storage data = issuerData[issuer];
                data.identity = IIdentity(issuerIdentity);
                data.claimTopics = topics;
                data.exists = true;
                data.index = trustedIssuers.length;

                trustedIssuers.push(issuer);

                for (uint256 j = 0; j < topics.length; j++) {
                    uint256 topic = topics[j];
                    if (!issuerHasTopic[topic][issuer]) {
                        issuerTopicIndex[topic][issuer] = issuersByTopic[topic].length;
                        issuersByTopic[topic].push(issuer);
                        issuerHasTopic[topic][issuer] = true;
                    }
                }

                emit TrustedIssuerAdded(issuer, issuerIdentity, topics);
            }
        }
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get all trusted issuers
     */
    function getTrustedIssuers() external view override returns (address[] memory) {
        return trustedIssuers;
    }

    /**
     * @notice Get trusted issuers for a specific claim topic
     */
    function getTrustedIssuersForClaimTopic(uint256 _claimTopic) external view override returns (address[] memory) {
        return issuersByTopic[_claimTopic];
    }

    /**
     * @notice Check if address is a trusted issuer
     */
    function isTrustedIssuer(address _issuer) external view override returns (bool) {
        return issuerData[_issuer].exists;
    }

    /**
     * @notice Check if issuer has a specific claim topic
     */
    function hasClaimTopic(address _issuer, uint256 _claimTopic) external view override returns (bool) {
        return issuerHasTopic[_claimTopic][_issuer];
    }

    /**
     * @notice Get claim topics for an issuer
     */
    function getTrustedIssuerClaimTopics(address _trustedIssuer) external view override returns (uint256[] memory) {
        require(issuerData[_trustedIssuer].exists, "Issuer does not exist");
        return issuerData[_trustedIssuer].claimTopics;
    }

    /**
     * @notice Get identity contract for an issuer
     */
    function getTrustedIssuerIdentity(address _trustedIssuer) external view override returns (IIdentity) {
        require(issuerData[_trustedIssuer].exists, "Issuer does not exist");
        return issuerData[_trustedIssuer].identity;
    }

    /**
     * @notice Get number of trusted issuers
     */
    function getTrustedIssuerCount() external view returns (uint256) {
        return trustedIssuers.length;
    }

    /**
     * @notice Get trusted issuer at index
     */
    function getTrustedIssuerAtIndex(uint256 _index) external view returns (address) {
        require(_index < trustedIssuers.length, "Index out of bounds");
        return trustedIssuers[_index];
    }

    /**
     * @notice Get number of issuers for a claim topic
     */
    function getIssuerCountForTopic(uint256 _claimTopic) external view returns (uint256) {
        return issuersByTopic[_claimTopic].length;
    }
}
