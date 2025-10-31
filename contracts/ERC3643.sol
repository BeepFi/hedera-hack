// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ICompliance} from "../interfaces/ICompliance.sol";

/**
 * @title TokenizedNaira (bNGN)
 * @notice Fiat-backed Nigerian Naira token with non-custodial controls
 * @dev ERC3643 compliant security token backed 1:1 by NGN fiat and bonds
 *
 * KEY FEATURES:
 * - 1:1 backed by Nigerian Naira (fiat + bonds in custody)
 * - Multi-signature minting/burning via Agent role
 * - Wallet freezing for regulatory compliance
 * - Forced transfers for legal requirements
 * - Identity registry for KYC/AML compliance
 * - Compliance module for transfer restrictions
 * - Emergency pause functionality
 * - Batch operations for efficiency
 * - Recovery mechanism for lost wallets
 */
contract ERC3643 is ERC20, ERC20Burnable, ERC20Pausable, AccessControl, ReentrancyGuard {
    // ==================== ROLES ====================
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ==================== STATE VARIABLES ====================

    // ERC3643 Core Components
    IIdentityRegistry public identityRegistry;
    ICompliance public compliance;

    // Token Information
    string private _tokenVersion;
    address public onchainId; // On-chain ID for regulatory reference

    // Frozen accounts and tokens
    mapping(address => bool) private _frozen;
    mapping(address => uint256) private _frozenTokens;

    // Reserve backing tracking
    struct ReserveProof {
        uint256 fiatReserves; // NGN in bank custody
        uint256 bondReserves; // NGN equivalent in bonds
        uint256 totalSupply; // bNGN in circulation
        uint256 timestamp;
        string proofUri; // IPFS/Arweave link to attestation
        address auditor;
    }

    ReserveProof[] public reserveProofs;
    mapping(address => bool) public authorizedAuditors;

    // ==================== EVENTS ====================

    event IdentityRegistryAdded(address indexed identityRegistry);
    event ComplianceAdded(address indexed compliance);
    event RecoverySuccess(address indexed lostWallet, address indexed newWallet, address indexed investoronchainId);
    event AddressFrozen(address indexed userAddress, bool indexed isFrozen, address indexed owner);
    event TokensFrozen(address indexed userAddress, uint256 amount);
    event TokensUnfrozen(address indexed userAddress, uint256 amount);
    event UpdatedTokenInformation(
        string newName, string newSymbol, uint8 newDecimals, string newVersion, address newonchainId
    );
    event ReserveProofSubmitted(
        uint256 indexed proofId, uint256 fiatReserves, uint256 bondReserves, uint256 totalSupply, address auditor
    );
    event AuditorAuthorized(address indexed auditor, bool status);
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount, address indexed agent);

    // ==================== MODIFIERS ====================

    modifier onlyAgent() {
        require(hasRole(AGENT_ROLE, msg.sender), "Caller is not an agent");
        _;
    }

    modifier notFrozen(address account) {
        require(!_frozen[account], "Account is frozen");
        _;
    }

    // ==================== CONSTRUCTOR ====================

    constructor(string memory name, string memory symbol, address _identityRegistry, address _compliance)
        ERC20(name, symbol)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AGENT_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        identityRegistry = IIdentityRegistry(_identityRegistry);
        compliance = ICompliance(_compliance);
        _tokenVersion = "1.0.0";

        emit IdentityRegistryAdded(_identityRegistry);
        emit ComplianceAdded(_compliance);
    }

    // ==================== ERC-20 OVERRIDES WITH COMPLIANCE ====================

    /**
     * @notice Transfer tokens with compliance checks
     * @dev Overrides ERC20 transfer to add regulatory compliance
     */
    function transfer(address to, uint256 amount)
        public
        override
        whenNotPaused
        notFrozen(msg.sender)
        notFrozen(to)
        nonReentrant
        returns (bool)
    {
        require(balanceOf(msg.sender) - _frozenTokens[msg.sender] >= amount, "Insufficient free balance");
        require(identityRegistry.isVerified(to), "Receiver not verified");
        require(compliance.canTransfer(msg.sender, to, amount), "Compliance check failed");

        bool success = super.transfer(to, amount);
        if (success) {
            compliance.transferred(msg.sender, to, amount);
        }
        return success;
    }

    /**
     * @notice Transfer tokens from another account with compliance checks
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        override
        whenNotPaused
        notFrozen(from)
        notFrozen(to)
        nonReentrant
        returns (bool)
    {
        require(balanceOf(from) - _frozenTokens[from] >= amount, "Insufficient free balance");
        require(identityRegistry.isVerified(to), "Receiver not verified");
        require(compliance.canTransfer(from, to, amount), "Compliance check failed");

        bool success = super.transferFrom(from, to, amount);
        if (success) {
            compliance.transferred(from, to, amount);
        }
        return success;
    }

    // ==================== MINTING (BACKED BY FIAT) ====================

    /**
     * @notice Mint new tokens when fiat is deposited
     * @dev Only agents can mint. Requires identity verification.
     * @param to Recipient address (must be verified)
     * @param amount Amount to mint (must match fiat deposited)
     */
    function mint(address to, uint256 amount) external onlyAgent whenNotPaused nonReentrant {
        require(identityRegistry.isVerified(to), "Recipient not verified");

        _mint(to, amount);
        compliance.created(to, amount);
    }

    /**
     * @notice Batch mint for multiple recipients
     */
    function batchMint(address[] calldata toList, uint256[] calldata amounts)
        external
        onlyAgent
        whenNotPaused
        nonReentrant
    {
        require(toList.length == amounts.length, "Array length mismatch");

        for (uint256 i = 0; i < toList.length; i++) {
            require(identityRegistry.isVerified(toList[i]), "Recipient not verified");
            _mint(toList[i], amounts[i]);
            compliance.created(toList[i], amounts[i]);
        }
    }

    // ==================== BURNING (REDEMPTION) ====================

    /**
     * @notice Burn tokens from caller's balance
     * @dev Overrides ERC20Burnable to include compliance and identity checks
     * @param amount Amount to burn
     */
    function burn(uint256 amount) public override whenNotPaused notFrozen(msg.sender) nonReentrant {
        require(balanceOf(msg.sender) - _frozenTokens[msg.sender] >= amount, "Insufficient free balance");
        require(identityRegistry.isVerified(msg.sender), "Caller not verified");

        super.burn(amount);
        compliance.destroyed(msg.sender, amount);
    }

    /**
     * @notice Burn tokens from another account using allowance
     * @dev Overrides ERC20Burnable to include compliance and identity checks
     * @param account Account to burn from
     * @param amount Amount to burn
     */
    function burnFrom(address account, uint256 amount) public override whenNotPaused notFrozen(account) nonReentrant {
        require(balanceOf(account) - _frozenTokens[account] >= amount, "Insufficient free balance");
        require(identityRegistry.isVerified(account), "Account not verified");

        super.burnFrom(account, amount);
        compliance.destroyed(account, amount);
    }

    /**
     * @notice Burn tokens from a specific account by an agent
     * @dev Agent-only function for regulatory burns
     * @param account Account to burn from
     * @param amount Amount to burn
     */
    function burnByAgent(address account, uint256 amount) external onlyAgent whenNotPaused nonReentrant {
        require(balanceOf(account) >= amount, "Insufficient balance");
        require(identityRegistry.isVerified(account), "Account not verified");

        _burn(account, amount);
        compliance.destroyed(account, amount);
    }

    /**
     * @notice Batch burn from multiple accounts by an agent
     */
    function batchBurn(address[] calldata accounts, uint256[] calldata amounts)
        external
        onlyAgent
        whenNotPaused
        nonReentrant
    {
        require(accounts.length == amounts.length, "Array length mismatch");

        for (uint256 i = 0; i < accounts.length; i++) {
            require(balanceOf(accounts[i]) >= amounts[i], "Insufficient balance");
            require(identityRegistry.isVerified(accounts[i]), "Account not verified");
            _burn(accounts[i], amounts[i]);
            compliance.destroyed(accounts[i], amounts[i]);
        }
    }

    // ==================== FORCED TRANSFER ====================

    /**
     * @notice Force transfer for legal/regulatory reasons
     * @dev Agent can transfer tokens without owner approval
     * @param from Source address
     * @param to Destination address (must be verified)
     * @param amount Amount to transfer
     */
    function forcedTransfer(address from, address to, uint256 amount)
        external
        onlyAgent
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        require(identityRegistry.isVerified(to), "Recipient not verified");
        require(balanceOf(from) >= amount, "Insufficient balance");

        _transfer(from, to, amount);
        compliance.transferred(from, to, amount);

        emit ForcedTransfer(from, to, amount, msg.sender);
        return true;
    }

    /**
     * @notice Batch forced transfers
     */
    function batchForcedTransfer(address[] calldata fromList, address[] calldata toList, uint256[] calldata amounts)
        external
        onlyAgent
        whenNotPaused
        nonReentrant
    {
        require(fromList.length == toList.length && toList.length == amounts.length, "Array length mismatch");

        for (uint256 i = 0; i < fromList.length; i++) {
            require(identityRegistry.isVerified(toList[i]), "Recipient not verified");
            _transfer(fromList[i], toList[i], amounts[i]);
            compliance.transferred(fromList[i], toList[i], amounts[i]);
            emit ForcedTransfer(fromList[i], toList[i], amounts[i], msg.sender);
        }
    }

    // ==================== FREEZING FUNCTIONS ====================

    /**
     * @notice Freeze/unfreeze an entire wallet
     */
    function setAddressFrozen(address userAddress, bool freeze) external onlyAgent {
        _frozen[userAddress] = freeze;
        emit AddressFrozen(userAddress, freeze, msg.sender);
    }

    /**
     * @notice Batch freeze/unfreeze wallets
     */
    function batchSetAddressFrozen(address[] calldata addresses, bool[] calldata freezeStatus) external onlyAgent {
        require(addresses.length == freezeStatus.length, "Array length mismatch");

        for (uint256 i = 0; i < addresses.length; i++) {
            _frozen[addresses[i]] = freezeStatus[i];
            emit AddressFrozen(addresses[i], freezeStatus[i], msg.sender);
        }
    }

    /**
     * @notice Freeze partial tokens in a wallet
     */
    function freezePartialTokens(address userAddress, uint256 amount) external onlyAgent {
        require(balanceOf(userAddress) >= _frozenTokens[userAddress] + amount, "Insufficient balance");
        _frozenTokens[userAddress] += amount;
        emit TokensFrozen(userAddress, amount);
    }

    /**
     * @notice Unfreeze partial tokens
     */
    function unfreezePartialTokens(address userAddress, uint256 amount) external onlyAgent {
        require(_frozenTokens[userAddress] >= amount, "Insufficient frozen tokens");
        _frozenTokens[userAddress] -= amount;
        emit TokensUnfrozen(userAddress, amount);
    }

    /**
     * @notice Batch freeze partial tokens
     */
    function batchFreezePartialTokens(address[] calldata addresses, uint256[] calldata amounts) external onlyAgent {
        require(addresses.length == amounts.length, "Array length mismatch");

        for (uint256 i = 0; i < addresses.length; i++) {
            require(balanceOf(addresses[i]) >= _frozenTokens[addresses[i]] + amounts[i], "Insufficient balance");
            _frozenTokens[addresses[i]] += amounts[i];
            emit TokensFrozen(addresses[i], amounts[i]);
        }
    }

    /**
     * @notice Batch unfreeze partial tokens
     */
    function batchUnfreezePartialTokens(address[] calldata addresses, uint256[] calldata amounts) external onlyAgent {
        require(addresses.length == amounts.length, "Array length mismatch");

        for (uint256 i = 0; i < addresses.length; i++) {
            require(_frozenTokens[addresses[i]] >= amounts[i], "Insufficient frozen tokens");
            _frozenTokens[addresses[i]] -= amounts[i];
            emit TokensUnfrozen(addresses[i], amounts[i]);
        }
    }

    // ==================== RECOVERY MECHANISM ====================

    /**
     * @notice Recover tokens from lost wallet to new wallet
     * @dev Used when investor loses private keys
     */
    function recoveryAddress(address lostWallet, address newWallet, address investoronchainId)
        external
        onlyAgent
        nonReentrant
        returns (bool)
    {
        require(identityRegistry.isVerified(newWallet), "New wallet not verified");
        require(balanceOf(lostWallet) > 0, "No balance to recover");

        uint256 balance = balanceOf(lostWallet);
        _transfer(lostWallet, newWallet, balance);

        // Transfer frozen tokens status
        if (_frozenTokens[lostWallet] > 0) {
            _frozenTokens[newWallet] = _frozenTokens[lostWallet];
            _frozenTokens[lostWallet] = 0;
        }

        emit RecoverySuccess(lostWallet, newWallet, investoronchainId);
        return true;
    }

    // ==================== RESERVE BACKING PROOF ====================

    /**
     * @notice Submit proof of reserves (attestation)
     * @dev Called by authorized auditors to prove 1:1 backing
     */
    function submitReserveProof(uint256 fiatReserves, uint256 bondReserves, string calldata proofUri) external {
        require(authorizedAuditors[msg.sender], "Not authorized auditor");
        require(fiatReserves + bondReserves >= totalSupply(), "Insufficient backing");

        reserveProofs.push(
            ReserveProof({
                fiatReserves: fiatReserves,
                bondReserves: bondReserves,
                totalSupply: totalSupply(),
                timestamp: block.timestamp,
                proofUri: proofUri,
                auditor: msg.sender
            })
        );

        emit ReserveProofSubmitted(reserveProofs.length - 1, fiatReserves, bondReserves, totalSupply(), msg.sender);
    }

    /**
     * @notice Authorize/deauthorize auditor
     */
    function setAuditorStatus(address auditor, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        authorizedAuditors[auditor] = status;
        emit AuditorAuthorized(auditor, status);
    }

    /**
     * @notice Get latest reserve proof
     */
    function getLatestReserveProof() external view returns (ReserveProof memory) {
        require(reserveProofs.length > 0, "No proofs submitted");
        return reserveProofs[reserveProofs.length - 1];
    }

    /**
     * @notice Get reserve proof count
     */
    function getReserveProofCount() external view returns (uint256) {
        return reserveProofs.length;
    }

    /**
     * @notice Check if reserves are sufficient
     */
    function isFullyBacked() external view returns (bool) {
        if (reserveProofs.length == 0) return false;

        ReserveProof memory latest = reserveProofs[reserveProofs.length - 1];

        // Proof must be recent (within 30 days)
        if (block.timestamp - latest.timestamp > 30 days) return false;

        // Reserves must cover current supply
        return (latest.fiatReserves + latest.bondReserves) >= totalSupply();
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @notice Update identity registry
     */
    function setIdentityRegistry(address _identityRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_identityRegistry != address(0), "Invalid address");
        identityRegistry = IIdentityRegistry(_identityRegistry);
        emit IdentityRegistryAdded(_identityRegistry);
    }

    /**
     * @notice Update compliance module
     */
    function setCompliance(address _compliance) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_compliance != address(0), "Invalid address");
        compliance = ICompliance(_compliance);
        emit ComplianceAdded(_compliance);
    }

    /**
     * @notice Update token information
     */
    function setTokenInformation(
        string calldata newName,
        string calldata newSymbol,
        string calldata newVersion,
        address newonchainId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Note: ERC20 doesn't allow name/symbol changes in standard implementation
        // This would require custom storage
        _tokenVersion = newVersion;
        onchainId = newonchainId;

        emit UpdatedTokenInformation(newName, newSymbol, decimals(), newVersion, newonchainId);
    }

    /**
     * @notice Pause all token operations
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause token operations
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Check if address is frozen
     */
    function isFrozen(address userAddress) external view returns (bool) {
        return _frozen[userAddress];
    }

    /**
     * @notice Get frozen token amount for address
     */
    function getFrozenTokens(address userAddress) external view returns (uint256) {
        return _frozenTokens[userAddress];
    }

    /**
     * @notice Get free balance (total - frozen)
     */
    function getFreeBalance(address userAddress) external view returns (uint256) {
        return balanceOf(userAddress) - _frozenTokens[userAddress];
    }

    /**
     * @notice Get token version
     */
    function version() external view returns (string memory) {
        return _tokenVersion;
    }

    /**
     * @notice Check if token is paused
     */
    function paused() public view override returns (bool) {
        return super.paused();
    }

    // ==================== INTERNAL ====================

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}
