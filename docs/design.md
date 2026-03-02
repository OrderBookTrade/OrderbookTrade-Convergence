# OrderbookTrade — Prediction Market Infrastructure Architecture Design

> **Project**: OrderbookTrade Convergence  
> **Hackathon**: Chainlink Convergence Hackathon 2026  
> **Track**: Prediction Markets  
> **Core Tech**: Chainlink CRE (Compute Runtime Environment) + Solidity + CCIP  
---

## Table of Contents

1. [Overview & Core Philosophy](#1-overview--core-philosophy)
2. [High-Level Architecture](#2-high-level-architecture)
3. [On-Chain Layer — Smart Contracts](#3-on-chain-layer--smart-contracts)
4. [CRE Orchestration Layer — Workflows](#4-cre-orchestration-layer--workflows)
5. [Peripheral Layer — SDK, Testing & Extensions](#5-peripheral-layer--sdk-testing--extensions)
6. [Data Flow & Interaction Sequences](#6-data-flow--interaction-sequences)
7. [Technology Stack](#7-technology-stack)
8. [Scalability & Optimization](#8-scalability--optimization)
9. [Edge Cases & Risk Mitigation](#9-edge-cases--risk-mitigation)
10. [Hackathon Submission Preparation Guide](#10-hackathon-submission-preparation-guide)

---

## 1. Overview & Core Philosophy

### What We're Building

A **protocol-level prediction market infrastructure** that separates the concerns of:

- **On-Chain Contracts** — stateless execution engines handling core market logic
- **CRE Workflows** — intelligent agents that orchestrate off-chain/cross-chain operations via Chainlink's Decentralized Oracle Network (DON)

This is **not** a single DApp. It's a modular, reusable infra layer — an ecosystem enabler where third-party developers can build custom prediction markets on top using our SDK and templates.

### Why This Architecture?

| Perspective | Rationale |
|---|---|
| **Technical** | Pure on-chain markets (legacy Polymarket) suffer from high gas costs and slow settlement. CRE offloads computation to DON, achieving **~10x efficiency gains**. |
| **Ecosystem** | Aligns with Chainlink's narrative of CRE as "onchain finance rails". Easily integrates with RWA projects (e.g., Ondo tokenized assets) and DeFi protocols. |
| **Hackathon** | CRE must be "core orchestration" (not just a plugin). Tenderly Virtual TestNets demonstrate the full pipeline. |
| **Business** | Positions for institutional adoption — standardized infra that banks/funds can use for risk hedging, RWA prediction, and internal forecasting. |

### Core Value Propositions

1. **CLOB Matching Engine** — Off-chain order matching with on-chain settlement for capital efficiency
2. **AI-Powered Settlement** — Automated market resolution using Chainlink Data Streams + AI (Gemini) for ambiguous events
3. **Cross-Chain Liquidity Aggregation** — CCIP-powered routing across Base/Ethereum/Optimism for deep liquidity pools

---

## 2. High-Level Architecture

### Layered Design

```
┌──────────────────────────────────────────────────────────────────┐
│                     USER / FRONTEND LAYER                        │
│              Web App  ·  SDK  ·  API Consumers                   │
└──────────────┬───────────────────────────────┬───────────────────┘
               │                               │
               │  Place Orders / Create Markets │  Read State
               ▼                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                     ON-CHAIN LAYER (Solidity)                    │
│                                                                  │
│  ┌─────────────────┐  ┌──────────────────┐  ┌────────────────┐  │
│  │  MarketFactory   │  │  MatchingEngine  │  │ SettlementVault│  │
│  │  Create markets  │  │  CLOB execution  │  │ Settle & pay   │  │
│  │  ERC-1155 tokens │  │  Order book      │  │ Liquidity mgmt │  │
│  └────────┬────────┘  └───────┬──────────┘  └───────┬────────┘  │
│           │ emit               │ emit                │ emit      │
│      MarketCreated        NewOrder           SettlementRequest   │
└───────────┼────────────────────┼─────────────────────┼───────────┘
            │                    │                     │
            ▼                    ▼                     ▼
┌──────────────────────────────────────────────────────────────────┐
│                   CRE ORCHESTRATION LAYER                        │
│              Chainlink DON — Event-Driven Workflows              │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐ │
│  │  MatchWorkflow    │  │  SettleWorkflow  │  │ LiqAggWorkflow │ │
│  │  Off-chain match  │  │  AI + Data Feed  │  │ Cross-chain    │ │
│  │  → executeMatch() │  │  → settleMarket()│  │ → updateLiq()  │ │
│  └──────────────────┘  └──────────────────┘  └────────────────┘ │
│                     │              │              │               │
│                     ▼              ▼              ▼               │
│             ┌─────────────────────────────────────────┐          │
│             │  External Services                      │          │
│             │  Data Streams · CCIP · Gemini AI · DEXs │          │
│             └─────────────────────────────────────────┘          │
└──────────────────────────────────────────────────────────────────┘
```

### Component Responsibility Matrix

| Component | Layer | Language | Responsibility |
|---|---|---|---|
| `MarketFactory` | On-Chain | Solidity | Create prediction markets, mint outcome tokens (ERC-1155) |
| `MatchingEngine` | On-Chain | Solidity | Accept orders, execute matched trades (from CRE) |
| `SettlementVault` | On-Chain | Solidity | Hold collateral, distribute payouts, manage liquidity |
| `MatchWorkflow` | CRE | Go | Listen for `NewOrder`, aggregate liquidity, compute matches off-chain, write back |
| `SettleWorkflow` | CRE | Go | Listen for `SettlementRequest`, fetch data + AI resolution, write back outcome |
| `LiqAggWorkflow` | CRE | Go | Scheduled cross-chain liquidity reads via CCIP, update on-chain pool view |
| SDK | Peripheral | TypeScript | Developer-facing library for market creation & workflow deployment |

---

## 3. On-Chain Layer — Smart Contracts

> **Estimated code share**: ~60% of project  
> **Framework**: Foundry (Solidity ^0.8.13)  
> **Network**: Ethereum Sepolia → Base Mainnet

### 3.1 MarketFactory

**Purpose**: Factory pattern for creating new prediction markets with configurable parameters.

```solidity
// Core interface (simplified)
interface IMarketFactory {
    /// @notice Create a new prediction market
    /// @param question Human-readable market question
    /// @param outcomes Array of possible outcomes (e.g., ["Yes", "No"])
    /// @param deadline Timestamp when market closes for betting
    /// @param collateralToken ERC-20 used as collateral (e.g., USDC)
    /// @param initialLiquidity Seed liquidity amount
    function createMarket(
        string calldata question,
        string[] calldata outcomes,
        uint256 deadline,
        address collateralToken,
        uint256 initialLiquidity
    ) external returns (uint256 marketId);

    event MarketCreated(
        uint256 indexed marketId,
        string question,
        uint256 deadline,
        address creator
    );
}
```

**Key Design Decisions**:
- **ERC-1155** for outcome tokens — gas-efficient batch operations, one contract for all markets
- **Configurable collateral** — supports USDC, LINK, or any ERC-20
- Market state machine: `Open → Closed → Resolving → Settled`

### 3.2 MatchingEngine

**Purpose**: Central Limit Order Book (CLOB) on-chain — accepts orders, executes CRE-computed matches.

```solidity
interface IMatchingEngine {
    struct Order {
        uint256 marketId;
        address trader;
        bool isBuy;           // true = buy outcome token, false = sell
        uint256 price;        // in basis points (0-10000)
        uint256 amount;       // outcome token quantity
        uint256 timestamp;
    }

    /// @notice Place a new limit order
    function placeOrder(
        uint256 marketId,
        bool isBuy,
        uint256 price,
        uint256 amount
    ) external returns (bytes32 orderId);

    /// @notice Execute matched orders (called by CRE via Forwarder)
    /// @dev Only callable by authorized CRE DON
    function executeMatch(
        bytes32[] calldata buyOrderIds,
        bytes32[] calldata sellOrderIds,
        uint256[] calldata fillAmounts,
        uint256 executionPrice
    ) external;

    event NewOrder(bytes32 indexed orderId, uint256 indexed marketId, address trader);
    event OrderMatched(bytes32 buyOrderId, bytes32 sellOrderId, uint256 price, uint256 amount);
}
```

**Key Design Decisions**:
- Orders stored on-chain for transparency; matching computed off-chain for gas efficiency
- **Access control**: `executeMatch` restricted to Chainlink Forwarder contract (CRE DON)
- Anti-MEV: order hashing + commit-reveal optional for large orders

### 3.3 SettlementVault

**Purpose**: Escrow, settlement, and liquidity management.

```solidity
interface ISettlementVault {
    /// @notice Request market resolution (can be triggered by anyone after deadline)
    function requestSettlement(uint256 marketId) external;

    /// @notice Settle market with outcome (called by CRE SettleWorkflow)
    /// @dev Distributes payouts to winning outcome token holders
    function settleMarket(
        uint256 marketId,
        uint256 winningOutcome,
        bytes calldata proof    // DON consensus attestation
    ) external;

    /// @notice Update cross-chain liquidity view (called by CRE LiqAggWorkflow)
    function updateLiquidity(
        uint256 marketId,
        uint256[] calldata chainLiquidities,
        uint64[] calldata chainSelectors
    ) external;

    event SettlementRequested(uint256 indexed marketId, uint256 deadline);
    event MarketSettled(uint256 indexed marketId, uint256 winningOutcome);
    event LiquidityUpdated(uint256 indexed marketId, uint256 totalLiquidity);
}
```

**Key Design Decisions**:
- **DON attestation proof** required for settlement — prevents single-point manipulation
- Liquidity view is advisory (read layer for UI/routing), not custodial across chains
- Integration point for **Chainlink VRF** on edge cases (random tiebreakers)

### 3.4 Token Architecture

```
ERC-1155 Outcome Tokens
├── tokenId = marketId * 100 + outcomeIndex
├── Minted on order fill via MatchingEngine
├── Burned on settlement payout via SettlementVault
└── Transferable — enables secondary market trading
```

---

## 4. CRE Orchestration Layer — Workflows

> **Estimated code share**: ~30% of project (hackathon focus)  
> **Language**: Go (CRE SDK `cre-sdk-go`)  
> **Runtime**: WASM on Chainlink DON nodes

### 4.1 MatchWorkflow — Order Matching

**Trigger**: `NewOrder` event from `MatchingEngine` contract  
**Frequency**: Event-driven (every new order)

```
┌─────────────┐     ┌──────────────────┐     ┌───────────────────┐     ┌──────────────┐
│  NewOrder    │────▶│  Read Order Book │────▶│  Match Algorithm  │────▶│ executeMatch │
│  (trigger)   │     │  + Aggregated    │     │  Price-Time       │     │ (write-back) │
│              │     │  Liquidity View  │     │  Priority CLOB    │     │              │
└─────────────┘     └──────────────────┘     └───────────────────┘     └──────────────┘
```

**Logic Flow**:
1. Listen for `NewOrder` event on-chain
2. Read current order book state + cross-chain liquidity snapshot
3. Run price-time priority matching algorithm off-chain
4. Compute optimal fill (partial fills supported)
5. DON consensus on match result
6. Write `executeMatch()` back to contract

**Key Considerations**:
- **Latency**: DON consensus ~seconds, suitable for mid-frequency markets
- **High-frequency edge**: Use optimistic matching + on-chain challenge for sub-second markets

### 4.2 SettleWorkflow — Market Resolution

**Trigger**: `SettlementRequested` event from `SettlementVault`  
**Frequency**: Event-driven (after market deadline)

```
┌────────────────┐     ┌──────────────────┐     ┌─────────────────┐     ┌──────────────┐
│ SettlementReq  │────▶│  Fetch Data      │────▶│  AI Resolution  │────▶│ settleMarket │
│ (trigger)      │     │  Chainlink Data  │     │  Gemini API     │     │ (write-back) │
│                │     │  Streams         │     │  Parse outcome  │     │ + DON proof  │
└────────────────┘     └──────────────────┘     └─────────────────┘     └──────────────┘
```

**Logic Flow**:
1. Listen for `SettlementRequested` event
2. Fetch real-world data via Chainlink Data Streams (price feeds, sports scores, etc.)
3. For ambiguous events: invoke **Gemini AI** via HTTP capability to parse natural language outcomes
4. DON consensus on resolved outcome
5. Write `settleMarket()` with consensus proof back to contract

**AI Integration Details**:
- **Clear events** (e.g., "BTC > $100k on March 1?"): Data Streams alone suffice
- **Ambiguous events** (e.g., "Will AI regulation pass?"): AI parses news + data, returns structured outcome
- **Confidential Compute** (optional): Hide sensitive settlement data from individual DON nodes

### 4.3 LiqAggWorkflow — Cross-Chain Liquidity Aggregation

**Trigger**: Cron schedule (every 30 seconds) + on-demand event  
**Frequency**: Scheduled + event-driven hybrid

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────────┐     ┌────────────────┐
│  Cron / Event│────▶│  CCIP Cross-Chain│────▶│  Compute Route  │────▶│ updateLiquidity│
│  (trigger)   │     │  Read DEX Depth  │     │  Best execution │     │ (write-back)   │
│              │     │  Base/Eth/Opt    │     │  path            │     │                │
└──────────────┘     └──────────────────┘     └─────────────────┘     └────────────────┘
```

**Logic Flow**:
1. Triggered by cron (`*/30 * * * * *`) or liquidity threshold event
2. Read liquidity depth from DEXs across multiple chains via **CCIP**
3. Compute optimal routing and aggregate liquidity view
4. Write `updateLiquidity()` to `SettlementVault` on primary chain

**Cross-Chain Support**:
- Ethereum Sepolia, Base, Optimism (initial)
- CCIP chain selectors for each target
- Liquidity view is non-custodial: advisory data for order routing

### 4.4 Workflow Configuration

```yaml
# workflow.yaml — Staging Target
staging-settings:
  user-workflow:
    workflow-name: "orderbooktrade-workflow-staging"
  workflow-artifacts:
    workflow-path: "."
    config-path: "./config.staging.json"
    secrets-path: ""
```

```yaml
# project.yaml — RPC Configuration
staging-settings:
  rpcs:
    - chain-name: ethereum-testnet-sepolia
      url: https://ethereum-sepolia-rpc.publicnode.com
```

---

## 5. Peripheral Layer — SDK, Testing & Extensions

> **Estimated code share**: ~10% of project

### 5.1 JavaScript SDK (Future / Bonus)

```typescript
// Example: Creating a market via SDK
import { OrderbookTrade } from '@orderbooktrade/sdk';

const infra = new OrderbookTrade({
  rpc: 'https://sepolia.infura.io/v3/...',
  signer: wallet,
});

const market = await infra.createMarket({
  question: 'Will ETH reach $10k by June 2026?',
  outcomes: ['Yes', 'No'],
  deadline: 1751328000,
  collateral: USDC_ADDRESS,
  initialLiquidity: 10000e6,
});

await infra.placeOrder(market.id, {
  side: 'buy',
  outcome: 0,   // "Yes"
  price: 6500,  // 65.00%
  amount: 100,
});
```

### 5.2 Testing Strategy

| Layer | Tool | Purpose |
|---|---|---|
| Contracts | Foundry (`forge test`) | Unit tests for all contract functions |
| Contracts | Tenderly Virtual TestNet | Integration tests with full fork state |
| Workflows | CRE Simulator (`cre sim`) | Local workflow execution testing |
| E2E | Tenderly + CRE Deploy | Full pipeline: event → CRE → write-back |

### 5.3 Optional Extensions

- **x402 Payments**: AI agent pays for settlement API calls via x402 protocol
- **Chainlink VRF**: Random tiebreakers for edge-case market resolution
- **ACE (Access Control Engine)**: KYC/compliance layer for institutional markets

---

## 6. Data Flow & Interaction Sequences

### 6.1 Normal Trading Flow

```
User                  MatchingEngine         CRE MatchWorkflow        SettlementVault
 │                          │                       │                       │
 │── placeOrder() ─────────▶│                       │                       │
 │                          │── emit NewOrder ──────▶│                       │
 │                          │                       │── read order book ────▶│
 │                          │                       │◀── liquidity data ─────│
 │                          │                       │                       │
 │                          │                       │── compute match ──┐   │
 │                          │                       │◀─ DON consensus ──┘   │
 │                          │                       │                       │
 │                          │◀── executeMatch() ────│                       │
 │◀── OrderMatched event ───│                       │                       │
```

### 6.2 Settlement Flow

```
Anyone                SettlementVault         CRE SettleWorkflow       External
 │                          │                       │                    │
 │── requestSettlement() ──▶│                       │                    │
 │                          │── emit SettlementReq ▶│                    │
 │                          │                       │── Data Streams ───▶│
 │                          │                       │◀── price/score ────│
 │                          │                       │── Gemini AI ──────▶│
 │                          │                       │◀── parsed outcome ─│
 │                          │                       │                    │
 │                          │                       │── DON consensus ──┐│
 │                          │                       │◀─────────────────┘ │
 │                          │◀── settleMarket() ────│                    │
 │◀── MarketSettled event ──│                       │                    │
```

### 6.3 Cross-Chain Liquidity Aggregation Flow

```
Cron Timer            CRE LiqAggWorkflow      CCIP Bridge             DEXs (Multi-Chain)
 │                          │                       │                       │
 │── trigger ──────────────▶│                       │                       │
 │                          │── CCIP read ─────────▶│── read depth ────────▶│
 │                          │                       │◀── liquidity data ────│
 │                          │◀── aggregated data ───│                       │
 │                          │                       │                       │
 │                          │── compute routing ──┐ │                       │
 │                          │◀───────────────────┘  │                       │
 │                          │                       │                       │
 │                          │── updateLiquidity() ──▶ SettlementVault       │
```

### 6.4 Performance & Security Characteristics

| Aspect | Design Choice | Implication |
|---|---|---|
| **Latency** | DON consensus ~seconds | Suitable for mid-frequency prediction markets |
| **Security** | DON multi-node consensus | Prevents single-point oracle manipulation |
| **Oracle Failure** | Fallback to manual DAO vote resolution | Markets never stuck permanently |
| **Cross-Chain** | CCIP bridges Base/Eth/Optimism | Multi-chain ecosystem, deeper liquidity |
| **Privacy** | Confidential Compute (optional) | Attracts institutional/TradFi users |
| **MEV** | Commit-reveal option for large orders | Protects traders from frontrunning |

---

## 7. Technology Stack

| Category | Technology | Purpose |
|---|---|---|
| Smart Contracts | Solidity ^0.8.13 | Core market logic |
| Contract Framework | Foundry (Forge) | Build, test, deploy |
| CRE Workflows | Go + CRE SDK | Off-chain orchestration |
| CRE Runtime | WASM (wasip1) | DON node execution |
| Cross-Chain | Chainlink CCIP | Bridge reads/writes across EVM chains |
| Data Feeds | Chainlink Data Streams | Real-time price/event data |
| AI | Google Gemini (HTTP) | Ambiguous event resolution |
| Testing | Tenderly Virtual TestNets | Fork-based integration testing |
| Network | Ethereum Sepolia → Base | Testnet development → mainnet |
| Version Control | GitHub (public) | Source code + documentation |

---

## 8. Scalability & Optimization

### Gas Optimization

- **Off-chain computation**: Matching logic runs in CRE, only results written on-chain
- **ERC-1155 batching**: Single contract for all outcome tokens, batch mint/burn
- **Minimal on-chain state**: Order book stored as mapping, not sorted array

### Modular Extensibility

- **Add new Workflows**: Each CRE workflow is independent — adding RWA, sports, or election markets requires only a new workflow + minor contract extension
- **Multi-chain**: Deploy contracts on any EVM chain; CRE workflows chain-agnostic via config
- **SDK composability**: Third parties build on top without understanding CRE internals

### Cost Model

| Resource | Payer | Mechanism |
|---|---|---|
| Gas (contract txns) | User / Protocol | ETH/native token |
| CRE execution | Protocol | LINK token |
| AI API calls | Protocol | x402 / API key |
| CCIP messages | Protocol | LINK token |

---

## 9. Edge Cases & Risk Mitigation

| Edge Case | Mitigation Strategy |
|---|---|
| **Low liquidity** | Auto-rebalance via LiqAggWorkflow; minimum liquidity thresholds |
| **Disputed settlement** | Multi-oracle consensus + AI + fallback DAO vote |
| **Oracle downtime** | Grace period before fallback; redundant data sources |
| **CRE node failure** | DON redundancy (F+1 of N nodes); auto-retry |
| **AI bias/hallucination** | Multi-source verification; human-in-the-loop for high-value markets |
| **MEV / Frontrunning** | Commit-reveal scheme; CRE batch execution |
| **Regulatory (KYC)** | Optional ACE integration for permissioned markets |
| **Market manipulation** | Position limits; cross-reference with Data Streams |

---

## 10. Hackathon Submission Preparation Guide

### 10.1 Timeline (6-Day Countdown to March 8)

| Day | Focus | Deliverable |
|---|---|---|
| **Day 1-2** | Build MVP | Contracts + 3 CRE Workflows |
| **Day 3** | Testing | Tenderly deployment + simulation |
| **Day 4** | Documentation | README + design docs + demo video |
| **Day 5** | Polish | Community feedback (Discord/X), bug fixes |
| **Day 6** | Submit | Final submission via chain.link/hackathon |

> **⚠️ Deadline**: March 8, 2026, 23:59 ET (March 9 ~12:00 UTC+8)

### 10.2 Required Submission Materials

#### GitHub Repository
- **Public repo** with complete, runnable source code
- Clear structure: `contracts/`, `workflows/`, `scripts/`, `tests/`, `docs/`, `sdk/`
- Comprehensive README (see below)
- MIT license for open-source positioning

#### README.md Checklist
- [ ] Project Overview + core value proposition
- [ ] Architecture diagram (text or image)
- [ ] Setup / Installation instructions (clone → install → deploy → run)
- [ ] Usage examples with code snippets
- [ ] **CRE Integration section** (detailed workflow code + orchestration explanation)
- [ ] Testing section with Tenderly links
- [ ] Future work / extensibility

#### Tenderly Virtual TestNet Explorer Link
- Deploy all contracts + run workflows on Tenderly fork of Sepolia
- Generate at least 5-10 transactions demonstrating the full pipeline
- Link the explorer URL in README and submission form

#### Demo Video (3-5 min, YouTube unlisted)
- **0:00-0:30** — Problem statement + solution overview
- **0:30-2:00** — Live demo: create market → place order → CRE match → settle
- **2:00-3:00** — Deep dive into CRE workflow code + execution logs
- **3:00-5:00** — Innovation highlights + real-world impact

#### Submission Form
- Via [chain.link/hackathon](https://chain.link/hackathon)
- Includes: repo link, video URL, Tenderly link, team info
- Must be a new project (or significant update to existing)

### 10.3 Evaluation Criteria Alignment

| Criteria | How We Score |
|---|---|
| **CRE as Core Orchestration** | 3 workflows as the backbone — not just a plugin |
| **Innovation** | AI settlement + cross-chain aggregation — novel combination |
| **Production Readiness** | Modular infra with SDK, not a toy DApp |
| **Tenderly Integration** | Full transaction history with annotated flows |
| **Documentation Quality** | This design doc + comprehensive README |

---

## Appendix: Repository Structure

```
orderbooktrade-convergence/
├── OrderbookTrade-contracts/          # Foundry project
│   ├── src/
│   │   ├── MarketFactory.sol          # Market creation + ERC-1155 tokens
│   │   ├── MatchingEngine.sol         # CLOB order book + CRE execution
│   │   ├── SettlementVault.sol        # Escrow + settlement + liquidity
│   │   └── interfaces/               # Contract interfaces
│   ├── test/                          # Forge unit tests
│   ├── script/                        # Deployment scripts
│   └── foundry.toml
│
├── orderbooktrade-workflow/           # CRE Workflows (Go)
│   ├── orderbooktrade-workflow/
│   │   ├── main.go                    # WASM entry point
│   │   ├── workflow.go                # Workflow initialization + handlers
│   │   ├── match_handler.go           # MatchWorkflow logic
│   │   ├── settle_handler.go          # SettleWorkflow logic
│   │   ├── liquidity_handler.go       # LiqAggWorkflow logic
│   │   ├── workflow.yaml              # Workflow settings
│   │   └── workflow_test.go           # Workflow tests
│   ├── project.yaml                   # CRE project config
│   └── secrets.yaml                   # Secrets (gitignored)
│
├── sdk/                               # TypeScript SDK (bonus)
│   └── src/
│
├── docs/
│   └── design.md                      # ← This document
│
└── README.md                          # Submission README
```

---

