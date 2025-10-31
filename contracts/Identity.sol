// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IIdentity} from "../interfaces/IIdentity.sol";

contract Identity is IIdentity, Ownable {
    uint256 public constant MANAGEMENT_KEY = 1;
    uint256 public constant CLAIM_SIGNER_KEY = 3;

    struct Key {
        uint256[] purposes;
        uint256 keyType; // 1 = ECDSA
    }

    struct Claim {
        uint256 topic;
        uint256 scheme;
        address issuer;
        bytes signature;
        bytes data;
        string uri;
    }

    mapping(address => mapping(uint256 => bytes32[])) private claimIdsByUserAndTopic;
    mapping(bytes32 => Claim) private claims;
    mapping(bytes32 => Key) private keys;

    event KeyAdded(bytes32 indexed key, uint256 purpose, uint256 keyType);
    event KeyRemoved(bytes32 indexed key, uint256 purpose);
    event ClaimAdded(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );
    event ClaimRemoved(bytes32 indexed claimId, uint256 indexed topic, address indexed issuer);

    constructor(address initialOwner) Ownable(initialOwner) {
        _addKey(keccak256(abi.encode(initialOwner)), MANAGEMENT_KEY, 1);
        _addKey(keccak256(abi.encode(initialOwner)), CLAIM_SIGNER_KEY, 1);
    }

    function addKey(bytes32 _key, uint256 _purpose, uint256 _keyType) external onlyOwner {
        require(_key != bytes32(0), "Invalid key");
        require(_keyType == 1, "Only ECDSA key type supported");
        require(_purpose == MANAGEMENT_KEY || _purpose == CLAIM_SIGNER_KEY, "Unsupported purpose");
        _addKey(_key, _purpose, _keyType);
    }

    function _addKey(bytes32 _key, uint256 _purpose, uint256 _keyType) internal {
        Key storage key = keys[_key];
        if (key.keyType == 0) {
            key.keyType = _keyType;
        }
        for (uint256 i = 0; i < key.purposes.length; i++) {
            require(key.purposes[i] != _purpose, "Key already has purpose");
        }
        key.purposes.push(_purpose);
        emit KeyAdded(_key, _purpose, _keyType);
    }

    function removeKey(bytes32 _key, uint256 _purpose) external onlyOwner {
        require(keyHasPurpose(_key, _purpose), "Key does not have purpose");
        Key storage key = keys[_key];
        for (uint256 i = 0; i < key.purposes.length; i++) {
            if (key.purposes[i] == _purpose) {
                key.purposes[i] = key.purposes[key.purposes.length - 1];
                key.purposes.pop();
                break;
            }
        }
        if (key.purposes.length == 0) {
            delete keys[_key];
        }
        emit KeyRemoved(_key, _purpose);
    }

    function keyHasPurpose(bytes32 _key, uint256 _purpose) public view override returns (bool) {
        Key storage key = keys[_key];
        for (uint256 i = 0; i < key.purposes.length; i++) {
            if (key.purposes[i] == _purpose) {
                return true;
            }
        }
        return false;
    }

    function addClaim(
        address user,
        uint256 _topic,
        uint256 _scheme,
        address _issuer,
        bytes calldata _signature,
        bytes calldata _data,
        string calldata _uri
    ) external override returns (bytes32) {
        require(user != address(0), "Invalid user address");
        require(_issuer != address(0), "Invalid issuer");
        require(_scheme == 1, "Only ECDSA scheme supported");
        require(msg.sender == _issuer || keyHasPurpose(keccak256(abi.encode(msg.sender)), 3), "Caller not authorized");

        // Encode data to be hashed
        bytes memory encodedData = abi.encode(_issuer, _topic, user, _data);
        bytes32 claimId = keccak256(encodedData);

        // FIX: Match the prefix used in the test script
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", claimId));

        // Verify signature
        (uint8 v, bytes32 r, bytes32 s) = splitSignature(_signature);
        address signer = ecrecover(prefixedHash, v, r, s);
        require(signer == _issuer, "Invalid signature");

        claims[claimId] = Claim(_topic, _scheme, _issuer, _signature, _data, _uri);
        claimIdsByUserAndTopic[user][_topic].push(claimId);
        emit ClaimAdded(claimId, _topic, _scheme, _issuer, _signature, _data, _uri);
        return claimId;
    }

    function removeClaim(address user, bytes32 _claimId) external override returns (bool) {
        require(
            msg.sender == owner() || keyHasPurpose(keccak256(abi.encode(msg.sender)), CLAIM_SIGNER_KEY),
            "Caller not authorized"
        );
        Claim memory claim = claims[_claimId];
        require(claim.topic != 0, "Claim does not exist");
        bytes32[] storage claimIds = claimIdsByUserAndTopic[user][claim.topic];
        for (uint256 i = 0; i < claimIds.length; i++) {
            if (claimIds[i] == _claimId) {
                claimIds[i] = claimIds[claimIds.length - 1];
                claimIds.pop();
                break;
            }
        }
        delete claims[_claimId];
        emit ClaimRemoved(_claimId, claim.topic, claim.issuer);
        return true;
    }

    function getClaim(bytes32 _claimId)
        external
        view
        override
        returns (
            uint256 topic,
            uint256 scheme,
            address issuer,
            bytes memory signature,
            bytes memory data,
            string memory uri
        )
    {
        Claim memory claim = claims[_claimId];
        return (claim.topic, claim.scheme, claim.issuer, claim.signature, claim.data, claim.uri);
    }

    function getClaimIdsByTopic(address _user, uint256 _topic) external view override returns (bytes32[] memory) {
        return claimIdsByUserAndTopic[_user][_topic];
    }

    function splitSignature(bytes memory sig) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65, "Invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}
