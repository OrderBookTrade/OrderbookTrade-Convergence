// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PredictionMarket
 * @notice Onchain prediction market contract for OrderbookTrade.
 *         Designed to be resolved by a CRE Workflow via the Chainlink Forwarder.
 *
 * Flow:
 *   1. Anyone creates a market with a question, asset, threshold, and expiry.
 *   2. The CRE Workflow monitors active markets (Cron trigger).
 *   3. When a market expires, the CRE Workflow resolves it (EVM Log trigger fires).
 *   4. The SettlementContract distributes funds to winners.
 */
contract PredictionMarket {
    // ─── Events ───────────────────────────────────────────────────────────

    /// @notice Emitted when a market is created
    event MarketCreated(bytes32 indexed marketId, string question, string asset, uint256 threshold, uint256 expiry);

    /// @notice Emitted when a market is resolved — CRE EVM Log Trigger listens to this
    event MarketResolved( // true = YES wins, false = NO wins
    bytes32 indexed marketId, bool outcome);

    /// @notice Emitted by CRE Workflow heartbeat (Cron trigger)
    event ActiveMarketCountUpdated(uint256 count, uint256 timestamp);

    // ─── State ────────────────────────────────────────────────────────────

    struct Market {
        string question;
        string asset;
        uint256 threshold; // e.g. 100000 * 1e8 for $100K BTC
        uint256 expiry; // unix timestamp
        bool resolved;
        bool outcome;
    }

    mapping(bytes32 => Market) public markets;
    bytes32[] public marketIds;

    uint256 public activeMarketCount;

    /// @notice Only the CRE Forwarder contract can call protected functions
    address public immutable CRE_FORWARDER;

    constructor(address _creForwarder) {
        CRE_FORWARDER = _creForwarder;
    }

    modifier onlyForwarder() {
        require(msg.sender == CRE_FORWARDER, "Only CRE Forwarder");
        _;
    }

    // ─── Market creation ─────────────────────────────────────────────────

    function createMarket(string calldata question, string calldata asset, uint256 threshold, uint256 expiry)
        external
        returns (bytes32 marketId)
    {
        require(expiry > block.timestamp, "Expiry must be in the future");

        marketId = keccak256(abi.encodePacked(question, asset, threshold, expiry, block.timestamp));
        require(markets[marketId].expiry == 0, "Market already exists");

        markets[marketId] = Market({
            question: question,
            asset: asset,
            threshold: threshold,
            expiry: expiry,
            resolved: false,
            outcome: false
        });

        marketIds.push(marketId);

        emit MarketCreated(marketId, question, asset, threshold, expiry);
    }

    // ─── CRE Workflow functions ───────────────────────────────────────────

    /**
     * @notice Called by CRE Workflow (Cron Handler) as a heartbeat.
     *         Updates the active market count onchain.
     */
    function updateActiveMarketCount(uint256 count) external onlyForwarder {
        activeMarketCount = count;
        emit ActiveMarketCountUpdated(count, block.timestamp);
    }

    /**
     * @notice Resolves a market. Called by CRE Workflow after confirming outcome.
     *         Emits MarketResolved event which the CRE EVM Log Trigger listens to.
     * @param marketId  The market to resolve
     * @param outcome   true = YES wins (e.g. BTC > $100K), false = NO wins
     */
    function resolveMarket(bytes32 marketId, bool outcome) external onlyForwarder {
        Market storage market = markets[marketId];
        require(market.expiry > 0, "Market does not exist");
        require(!market.resolved, "Market already resolved");
        require(block.timestamp >= market.expiry, "Market not yet expired");

        market.resolved = true;
        market.outcome = outcome;

        emit MarketResolved(marketId, outcome);
    }

    // ─── View helpers ─────────────────────────────────────────────────────

    function getMarket(bytes32 marketId) external view returns (Market memory) {
        return markets[marketId];
    }

    function getActiveMarketIds() external view returns (bytes32[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < marketIds.length; i++) {
            if (!markets[marketIds[i]].resolved) count++;
        }

        bytes32[] memory active = new bytes32[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < marketIds.length; i++) {
            if (!markets[marketIds[i]].resolved) {
                active[idx++] = marketIds[i];
            }
        }
        return active;
    }
}
