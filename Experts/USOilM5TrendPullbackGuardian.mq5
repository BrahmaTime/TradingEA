//+------------------------------------------------------------------+
//|                              USOilM5TrendPullbackGuardian.mq5    |
//| Conservative M5 USOIL trend-pullback breakout EA                 |
//+------------------------------------------------------------------+
#property copyright "Generated for TradingEA"
#property version   "1.00"
#property strict
#property description "USOIL M5 trend-pullback breakout EA with EIA blackout and account-currency risk sizing."

#include <Trade/Trade.mqh>

enum ENUM_RISK_BASIS
{
   RISK_BASIS_BALANCE = 0,
   RISK_BASIS_EQUITY  = 1
};

enum ENUM_TRADE_DIRECTION
{
   TRADE_BOTH       = 0,
   TRADE_LONG_ONLY  = 1,
   TRADE_SHORT_ONLY = 2
};

input group "Symbol"
input string               InpSymbol                     = "USOIL"; // Tickmill symbol; suffix/prefix auto-detected when possible
input bool                 InpAutoResolveSymbol          = true;
input bool                 InpUseChartSymbolOnlyInTester = true;
input bool                 InpStrictTesterSymbol         = true;
input ENUM_TIMEFRAMES      InpTradeTimeframe             = PERIOD_M5;

input group "Session - broker/server time"
input int                  InpSessionStartHour           = 16;
input int                  InpSessionStartMinute         = 0;
input int                  InpSessionCloseHour           = 23;
input int                  InpSessionCloseMinute         = 0;
input bool                 InpCloseAtSessionEnd          = true;
input int                  InpForcedCloseBufferMin       = 5;

input group "Oil event / timing filters - broker/server time"
input bool                 InpUseEiaBlackout             = true;   // Skip EIA volatility window
input int                  InpEiaBlackoutDayOfWeek       = 3;      // 0=Sun..3=Wed..6=Sat
input int                  InpEiaBlackoutStartHour       = 17;
input int                  InpEiaBlackoutStartMinute     = 25;
input int                  InpEiaBlackoutEndHour         = 17;
input int                  InpEiaBlackoutEndMinute       = 45;
input bool                 InpSkipLateFriday             = true;
input int                  InpFridayCutoffHour           = 21;

input group "Trend-pullback breakout logic"
input int                  InpFastEmaPeriod              = 20;
input int                  InpPullbackEmaPeriod          = 50;
input ENUM_TIMEFRAMES      InpTrendTimeframe             = PERIOD_M15;
input int                  InpTrendEmaPeriod             = 200;
input int                  InpAtrPeriod                  = 14;
input int                  InpBreakoutLookbackBars       = 10;     // Highest/lowest lookback before trigger bar
input double               InpPullbackToleranceAtr       = 0.20;   // Pullback touch tolerance around EMA50
input double               InpBreakoutBufferAtr          = 0.04;   // Close beyond breakout level
input double               InpMinSignalBodyAtr           = 0.05;   // Candle body quality gate
input bool                 InpRequireFreshBreakout       = true;
input int                  InpCooldownBarsAfterTrade     = 3;

input group "Trend strength filters"
input bool                 InpUseAdxFilter               = true;
input int                  InpAdxPeriod                  = 14;
input double               InpMinAdx                     = 22.0;
input bool                 InpUseRsiFilter               = true;
input int                  InpRsiPeriod                  = 14;
input double               InpMinRsiLong                 = 52.0;
input double               InpMaxRsiShort                = 48.0;
input ENUM_TRADE_DIRECTION InpTradeDirection             = TRADE_BOTH;
input bool                 InpUseVolumeFilter            = false;   // Tick volume on CFDs can be broker-specific
input int                  InpVolumeLookbackBars         = 20;
input double               InpVolumeMultiplier           = 1.20;

input group "Cost and execution filters"
input int                  InpMaxSpreadPoints            = 0;       // 0 disables fixed spread points check
input double               InpMaxSpreadAtrPercent        = 8.0;

input group "Risk and orders"
input bool                 InpTradingEnabled             = true;
input ENUM_RISK_BASIS      InpRiskBasis                  = RISK_BASIS_EQUITY;
input double               InpRiskPercentPerTrade        = 0.25;    // Risk in account currency (e.g. ZAR)
input double               InpMaxDailyLossPercent        = 1.00;
input bool                 InpCloseOnDailyLossLimit      = false;
input bool                 InpOneTradePerDay             = true;
input double               InpRewardRisk                 = 1.90;
input int                  InpSwingStopLookbackBars      = 8;
input double               InpMinStopAtr                 = 1.00;
input double               InpMaxStopAtr                 = 3.00;
input double               InpStopBufferAtr              = 0.08;
input bool                 InpAllowMinLotIfRiskTooLow    = true;
input double               InpMaxMinLotRiskPercent       = 0.60;
input int                  InpSlippagePoints             = 30;
input int                  InpMagic                      = 260625;
input int                  InpTimerSeconds               = 2;

input group "Trade management"
input double               InpBreakevenAtR               = 1.20;
input double               InpBreakevenBufferAtr         = 0.05;
input double               InpTrailStartR                = 1.60;
input double               InpTrailAtrMultiplier         = 1.25;

input group "Diagnostics"
input bool                 InpPrintDiagnostics           = true;

struct EAState
{
   string   requestedSymbol;
   string   symbol;
   int      fastEmaHandle;
   int      pullbackEmaHandle;
   int      trendEmaHandle;
   int      atrHandle;
   int      adxHandle;
   int      rsiHandle;
   datetime sessionStart;
   datetime sessionClose;
   datetime currentDay;
   datetime lastBarTime;
   datetime lastTradeDay;
   datetime lastTradeBarTime;
   bool     longTaken;
   bool     shortTaken;
   long     barsProcessed;
   long     atrMissing;
   long     spreadRejected;
   long     trendRejectedLong;
   long     trendRejectedShort;
   long     volumeRejectedLong;
   long     volumeRejectedShort;
   long     signalLong;
   long     signalShort;
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

int MaxInt(const int left, const int right)
{
   return left > right ? left : right;
}

datetime DayStart(const datetime value)
{
   MqlDateTime dt;
   TimeToStruct(value, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

datetime BuildTimeForDay(const datetime anchor, const int hour, const int minute)
{
   MqlDateTime dt;
   TimeToStruct(anchor, dt);
   dt.hour = hour;
   dt.min = minute;
   dt.sec = 0;
   return StructToTime(dt);
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
   const double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(minVol <= 0.0 || maxVol <= 0.0 || step <= 0.0)
      return 0.0;

   double volume = MathMax(minVol, MathMin(maxVol, requestedVolume));
   volume = MathFloor(volume / step) * step;
   volume = NormalizeDouble(volume, VolumeDigits(step));

   if(volume < minVol)
      return 0.0;
   return volume;
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

bool GetLatestBars(const string symbol, MqlRates &rates[], const int requiredBars)
{
   ArraySetAsSeries(rates, true);
   const int copied = CopyRates(symbol, InpTradeTimeframe, 0, requiredBars, rates);
   return copied >= requiredBars;
}

void ResetSession(const datetime now)
{
   g_state.currentDay = DayStart(now);
   g_state.sessionStart = BuildTimeForDay(now, InpSessionStartHour, InpSessionStartMinute);
   g_state.sessionClose = BuildTimeForDay(now, InpSessionCloseHour, InpSessionCloseMinute);
   if(g_state.sessionClose <= g_state.sessionStart)
      g_state.sessionClose += 24 * 60 * 60;

   g_state.longTaken = false;
   g_state.shortTaken = false;
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
   if(barTime < g_state.sessionStart || barTime > g_state.sessionClose)
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

bool DirectionAllowed(const bool isLong)
{
   if(InpTradeDirection == TRADE_BOTH)
      return true;
   if(isLong)
      return InpTradeDirection == TRADE_LONG_ONLY;
   return InpTradeDirection == TRADE_SHORT_ONLY;
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
   if(!GetLatestBars(g_state.symbol, rates, required))
   {
      if(isLong)
         g_state.volumeRejectedLong++;
      else
         g_state.volumeRejectedShort++;
      return false;
   }

   const long triggerVolume = rates[1].tick_volume;
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
   if((double)triggerVolume < average * InpVolumeMultiplier)
   {
      if(isLong)
         g_state.volumeRejectedLong++;
      else
         g_state.volumeRejectedShort++;
      return false;
   }

   return true;
}

bool GetHighestHigh(const MqlRates &rates[], const int startShift, const int bars, double &highest)
{
   highest = 0.0;
   bool initialized = false;
   for(int i = startShift; i < startShift + bars; i++)
   {
      if(!initialized)
      {
         highest = rates[i].high;
         initialized = true;
      }
      else
      {
         highest = MathMax(highest, rates[i].high);
      }
   }
   return initialized;
}

bool GetLowestLow(const MqlRates &rates[], const int startShift, const int bars, double &lowest)
{
   lowest = 0.0;
   bool initialized = false;
   for(int i = startShift; i < startShift + bars; i++)
   {
      if(!initialized)
      {
         lowest = rates[i].low;
         initialized = true;
      }
      else
      {
         lowest = MathMin(lowest, rates[i].low);
      }
   }
   return initialized;
}

bool TrendPassesFilter(const bool isLong, const MqlRates &lastClosed)
{
   double emaFast = 0.0;
   double emaPull = 0.0;
   double emaTrend = 0.0;
   double adx = 0.0;
   double plusDi = 0.0;
   double minusDi = 0.0;
   double rsi = 0.0;

   if(!GetBufferValue(g_state.fastEmaHandle, 0, 1, emaFast) ||
      !GetBufferValue(g_state.pullbackEmaHandle, 0, 1, emaPull) ||
      !GetBufferValue(g_state.trendEmaHandle, 0, 1, emaTrend) ||
      !GetBufferValue(g_state.adxHandle, 0, 1, adx) ||
      !GetBufferValue(g_state.adxHandle, 1, 1, plusDi) ||
      !GetBufferValue(g_state.adxHandle, 2, 1, minusDi) ||
      !GetBufferValue(g_state.rsiHandle, 0, 1, rsi))
      return false;

   bool pass = false;
   if(isLong)
   {
      pass = lastClosed.close > emaTrend && emaFast > emaPull && emaPull > emaTrend;
      if(pass && InpUseAdxFilter)
         pass = (adx >= InpMinAdx && plusDi > minusDi);
      if(pass && InpUseRsiFilter)
         pass = (rsi >= InpMinRsiLong);
      if(!pass)
         g_state.trendRejectedLong++;
   }
   else
   {
      pass = lastClosed.close < emaTrend && emaFast < emaPull && emaPull < emaTrend;
      if(pass && InpUseAdxFilter)
         pass = (adx >= InpMinAdx && minusDi > plusDi);
      if(pass && InpUseRsiFilter)
         pass = (rsi <= InpMaxRsiShort);
      if(!pass)
         g_state.trendRejectedShort++;
   }

   return pass;
}

bool BreakoutSignalConfirmed(const bool isLong, const double atr, MqlRates &rates[])
{
   if(!DirectionAllowed(isLong))
      return false;

   const int neededBars = MaxInt(InpBreakoutLookbackBars + 4, InpSwingStopLookbackBars + 4);
   if(ArraySize(rates) < neededBars)
      return false;

   const MqlRates signalBar = rates[1];
   const MqlRates prevBar = rates[2];
   const double tolerance = atr * InpPullbackToleranceAtr;
   const double breakoutBuffer = atr * InpBreakoutBufferAtr;
   double emaPull = 0.0;
   if(!GetBufferValue(g_state.pullbackEmaHandle, 0, 1, emaPull))
      return false;

   double breakoutLevel = 0.0;
   bool levelOk = isLong
                  ? GetHighestHigh(rates, 2, InpBreakoutLookbackBars, breakoutLevel)
                  : GetLowestLow(rates, 2, InpBreakoutLookbackBars, breakoutLevel);
   if(!levelOk)
      return false;

   const double bodySize = MathAbs(signalBar.close - signalBar.open);
   const bool bodyPass = bodySize >= atr * InpMinSignalBodyAtr;
   if(!bodyPass)
      return false;

   if(isLong)
   {
      const bool pullbackTouched = signalBar.low <= (emaPull + tolerance) &&
                                   signalBar.close >= emaPull;
      const bool reclaimed = signalBar.close > signalBar.open;
      const bool breakout = signalBar.close > breakoutLevel + breakoutBuffer;
      const bool fresh = !InpRequireFreshBreakout || prevBar.close <= breakoutLevel + breakoutBuffer;
      return pullbackTouched && reclaimed && breakout && fresh;
   }

   const bool pullbackTouched = signalBar.high >= (emaPull - tolerance) &&
                                signalBar.close <= emaPull;
   const bool reclaimed = signalBar.close < signalBar.open;
   const bool breakout = signalBar.close < breakoutLevel - breakoutBuffer;
   const bool fresh = !InpRequireFreshBreakout || prevBar.close >= breakoutLevel - breakoutBuffer;
   return pullbackTouched && reclaimed && breakout && fresh;
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

void OpenTrade(const bool isLong, const double atr, MqlRates &rates[])
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

   if(InpCooldownBarsAfterTrade > 0 && g_state.lastTradeBarTime > 0)
   {
      const int shift = iBarShift(g_state.symbol, InpTradeTimeframe, g_state.lastTradeBarTime, true);
      if(shift >= 0 && shift <= InpCooldownBarsAfterTrade)
         return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(g_state.symbol, tick))
      return;

   const double entry = isLong ? tick.ask : tick.bid;
   double swingLevel = 0.0;
   if(isLong)
   {
      if(!GetLowestLow(rates, 1, InpSwingStopLookbackBars, swingLevel))
         return;
   }
   else
   {
      if(!GetHighestHigh(rates, 1, InpSwingStopLookbackBars, swingLevel))
         return;
   }

   double stopLoss = isLong ? swingLevel - atr * InpStopBufferAtr
                            : swingLevel + atr * InpStopBufferAtr;
   const double minStopDistance = atr * InpMinStopAtr;

   if(isLong && (entry - stopLoss) < minStopDistance)
      stopLoss = entry - minStopDistance;
   if(!isLong && (stopLoss - entry) < minStopDistance)
      stopLoss = entry + minStopDistance;

   const double riskDistance = MathAbs(entry - stopLoss);
   if(riskDistance > atr * InpMaxStopAtr || riskDistance <= 0.0)
   {
      if(isLong)
         g_state.sizeRejectedLong++;
      else
         g_state.sizeRejectedShort++;
      return;
   }

   double takeProfit = isLong ? entry + riskDistance * InpRewardRisk
                              : entry - riskDistance * InpRewardRisk;
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

   const string comment = isLong ? "USOIL pullback long" : "USOIL pullback short";
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
      g_state.lastTradeBarTime = rates[1].time;
   }
}

void ManageOpenPositions()
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
   const int required = MaxInt(InpBreakoutLookbackBars + 6, InpSwingStopLookbackBars + 6);
   MqlRates rates[];
   if(!GetLatestBars(g_state.symbol, rates, required))
      return;

   const datetime currentBarTime = rates[0].time;
   if(g_state.lastBarTime == currentBarTime)
      return;

   g_state.lastBarTime = currentBarTime;
   g_state.barsProcessed++;

   if(g_state.currentDay != DayStart(currentBarTime))
      ResetSession(currentBarTime);

   if(!TradingTimeAllowed(currentBarTime))
      return;

   double atr = 0.0;
   if(!GetBufferValue(g_state.atrHandle, 0, 1, atr) || atr <= 0.0)
   {
      g_state.atrMissing++;
      return;
   }

   if(!SpreadPassesFilters(atr))
      return;

   const MqlRates lastClosed = rates[1];
   if(BreakoutSignalConfirmed(true, atr, rates))
   {
      g_state.signalLong++;
      if(TrendPassesFilter(true, lastClosed) && VolumePassesFilter(true))
      {
         OpenTrade(true, atr, rates);
         return;
      }
   }

   if(BreakoutSignalConfirmed(false, atr, rates))
   {
      g_state.signalShort++;
      if(TrendPassesFilter(false, lastClosed) && VolumePassesFilter(false))
         OpenTrade(false, atr, rates);
   }
}

void ProcessAll()
{
   UpdateDailyRiskAnchor();
   ManageOpenPositions();

   if(DailyLossLimitReached())
      return;

   ProcessSymbol();
}

void PrintDiagnostics()
{
   if(!InpPrintDiagnostics)
      return;

   Print("==== USOilM5TrendPullbackGuardian diagnostics ====");
   PrintFormat("%s diagnostics: bars=%I64d atr_missing=%I64d spread_reject=%I64d",
               g_state.symbol, g_state.barsProcessed, g_state.atrMissing, g_state.spreadRejected);
   PrintFormat("%s diagnostics: signal_long=%I64d signal_short=%I64d trend_reject_long=%I64d trend_reject_short=%I64d",
               g_state.symbol, g_state.signalLong, g_state.signalShort,
               g_state.trendRejectedLong, g_state.trendRejectedShort);
   PrintFormat("%s diagnostics: volume_reject_long=%I64d volume_reject_short=%I64d size_reject_long=%I64d size_reject_short=%I64d",
               g_state.symbol, g_state.volumeRejectedLong, g_state.volumeRejectedShort,
               g_state.sizeRejectedLong, g_state.sizeRejectedShort);
   PrintFormat("%s diagnostics: order_attempts=%I64d orders_opened=%I64d",
               g_state.symbol, g_state.orderAttempts, g_state.ordersOpened);
   Print("==== End diagnostics ====");
}

int OnInit()
{
   if(InpTradeTimeframe != PERIOD_M5)
      Print("Warning: this EA was designed for PERIOD_M5.");

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

   g_state.fastEmaHandle = iMA(g_state.symbol, InpTradeTimeframe, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_state.pullbackEmaHandle = iMA(g_state.symbol, InpTradeTimeframe, InpPullbackEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_state.trendEmaHandle = iMA(g_state.symbol, InpTrendTimeframe, InpTrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_state.atrHandle = iATR(g_state.symbol, InpTradeTimeframe, InpAtrPeriod);
   g_state.adxHandle = iADX(g_state.symbol, InpTradeTimeframe, InpAdxPeriod);
   g_state.rsiHandle = iRSI(g_state.symbol, InpTradeTimeframe, InpRsiPeriod, PRICE_CLOSE);

   if(g_state.fastEmaHandle == INVALID_HANDLE ||
      g_state.pullbackEmaHandle == INVALID_HANDLE ||
      g_state.trendEmaHandle == INVALID_HANDLE ||
      g_state.atrHandle == INVALID_HANDLE ||
      g_state.adxHandle == INVALID_HANDLE ||
      g_state.rsiHandle == INVALID_HANDLE)
      return INIT_FAILED;

   g_state.lastBarTime = 0;
   g_state.lastTradeDay = 0;
   g_state.lastTradeBarTime = 0;
   g_state.barsProcessed = 0;
   g_state.atrMissing = 0;
   g_state.spreadRejected = 0;
   g_state.trendRejectedLong = 0;
   g_state.trendRejectedShort = 0;
   g_state.volumeRejectedLong = 0;
   g_state.volumeRejectedShort = 0;
   g_state.signalLong = 0;
   g_state.signalShort = 0;
   g_state.sizeRejectedLong = 0;
   g_state.sizeRejectedShort = 0;
   g_state.orderAttempts = 0;
   g_state.ordersOpened = 0;

   ResetSession(TimeCurrent());
   UpdateDailyRiskAnchor();
   EventSetTimer(MaxInt(1, InpTimerSeconds));

   PrintFormat("Initialized %s for USOIL trend-pullback variant. Account currency=%s",
               g_state.symbol, AccountInfoString(ACCOUNT_CURRENCY));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintDiagnostics();
   EventKillTimer();

   if(g_state.fastEmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_state.fastEmaHandle);
   if(g_state.pullbackEmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_state.pullbackEmaHandle);
   if(g_state.trendEmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_state.trendEmaHandle);
   if(g_state.atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_state.atrHandle);
   if(g_state.adxHandle != INVALID_HANDLE)
      IndicatorRelease(g_state.adxHandle);
   if(g_state.rsiHandle != INVALID_HANDLE)
      IndicatorRelease(g_state.rsiHandle);
}

void OnTick()
{
   ProcessAll();
}

void OnTimer()
{
   ProcessAll();
}
