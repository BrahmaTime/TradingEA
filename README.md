# TradingEA

## Index Opening Range Guardian for MT5

## USOIL M5 Safety Guardian for MT5

`Experts/USOilM5SafetyGuardian.mq5` is a dedicated USOIL M5 Expert Advisor
built for conservative intraday breakout trading with strict risk-first
controls. It uses a retest-confirmed opening-range breakout model with:

- M5 opening-range breakout with optional retest-rebreak confirmation
- EMA 20/50 alignment plus M15 EMA 200 directional filter
- ADX trend-strength filter (default threshold 22)
- ATR-based range quality, stop distance, spread filter, and trailing
- Optional tick-volume participation filter
- EIA inventory blackout window (default Wednesday 17:25-17:45 server time)
- Daily drawdown guard and fixed-fractional account-currency risk sizing
- One-trade-per-day guard by default

### Why this strategy shape for USOIL

There is no strategy that is both guaranteed safe and guaranteed profitable.
The design intentionally favors trade quality over trade frequency. It follows
widely used crude-oil risk principles: avoid event-whipsaw windows, use
ATR-normalized stops/sizing, and require trend-strength confirmation before
breakout participation.

Reference materials reviewed while designing this EA:

- Investopedia: ADX trend-strength interpretation (trend filters)
- Investopedia and ATR position-sizing references (volatility-sized risk)
- U.S. EIA Weekly Petroleum Status Report schedule (10:30 ET release timing)
- Multiple ORB/retest studies and practitioner writeups emphasizing retest
  confirmation to reduce false breakouts

### USOIL installation quick start

1. Copy `Experts/USOilM5SafetyGuardian.mq5` into:
   `MQL5/Experts/USOilM5SafetyGuardian.mq5`
2. Compile in MetaEditor.
3. Attach to a single USOIL chart on M5.
4. Load `Presets/USOIL_M5_Tickmill_Conservative.set`.
5. Confirm broker symbol naming (for example `USOIL`, `USOIL.cash`, etc.).
6. Verify server-time alignment for:
   - Session inputs
   - EIA blackout window inputs

If Strategy Tester does not start:

- Recompile the EA in MetaEditor so the latest `.mq5` changes are used.
- Load the latest preset files (both now default `InpStrictTesterSymbol=false`).
- In the tester journal, check initialization lines for symbol/indicator warnings.

### Tickmill / ZAR account note (USOIL EA)

`USOilM5SafetyGuardian` calculates lot size using `OrderCalcProfit()` from
entry to stop for 1 lot, then scales by your configured risk percent. MT5
returns that in deposit currency, so risk is calculated in ZAR automatically
for a Tickmill ZAR account.

## USOIL M5 Trend Pullback Guardian (alternate variant)

`Experts/USOilM5TrendPullbackGuardian.mq5` is a second-pass strategy variant
for A/B testing against the opening-range model. It trades trend continuation
instead of session-range breakouts:

- Trend stack filter: EMA 20/50 alignment with M15 EMA 200 direction
- Momentum/strength gate: ADX + DI confirmation and RSI regime filter
- Entry style: pullback toward EMA 50, then close-based breakout of recent
  structure (`InpBreakoutLookbackBars`)
- Volatility-normalized stops and account-currency risk sizing
- Same risk architecture: daily loss guard, EIA blackout window, optional
  one-trade-per-day guard

Recommended preset:

- `Presets/USOIL_M5_Tickmill_TrendPullback_Conservative.set`

Usage:

1. Copy `Experts/USOilM5TrendPullbackGuardian.mq5` into:
   `MQL5/Experts/USOilM5TrendPullbackGuardian.mq5`
2. Compile in MetaEditor.
3. Attach to a single USOIL M5 chart.
4. Load `Presets/USOIL_M5_Tickmill_TrendPullback_Conservative.set`.
5. Compare this variant vs `USOilM5SafetyGuardian` in Strategy Tester over the
   same date ranges and spread assumptions.

`Experts/IndexOpeningRangeGuardian.mq5` is a conservative MetaTrader 5 Expert
Advisor designed for the M5 timeframe on US index CFDs:

- US30
- US500
- USTEC

The EA trades a New York-session Opening Range Breakout (ORB) rather than a
continuous scalping system. Public strategy references consistently emphasize
that raw ORB entries are vulnerable to false breakouts, so this implementation
adds filters and risk controls:

- 30-minute opening range by default
- M5 candle-close breakout confirmation
- Optional break-retest-rebreak confirmation to reduce false breakout chasing
- Optional long-only, short-only, or both-direction operation
- EMA 20/50 trend alignment
- M15 EMA 200 directional filter
- ADX directional-strength filter
- ATR-based range quality, stop, trailing, and spread filters
- Tick-volume participation filter
- One trade per symbol/session by default
- Daily equity drawdown guard
- Fixed-fractional risk sizing in the account currency

There is no such thing as a strategy that is both guaranteed safe and guaranteed
profitable. Treat this EA as a robust, backtestable starting point. Run Tickmill
strategy tests and forward demo tests before live use.

## Tickmill / ZAR account notes

The lot-size calculation uses `OrderCalcProfit()` to estimate the loss for 1 lot
from entry to stop-loss. MT5 returns this in the deposit currency, so on a
Tickmill ZAR account the risk amount is calculated in ZAR automatically.

Default risk is intentionally modest:

- `InpRiskPercentPerTrade = 0.35`
- `InpMaxDailyLossPercent = 1.20`
- `InpMaxPortfolioPositions = 3`
- `InpMaxMinLotRiskPercent = 0.75`

If the calculated volume is below the broker's minimum lot, the EA can use the
broker minimum lot only when the estimated stop-loss risk remains below
`InpMaxMinLotRiskPercent`. This matters on a 10,000 ZAR account because a 0.35%
target risk is only R35, and US index CFD minimum-lot risk can be slightly above
that. If the minimum-lot risk is too high, the EA still skips the trade.

## Installation

1. Copy `Experts/IndexOpeningRangeGuardian.mq5` into your MT5 data folder:
   `MQL5/Experts/IndexOpeningRangeGuardian.mq5`
2. Open MetaEditor.
3. Compile the file.
4. Attach it to one chart. It scans all configured symbols itself.
5. Ensure the symbols are visible in Market Watch.

The default symbol input is:

```text
US30,US500,USTEC
```

If Tickmill appends suffixes such as `.cash`, leave
`InpAutoResolveSymbols = true`; otherwise edit `InpSymbols` to the exact broker
names.

In MT5 Strategy Tester the EA defaults to `InpUseChartSymbolOnlyInTester = true`.
This makes single-symbol tests easier to interpret and avoids missing-history
issues from other symbols in `InpSymbols`. For live trading, attach the EA to one
chart and leave `InpSymbols` configured with all instruments you want scanned.

The tester also defaults to `InpStrictTesterSymbolList = true`. If MT5 reports a
chart/tester symbol that is not listed in `InpSymbols`, the EA aborts during
initialization and prints a clear journal message. This prevents accidental tests
or trades on unrelated broker symbols such as AFRICA40 when you intended US30.

At startup, check the journal for:

```text
Tester mode detected. MT5 chart/tester symbol=...
```

If that symbol is not the one selected in Strategy Tester, reselect the intended
symbol, clear any cached tester setup, and make sure the latest `.mq5` has been
compiled into the `.ex5` being tested.

## Presets

MT5 Strategy Tester keeps old input values unless you reset them or load a set
file. If a report still shows `InpUseVolumeFilter=true`, `InpMinAdx=18.0`, or
`InpAllowMinLotIfRiskTooLow=false`, it is using an older saved configuration.

Load one of these files from the Strategy Tester input tab:

- `Presets/US30_M5_Tickmill_Recommended.set`
  - Intended first-pass Tickmill US30 configuration.
  - Uses break-retest-rebreak confirmation rather than instant breakout entry.
  - Disables the CFD tick-volume filter.
  - Uses ADX 14 instead of 18.
  - Allows minimum-lot trades only when estimated risk is capped.
  - Uses later breakeven/trailing so winners have more room to develop.
- `Presets/US30_M5_Tickmill_SignalDiscovery.set`
  - Diagnostic only, not a live preset.
  - Uses direct breakout mode.
  - Loosens filters to confirm the EA can produce a meaningful sample size.
  - Use this if the recommended preset still produces very few trades.

The earlier direct-breakout recommended preset produced a larger sample but poor
trade quality on US30: average losses were materially larger than average wins.
The recommended preset now prioritizes cleaner entries and larger winner room,
even if trade count falls. If the signal-discovery preset produces many trades
but the recommended preset produces very few, copy the diagnostics block from the
journal because it will identify which retest/filter gate is the bottleneck.

## If a backtest shows zero trades

Check the Strategy Tester journal for lines beginning with:

```text
==== IndexOpeningRangeGuardian diagnostics ====
```

The summary shows how many bars reached each gate:

- `ranges`: opening ranges successfully built
- `range_reject`: ATR/percent range filters rejected the day
- `spread_reject`: spread filter blocked entries
- `breakouts_long` / `breakouts_short`: valid ORB closes detected
- `retests_long` / `retests_short`: retests detected after initial breaks
- `retest_expired_*`: initial breaks that failed to retest/rebreak in time
- `trend_reject_*`: EMA/ADX trend filters blocked detected breakouts
- `volume_reject_*`: tick-volume filter blocked detected breakouts
- `size_reject_*`: stop distance, broker stop-level, margin, or lot-size risk
  blocked detected breakouts
- `order_attempts` / `orders_opened`: actual trade sends and accepted trades

For Tickmill CFD data, the volume filter is disabled by default because tick
volume behavior varies by broker. Enable it only after confirming it does not
filter out nearly every valid breakout.

## Important setup inputs

All session inputs are broker/server time:

- `InpSessionStartHour = 16`
- `InpSessionStartMinute = 30`
- `InpOpeningRangeMinutes = 30`
- `InpEntryWindowMinutes = 150`
- `InpSessionCloseHour = 22`
- `InpSessionCloseMinute = 45`

Tickmill server time may shift with daylight saving. Confirm the broker time
that corresponds to the US cash equity open before enabling live trading.

## Recommended validation process

Backtest each symbol separately first, then the three-symbol portfolio:

1. Use "Every tick based on real ticks" if available.
2. Test at least one volatile period and one quiet period.
3. Validate spread assumptions around the US cash open.
4. Optimize only a small set of inputs at a time:
   - `InpOpeningRangeMinutes`
   - `InpEntryWindowMinutes`
   - `InpMinRangeAtr` / `InpMaxRangeAtr`
   - `InpRewardRisk`
   - `InpMinAdx`
   - `InpVolumeMultiplier`
5. Forward test on demo before live use.

Avoid curve fitting. The goal is a stable ruleset, not a perfect historical
equity curve.
