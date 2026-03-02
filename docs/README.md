# OrderbookTrade × CRE — Prediction Market Settlement

> **Convergence: A Chainlink Hackathon** — Prediction Markets Track

## Overview

OrderbookTrade is a **B2B infrastructure service** that provides prediction market platforms and DeFi protocols with a **High-Performance Central Limit Order Book (CLOB) matching engine**.

This project uses **Chainlink Runtime Environment (CRE)** as the **settlement orchestration layer** — the trusted, decentralized bridge between our off-chain matching engine and on-chain settlement.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                      CRE Workflow (Go)                         │
│                                                                │
│  Handler 1 — Cron Trigger (every 5 min)                        │
│  └─→ GET /markets?status=active  (OrderbookTrade API)          │
│      └─→ EVM Write → updateActiveMarketCount()                 │
│                                                                │
│  Handler 2 — EVM Log Trigger (MarketResolved event)            │
│  └─→ GET CoinGecko BTC/USD price  (consensus across DON nodes) │
│  └─→ GET /orders/matched?marketId  (OrderbookTrade API)        │
│      └─→ Calculate winner payouts                              │
│          └─→ EVM Write → settle(marketId, winners, amounts)    │
└────────────────────────────────────────────────────────────────┘
         ↑ MarketResolved event                ↓ settle()
┌──────────────────────┐             ┌──────────────────────────┐
│  PredictionMarket    │             │   SettlementContract     │
│  .sol (Sepolia)      │             │   .sol (Sepolia)         │
└──────────────────────┘             └──────────────────────────┘
```

**Why CRE?**
- Without CRE: settlement result comes from a single server → users must trust OrderbookTrade
- With CRE: every node in the Chainlink DON independently fetches price + order data, BFT consensus produces a single verified result → **trustless settlement**

---

## Chainlink Files

| File | Description |
|------|-------------|
| `workflow/workflow.go` | CRE Workflow — Cron + EVM Log handlers |
| `workflow/bindings.go` | Type-safe EVM contract bindings |
| `workflow/config.staging.json` | Workflow configuration (Sepolia) |
| `contracts/PredictionMarket.sol` | Onchain prediction market (emits `MarketResolved`) |
| `contracts/SettlementContract.sol` | Distributes USDC to winners via CRE Forwarder |

---

## Quick Start

### Prerequisites
- Go 1.21+
- CRE CLI installed (`cre.chain.link`)
- Sepolia ETH for deployment

### 1. Install CRE CLI & Login
```bash
# Download from cre.chain.link
cre login
```

### 2. Deploy Contracts (Sepolia)
```bash
cd contracts
# Deploy PredictionMarket.sol with CRE Forwarder address
# Deploy SettlementContract.sol with USDC + CRE Forwarder addresses
# Update config.staging.json with deployed addresses
```

### 3. Configure
```bash
cd workflow
# Edit config.staging.json:
# - marketContractAddr: your deployed PredictionMarket address
# - settlementContractAddr: your deployed SettlementContract address
# - orderbookApiUrl: your OrderbookTrade API endpoint
```

### 4. Simulate (Cron Handler)
```bash
cre workflow simulate orderbooktrade-settlement --target staging-settings
# Select: 1. Cron Trigger
```

### 5. Simulate (EVM Log Handler)
```bash
cre workflow simulate orderbooktrade-settlement \
  --non-interactive \
  --trigger-index 1 \
  --evm-tx-hash <tx_hash_of_MarketResolved_event> \
  --evm-event-index 0 \
  --target staging-settings
```

---

## Prediction Market Demo

**Question:** "Will BTC exceed $100,000 by March 8, 2026?"

1. Traders place YES/NO orders via OrderbookTrade CLOB
2. Orders are matched off-chain by the matching engine
3. At expiry, `PredictionMarket.resolveMarket()` is called
4. `MarketResolved` event fires → CRE Workflow triggers
5. CRE fetches BTC price (CoinGecko, consensus-verified)
6. CRE fetches matched orders (OrderbookTrade API)
7. CRE calculates payouts and writes to `SettlementContract`
8. Winners call `withdraw()` to claim USDC

---

## Team

**OrderbookTrade** — High-frequency CLOB matching engine infrastructure for prediction markets and DeFi protocols.

- Twitter: [@OrderbookTrade](https://x.com/OrderbookTrade)
