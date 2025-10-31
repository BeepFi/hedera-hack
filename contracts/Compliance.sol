// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ICompliance, IIdentityRegistry} from "./ERC3643.sol";
import {IERC20} from "./BeepContract.sol";

abstract contract ACompliance is ICompliance, AccessControl {
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    address public tokenBound;
    IIdentityRegistry public identityRegistry;

    struct ComplianceLimits {
        uint256 dailyLimit;
        uint256 monthlyLimit;
        uint256 maxBalance;
        uint256 minHoldingPeriod;
    }

    ComplianceLimits public limits;

    struct TransferRecord {
        uint256 dailyTotal;
        uint256 monthlyTotal;
        uint256 dailyResetTime;
        uint256 monthlyResetTime;
    }

    mapping(address => TransferRecord) public transferRecords;
    mapping(address => uint256) public lastReceiveTime;
    mapping(uint16 => bool) public countryRestrictions;
    mapping(uint16 => uint256) public countryHolderCount;
    mapping(uint16 => uint256) public maxHoldersPerCountry;
    mapping(address => bool) public isHolder;
    mapping(address => uint256) public totalMinted;
    mapping(address => uint256) public totalBurned;
    mapping(address => uint256) public mintCount;
    mapping(address => uint256) public burnCount;
    mapping(uint16 => uint256) public countryTotalMinted;
    mapping(uint16 => uint256) public countryTotalBurned;

    event TokenBound(address indexed token);
    event TokenUnbound(address indexed token);
    event ComplianceLimitsUpdated(
        uint256 dailyLimit, uint256 monthlyLimit, uint256 maxBalance, uint256 minHoldingPeriod
    );
    event CountryRestrictionSet(uint16 indexed country, bool restricted);
    event MaxHoldersPerCountrySet(uint16 indexed country, uint256 maxHolders);
    event TransferCompliance(address indexed from, address indexed to, uint256 amount, bool compliant);
    event TokenCreated(address indexed to, uint256 amount, uint256 timestamp);
    event TokenDestroyed(address indexed from, uint256 amount, uint256 timestamp);

    constructor(address _identityRegistry) {
        require(_identityRegistry != address(0), "Invalid identity registry");
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AGENT_ROLE, msg.sender);
        identityRegistry = IIdentityRegistry(_identityRegistry);
        limits = ComplianceLimits({
            dailyLimit: 1_000_000 * 10 ** 18,
            monthlyLimit: 10_000_000 * 10 ** 18,
            maxBalance: 100_000_000 * 10 ** 18,
            minHoldingPeriod: 0
        });
    }

    function bindToken(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(0), "Invalid token address");
        require(tokenBound == address(0), "Token already bound");
        tokenBound = _token;
        emit TokenBound(_token);
    }

    function unbindToken(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenBound == _token, "Token not bound");
        tokenBound = address(0);
        emit TokenUnbound(_token);
    }

    function isTokenBound(address _token) external view returns (bool) {
        return tokenBound == _token;
    }

    function isTokenAgent(address _agentAddress) external view returns (bool) {
        return hasRole(AGENT_ROLE, _agentAddress);
    }

    function canTransfer(address _from, address _to, uint256 _amount) external view override returns (bool) {
        if (_from == address(0) || _to == address(0)) {
            return _checkCreationDestruction(_to, _amount);
        }

        uint16 fromCountry = identityRegistry.investorCountry(_from);
        uint16 toCountry = identityRegistry.investorCountry(_to);

        if (countryRestrictions[fromCountry] || countryRestrictions[toCountry]) {
            return false;
        }

        if (limits.minHoldingPeriod > 0 && lastReceiveTime[_from] > 0) {
            if (block.timestamp < lastReceiveTime[_from] + limits.minHoldingPeriod) {
                return false;
            }
        }

        if (!_checkTransferLimits(_from, _amount)) {
            return false;
        }

        if (!_checkBalanceLimit(_to, _amount)) {
            return false;
        }

        if (!_checkCountryHolderLimit(_to, toCountry)) {
            return false;
        }

        return true;
    }

    function _checkCreationDestruction(address _to, uint256 _amount) internal view returns (bool) {
        if (_to == address(0)) {
            return true; // Burning is always allowed
        }
        // For minting (_from == address(0)), check balance and country holder limits
        uint16 toCountry = identityRegistry.investorCountry(_to);
        if (countryRestrictions[toCountry]) {
            return false;
        }
        if (!_checkBalanceLimit(_to, _amount)) {
            return false;
        }
        if (!_checkCountryHolderLimit(_to, toCountry)) {
            return false;
        }
        return true;
    }

    function _checkTransferLimits(address _from, uint256 _amount) internal view returns (bool) {
        TransferRecord memory record = transferRecords[_from];
        if (limits.dailyLimit > 0) {
            uint256 dailyTotal = record.dailyTotal;
            if (block.timestamp >= record.dailyResetTime) {
                dailyTotal = 0;
            }
            if (dailyTotal + _amount > limits.dailyLimit) {
                return false;
            }
        }
        if (limits.monthlyLimit > 0) {
            uint256 monthlyTotal = record.monthlyTotal;
            if (block.timestamp >= record.monthlyResetTime) {
                monthlyTotal = 0;
            }
            if (monthlyTotal + _amount > limits.monthlyLimit) {
                return false;
            }
        }
        return true;
    }

    function _checkBalanceLimit(address _to, uint256 _amount) internal view returns (bool) {
        if (limits.maxBalance == 0) {
            return true;
        }
        return IERC20(tokenBound).balanceOf(_to) + _amount <= limits.maxBalance;
    }

    function _checkCountryHolderLimit(address _to, uint16 _country) internal view returns (bool) {
        uint256 maxHolders = maxHoldersPerCountry[_country];
        if (maxHolders == 0) {
            return true;
        }
        if (isHolder[_to]) {
            return true;
        }
        return countryHolderCount[_country] < maxHolders;
    }

    function transferred(address _from, address _to, uint256 _amount) external override {
        require(msg.sender == tokenBound, "Only bound token can call");
        _updateTransferRecord(_from, _amount);
        lastReceiveTime[_to] = block.timestamp;
        _updateHolderStatus(_to);
    }

    function created(address _to, uint256 _amount) external override {
        require(msg.sender == tokenBound, "Only bound token can call");
        require(_to != address(0), "Invalid recipient");
        require(_amount > 0, "Amount must be > 0");
        lastReceiveTime[_to] = block.timestamp;
        totalMinted[_to] += _amount;
        mintCount[_to] += 1;
        uint16 country = identityRegistry.investorCountry(_to);
        countryTotalMinted[country] += _amount;
        uint256 newBalance = IERC20(tokenBound).balanceOf(_to);
        if (!isHolder[_to] && newBalance > 0) {
            isHolder[_to] = true;
            countryHolderCount[country] += 1;
        }
        emit TokenCreated(_to, _amount, block.timestamp);
    }

    function destroyed(address _from, uint256 _amount) external override {
        require(msg.sender == tokenBound, "Only bound token can call");
        require(_from != address(0), "Invalid address");
        require(_amount > 0, "Amount must be > 0");
        totalBurned[_from] += _amount;
        burnCount[_from] += 1;
        uint16 country = identityRegistry.investorCountry(_from);
        countryTotalBurned[country] += _amount;
        uint256 postBalance = IERC20(tokenBound).balanceOf(_from);
        if (postBalance == 0 && isHolder[_from]) {
            isHolder[_from] = false;
            if (countryHolderCount[country] > 0) {
                countryHolderCount[country] -= 1;
            }
        } else if (postBalance == _amount && isHolder[_from]) {
            isHolder[_from] = false;
            if (countryHolderCount[country] > 0) {
                countryHolderCount[country] -= 1;
            }
        }
        emit TokenDestroyed(_from, _amount, block.timestamp);
    }

    function _updateTransferRecord(address _from, uint256 _amount) internal {
        TransferRecord storage record = transferRecords[_from];
        if (block.timestamp >= record.dailyResetTime) {
            record.dailyTotal = _amount;
            record.dailyResetTime = block.timestamp + 1 days;
        } else {
            record.dailyTotal += _amount;
        }
        if (block.timestamp >= record.monthlyResetTime) {
            record.monthlyTotal = _amount;
            record.monthlyResetTime = block.timestamp + 30 days;
        } else {
            record.monthlyTotal += _amount;
        }
    }

    function _updateHolderStatus(address _to) internal {
        if (!isHolder[_to]) {
            isHolder[_to] = true;
            uint16 toCountry = identityRegistry.investorCountry(_to);
            countryHolderCount[toCountry]++;
        }
    }

    function setComplianceLimits(
        uint256 _dailyLimit,
        uint256 _monthlyLimit,
        uint256 _maxBalance,
        uint256 _minHoldingPeriod
    ) external onlyRole(AGENT_ROLE) {
        limits = ComplianceLimits({
            dailyLimit: _dailyLimit,
            monthlyLimit: _monthlyLimit,
            maxBalance: _maxBalance,
            minHoldingPeriod: _minHoldingPeriod
        });
        emit ComplianceLimitsUpdated(_dailyLimit, _monthlyLimit, _maxBalance, _minHoldingPeriod);
    }

    function setCountryRestriction(uint16 _country, bool _restricted) external onlyRole(AGENT_ROLE) {
        countryRestrictions[_country] = _restricted;
        emit CountryRestrictionSet(_country, _restricted);
    }

    function setMaxHoldersPerCountry(uint16 _country, uint256 _maxHolders) external onlyRole(AGENT_ROLE) {
        maxHoldersPerCountry[_country] = _maxHolders;
        emit MaxHoldersPerCountrySet(_country, _maxHolders);
    }

    function batchSetCountryRestrictions(uint16[] calldata _countries, bool[] calldata _restricted)
        external
        onlyRole(AGENT_ROLE)
    {
        require(_countries.length == _restricted.length, "Array length mismatch");
        for (uint256 i = 0; i < _countries.length; i++) {
            countryRestrictions[_countries[i]] = _restricted[i];
            emit CountryRestrictionSet(_countries[i], _restricted[i]);
        }
    }

    function setIdentityRegistry(address _identityRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_identityRegistry != address(0), "Invalid address");
        identityRegistry = IIdentityRegistry(_identityRegistry);
    }

    function resetTransferRecord(address _address) external onlyRole(AGENT_ROLE) {
        delete transferRecords[_address];
    }

    function getTransferRecord(address _address)
        external
        view
        returns (uint256 dailyTotal, uint256 monthlyTotal, uint256 dailyResetTime, uint256 monthlyResetTime)
    {
        TransferRecord memory record = transferRecords[_address];
        return (record.dailyTotal, record.monthlyTotal, record.dailyResetTime, record.monthlyResetTime);
    }

    function getRemainingDailyLimit(address _address) external view returns (uint256) {
        TransferRecord memory record = transferRecords[_address];
        if (limits.dailyLimit == 0) {
            return type(uint256).max;
        }
        uint256 dailyTotal = record.dailyTotal;
        if (block.timestamp >= record.dailyResetTime) {
            dailyTotal = 0;
        }
        if (dailyTotal >= limits.dailyLimit) {
            return 0;
        }
        return limits.dailyLimit - dailyTotal;
    }

    function getRemainingMonthlyLimit(address _address) external view returns (uint256) {
        TransferRecord memory record = transferRecords[_address];
        if (limits.monthlyLimit == 0) {
            return type(uint256).max;
        }
        uint256 monthlyTotal = record.monthlyTotal;
        if (block.timestamp >= record.monthlyResetTime) {
            monthlyTotal = 0;
        }
        if (monthlyTotal >= limits.monthlyLimit) {
            return 0;
        }
        return limits.monthlyLimit - monthlyTotal;
    }

    function getCountryHolderCount(uint16 _country) external view returns (uint256) {
        return countryHolderCount[_country];
    }

    function getCountryTotalMinted(uint16 _country) external view returns (uint256) {
        return countryTotalMinted[_country];
    }

    function getCountryTotalBurned(uint16 _country) external view returns (uint256) {
        return countryTotalBurned[_country];
    }
}

contract Compliance is ACompliance {
    constructor(address _identityRegistry) ACompliance(_identityRegistry) {}
}
