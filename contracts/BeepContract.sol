// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract BeepContract {
    address public constant HBAR = address(0);

    enum IntentStatus {
        Active,
        Completed,
        Expired,
        Cancelled
    }
    enum Priority {
        Low,
        Normal,
        High,
        Urgent
    }

    struct BeepCoin {
        address token;
        bool isNative;
        uint256 amount;
    }

    struct ExpectedToken {
        address token;
        bool isNative;
        uint256 amount;
        address targetAddress;
    }

    struct Intent {
        string id;
        address creator;
        BeepCoin[] inputTokens;
        ExpectedToken[] outputTokens;
        address executor;
        IntentStatus status;
        uint64 createdAt;
        uint64 timeout;
        BeepCoin tip;
        Priority priority;
    }

    struct Config {
        address admin;
        address[] supportedTokens;
        string[] supportedProtocols;
        uint64 defaultTimeoutHeight;
    }

    struct WalletBalance {
        BeepCoin[] balances;
    }

    Config public config;
    mapping(string => Intent) public intents;
    mapping(address => mapping(string => BeepCoin[])) public escrow;
    mapping(address => uint128) public userNonce;
    mapping(address => WalletBalance) internal walletBalances; // Changed to internal
    uint256 public paymasterNative;
    mapping(address => uint256) public paymasterTokens;

    event IntentCreated(string indexed id, address indexed creator);
    event IntentFilled(string indexed id, address indexed executor);
    event IntentCancelled(string indexed id, address indexed creator);
    event IntentWithdrawn(string indexed id, address indexed creator);
    event DepositToWallet(address indexed user, BeepCoin[] tokens);
    event TransferFromWallet(address indexed user, address indexed recipient, BeepCoin[] tokens);
    event PaymasterFunded(address indexed funder, uint256 amount);

    error Unauthorized();
    error IntentNotActive();
    error IntentNotExpired();
    error IntentIdExists();
    error UnsupportedToken(address token);
    error InsufficientBalance();
    error TokenNotFound();
    error InsufficientMsgValue();
    error InsufficientAllowance();
    error TokenTransferFailed();

    constructor(address[] memory supportedTokens, string[] memory supportedProtocols, uint64 defaultTimeoutHeight) {
        config.admin = msg.sender;
        config.supportedTokens = supportedTokens;
        config.supportedProtocols = supportedProtocols;
        config.defaultTimeoutHeight = defaultTimeoutHeight;
    }

    function createIntent(
        BeepCoin[] memory inputTokens,
        ExpectedToken[] memory outputTokens,
        uint64 timeout,
        BeepCoin memory tip,
        bool useWalletBalance,
        Priority priority,
        bool allowPaymasterFallback
    ) public payable returns (string memory) {
        uint128 nonce = userNonce[msg.sender];
        string memory id = generateIntentId(msg.sender, nonce);
        if (bytes(intents[id].id).length > 0) revert IntentIdExists();
        userNonce[msg.sender] += 1;

        for (uint256 i = 0; i < inputTokens.length; i++) {
            if (!isSupportedToken(inputTokens[i].token)) revert UnsupportedToken(inputTokens[i].token);
        }
        for (uint256 i = 0; i < outputTokens.length; i++) {
            if (!isSupportedToken(outputTokens[i].token)) revert UnsupportedToken(outputTokens[i].token);
        }

        uint256 fee = calculateFee(priority);
        uint256 nativeRequired = fee;

        if (useWalletBalance) {
            for (uint256 i = 0; i < inputTokens.length; i++) {
                subtractFromWallet(msg.sender, inputTokens[i]);
            }
            subtractFromWallet(msg.sender, tip);
            subtractFromWallet(msg.sender, BeepCoin({token: HBAR, isNative: true, amount: fee}));
            nativeRequired = 0;
        } else {
            for (uint256 i = 0; i < inputTokens.length; i++) {
                if (inputTokens[i].isNative) {
                    nativeRequired += inputTokens[i].amount;
                } else {
                    transferToContract(msg.sender, inputTokens[i]);
                }
            }
            if (tip.isNative) {
                nativeRequired += tip.amount;
            } else {
                transferToContract(msg.sender, tip);
            }
        }

        if (msg.value < nativeRequired) {
            uint256 shortfall = nativeRequired - msg.value;
            if (!allowPaymasterFallback || paymasterNative < shortfall) revert InsufficientMsgValue();
            paymasterNative -= shortfall;
        }

        Intent storage intent = intents[id];
        intent.id = id;
        intent.creator = msg.sender;
        for (uint256 i = 0; i < inputTokens.length; i++) {
            intent.inputTokens.push(inputTokens[i]);
        }
        for (uint256 i = 0; i < outputTokens.length; i++) {
            intent.outputTokens.push(outputTokens[i]);
        }
        intent.status = IntentStatus.Active;
        intent.createdAt = uint64(block.number);
        intent.timeout = uint64(block.number) + (timeout == 0 ? config.defaultTimeoutHeight : timeout);
        intent.tip = tip;
        intent.priority = priority;

        BeepCoin[] storage esc = escrow[msg.sender][id];
        for (uint256 i = 0; i < inputTokens.length; i++) {
            esc.push(inputTokens[i]);
        }

        emit IntentCreated(id, msg.sender);
        return id;
    }

    function fillIntent(string memory intentId, bool useWalletBalance, bool allowPaymasterFallback) public payable {
        Intent storage intent = intents[intentId];
        if (intent.status != IntentStatus.Active) revert IntentNotActive();

        uint256 fee = calculateFee(intent.priority);
        uint256 nativeRequired = fee;

        if (useWalletBalance) {
            for (uint256 i = 0; i < intent.outputTokens.length; i++) {
                BeepCoin memory coin = BeepCoin({
                    token: intent.outputTokens[i].token,
                    isNative: intent.outputTokens[i].isNative,
                    amount: intent.outputTokens[i].amount
                });
                subtractFromWallet(msg.sender, coin);
            }
            subtractFromWallet(msg.sender, BeepCoin({token: HBAR, isNative: true, amount: fee}));
            nativeRequired = 0;
        } else {
            for (uint256 i = 0; i < intent.outputTokens.length; i++) {
                BeepCoin memory coin = BeepCoin({
                    token: intent.outputTokens[i].token,
                    isNative: intent.outputTokens[i].isNative,
                    amount: intent.outputTokens[i].amount
                });
                if (coin.isNative) {
                    nativeRequired += coin.amount;
                } else {
                    transferToContract(msg.sender, coin);
                }
            }
        }

        if (msg.value < nativeRequired) {
            uint256 shortfall = nativeRequired - msg.value;
            if (!allowPaymasterFallback || paymasterNative < shortfall) revert InsufficientMsgValue();
            paymasterNative -= shortfall;
        }

        intent.executor = msg.sender;
        intent.status = IntentStatus.Completed;

        for (uint256 i = 0; i < intent.inputTokens.length; i++) {
            if (intent.inputTokens[i].isNative && address(this).balance < intent.inputTokens[i].amount) {
                revert InsufficientBalance();
            }
            transferFromContract(msg.sender, intent.inputTokens[i]);
        }
        if (intent.tip.isNative && address(this).balance < intent.tip.amount) {
            revert InsufficientBalance();
        }
        transferFromContract(msg.sender, intent.tip);

        for (uint256 i = 0; i < intent.outputTokens.length; i++) {
            address recipient = intent.outputTokens[i].targetAddress == address(0)
                ? intent.creator
                : intent.outputTokens[i].targetAddress;
            BeepCoin memory coin = BeepCoin({
                token: intent.outputTokens[i].token,
                isNative: intent.outputTokens[i].isNative,
                amount: intent.outputTokens[i].amount
            });
            transferFromContract(recipient, coin);
        }

        delete escrow[intent.creator][intentId];

        emit IntentFilled(intentId, msg.sender);
    }

    function cancelIntent(string memory intentId, bool allowPaymasterFallback) public payable {
        Intent storage intent = intents[intentId];
        if (intent.status != IntentStatus.Active) revert IntentNotActive();
        if (intent.creator != msg.sender) revert Unauthorized();

        uint256 fee = calculateFee(Priority.Normal);
        uint256 nativeRequired = fee;

        if (msg.value < nativeRequired) {
            uint256 shortfall = nativeRequired - msg.value;
            if (!allowPaymasterFallback || paymasterNative < shortfall) revert InsufficientMsgValue();
            paymasterNative -= shortfall;
        }

        intent.status = IntentStatus.Cancelled;

        for (uint256 i = 0; i < intent.inputTokens.length; i++) {
            if (intent.inputTokens[i].isNative && address(this).balance < intent.inputTokens[i].amount) {
                revert InsufficientBalance();
            }
            transferFromContract(msg.sender, intent.inputTokens[i]);
        }
        // Refund the tip
        if (intent.tip.isNative && address(this).balance < intent.tip.amount) {
            revert InsufficientBalance();
        }
        transferFromContract(msg.sender, intent.tip);

        delete escrow[msg.sender][intentId];

        emit IntentCancelled(intentId, msg.sender);
    }

    function withdrawIntentFund(string memory intentId, bool allowPaymasterFallback) public payable {
        Intent storage intent = intents[intentId];
        if (uint64(block.number) < intent.timeout) revert IntentNotExpired();
        if (intent.creator != msg.sender) revert Unauthorized();

        uint256 fee = calculateFee(Priority.Normal);
        uint256 nativeRequired = fee;

        if (msg.value < nativeRequired) {
            uint256 shortfall = nativeRequired - msg.value;
            if (!allowPaymasterFallback || paymasterNative < shortfall) revert InsufficientMsgValue();
            paymasterNative -= shortfall;
        }

        intent.status = IntentStatus.Expired;

        for (uint256 i = 0; i < intent.inputTokens.length; i++) {
            if (intent.inputTokens[i].isNative && address(this).balance < intent.inputTokens[i].amount) {
                revert InsufficientBalance();
            }
            transferFromContract(msg.sender, intent.inputTokens[i]);
        }
        // Refund the tip
        if (intent.tip.isNative && address(this).balance < intent.tip.amount) {
            revert InsufficientBalance();
        }
        transferFromContract(msg.sender, intent.tip);

        delete escrow[msg.sender][intentId];

        emit IntentWithdrawn(intentId, msg.sender);
    }

    function paymasterFund() public payable {
        paymasterNative += msg.value;
        emit PaymasterFunded(msg.sender, msg.value);
    }

    function paymasterFundToken(address token, uint256 amount) public {
        if (!isSupportedToken(token)) revert UnsupportedToken(token);
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!success) revert TokenTransferFailed();
        paymasterTokens[token] += amount;
        emit PaymasterFunded(msg.sender, amount);
    }

    function depositToWallet(BeepCoin[] memory tokens) public payable {
        uint256 nativeRequired = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isSupportedToken(tokens[i].token)) revert UnsupportedToken(tokens[i].token);
            if (tokens[i].isNative) {
                nativeRequired += tokens[i].amount;
            } else {
                transferToContract(msg.sender, tokens[i]);
            }
            addToWallet(msg.sender, tokens[i]);
        }
        if (msg.value < nativeRequired) revert InsufficientMsgValue();

        emit DepositToWallet(msg.sender, tokens);
    }

    function transferFromWallet(address recipient, BeepCoin[] memory tokens) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            subtractFromWallet(msg.sender, tokens[i]);
            transferFromContract(recipient, tokens[i]);
        }

        emit TransferFromWallet(msg.sender, recipient, tokens);
    }

    function updateAdmin(address newAdmin) public {
        if (msg.sender != config.admin) revert Unauthorized();
        config.admin = newAdmin;
    }

    function addSupportedTokens(address[] memory tokens) public {
        if (msg.sender != config.admin) revert Unauthorized();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isSupportedToken(tokens[i])) {
                config.supportedTokens.push(tokens[i]);
            }
        }
    }

    function removeSupportedTokens(address[] memory tokens) public {
        if (msg.sender != config.admin) revert Unauthorized();
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = 0; j < config.supportedTokens.length; j++) {
                if (config.supportedTokens[j] == tokens[i]) {
                    config.supportedTokens[j] = config.supportedTokens[config.supportedTokens.length - 1];
                    config.supportedTokens.pop();
                    break;
                }
            }
        }
    }

    function addSupportedProtocols(string[] memory protocols) public {
        if (msg.sender != config.admin) revert Unauthorized();
        for (uint256 i = 0; i < protocols.length; i++) {
            bool exists = false;
            for (uint256 j = 0; j < config.supportedProtocols.length; j++) {
                if (keccak256(bytes(config.supportedProtocols[j])) == keccak256(bytes(protocols[i]))) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                config.supportedProtocols.push(protocols[i]);
            }
        }
    }

    function removeSupportedProtocols(string[] memory protocols) public {
        if (msg.sender != config.admin) revert Unauthorized();
        for (uint256 i = 0; i < protocols.length; i++) {
            for (uint256 j = 0; j < config.supportedProtocols.length; j++) {
                if (keccak256(bytes(config.supportedProtocols[j])) == keccak256(bytes(protocols[i]))) {
                    config.supportedProtocols[j] = config.supportedProtocols[config.supportedProtocols.length - 1];
                    config.supportedProtocols.pop();
                    break;
                }
            }
        }
    }

    function updateDefaultTimeoutHeight(uint64 defaultTimeoutHeight) public {
        if (msg.sender != config.admin) revert Unauthorized();
        config.defaultTimeoutHeight = defaultTimeoutHeight;
    }

    function getConfig() public view returns (Config memory) {
        return config;
    }

    function getIntent(string memory id) public view returns (Intent memory) {
        return intents[id];
    }

    function getUserNonce(address user) public view returns (uint128) {
        return userNonce[user];
    }

    function getWalletBalance(address user) public view returns (BeepCoin[] memory) {
        return walletBalances[user].balances;
    }

    function calculateFee(Priority priority) public pure returns (uint256) {
        uint256 base = 100;
        uint256 multiplier = 100;
        if (priority == Priority.Low) multiplier = 80;
        else if (priority == Priority.Normal) multiplier = 100;
        else if (priority == Priority.High) multiplier = 150;
        else if (priority == Priority.Urgent) multiplier = 200;
        return base * multiplier / 100;
    }

    function generateIntentId(address creator, uint128 nonce) internal pure returns (string memory) {
        bytes32 hash = sha256(abi.encodePacked(creator, ":", nonce));
        return string(abi.encodePacked("intent", toHexString(uint160(uint256(hash)), 10)));
    }

    function toHexString(uint160 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length);
        bytes memory hexChars = "0123456789abcdef";
        for (uint256 i = 2 * length; i > 0; --i) {
            buffer[i - 1] = hexChars[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }

    function isSupportedToken(address token) internal view returns (bool) {
        if (token == address(0)) return true; // Support native token
        for (uint256 i = 0; i < config.supportedTokens.length; i++) {
            if (config.supportedTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    function addToWallet(address user, BeepCoin memory coin) internal {
        WalletBalance storage wb = walletBalances[user];
        for (uint256 i = 0; i < wb.balances.length; i++) {
            if (wb.balances[i].token == coin.token) {
                wb.balances[i].amount += coin.amount;
                return;
            }
        }
        wb.balances.push(coin);
    }

    function subtractFromWallet(address user, BeepCoin memory coin) internal {
        WalletBalance storage wb = walletBalances[user];
        for (uint256 i = 0; i < wb.balances.length; i++) {
            if (wb.balances[i].token == coin.token) {
                if (wb.balances[i].amount < coin.amount) revert InsufficientBalance();
                wb.balances[i].amount -= coin.amount;
                return;
            }
        }
        revert TokenNotFound();
    }

    function transferToContract(address from, BeepCoin memory coin) internal {
        if (coin.isNative) {
            // Msg.value handled in payable
        } else {
            uint256 allowance = IERC20(coin.token).allowance(from, address(this));
            if (allowance < coin.amount) revert InsufficientAllowance();
            bool success = IERC20(coin.token).transferFrom(from, address(this), coin.amount);
            if (!success) revert TokenTransferFailed();
        }
    }

    function transferFromContract(address to, BeepCoin memory coin) internal {
        if (coin.isNative) {
            if (address(this).balance < coin.amount) revert InsufficientBalance();
            payable(to).transfer(coin.amount);
        } else {
            bool success = IERC20(coin.token).transfer(to, coin.amount);
            if (!success) revert TokenTransferFailed();
        }
    }
}
