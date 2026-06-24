//+------------------------------------------------------------------+
//|                                      USOilM5SafetyGuardian.mq5   |
//| Conservative M5 USOIL EA with strong risk controls               |
//+------------------------------------------------------------------+
#property copyright "Generated for TradingEA"
#property version   "1.00"
#property strict
#property description "USOIL M5 retest-breakout EA with ATR/ADX filters, EIA blackout, and account-currency risk sizing."

#include <Trade/Trade.mqh>

enum ENUM_RISK_BASIS
{
   RISK_BASIS_BALANCE = 0,
   RISK_BASIS_EQUITY  = 1
};

enum ENUM_SIGNAL_MODE
{
   SIGNAL_DIRECT_CLOSE    = 0,
   SIGNAL_RETEST_REBREAK  = 1
};

enum ENUM_TRADE_DIRECTION
{
   TRADE_BOTH       = 0,
   TRADE_LONG_ONLY  = 1,
   TRADE_SHORT_ONLY = 2
};

input group "Symbol"
input string               InpSymbol                     = "USOIL";      // Tickmill symbol; suffix is auto-detected if possible
input bool                 InpAutoResolveSymbol          = true;
input bool                 InpUseChartSymbolOnlyInTester = true;
input bool                 InpStrictTesterSymbol         = true;
input ENUM_TIMEFRAMES      InpTradeTimeframe             = PERIOD_M5;

input group "Session - broker/server time"
input int                  InpSessionStartHour           = 16;           // Confirm against broker server time
input int                  InpSessionStartMinute         = 0;
input int                  InpSessionCloseHour           = 23;
input int                  InpSessionCloseMinute         = 0;
input int                  InpOpeningRangeMinutes        = 30;
input int                  InpEntryWindowMinutes         = 180;
input bool                 InpCloseAtSessionEnd          = true;
input int                  InpForcedCloseBufferMin       = 5;

input group "Oil event / timing filters - broker/server time"
input bool                 InpUseEiaBlackout             = true;         // Skip EIA window to reduce whipsaw risk
input int                  InpEiaBlackoutDayOfWeek       = 3;            // 0=Sun...3=Wed...6=Sat
input int                  InpEiaBlackoutStartHour       = 17;
input int                  InpEiaBlackoutStartMinute     = 25;
input int                  InpEiaBlackoutEndHour         = 17;
input int                  InpEiaBlackoutEndMinute       = 45;
input bool                 InpSkipLateFriday             = true;
input int                  InpFridayCutoffHour           = 21;

input group "Signal filters"
input int                  InpFastEmaPeriod              = 20;
input int                  InpSlowEmaPeriod              = 50;
input ENUM_TIMEFRAMES      InpTrendTimeframe             = PERIOD_M15;
input int                  InpTrendEmaPeriod             = 200;
input int                  InpAtrPeriod                  = 14;
input int                  InpAdxPeriod                  = 14;
input bool                 InpUseAdxFilter               = true;
input double               InpMinAdx                     = 22.0;
input bool                 InpUseVolumeFilter            = false;        // CFD tick volume behavior varies by broker
input int                  InpVolumeLookbackBars         = 20;
input double               InpVolumeMultiplier           = 1.30;
input ENUM_SIGNAL_MODE     InpSignalMode                 = SIGNAL_RETEST_REBREAK;
input ENUM_TRADE_DIRECTION InpTradeDirection             = TRADE_BOTH;
input int                  InpConfirmCloses              = 1;
input bool                 InpRequireFreshBreakout       = true;
input double               InpBreakoutBufferAtr          = 0.03;
input double               InpRetestToleranceAtr         = 0.12;
input int                  InpRetestMaxBars              = 12;
input double               InpMinRebreakBodyAtr          = 0.05;

input group "Range and cost filters"
input double               InpMinRangeAtr                = 0.40;
input double               InpMaxRangeAtr                = 2.50;
input double               InpMaxRangePercent            = 1.20;
input int                  InpMaxSpreadPoints            = 0;            // 0 disables fixed-points filter
input double               InpMaxSpreadAtrPercent        = 8.0;

input group "Risk and orders"
input bool                 InpTradingEnabled             = true;
input ENUM_RISK_BASIS      InpRiskBasis                  = RISK_BASIS_EQUITY;
input double               InpRiskPercentPerTrade        = 0.25;         // Risk in account currency (e.g., ZAR)
input double               InpMaxDailyLossPercent        = 1.00;
input bool                 InpCloseOnDailyLossLimit      = false;
input bool                 InpOneTradePerDay             = true;
input double               InpRewardRisk                 = 2.00;
input double               InpMinStopAtr                 = 1.00;
input double               InpMaxStopAtr                 = 3.00;
input double               InpStopBufferAtr              = 0.08;
input bool                 InpAllowMinLotIfRiskTooLow    = true;
input double               InpMaxMinLotRiskPercent       = 0.60;
input int                  InpSlippagePoints             = 30;
input int                  InpMagic                      = 260624;
input int                  InpTimerSeconds               = 2;

input group "Trade management"
input double               InpBreakevenAtR               = 1.20;
input double               InpBreakevenBufferAtr         = 0.05;
input double               InpTrailStartR                = 1.70;
input double               InpTrailAtrMultiplier         = 1.30;

input group "Diagnostics"
input bool                 InpPrintDiagnostics           = true;

struct EAState
{
   string   requestedSymbol;
   string   symbol;
   int      fastEmaHandle;
   int      slowEmaHandle;
   int      trendEmaHandle;
   int      atrHandle;
   int      adxHandle;
   datetime lastBarTime;
   datetime sessionStart;
   datetime rangeEnd;
   datetime entryCutoff;
   datetime sessionClose;
   datetime lastTradeDay;
   double   rangeHigh;
   double   rangeLow;
   bool     rangeReady;
   bool     longTaken;
   bool     shortTaken;
   bool     longBreakSeen;
   bool     shortBreakSeen;
   bool     longRetested;
   bool     shortRetested;
   int      longBreakBars;
   int      shortBreakBars;

   long     barsProcessed;
   long     atrMissing;
   long     rangeBuilt;
   long     rangeDataMissing;
   long     rangeRejected;
   long     spreadRejected;
   long     longBreakouts;
   long     shortBreakouts;
   long     longRetests;
   long     shortRetests;
   long     longRetestExpired;
   long     shortRetestExpired;
   long     trendRejectedLong;
   long     trendRejectedShort;
   long     volumeRejectedLong;
   long     volumeRejectedShort;
   long     sizeRejectedLong;
   long     sizeRejectedShort;
   long     orderAttempts;
   long     ordersOpened;
};

CTrade   g_trade;
EAState  g_state;
datetime g_riskDayStart = 0;
double   g_dayStartEquity = 0.0;

string Trim(const string value)
{
   string result = value;
   StringTrimLeft(result);
   StringTrimRight(result);
   return result;
}

int MaxInt(const int a, const int b)
{
   return a > b ? a : b;
}

datetime DayStart(const datetime value)
{
   MqlDateTime dt;
   TimeToStruct(value, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

datetime BuildTimeForDay(const datetime anchor, const int hour, const int minute)
{
   MqlDateTime dt;
   TimeToStruct(anchor, dt);
   dt.hour = hour;
   dt.min  = minute;
   dt.sec  = 0;
   return StructToTime(dt);
}

double NormalizePrice(const string symbol, const double price)
{
   const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

int VolumeDigits(const double step)
{
   if(step <= 0.0)
      return 2;

   int digits = 0;
   double scaled = step;
   while(digits < 8 && MathAbs(scaled - MathRound(scaled)) > 0.00000001)
   {
      scaled *= 10.0;
      digits++;
   }
   return digits;
}

double NormalizeVolume(const string symbol, const double requestedVolume)
{
   const double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   const double maxVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   const double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(minVol <= 0.0 || maxVol <= 0.0 || step <= 0.0)
      return 0.0;

   double volume = MathMax(minVol, MathMin(maxVol, requestedVolume));
   volume = MathFloor(volume / step) * step;
   volume = NormalizeDouble(volume, VolumeDigits(step));

   if(volume < minVol)
      return 0.0;
   return volume;
}

bool SymbolNameMatchesRequest(const string symbolName, const string requested)
{
   if(symbolName == requested)
      return true;

   const int requestedLength = StringLen(requested);
   const int symbolLength = StringLen(symbolName);
   if(requestedLength <= 0 || symbolLength < requestedLength)
      return false;

   if(StringFind(symbolName, requested) == 0)
      return true;

   const int suffixPosition = symbolLength - requestedLength;
   return StringFind(symbolName, requested, suffixPosition) == suffixPosition;
}

string ResolveSymbolName(const string requested)
{
   if(SymbolSelect(requested, true))
      return requested;

   if(!InpAutoResolveSymbol)
      return requested;

   const int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
   {
      const string name = SymbolName(i, false);
      if(SymbolNameMatchesRequest(name, requested) && SymbolSelect(name, true))
         return name;
   }

   return requested;
}

bool GetBufferValue(const int handle, const int buffer, const int shift, double &value)
{
   double values[];
   ArraySetAsSeries(values, true);
   if(CopyBuffer(handle, buffer, shift, 1, values) != 1)
      return false;
   value = values[0];
   return value != EMPTY_VALUE;
}

bool GetLatestClosedBars(const string symbol, MqlRates &rates[], const int barsRequired)
{
   ArraySetAsSeries(rates, true);
   const int copied = CopyRates(symbol, InpTradeTimeframe, 0, barsRequired, rates);
   return copied >= barsRequired;
}

void ResetDiagnostics()
{
   g_state.barsProcessed = 0;
   g_state.atrMissing = 0;
   g_state.rangeBuilt = 0;
   g_state.rangeDataMissing = 0;
   g_state.rangeRejected = 0;
   g_state.spreadRejected = 0;
   g_state.longBreakouts = 0;
   g_state.shortBreakouts = 0;
   g_state.longRetests = 0;
   g_state.shortRetests = 0;
   g_state.longRetestExpired = 0;
   g_state.shortRetestExpired = 0;
   g_state.trendRejectedLong = 0;
   g_state.trendRejectedShort = 0;
   g_state.volumeRejectedLong = 0;
   g_state.volumeRejectedShort = 0;
   g_state.sizeRejectedLong = 0;
   g_state.sizeRejectedShort = 0;
   g_state.orderAttempts = 0;
   g_state.ordersOpened = 0;
}

void ResetSession(const datetime now)
{
   g_state.sessionStart = BuildTimeForDay(now, InpSessionStartHour, InpSessionStartMinute);
   g_state.rangeEnd     = g_state.sessionStart + InpOpeningRangeMinutes * 60;
   g_state.entryCutoff  = g_state.rangeEnd + InpEntryWindowMinutes * 60;
   g_state.sessionClose = BuildTimeForDay(now, InpSessionCloseHour, InpSessionCloseMinute);

   if(g_state.sessionClose <= g_state.sessionStart)
      g_state.sessionClose += 24 * 60 * 60;
   if(g_state.entryCutoff > g_state.sessionClose)
      g_state.entryCutoff = g_state.sessionClose;

   g_state.rangeHigh = 0.0;
   g_state.rangeLow = 0.0;
   g_state.rangeReady = false;
   g_state.longTaken = false;
   g_state.shortTaken = false;
   g_state.longBreakSeen = false;
   g_state.shortBreakSeen = false;
   g_state.longRetested = false;
   g_state.shortRetested = false;
   g_state.longBreakBars = 0;
   g_state.shortBreakBars = 0;
}

void UpdateDailyRiskAnchor()
{
   const datetime today = DayStart(TimeCurrent());
   if(g_riskDayStart != today || g_dayStartEquity <= 0.0)
   {
      g_riskDayStart = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      PrintFormat("Daily risk anchor reset. Account currency=%s, start equity=%.2f",
                  AccountInfoString(ACCOUNT_CURRENCY), g_dayStartEquity);
   }
}

double RiskCapital()
{
   if(InpRiskBasis == RISK_BASIS_BALANCE)
      return AccountInfoDouble(ACCOUNT_BALANCE);
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

bool DailyLossLimitReached()
{
   if(InpMaxDailyLossPercent <= 0.0 || g_dayStartEquity <= 0.0)
      return false;

   const double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double maxLossMoney = g_dayStartEquity * InpMaxDailyLossPercent / 100.0;
   return (g_dayStartEquity - currentEquity) >= maxLossMoney;
}

bool HasManagedPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_state.symbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      return true;
   }
   return false;
}

bool IsInEiaBlackout(const datetime now)
{
   if(!InpUseEiaBlackout)
      return false;

   MqlDateTime dtNow;
   TimeToStruct(now, dtNow);
   if(dtNow.day_of_week != InpEiaBlackoutDayOfWeek)
      return false;

   datetime start = BuildTimeForDay(now, InpEiaBlackoutStartHour, InpEiaBlackoutStartMinute);
   datetime stop  = BuildTimeForDay(now, InpEiaBlackoutEndHour, InpEiaBlackoutEndMinute);
   if(stop <= start)
      stop += 24 * 60 * 60;

   datetime compareNow = now;
   if(compareNow < start && stop > start)
      compareNow += 24 * 60 * 60;

   return compareNow >= start && compareNow <= stop;
}

bool TradingTimeAllowed(const datetime barTime)
{
   if(barTime < g_state.rangeEnd || barTime > g_state.entryCutoff || barTime > g_state.sessionClose)
      return false;

   if(IsInEiaBlackout(barTime))
      return false;

   if(InpSkipLateFriday)
   {
      MqlDateTime dt;
      TimeToStruct(barTime, dt);
      if(dt.day_of_week == 5 && dt.hour >= InpFridayCutoffHour)
         return false;
   }

   return true;
}

bool BuildOpeningRange()
{
   MqlRates rangeRates[];
   ArraySetAsSeries(rangeRates, false);
   const int copied = CopyRates(g_state.symbol, InpTradeTimeframe, g_state.sessionStart, g_state.rangeEnd - 1, rangeRates);
   if(copied <= 0)
   {
      g_state.rangeDataMissing++;
      return false;
   }

   const int periodSeconds = PeriodSeconds(InpTradeTimeframe);
   const int expectedBars = MaxInt(1, (int)MathFloor((double)(InpOpeningRangeMinutes * 60) / (double)periodSeconds));

   double high = 0.0;
   double low = 0.0;
   int validBars = 0;

   for(int i = 0; i < copied; i++)
   {
      if(rangeRates[i].time < g_state.sessionStart || rangeRates[i].time >= g_state.rangeEnd)
         continue;

      if(validBars == 0)
      {
         high = rangeRates[i].high;
         low = rangeRates[i].low;
      }
      else
      {
         high = MathMax(high, rangeRates[i].high);
         low = MathMin(low, rangeRates[i].low);
      }
      validBars++;
   }

   if(validBars < expectedBars)
      return false;

   g_state.rangeHigh = high;
   g_state.rangeLow = low;
   g_state.rangeReady = high > low;
   if(g_state.rangeReady)
      g_state.rangeBuilt++;

   return g_state.rangeReady;
}

bool RangePassesFilters(const double atr)
{
   if(atr <= 0.0 || g_state.rangeHigh <= g_state.rangeLow)
   {
      g_state.rangeRejected++;
      return false;
   }

   const double range = g_state.rangeHigh - g_state.rangeLow;
   const double midpoint = (g_state.rangeHigh + g_state.rangeLow) / 2.0;
   const double rangeAtr = range / atr;
   const double rangePercent = midpoint > 0.0 ? (range / midpoint) * 100.0 : 0.0;

   if(rangeAtr < InpMinRangeAtr || rangeAtr > InpMaxRangeAtr)
   {
      g_state.rangeRejected++;
      return false;
   }

   if(InpMaxRangePercent > 0.0 && rangePercent > InpMaxRangePercent)
   {
      g_state.rangeRejected++;
      return false;
   }

   return true;
}

bool SpreadPassesFilters(const double atr)
{
   MqlTick tick;
   if(!SymbolInfoTick(g_state.symbol, tick))
   {
      g_state.spreadRejected++;
      return false;
   }

   const double point = SymbolInfoDouble(g_state.symbol, SYMBOL_POINT);
   const double spread = MathMax(0.0, tick.ask - tick.bid);
   const int spreadPoints = point > 0.0 ? (int)MathRound(spread / point) : 0;

   if(InpMaxSpreadPoints > 0 && spreadPoints > InpMaxSpreadPoints)
   {
      g_state.spreadRejected++;
      return false;
   }

   if(InpMaxSpreadAtrPercent > 0.0 && atr > 0.0 && (spread / atr) * 100.0 > InpMaxSpreadAtrPercent)
   {
      g_state.spreadRejected++;
      return false;
   }

   return true;
}

bool VolumePassesFilter(const bool isLong)
{
   if(!InpUseVolumeFilter)
      return true;

   const int required = MaxInt(3, InpVolumeLookbackBars + 2);
   MqlRates rates[];
   if(!GetLatestClosedBars(g_state.symbol, rates, required))
   {
      if(isLong)
         g_state.volumeRejectedLong++;
      else
         g_state.volumeRejectedShort++;
      return false;
   }

   const long breakoutVolume = rates[1].tick_volume;
   double average = 0.0;
   int count = 0;
   for(int i = 2; i < required; i++)
   {
      average += (double)rates[i].tick_volume;
      count++;
   }

   if(count <= 0 || average <= 0.0)
   {
      if(isLong)
         g_state.volumeRejectedLong++;
      else
         g_state.volumeRejectedShort++;
      return false;
   }

   average /= (double)count;
   if((double)breakoutVolume < average * InpVolumeMultiplier)
   {
      if(isLong)
         g_state.volumeRejectedLong++;
      else
         g_state.volumeRejectedShort++;
      return false;
   }

   return true;
}

bool TrendPassesFilter(const bool isLong, const MqlRates &lastClosed)
{
   double fastEma = 0.0;
   double slowEma = 0.0;
   double trendEma = 0.0;
   double adx = 0.0;
   double plusDi = 0.0;
   double minusDi = 0.0;

   if(!GetBufferValue(g_state.fastEmaHandle, 0, 1, fastEma) ||
      !GetBufferValue(g_state.slowEmaHandle, 0, 1, slowEma) ||
      !GetBufferValue(g_state.trendEmaHandle, 0, 1, trendEma) ||
      !GetBufferValue(g_state.adxHandle, 0, 1, adx) ||
      !GetBufferValue(g_state.adxHandle, 1, 1, plusDi) ||
      !GetBufferValue(g_state.adxHandle, 2, 1, minusDi))
      return false;

   if(InpUseAdxFilter && adx < InpMinAdx)
   {
      if(isLong)
         g_state.trendRejectedLong++;
      else
         g_state.trendRejectedShort++;
      return false;
   }

   if(isLong)
   {
      const bool passLong = fastEma > slowEma && lastClosed.close > fastEma &&
                            lastClosed.close > trendEma &&
                            (!InpUseAdxFilter || plusDi > minusDi);
      if(!passLong)
         g_state.trendRejectedLong++;
      return passLong;
   }

   const bool passShort = fastEma < slowEma && lastClosed.close < fastEma &&
                          lastClosed.close < trendEma &&
                          (!InpUseAdxFilter || minusDi > plusDi);
   if(!passShort)
      g_state.trendRejectedShort++;
   return passShort;
}

bool BreakoutConfirmed(const bool isLong, const double atr)
{
   const int confirmations = MaxInt(1, InpConfirmCloses);
   const int requiredBars = confirmations + 2;
   MqlRates rates[];
   if(!GetLatestClosedBars(g_state.symbol, rates, requiredBars))
      return false;

   const double buffer = atr * InpBreakoutBufferAtr;
   for(int i = 1; i <= confirmations; i++)
   {
      if(isLong && rates[i].close <= g_state.rangeHigh + buffer)
         return false;
      if(!isLong && rates[i].close >= g_state.rangeLow - buffer)
         return false;
   }

   if(InpRequireFreshBreakout)
   {
      const int prior = confirmations + 1;
      if(isLong && rates[prior].close > g_state.rangeHigh + buffer)
         return false;
      if(!isLong && rates[prior].close < g_state.rangeLow - buffer)
         return false;
   }

   return true;
}

bool DirectionAllowed(const bool isLong)
{
   if(InpTradeDirection == TRADE_BOTH)
      return true;
   if(isLong)
      return InpTradeDirection == TRADE_LONG_ONLY;
   return InpTradeDirection == TRADE_SHORT_ONLY;
}

bool RebreakBodyPasses(const MqlRates &bar, const double atr)
{
   if(InpMinRebreakBodyAtr <= 0.0)
      return true;
   if(atr <= 0.0)
      return false;
   return MathAbs(bar.close - bar.open) >= atr * InpMinRebreakBodyAtr;
}

void ClearRetestState(const bool isLong)
{
   if(isLong)
   {
      g_state.longBreakSeen = false;
      g_state.longRetested = false;
      g_state.longBreakBars = 0;
   }
   else
   {
      g_state.shortBreakSeen = false;
      g_state.shortRetested = false;
      g_state.shortBreakBars = 0;
   }
}

bool RetestRebreakConfirmed(const bool isLong, const double atr, const MqlRates &lastClosed)
{
   if(!DirectionAllowed(isLong))
      return false;

   const double buffer = atr * InpBreakoutBufferAtr;
   const double tolerance = atr * InpRetestToleranceAtr;
   const bool breakSeen = isLong ? g_state.longBreakSeen : g_state.shortBreakSeen;
   const bool retested = isLong ? g_state.longRetested : g_state.shortRetested;
   int barsSinceBreak = isLong ? g_state.longBreakBars : g_state.shortBreakBars;

   if(!breakSeen)
   {
      if(BreakoutConfirmed(isLong, atr))
      {
         if(isLong)
         {
            g_state.longBreakSeen = true;
            g_state.longRetested = false;
            g_state.longBreakBars = 0;
            g_state.longBreakouts++;
         }
         else
         {
            g_state.shortBreakSeen = true;
            g_state.shortRetested = false;
            g_state.shortBreakBars = 0;
            g_state.shortBreakouts++;
         }
      }
      return false;
   }

   barsSinceBreak++;
   if(isLong)
      g_state.longBreakBars = barsSinceBreak;
   else
      g_state.shortBreakBars = barsSinceBreak;

   if(InpRetestMaxBars > 0 && barsSinceBreak > InpRetestMaxBars)
   {
      if(isLong)
         g_state.longRetestExpired++;
      else
         g_state.shortRetestExpired++;
      ClearRetestState(isLong);
      return false;
   }

   if(!retested)
   {
      const bool touchedBoundary = isLong
                                   ? lastClosed.low <= g_state.rangeHigh + tolerance
                                   : lastClosed.high >= g_state.rangeLow - tolerance;
      if(touchedBoundary)
      {
         if(isLong)
         {
            g_state.longRetested = true;
            g_state.longRetests++;
         }
         else
         {
            g_state.shortRetested = true;
            g_state.shortRetests++;
         }
      }
      return false;
   }

   const bool rebreak = isLong
                        ? lastClosed.close > g_state.rangeHigh + buffer
                        : lastClosed.close < g_state.rangeLow - buffer;
   if(rebreak && RebreakBodyPasses(lastClosed, atr))
   {
      ClearRetestState(isLong);
      return true;
   }

   return false;
}

bool SignalConfirmed(const bool isLong, const double atr, const MqlRates &lastClosed)
{
   if(!DirectionAllowed(isLong))
      return false;

   if(InpSignalMode == SIGNAL_RETEST_REBREAK)
      return RetestRebreakConfirmed(isLong, atr, lastClosed);

   if(BreakoutConfirmed(isLong, atr))
   {
      if(isLong)
         g_state.longBreakouts++;
      else
         g_state.shortBreakouts++;
      return true;
   }

   return false;
}

bool CalculatePositionSize(const ENUM_ORDER_TYPE orderType,
                           const double entry,
                           const double stopLoss,
                           double &volume)
{
   volume = 0.0;

   const double riskMoney = RiskCapital() * InpRiskPercentPerTrade / 100.0;
   if(riskMoney <= 0.0)
      return false;

   double oneLotProfit = 0.0;
   if(!OrderCalcProfit(orderType, g_state.symbol, 1.0, entry, stopLoss, oneLotProfit))
      return false;

   const double oneLotLoss = MathAbs(oneLotProfit);
   if(oneLotLoss <= 0.0)
      return false;

   const double rawVolume = riskMoney / oneLotLoss;
   const double minVol = SymbolInfoDouble(g_state.symbol, SYMBOL_VOLUME_MIN);

   if(rawVolume < minVol && !InpAllowMinLotIfRiskTooLow)
      return false;

   if(rawVolume < minVol && InpAllowMinLotIfRiskTooLow)
   {
      const double maxMinLotRiskMoney = RiskCapital() * InpMaxMinLotRiskPercent / 100.0;
      const double minLotRiskMoney = oneLotLoss * minVol;
      if(maxMinLotRiskMoney <= 0.0 || minLotRiskMoney > maxMinLotRiskMoney)
         return false;
   }

   volume = NormalizeVolume(g_state.symbol, rawVolume);
   if(volume <= 0.0)
      return false;

   double margin = 0.0;
   if(OrderCalcMargin(orderType, g_state.symbol, volume, entry, margin))
   {
      const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin * 0.90)
         return false;
   }

   return true;
}

bool StopsMeetBrokerMinimums(const bool isLong, const double sl, const double tp)
{
   MqlTick tick;
   if(!SymbolInfoTick(g_state.symbol, tick))
      return false;

   const double point = SymbolInfoDouble(g_state.symbol, SYMBOL_POINT);
   const int stopsLevel = (int)SymbolInfoInteger(g_state.symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double minDistance = stopsLevel * point;
   if(minDistance <= 0.0)
      return true;

   if(isLong)
      return (tick.bid - sl) >= minDistance && (tp - tick.bid) >= minDistance;

   return (sl - tick.ask) >= minDistance && (tick.ask - tp) >= minDistance;
}

void OpenBreakoutTrade(const bool isLong, const double atr)
{
   if(!InpTradingEnabled || DailyLossLimitReached())
      return;

   if(HasManagedPosition())
      return;

   if(InpOneTradePerDay && g_state.lastTradeDay == DayStart(TimeCurrent()))
      return;

   if(isLong && g_state.longTaken)
      return;
   if(!isLong && g_state.shortTaken)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(g_state.symbol, tick))
      return;

   const double entry = isLong ? tick.ask : tick.bid;
   const double rangeStopBuffer = atr * InpStopBufferAtr;
   double stopLoss = isLong ? g_state.rangeLow - rangeStopBuffer : g_state.rangeHigh + rangeStopBuffer;
   const double minStopDistance = atr * InpMinStopAtr;

   if(isLong && (entry - stopLoss) < minStopDistance)
      stopLoss = entry - minStopDistance;
   if(!isLong && (stopLoss - entry) < minStopDistance)
      stopLoss = entry + minStopDistance;

   const double riskDistance = MathAbs(entry - stopLoss);
   if(atr <= 0.0 || riskDistance > atr * InpMaxStopAtr)
   {
      if(isLong)
         g_state.sizeRejectedLong++;
      else
         g_state.sizeRejectedShort++;
      return;
   }

   double takeProfit = isLong ? entry + riskDistance * InpRewardRisk : entry - riskDistance * InpRewardRisk;
   stopLoss = NormalizePrice(g_state.symbol, stopLoss);
   takeProfit = NormalizePrice(g_state.symbol, takeProfit);

   if(!StopsMeetBrokerMinimums(isLong, stopLoss, takeProfit))
   {
      if(isLong)
         g_state.sizeRejectedLong++;
      else
         g_state.sizeRejectedShort++;
      return;
   }

   double volume = 0.0;
   const ENUM_ORDER_TYPE orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!CalculatePositionSize(orderType, entry, stopLoss, volume))
   {
      if(isLong)
         g_state.sizeRejectedLong++;
      else
         g_state.sizeRejectedShort++;
      return;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(g_state.symbol);

   const string comment = isLong ? "USOIL safe long" : "USOIL safe short";
   g_state.orderAttempts++;
   const bool sent = isLong
                     ? g_trade.Buy(volume, g_state.symbol, 0.0, stopLoss, takeProfit, comment)
                     : g_trade.Sell(volume, g_state.symbol, 0.0, stopLoss, takeProfit, comment);

   if(sent)
   {
      if(isLong)
         g_state.longTaken = true;
      else
         g_state.shortTaken = true;

      g_state.ordersOpened++;
      g_state.lastTradeDay = DayStart(TimeCurrent());
   }
}

void ManageOpenPosition()
{
   const bool dailyLimit = DailyLossLimitReached();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != g_state.symbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      MqlTick tick;
      if(!SymbolInfoTick(g_state.symbol, tick))
         continue;

      const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const bool isLong = (type == POSITION_TYPE_BUY);
      const double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      const double currentSl = PositionGetDouble(POSITION_SL);
      const double currentTp = PositionGetDouble(POSITION_TP);
      const double mark = isLong ? tick.bid : tick.ask;

      if(dailyLimit && InpCloseOnDailyLossLimit)
      {
         g_trade.SetExpertMagicNumber(InpMagic);
         g_trade.PositionClose(ticket);
         continue;
      }

      if(InpCloseAtSessionEnd)
      {
         const datetime now = TimeCurrent();
         const datetime closeTime = BuildTimeForDay(now, InpSessionCloseHour, InpSessionCloseMinute)
                                    - InpForcedCloseBufferMin * 60;
         if(now >= closeTime)
         {
            g_trade.SetExpertMagicNumber(InpMagic);
            g_trade.PositionClose(ticket);
            continue;
         }
      }

      double atr = 0.0;
      if(!GetBufferValue(g_state.atrHandle, 0, 1, atr) || atr <= 0.0)
         continue;

      double initialRisk = 0.0;
      if(currentTp > 0.0 && InpRewardRisk > 0.0)
         initialRisk = MathAbs(currentTp - openPrice) / InpRewardRisk;
      if(initialRisk <= 0.0 && currentSl > 0.0)
         initialRisk = MathAbs(openPrice - currentSl);
      if(initialRisk <= 0.0)
         continue;

      const double profitDistance = isLong ? mark - openPrice : openPrice - mark;
      const double currentR = profitDistance / initialRisk;
      double newSl = currentSl;

      if(currentR >= InpBreakevenAtR)
      {
         const double breakeven = isLong ? openPrice + atr * InpBreakevenBufferAtr
                                         : openPrice - atr * InpBreakevenBufferAtr;
         if((isLong && (currentSl <= 0.0 || breakeven > newSl)) ||
            (!isLong && (currentSl <= 0.0 || breakeven < newSl)))
            newSl = breakeven;
      }

      if(currentR >= InpTrailStartR)
      {
         const double trailing = isLong ? mark - atr * InpTrailAtrMultiplier
                                        : mark + atr * InpTrailAtrMultiplier;
         if((isLong && trailing > newSl) || (!isLong && (newSl <= 0.0 || trailing < newSl)))
            newSl = trailing;
      }

      if(newSl > 0.0 && MathAbs(newSl - currentSl) > SymbolInfoDouble(g_state.symbol, SYMBOL_POINT))
      {
         newSl = NormalizePrice(g_state.symbol, newSl);
         if(StopsMeetBrokerMinimums(isLong, newSl, currentTp))
         {
            g_trade.SetExpertMagicNumber(InpMagic);
            g_trade.PositionModify(ticket, newSl, currentTp);
         }
      }
   }
}

void ProcessSymbol()
{
   MqlRates rates[];
   if(!GetLatestClosedBars(g_state.symbol, rates, MaxInt(4, InpConfirmCloses + 3)))
      return;

   const datetime currentBarTime = rates[0].time;
   if(g_state.lastBarTime == currentBarTime)
      return;

   g_state.lastBarTime = currentBarTime;
   g_state.barsProcessed++;

   if(g_state.sessionStart == 0 || currentBarTime >= g_state.sessionStart + 24 * 60 * 60)
      ResetSession(currentBarTime);

   if(currentBarTime < g_state.sessionStart)
      ResetSession(currentBarTime);

   if(currentBarTime < g_state.rangeEnd || currentBarTime > g_state.sessionClose)
      return;

   double atr = 0.0;
   if(!GetBufferValue(g_state.atrHandle, 0, 1, atr) || atr <= 0.0)
   {
      g_state.atrMissing++;
      return;
   }

   if(!g_state.rangeReady && !BuildOpeningRange())
      return;

   if(!TradingTimeAllowed(currentBarTime))
      return;

   if(!RangePassesFilters(atr) || !SpreadPassesFilters(atr))
      return;

   const MqlRates lastClosed = rates[1];

   if(SignalConfirmed(true, atr, lastClosed))
   {
      if(TrendPassesFilter(true, lastClosed) && VolumePassesFilter(true))
      {
         OpenBreakoutTrade(true, atr);
         return;
      }
   }

   if(SignalConfirmed(false, atr, lastClosed))
   {
      if(TrendPassesFilter(false, lastClosed) && VolumePassesFilter(false))
         OpenBreakoutTrade(false, atr);
   }
}

void ProcessAll()
{
   UpdateDailyRiskAnchor();
   ManageOpenPosition();

   if(DailyLossLimitReached())
   {
      static datetime lastPrint = 0;
      if(TimeCurrent() - lastPrint > 300)
      {
         PrintFormat("Daily loss limit reached. New entries paused. Start equity=%.2f current equity=%.2f",
                     g_dayStartEquity, AccountInfoDouble(ACCOUNT_EQUITY));
         lastPrint = TimeCurrent();
      }
      return;
   }

   ProcessSymbol();
}

void PrintDiagnostics()
{
   if(!InpPrintDiagnostics)
      return;

   Print("==== USOilM5SafetyGuardian diagnostics ====");
   PrintFormat("%s diagnostics: bars=%I64d atr_missing=%I64d ranges=%I64d range_data_missing=%I64d range_reject=%I64d spread_reject=%I64d",
               g_state.symbol, g_state.barsProcessed, g_state.atrMissing, g_state.rangeBuilt,
               g_state.rangeDataMissing, g_state.rangeRejected, g_state.spreadRejected);
   PrintFormat("%s diagnostics: breakouts_long=%I64d breakouts_short=%I64d trend_reject_long=%I64d trend_reject_short=%I64d volume_reject_long=%I64d volume_reject_short=%I64d",
               g_state.symbol, g_state.longBreakouts, g_state.shortBreakouts,
               g_state.trendRejectedLong, g_state.trendRejectedShort,
               g_state.volumeRejectedLong, g_state.volumeRejectedShort);
   PrintFormat("%s diagnostics: retests_long=%I64d retests_short=%I64d retest_expired_long=%I64d retest_expired_short=%I64d",
               g_state.symbol, g_state.longRetests, g_state.shortRetests,
               g_state.longRetestExpired, g_state.shortRetestExpired);
   PrintFormat("%s diagnostics: size_reject_long=%I64d size_reject_short=%I64d order_attempts=%I64d orders_opened=%I64d",
               g_state.symbol, g_state.sizeRejectedLong, g_state.sizeRejectedShort,
               g_state.orderAttempts, g_state.ordersOpened);
   Print("==== End diagnostics ====");
}

int OnInit()
{
   if(InpOpeningRangeMinutes <= 0 || InpEntryWindowMinutes <= 0)
      return INIT_PARAMETERS_INCORRECT;

   if(InpTradeTimeframe != PERIOD_M5)
      Print("Warning: this EA was designed for PERIOD_M5. Validate thoroughly if changed.");

   g_state.requestedSymbol = Trim(InpSymbol);
   if(g_state.requestedSymbol == "")
      return INIT_PARAMETERS_INCORRECT;

   if(InpUseChartSymbolOnlyInTester && (bool)MQLInfoInteger(MQL_TESTER))
   {
      if(InpStrictTesterSymbol && !SymbolNameMatchesRequest(_Symbol, g_state.requestedSymbol))
      {
         PrintFormat("Tester symbol guard stopped EA: chart symbol '%s' does not match requested '%s'.",
                     _Symbol, g_state.requestedSymbol);
         return INIT_PARAMETERS_INCORRECT;
      }
      g_state.requestedSymbol = _Symbol;
   }

   g_state.symbol = ResolveSymbolName(g_state.requestedSymbol);
   if(!SymbolSelect(g_state.symbol, true))
      return INIT_FAILED;

   g_state.fastEmaHandle  = iMA(g_state.symbol, InpTradeTimeframe, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_state.slowEmaHandle  = iMA(g_state.symbol, InpTradeTimeframe, InpSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_state.trendEmaHandle = iMA(g_state.symbol, InpTrendTimeframe, InpTrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_state.atrHandle      = iATR(g_state.symbol, InpTradeTimeframe, InpAtrPeriod);
   g_state.adxHandle      = iADX(g_state.symbol, InpTradeTimeframe, InpAdxPeriod);

   if(g_state.fastEmaHandle == INVALID_HANDLE ||
      g_state.slowEmaHandle == INVALID_HANDLE ||
      g_state.trendEmaHandle == INVALID_HANDLE ||
      g_state.atrHandle == INVALID_HANDLE ||
      g_state.adxHandle == INVALID_HANDLE)
      return INIT_FAILED;

   g_state.lastBarTime = 0;
   g_state.lastTradeDay = 0;
   ResetDiagnostics();
   ResetSession(TimeCurrent());
   UpdateDailyRiskAnchor();
   EventSetTimer(MaxInt(1, InpTimerSeconds));

   PrintFormat("Initialized %s for USOIL M5 guard. Account currency=%s",
               g_state.symbol, AccountInfoString(ACCOUNT_CURRENCY));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintDiagnostics();
   EventKillTimer();

   if(g_state.fastEmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_state.fastEmaHandle);
   if(g_state.slowEmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_state.slowEmaHandle);
   if(g_state.trendEmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_state.trendEmaHandle);
   if(g_state.atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_state.atrHandle);
   if(g_state.adxHandle != INVALID_HANDLE)
      IndicatorRelease(g_state.adxHandle);
}

void OnTick()
{
   ProcessAll();
}

void OnTimer()
{
   ProcessAll();
}
