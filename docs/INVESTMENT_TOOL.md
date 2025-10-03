# EtBook Investment Decision Tool

Version: 0.1.0 (engine `INVESTMENT_ENGINE_VERSION` in code)

## Purpose
Professional-grade, mobile-first investment planning, comparison, portfolio construction, scenario simulation, and export module. Ethiopia-first (ETB) with global multi-currency readiness. Transparent, explainable, tax-aware.

## Modules
- Plan: Single investment modeling (cash flows, taxes, leverage TBD)
- Compare: Up to 6 strategies with deltas & sensitivity
- Portfolio: Allocation builder, optimizers (min variance, risk parity, equal-weight baseline)
- Scenarios: Monte Carlo & stress presets (Base/Bear/Bull) (initial subset implemented)
- Schedule: Tabular cash-flow/amortization view (placeholder)
- Export: PDF / CSV / deep link (placeholders pending)

## Engine Architecture
`src/investment/engine` contains pure functions:
- deterministic.ts: NPV, IRR, XIRR, MIRR, payback, benefit-cost ratio, drawdown, Sharpe/Sortino
- monteCarlo.ts: Seeded simulation supporting normal, lognormal, student-t distributions
- portfolio.ts: Basic optimizers (min variance via projected gradient, risk parity approximation, equal weight)
- decision.ts: Objective-based scoring to propose top strategies

State layer: `src/investment/state/investmentStore.ts` (Zustand + persistence).
Rules: `src/investment/rules/*` tax packs.
Versioning: `src/investment/version.ts` referenced in exports & audit trail.

## Ethiopia 2025 Example Tax Pack
`ethiopia-tax-pack-2025.json` contains simplified, editable illustrative rates (NOT official). Includes dividend & interest withholding, capital gains categories, rental allowance, transaction duties.

## Glossary
- XIRR: Extended IRR using irregular actual dates.
- IRR: Discount rate making NPV of ordered periodic cash flows = 0.
- NPV: Present value of future cash flows discounted at required rate.
- MIRR: Modified IRR using finance & reinvestment rates.
- Payback Period: Time until cumulative cash flows become >= 0.
- Benefit–Cost Ratio: PV(benefits)/PV(costs) > 1 implies value creation.
- TWR (Time-Weighted Return): Performance measure stripping out external flow timing bias.
- Max Drawdown: Largest peak-to-trough percentage decline.
- Sharpe Ratio: (Return - Risk-free) / Volatility (annualized).
- Sortino Ratio: (Return - Risk-free) / Downside deviation.
- Drawdown (probability of ruin context): Probability of capital falling below threshold or failing goal.
- Rebalancing: Adjusting weights back to targets.
- Withholding Tax: Tax retained at source on income distributions.
- FX Spread: Difference between mid-market rate and actual trade (cost).
- Cap Rate: Net operating income / property value.
- NOI: Rental income minus operating expenses (before debt & taxes).
- DSCR: Debt Service Coverage Ratio = NOI / Debt Service.
- Equity Multiple: Total distributions / total equity invested.

## Playbooks (Initial Drafts)
### T-bills vs Savings (After Tax)
Compare expected net yield using tax pack withholding & any deposit taxes; adjust contributions and reinvestment assumptions.

### Rental: Buy/Hold/Sell Decision Tree
Model purchase (outflow), periodic rental net income (NOI), capex, sale proceeds minus transaction costs & capital gains tax, compare IRR vs required hurdle and scenario sell timings.

### Post-tax vs Pre-tax Returns
Run the same cash-flow under two tax packs: real rates vs zero-tax baseline to surface tax drag (delta in XIRR and Ending Value).

### ETB → USD Goals and FX Risk
Simulate contributions in ETB with FX shock bands to probability of reaching USD target (goal success probability from Monte Carlo).

## Planned Enhancements (Roadmap)
- Real estate specific metrics (cap rate, NOI breakdown, DSCR) integration
- Leverage modeling (LTV, margin call, amortization schedule)
- Stress test panel (FX ±, rent vacancy shock, fee increase) UI
- PDF memo export (charts + assumptions + tax pack ID + engine version) ≤2MB
- Deep link encoder/decoder (base64 + checksum)
- Sensitivity tornado builder for NPV / XIRR factors
- Goal planning (reach target by date; drawdown retirement probability)
- Optimizer: Mean-variance frontier sweep & top 3 suggestions
- Black-Litterman (stretch)

## Data & Persistence
- Local persisted store key: `investment-store-v1`
- Each export (future) must embed: engineVersion, taxPackId(s), timestamp, user locale

## Assumptions & Limitations (Current Stage)
- Taxes applied only through placeholder pack (no dynamic application yet in deterministic metrics)
- Monte Carlo uses simplistic arithmetic to monthly conversion; drift adjustment minimal
- Portfolio optimization is heuristic / educational, not institutional-grade solver
- Schedule & exports placeholders; no PDF or CSV generation yet

## Disclaimers
Educational tool; not investment advice. User-provided data & assumptions drive outputs; accuracy not guaranteed. Past performance not indicative of future results.

## Testing
`tests/unit/investment-engine.test.ts` covers deterministic metrics presence, Monte Carlo reproducibility, optimizer outputs, decision engine shape. Target ≥85% engine coverage in future.

## Accessibility
Planned: VoiceOver labels for all metric tiles, text alternatives for charts, high-contrast theme compatibility.

## Contributing
1. Add/modify engine logic then bump `INVESTMENT_ENGINE_VERSION`.
2. Update tests for parity.
3. Add migration note if export schema changes.

## License & Compliance
All logic is deterministic & offline; no external market data fetched. Ensure user acceptance of disclaimers before exporting (to implement in export screen).
