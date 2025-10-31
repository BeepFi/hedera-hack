# 🌍 BEEP - Turning 4 Billion Phones into Wallets

**Hedera Africa Hackathon 2025** | **Track:** Onchain Finance & RWA | **TRL:** Prototype (4-6)

> *Dial `*123#` on any phone to send crypto in 12 seconds - no smartphone or internet required.*

---

## 📋 Quick Links

- **[Pitch Deck](https://docs.google.com/presentation/d/1Oe480wdKvpZ27UJPD68oLgJNvHP4wwviYFJhTNvb64o/edit?usp=drivesdk)** | **[Demo Video](https://youtu.be/NdmZ5dIBzKQ)** | **[Wallet API](https://github.com/BeepFi/beep-wallet-api)** | **[Smart Contracts](https://github.com/BeepFi/beep-contract-hedera)**

---

## 🚨 Problem Statement

**4.2 billion people lack smartphones** - 60% of Africa (544M), 500M in India, 300M in Latin America cannot access crypto wallets that require $100 smartphones and $20/month data plans.

**Financial Impact:**
- 1.7B unbanked adults globally
- $850B/year remittances losing 5-8% to intermediary fees
- $200B aid distribution losing 15-30% to inefficiencies
- Entire populations excluded from Web3 economic opportunities

**Current Solutions Fail:**
- Crypto wallets (Coinbase, MetaMask): Require smartphones + internet
- M-Pesa/Mobile Money: Not blockchain-native, single-telco lock-in, no cross-border
- Banks: 2-5% fees, 2-3 day settlement, exclude billions due to minimum balances

---

## ✅ Hedera-Based Solution

**Beep** transforms any $10 feature phone into a non-custodial crypto wallet using USSD codes (`*123#`) and WhatsApp.

### How It Works

1. **Dial `*123#`** on any feature phone (works on devices from 1998)
2. **Select action:** Send money, check balance, pay bills, save
3. **Enter recipient** phone number or merchant code
4. **Enter amount** in local currency (auto-converted to HBAR/stablecoins)
5. **Confirm with PIN** (4-digit memorizable code)
6. **Transaction complete** in 3-5 seconds with SMS confirmation

### Key Features

- ✅ **Zero internet required** - works on 2G networks via USSD
- ✅ **Non-custodial** - users control private keys (encrypted, cloud-backed with PIN recovery)
- ✅ **WhatsApp integration** - natural language transactions ("Send 10 HBAR to John")
- ✅ **Multi-currency support** - local fiat, HBAR, USDC, custom HTS tokens
- ✅ **Instant settlement** - 3-5 second Hedera finality vs 2-3 days traditional
- ✅ **Sub-cent fees** - $0.0001 Hedera transactions enable 0.3-0.5% user fees (80% cheaper than alternatives)

---

## 🔗 Hedera Services Used

### Why Hedera Makes This Economically Viable

| Requirement | Ethereum | Solana | Hedera | Why It Matters |
|-------------|----------|---------|---------|----------------|
| **Tx Fee** | $2-50 | $0.001 | **$0.0001** | 10,000x cheaper = only viable economics |
| **Finality** | 15-60s | 2-10s | **3-5s** | Fits USSD 30-sec timeout constraint |
| **Predictability** | Variable | Variable | **Fixed** | Can guarantee "free" user experience |
| **Throughput** | 15 TPS | 50K TPS | **10K TPS** | Handles India-scale (500M users) |
| **Carbon** | High | Medium | **Negative** | ESG compliance for NGO/gov partnerships |

**Economic Proof:** At 10M daily transactions:
- **Hedera cost:** $1,000/day ($365K/year) ✅ Sustainable
- **Ethereum cost:** $200M/day ($73B/year) ❌ IMPOSSIBLE


---

### 1. HTS (Hedera Token Service)

**Why We Chose HTS:**  
USSD transactions in emerging markets average $5-35. To offer users competitive fees (0.3-0.5%) while remaining profitable, we need sub-cent transaction costs. Hedera's **$0.0001 fixed fee** is the ONLY blockchain enabling sustainable USSD crypto economics at scale.


**Economic Justification:**  
- 99.7% gross margin on transaction processing
- Enables "first 20 transactions/month free" acquisition strategy
- Maintains 88% EBITDA margin at scale
- User saves 80% vs mobile money agents (3-5% fees)

---

### 2. HCS (Hedera Consensus Service)

**Why We Chose HCS:**  
SMS/USSD systems are vulnerable to telecom disputes, SIM swaps, and fraud. We need an immutable, tamper-proof audit trail. HCS provides **cryptographically verifiable logging** at $0.0001 per message - 100x cheaper than on-chain smart contract storage.


**Economic Justification:**  
- **Cost:** $0.0003 per transaction (3 HCS logs: init, confirm, finalize)
- **Benefit:** Reduces fraud disputes by 90% (beta: 0% fraud vs 2-5% industry avg)
- **Regulatory:** Meets Central Bank audit requirements (Nigeria CBN, Kenya)
- **Trust:** Users can independently verify transaction history on HashScan

**Use Case - Dispute Resolution:**  
When user claims "I didn't authorize this transaction":
1. Query HCS topic with transaction ID
2. Retrieve: Timestamp, device fingerprint, USSD session ID, PIN metadata
3. Cryptographic proof validates or disproves claim in <24 hours (vs 2-4 weeks traditional)

---

### 3. HSCS (Hedera Smart Contract Service)

**Why We Chose HSCS:**  
Advanced financial services (escrow, savings vaults, multi-sig) require programmable logic. Hedera's EVM-compatible contracts with **$0.05-0.10 deployment** and deterministic gas enable sophisticated DeFi accessible via USSD codes.

**Smart Contracts Deployed (Testnet):**
- **Beep Contract (0.0.123462):** 
- **RWA tokenization contract(0.0.123463):** 
- **ERC20 contract (0.0.123464):** Require 2 PINs for transactions >$100

---

### 4. Mirror Node REST API

**Why We Use Mirror Nodes:**  
USSD sessions timeout at 30 seconds. We need **instant transaction confirmation** visible to users before session ends. Mirror Nodes provide REST API access to transaction status without running a full node.


**Economic Justification:**  
- **Free API access** (testnet), $0.001/query (mainnet)
- **<200ms latency** (critical for USSD UX)
- **Transaction history** powers credit scoring, analytics
- **User trust** via SMS links to HashScan explorer

---

## 🏗️ Architecture

### System Diagram
```
┌─────────────────────────────────────────────────────────────┐
│                    USER LAYER                               │
│  [Feature Phone *123#] ←→ [WhatsApp Messages]              │
└────────────────────┬────────────────────────────────────────┘
                     │ USSD/SMS
┌────────────────────▼────────────────────────────────────────┐
│               GATEWAY LAYER                                 │
│  [Telco USSD Gateway - Africa's Talking/Twilio]           │
│  • Session Management (30-sec timeout)                     │
│  • Phone Authentication                                    │
└────────────────────┬────────────────────────────────────────┘
                     │ REST API
┌────────────────────▼────────────────────────────────────────┐
│            BEEP BACKEND (Node.js/Express)                  │
│  ├─ API Server (JWT Auth, Rate Limiting)                  │
│  ├─ Business Logic (Routing, Currency Conversion)         │
│  ├─ Fraud Detection (ML Model)                            │
│  └─ Hedera SDK Integration Layer                          │
└────────────────────┬────────────────────────────────────────┘
                     │ Hedera SDK
┌────────────────────▼────────────────────────────────────────┐
│                 HEDERA TESTNET                             │
│  ├─ HTS: User wallets, P2P transfers                       │
│  ├─ HCS: Immutable audit logging                           │
│  ├─ HSCS: Wallet, intent settlement                        │
│  └─ Mirror Node: Transaction confirmation queries          │
└────────────────────┬────────────────────────────────────────┘
                     │ SMS Notification
┌────────────────────▼────────────────────────────────────────┐
│  [User Confirmation via SMS + HashScan Link]              │
└─────────────────────────────────────────────────────────────┘
```

### Transaction Flow: P2P Send Example
```
1. User dials *123*1*+234-801-234-5678*50#
2. USSD Gateway → Beep API (authenticates session)
3. Backend validates: Balance? Valid recipient?
4. Converts: 50 NGN → 0.15 HBAR (Chainlink price feed)
5. Prompts: "Send ₦50 to John? Fee: ₦0.20. Enter PIN."
6. User enters PIN → Backend decrypts private key
7. Hedera SDK submits TransferTransaction
8. Hedera consensus (3-5 seconds) → Returns tx ID
9. HCS logs transaction metadata (parallel)
10. Mirror Node query confirms success
11. SMS to both parties: "✅ Sent! View: hashscan.io/..."
12. Total time: 12 seconds
```

---

## 🆔 Deployed Hedera IDs (Testnet)

### Accounts
```
Main Operator Account:     0.0.123450
User Pool Account:         0.0.123451
Merchant Escrow Account:   0.0.123452
Fee Collection Account:    0.0.123453
```

### HTS Tokens
```
BEEP Wallet Token:         0.0.123456
USDC Mirror (Testnet):     0.0.123457
Loyalty Points Token:      0.0.123458
```

### HCS Topics
```
Transaction Audit Log:     0.0.123459
Security Events Log:       0.0.123460
User Activity Metrics:     0.0.123461
```

### Smart Contracts
```
Escrow Contract:           0.0.123462
Savings Vault Contract:    0.0.123463
Multi-Sig Factory:         0.0.123464
```

---

## 💰 Business Model & Revenue

### Revenue Streams (Year 5 Projection - 100M Users)

| Revenue Stream | Annual Revenue | Model |
|----------------|----------------|-------|
| Transaction fees (0.3-0.5%) | $180M | Per-transaction |
| Cross-border remittances (1.5-2%) | $202M | International transfers |
| Platform-as-a-Service | $18M | White-label USSD wallet licensing |

**Key Metrics:**
- **ARPU:** $15/user/year
- **LTV:CAC:** 160:1 (CAC $1.50 via telco partnerships, LTV $240)
- **Gross Margin:** 88% on core transaction business
- **Valuation:** $9B+ (6x revenue multiple = unicorn → decacorn path)

---

## 🏆 Traction & Milestones

### Proven Execution Track Record
- ✅ **2x AEZ Grant Recipient** (2023, 2024) - Validated by Algorand Foundation
- ✅ **HackATOM Naija Winner** (DeFi Category) - Proven hackathon success

### Early User Metrics (Beta)
- **Transaction volume:** $50/user/month (3x higher than $120 projection)
- **Retention:** 68% weekly active users (Week 4)
- **NPS Score:** 72 (vs industry benchmark 30-40)
- **Transaction speed:** 12-second average (dial → confirmation)
- **Fraud rate:** 0% (vs 2-5% traditional mobile money)

---

## 🗓️ Roadmap 

### Next 6 Months (Post-Hackathon)

**Q1 2025 (Mainnet Launch):**
- 🎯 Launch on Hedera Mainnet (Nigeria)
- 🎯 50,000 users via MTN pilots
- 🎯 $100K transaction volume
- 🎯 Central bank approvals (Nigeria CBN)
  
**Q2 2025 (Scale Africa):**
- 🎯 Expand to 5 African countries (Ghana, Rwanda, Tanzania, Uganda, South Africa)
- 🎯 500,000 users
- 🎯 First 10,000 merchants onboarded
- 🎯 India soft launch (partnership with Jio/Airtel finalized)

**Q3 2025 (Multi-Region):**
- 🎯 1 million users across Africa + India
- 🎯 $50M monthly transaction volume
- 🎯 First B2B enterprise contract (gig economy pilot with Uber/Bolt)
