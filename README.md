# TradingEA

This repository contains two independent MetaTrader 5 Expert Advisors:

- `Experts/CrudeOilPullbackTrader.mq5` — M5 trend-pullback EA for WTI crude oil
  (USOIL / Tickmill `XTIUSD`). This is the EA documented immediately below.
- `Experts/IndexOpeningRangeGuardian.mq5` — M5 opening-range breakout EA for US
  index CFDs (documented later in this file).

The two EAs share no code; each is a self-contained `.mq5` file.

## Crude Oil Pullback Trader for MT5 (USOIL / XTIUSD)

`Experts/CrudeOilPullbackTrader.mq5` is a single-symbol MetaTrader 5 Expert
Advisor for WTI crude oil on the M5 timeframe. It was designed from scratch for
intraday oil trading and deliberately avoids martingale, grid, and averaging.

### Strategy

The EA trades **trend pullback continuations**, which are generally considered
safer than chasing raw breakouts because every entry is aligned with the higher
timeframe trend and waits for a momentum confirmation:

1. **H1 trend bias** — longs only when the H1 `EMA50 > EMA200` and price is above
   `EMA200`; shorts only in the mirror condition. No bias means no trade.
2. **M5 pullback** — price must pull back into the `EMA20` zone (within an
   ATR-scaled tolerance), arming a setup for a limited number of bars.
3. **M5 trigger** — a momentum candle closes back through the `EMA20` in the
   trend direction, with an ATR-scaled minimum body and RSI confirmation
   (RSI ≥ 50 for longs, ≤ 50 for shorts).
4. **Trend-strength filter** — optional ADX gate (default ≥ 20) skips chop.
5. **Stops/targets** — stop is placed beyond the recent swing low/high plus an
   ATR buffer, bounded by `InpMinStopAtr` / `InpMaxStopAtr`. Take-profit is an
   R-multiple of the stop distance. Positions move to breakeven and then ATR
   trail as the trade runs in profit.

### Built-in risk controls

- Fixed-fractional risk per trade in the **account currency** (see ZAR note).
- Daily equity drawdown guard that pauses new entries (optionally flattens).
- Max concurrent positions and max trades per day.
- Spread filter (points and/or percent of ATR).
- Server-time session window so the EA only trades active oil hours.
- **Weekly EIA news blackout** — the EIA crude inventory report (Wednesday
  14:30 UTC) is the single biggest weekly oil event and routinely spikes WTI by
  $1–$3 within minutes. The EA blocks entries in a configurable window around it.

There is no strategy that is simultaneously guaranteed safe and guaranteed
profitable. Treat this EA as a robust, backtestable starting point and validate
it in the Tickmill Strategy Tester and on a demo account before going live.

### Tickmill / ZAR account notes

Position sizing uses `OrderCalcProfit()` to estimate the one-lot loss from entry
to stop. MT5 returns that figure in the **deposit currency**, so on a Tickmill
ZAR account the per-trade risk is computed directly in ZAR — no manual FX
conversion is required. Defaults are intentionally conservative:

- `InpRiskPercentPerTrade = 0.50`
- `InpMaxDailyLossPercent = 2.00`
- `InpMaxOpenPositions = 1`
- `InpMaxTradesPerDay = 4`

On small ZAR accounts the calculated volume can fall below the broker minimum
lot. When `InpAllowMinLotIfTooLow = true`, the EA uses the minimum lot only if
the resulting risk stays under `InpMaxMinLotRiskPercent`; otherwise it skips the
trade.

Tickmill lists WTI as **`XTIUSD`** (1 lot = 100 barrels). Leave `InpSymbol`
empty to trade the chart symbol, or set it explicitly. With
`InpAutoResolveSymbol = true`, the EA also tries common aliases
(`XTIUSD`, `USOIL`, `WTI`, broker prefixes/suffixes) if the exact name is not
found.

### Installation

1. Copy `Experts/CrudeOilPullbackTrader.mq5` into your MT5 data folder under
   `MQL5/Experts/`.
2. Open MetaEditor and compile it (`F7`).
3. Attach it to an **M5 WTI chart** (e.g. `XTIUSD`).
4. Load `Presets/USOIL_M5_Tickmill_Recommended.set` from the inputs tab.
5. Enable AutoTrading.

### Important: server time and the EIA blackout

All session and news inputs are in **broker/server time**. EIA is 14:30 UTC.
Tickmill's server is typically GMT+2/+3, so the default `InpNewsHour = 16`,
`InpNewsMinute = 30` targets a GMT+2 server. Confirm your server's UTC offset
(it shifts with daylight saving) and adjust `InpNewsHour` and the
`InpTradeStartHour` / `InpTradeEndHour` window accordingly.

### Presets

- `Presets/USOIL_M5_Tickmill_Recommended.set` — conservative, validated baseline
  (fixed 1.6R take-profit, ADX/news/session filters on).
- `Presets/USOIL_M5_Tickmill_RunnerTrail.set` — **trend-runner variant**.
  Disables the fixed take-profit (`InpUseTakeProfit=false`) and rides a wide
  ATR "chandelier" trail (`InpTrailAtrMultiplier=2.6`, breakeven/trail from
  ~1.2R) so strong oil trends can run well beyond 1.6R. Same conservative
  entries and risk. Use this to A/B against the Recommended baseline.
- `Presets/USOIL_M5_Tickmill_SignalDiscovery.set` — diagnostic only. Loosens
  filters (ADX off, news/session off) to confirm the EA produces a usable trade
  sample. Not intended for live use.

### Take-profit vs trailing-only

`InpUseTakeProfit=true` (default) closes at a fixed `InpRewardRisk` multiple —
steady and predictable, but it caps every winner. For a trend-pullback system on
oil, that ceiling throws away the fat-tailed moves that drive returns. Setting
`InpUseTakeProfit=false` removes the cap and exits purely on the ATR trail, which
typically raises the average win (at the cost of giving a little back on trades
that reverse). Backtest both on your data and pick the one with the better
return-to-drawdown profile.

### Tuning and validation

Backtest with "Every tick based on real ticks" if available, across both
volatile and quiet periods. If a backtest shows zero trades, check the journal
for the `==== CrudeOilPullbackTrader diagnostics ====` block, which reports how
many bars reached each gate (`no_bias`, `session_block`, `news_block`,
`spread_block`, `adx_block`, `armed_*`, `trig_*`, `size_reject`, `orders`).
Optimize only a few inputs at a time (e.g. `InpMinAdx`, `InpRewardRisk`,
`InpPullbackTouchAtr`, `InpTrailStartR`) and avoid curve fitting.

## Index Opening Range Guardian for MT5

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
