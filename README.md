# TradingEA

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
- Optional failed-breakout reversal mode for mean-reversion tests
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
  - Current US30 Tickmill candidate configuration.
  - Uses failed-breakout reversal mode (`InpSignalMode=2`) rather than breakout
    continuation.
  - Based on the first positive Tickmill US30 M5 test in this repo's iteration:
    17 trades, profit factor 2.19, net +139.00 ZAR, max balance drawdown 0.35%.
  - Disables the CFD tick-volume filter.
  - Disables ADX because the reversal signal is not trend-continuation based.
  - Allows minimum-lot trades only when estimated risk is capped.
  - Uses lower per-trade risk and closer targets because it is a reversal style.
- `Presets/US30_M5_Tickmill_SignalDiscovery.set`
  - Diagnostic only, not a live preset.
  - Uses direct breakout mode.
  - Loosens filters to confirm the EA can produce a meaningful sample size.
  - Use this if the recommended preset still produces very few trades.
- `Presets/US30_M5_Tickmill_FailedBreakReversal.set`
  - Same signal family as the recommended preset; kept as an explicit named
    preset for failed-break testing.
- `Presets/US30_M5_Tickmill_FailedBreak_LongOnly.set`
  - Same failed-break settings, but only trades failed downside breaks as long
    reversals.
- `Presets/US30_M5_Tickmill_FailedBreak_ShortOnly.set`
  - Same failed-break settings, but only trades failed upside breaks as short
    reversals.
- `Presets/US30_M5_Tickmill_RetestContinuation.set`
  - Diagnostic comparison preset, not a live preset.
  - Preserves the retest-continuation configuration that tested negative on the
    supplied Tickmill US30 sample.

The earlier direct-breakout recommended preset produced a larger sample but poor
trade quality on US30: average losses were materially larger than average wins.
The retest-breakout preset reduced trade count and drawdown, but the reported
US30 sample was still negative. The first failed-breakout reversal test was
positive, but 17 trades is still a small sample. Before live use, validate it
out-of-sample, test the long-only and short-only presets, and run the same
configuration on US500 and USTEC.

## Current validation notes

User-supplied Tickmill US30 M5 real-tick tests so far:

| Period | Preset / direction | Trades | Net ZAR | Profit factor | Max balance DD | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 2025.01.01-2026.06.30 | Direct breakout discovery | 182 | -610.05 | 0.79 | 9.19% | Enough trades; no edge. |
| 2025.01.01-2026.06.30 | Retest continuation | 22 | -225.83 | 0.44 | 2.48% | Cleaner but still negative. |
| 2025.01.01-2026.06.30 | Failed-break reversal, both directions | 17 | 139.00 | 2.19 | 0.35% | Promising but small sample. |
| 2025.01.01-2025.12.30 | Failed-break reversal, short-only | 7 | 80.99 | 2.86 | 0.43% | Positive; still very small sample. |

Next validation priority:

1. Test `US30_M5_Tickmill_FailedBreak_ShortOnly.set` on 2026 only.
2. Test `US30_M5_Tickmill_FailedBreak_LongOnly.set` on 2025 and 2026 separately.
3. Test `US30_M5_Tickmill_Recommended.set` on US500 and USTEC.
4. Only consider demo forward testing if the edge survives at least one
   out-of-sample period and is not carried by one isolated lucky trade.

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
- `failed_break_long` / `failed_break_short`: failed-break reversal signals
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
