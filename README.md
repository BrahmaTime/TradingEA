# TradingEA

## US Oil Trend Pullback Guardian for MT5

`Experts/USOilTrendPullbackGuardian.mq5` is a conservative MetaTrader 5 Expert
Advisor designed for the M5 timeframe on USOIL / WTI crude oil CFDs.

The strategy is a rules-based trend pullback model:

- EMA 20/50 trend alignment on M5
- M15 EMA 200 higher-timeframe direction filter
- ADX and DI trend-strength confirmation
- Pullback candle must trade back toward EMA 20 without breaking too far beyond
  EMA 50
- Confirmation candle must close beyond the pullback candle by an ATR buffer
- ATR-based stop-loss, take-profit, breakeven, and trailing stop
- Spread and abnormal-volatility filters
- Configurable Wednesday EIA oil-news guard
- One trade per day by default
- Fixed-fractional risk sizing in the account currency

There is no such thing as a strategy that is both guaranteed safe and guaranteed
profitable. Crude oil can move violently around inventory data, OPEC headlines,
geopolitical events, and US session liquidity shifts. Treat this EA as a
backtestable starting point, not as financial advice.

## Why this USOIL strategy

Public crude-oil strategy material consistently favors the same building blocks
for intraday systems: trend filters, pullback entries instead of chasing extended
moves, ATR-based stops, strict position sizing, and reduced exposure around major
oil news. This EA turns those ideas into a simple MT5 ruleset that can be audited
and tested before live use.

The defaults intentionally favor drawdown control over trade frequency:

- `InpRiskPercentPerTrade = 0.35`
- `InpMaxDailyLossPercent = 1.20`
- `InpOneTradePerDay = true`
- `InpRewardRisk = 1.75`
- `InpUseWeeklyOilNewsGuard = true`

## Tickmill / ZAR account notes for USOIL

The lot-size calculation uses `OrderCalcProfit()` to estimate the loss for 1 lot
from entry to stop-loss. MT5 returns this in the deposit currency, so on a
Tickmill ZAR account the risk amount is calculated in ZAR automatically.

On smaller ZAR accounts, the calculated risk volume can fall below the broker's
minimum lot. When `InpAllowMinLotIfRiskTooLow = true`, the EA only uses the
minimum lot if the estimated stop-loss risk remains below
`InpMaxMinLotRiskPercent`. If the minimum lot would risk too much ZAR, the EA
skips the trade.

## USOIL installation

1. Copy `Experts/USOilTrendPullbackGuardian.mq5` into your MT5 data folder:
   `MQL5/Experts/USOilTrendPullbackGuardian.mq5`
2. Open MetaEditor.
3. Compile the file.
4. Attach it to a USOIL M5 chart or run it in Strategy Tester on USOIL M5.
5. Ensure the USOIL symbol is visible in Market Watch.

If Tickmill appends suffixes such as `.cash`, leave
`InpAutoResolveSymbol = true`; otherwise set `InpSymbol` to the exact broker
symbol.

In MT5 Strategy Tester the EA defaults to `InpUseChartSymbolOnlyInTester = true`.
This makes tests easier to interpret because the tester chart symbol is used even
if your live input uses a different Tickmill suffix. The
`InpStrictTesterSymbolGuard` input stops Strategy Tester initialization when the
chart/tester symbol is not USOIL-like.

## USOIL presets

Load one of these files from the Strategy Tester input tab:

- `Presets/USOIL_M5_Tickmill_Recommended.set`
  - Intended first-pass Tickmill USOIL M5 configuration.
  - Uses one trade per day, ADX 22, conservative ATR/spread filters, and a
    Wednesday EIA news guard.
  - Start with this preset for real-tick backtests and demo forward testing.
- `Presets/USOIL_M5_Tickmill_SignalDiscovery.set`
  - Diagnostic only, not a live preset.
  - Loosens ADX, volatility, spread, and trade-frequency gates to confirm the EA
    can produce a meaningful sample size on your broker feed.

All session and news inputs are broker/server time. Tickmill server time may
shift with daylight saving. Confirm the server time that corresponds to the
liquid US oil session and the weekly EIA release before enabling live trading.

If a backtest shows zero trades, check the Strategy Tester journal for:

```text
==== USOilTrendPullbackGuardian diagnostics ====
```

The diagnostics show whether trades are blocked by trend, pullback, news,
spread, volatility, sizing, or order-send gates.

## USOIL validation process

1. Use "Every tick based on real ticks" if available.
2. Test at least one trending period, one choppy period, and one high-news period.
3. Validate that the configured EIA news window matches Tickmill server time.
4. Optimize only a small set of inputs at a time:
   - `InpMinAdx`
   - `InpPullbackTouchAtr`
   - `InpConfirmBufferAtr`
   - `InpStopAtrMultiplier`
   - `InpRewardRisk`
   - session start/close times
5. Reserve out-of-sample dates and forward test on demo before live use.

Avoid curve fitting. A robust USOIL EA should survive realistic spreads,
slippage, different volatility regimes, and unseen test periods.

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
