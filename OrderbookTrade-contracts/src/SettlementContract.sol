// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title SettlementContract
 * @notice Distributes USDC to winners after a prediction market resolves.
 *         Funded by traders when placing orders through OrderbookTrade.
 *         Called by the CRE Workflow (via Chainlink Forwarder) after market resolution.
 */
contract SettlementContract {
    // ─── Events ───────────────────────────────────────────────────────────

    event FundsDeposited(bytes32 indexed marketId, address indexed trader, uint256 amount);
    event MarketSettled(bytes32 indexed marketId, uint256 winnerCount, uint256 totalPayout);
    event Withdrawn(address indexed trader, uint256 amount);

    // ─── State ────────────────────────────────────────────────────────────

    IERC20 public immutable USDC;
    address public immutable CRE_FORWARDER;

    /// @notice Deposited funds per market per trader
    mapping(bytes32 => mapping(address => uint256)) public deposits;

    /// @notice Total pool per market
    mapping(bytes32 => uint256) public marketPool;

    /// @notice Whether a market has been settled
    mapping(bytes32 => bool) public settled;

    /// @notice Pending withdrawals per trader
    mapping(address => uint256) public pendingWithdrawals;

    // Sepolia USDC: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
    constructor(address _usdc, address _creForwarder) {
        USDC = IERC20(_usdc);
        CRE_FORWARDER = _creForwarder;
    }

    modifier onlyForwarder() {
        require(msg.sender == CRE_FORWARDER, "Only CRE Forwarder");
        _;
    }

    // ─── Deposit (called when order is placed) ───────────────────────────

    function deposit(bytes32 marketId, uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        USDC.transferFrom(msg.sender, address(this), amount);
        deposits[marketId][msg.sender] += amount;
        marketPool[marketId] += amount;
        emit FundsDeposited(marketId, msg.sender, amount);
    }

    // ─── Settle (called by CRE Workflow via Forwarder) ───────────────────

    /**
     * @notice Distributes market pool proportionally to winners.
     *         Called by CRE Workflow after verifying the real-world outcome.
     * @param marketId  The resolved market
     * @param winners   Array of winner addresses (from OrderbookTrade matched orders)
     * @param amounts   Array of USDC amounts each winner should receive
     */
    function settle(bytes32 marketId, address[] calldata winners, uint256[] calldata amounts) external onlyForwarder {
        require(!settled[marketId], "Already settled");
        require(winners.length == amounts.length, "Length mismatch");
        require(winners.length > 0, "No winners");

        settled[marketId] = true;

        uint256 totalPayout = 0;
        for (uint256 i = 0; i < winners.length; i++) {
            pendingWithdrawals[winners[i]] += amounts[i];
            totalPayout += amounts[i];
        }

        require(totalPayout <= marketPool[marketId], "Payout exceeds pool");

        emit MarketSettled(marketId, winners.length, totalPayout);
    }

    // ─── Withdraw ─────────────────────────────────────────────────────────

    function withdraw() external {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        pendingWithdrawals[msg.sender] = 0;
        USDC.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    // ─── View helpers ─────────────────────────────────────────────────────

    function getMarketPool(bytes32 marketId) external view returns (uint256) {
        return marketPool[marketId];
    }

    function getPendingWithdrawal(address trader) external view returns (uint256) {
        return pendingWithdrawals[trader];
    }
}
