//+------------------------------------------------------------------+
//|                                      IndexOpeningRangeGuardian.mq5 |
//| Conservative M5 ORB EA for US30, US500 and USTEC index CFDs       |
//+------------------------------------------------------------------+
#property copyright "Generated for TradingEA"
#property version   "1.00"
#property strict
#property description "Multi-symbol M5 NY-session Opening Range Breakout EA with ZAR/account-currency risk sizing."

#include <Trade/Trade.mqh>

enum ENUM_RISK_BASIS
{
   RISK_BASIS_BALANCE = 0,
   RISK_BASIS_EQUITY  = 1
};

input group "Symbols"
input string          InpSymbols                 = "US30,US500,USTEC"; // Tickmill symbols; suffixes are auto-detected when possible
input bool            InpAutoResolveSymbols      = true;                // Find broker suffix/prefix if exact name is unavailable
input ENUM_TIMEFRAMES InpTradeTimeframe          = PERIOD_M5;           // Strategy timeframe

input group "Session - broker/server time"
input int             InpSessionStartHour        = 16;                  // NY cash open is often 16:30 on GMT+3 brokers
input int             InpSessionStartMinute      = 30;
input int             InpSessionCloseHour        = 22;
input int             InpSessionCloseMinute      = 45;
input int             InpOpeningRangeMinutes     = 30;                  // First completed minutes used for the range
input int             InpEntryWindowMinutes      = 150;                 // Minutes after OR ends to allow entries
input bool            InpCloseAtSessionEnd       = true;
input int             InpForcedCloseBufferMin    = 5;

input group "Signal filters"
input int             InpFastEmaPeriod           = 20;
input int             InpSlowEmaPeriod           = 50;
input ENUM_TIMEFRAMES InpTrendTimeframe          = PERIOD_M15;
input int             InpTrendEmaPeriod          = 200;
input int             InpAtrPeriod               = 14;
input int             InpAdxPeriod               = 14;
input double          InpMinAdx                  = 18.0;
input bool            InpUseVolumeFilter         = true;
input int             InpVolumeLookbackBars      = 20;
input double          InpVolumeMultiplier        = 1.20;
input int             InpConfirmCloses           = 1;                   // Closed M5 bars beyond the range
input bool            InpRequireFreshBreakout    = true;                // Previous bar must not already be beyond range
input double          InpBreakoutBufferAtr       = 0.03;                // Extra distance beyond range as ATR fraction

input group "Range and cost filters"
input double          InpMinRangeAtr             = 0.35;                // Skip very small opening ranges
input double          InpMaxRangeAtr             = 2.20;                // Skip unusually wide opening ranges
input double          InpMaxRangePercent         = 0.90;                // Range width as percent of range midpoint
input int             InpMaxSpreadPoints         = 0;                   // 0 disables fixed points spread check
input double          InpMaxSpreadAtrPercent     = 8.0;                 // Spread must be <= this percent of ATR

input group "Risk and orders"
input bool            InpTradingEnabled          = true;
input ENUM_RISK_BASIS InpRiskBasis               = RISK_BASIS_EQUITY;
input double          InpRiskPercentPerTrade     = 0.35;                // Risk in account currency, e.g. ZAR
input double          InpMaxDailyLossPercent     = 1.20;                // Stops new entries once equity drawdown reaches this
input bool            InpCloseOnDailyLossLimit   = false;
input bool            InpOneTradePerSymbolDay    = true;
input bool            InpOneTradeTotalPerSymbol  = true;
input int             InpMaxPortfolioPositions   = 3;
input double          InpRewardRisk              = 1.80;
input double          InpMinStopAtr              = 0.80;                // Stop is at least this ATR distance
input double          InpMaxStopAtr              = 3.00;                // Skip if required stop is wider than this ATR
input double          InpStopBufferAtr           = 0.08;                // Buffer beyond opening range boundary
input bool            InpAllowMinLotIfRiskTooLow = false;               // False keeps risk cap strict
input int             InpSlippagePoints          = 30;
input int             InpMagicBase               = 503024;
input int             InpTimerSeconds            = 2;

input group "Trade management"
input double          InpBreakevenAtR            = 1.00;
input double          InpBreakevenBufferAtr      = 0.05;
input double          InpTrailStartR             = 1.25;
input double          InpTrailAtrMultiplier      = 1.15;

struct SymbolState
{
   string   requested;
   string   symbol;
   int      magic;
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
   double   rangeHigh;
   double   rangeLow;
   bool     rangeReady;
   bool     longTaken;
   bool     shortTaken;
   bool     initialized;
};

CTrade      g_trade;
SymbolState g_states[];
datetime    g_riskDayStart = 0;
double      g_dayStartEquity = 0.0;

//+------------------------------------------------------------------+
//| Utility functions                                                |
//+------------------------------------------------------------------+
string Trim(const string value)
{
   string result = value;
   result = StringTrimLeft(result);
   result = StringTrimRight(result);
   return result;
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

int MaxInt(const int left, const int right)
{
   return left > right ? left : right;
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

string ResolveSymbolName(const string requested)
{
   if(SymbolSelect(requested, true))
      return requested;

   if(!InpAutoResolveSymbols)
      return requested;

   const int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
   {
      const string name = SymbolName(i, false);
      if(StringFind(name, requested) >= 0 && SymbolSelect(name, true))
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

void ResetSession(SymbolState &state, const datetime now)
{
   state.sessionStart = BuildTimeForDay(now, InpSessionStartHour, InpSessionStartMinute);
   state.rangeEnd     = state.sessionStart + InpOpeningRangeMinutes * 60;
   state.entryCutoff  = state.rangeEnd + InpEntryWindowMinutes * 60;
   state.sessionClose = BuildTimeForDay(now, InpSessionCloseHour, InpSessionCloseMinute);

   if(state.sessionClose <= state.sessionStart)
      state.sessionClose += 24 * 60 * 60;
   if(state.entryCutoff > state.sessionClose)
      state.entryCutoff = state.sessionClose;

   state.rangeHigh  = 0.0;
   state.rangeLow   = 0.0;
   state.rangeReady = false;
   state.longTaken  = false;
   state.shortTaken = false;
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

int CountManagedPositions(const string symbol = "")
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      const long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic < InpMagicBase || magic >= InpMagicBase + 1000)
         continue;

      if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      count++;
   }
   return count;
}

bool HasManagedPosition(const string symbol)
{
   return CountManagedPositions(symbol) > 0;
}

bool BuildOpeningRange(SymbolState &state)
{
   MqlRates rangeRates[];
   ArraySetAsSeries(rangeRates, false);
   const int copied = CopyRates(state.symbol, InpTradeTimeframe, state.sessionStart, state.rangeEnd - 1, rangeRates);
   if(copied <= 0)
      return false;

   const int periodSeconds = PeriodSeconds(InpTradeTimeframe);
   const int expectedBars = MaxInt(1, (int)MathFloor((double)(InpOpeningRangeMinutes * 60) / (double)periodSeconds));

   double high = 0.0;
   double low = 0.0;
   int validBars = 0;

   for(int i = 0; i < copied; i++)
   {
      if(rangeRates[i].time < state.sessionStart || rangeRates[i].time >= state.rangeEnd)
         continue;

      if(validBars == 0)
      {
         high = rangeRates[i].high;
         low  = rangeRates[i].low;
      }
      else
      {
         high = MathMax(high, rangeRates[i].high);
         low  = MathMin(low, rangeRates[i].low);
      }
      validBars++;
   }

   if(validBars < expectedBars)
   {
      PrintFormat("%s opening range waiting for bars: %d/%d", state.symbol, validBars, expectedBars);
      return false;
   }

   state.rangeHigh = high;
   state.rangeLow = low;
   state.rangeReady = (high > low);

   if(state.rangeReady)
   {
      const int digits = (int)SymbolInfoInteger(state.symbol, SYMBOL_DIGITS);
      PrintFormat("%s opening range ready: high=%s low=%s bars=%d",
                  state.symbol,
                  DoubleToString(state.rangeHigh, digits),
                  DoubleToString(state.rangeLow, digits),
                  validBars);
   }

   return state.rangeReady;
}

bool RangePassesFilters(const SymbolState &state, const double atr)
{
   if(atr <= 0.0 || state.rangeHigh <= state.rangeLow)
      return false;

   const double range = state.rangeHigh - state.rangeLow;
   const double midpoint = (state.rangeHigh + state.rangeLow) / 2.0;
   const double rangeAtr = range / atr;
   const double rangePercent = midpoint > 0.0 ? (range / midpoint) * 100.0 : 0.0;

   if(rangeAtr < InpMinRangeAtr || rangeAtr > InpMaxRangeAtr)
   {
      PrintFormat("%s skipped: opening range %.2f ATR outside %.2f-%.2f",
                  state.symbol, rangeAtr, InpMinRangeAtr, InpMaxRangeAtr);
      return false;
   }

   if(InpMaxRangePercent > 0.0 && rangePercent > InpMaxRangePercent)
   {
      PrintFormat("%s skipped: opening range %.2f%% exceeds %.2f%%",
                  state.symbol, rangePercent, InpMaxRangePercent);
      return false;
   }

   return true;
}

bool SpreadPassesFilters(const string symbol, const double atr)
{
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return false;

   const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   const double spread = MathMax(0.0, tick.ask - tick.bid);
   const int spreadPoints = point > 0.0 ? (int)MathRound(spread / point) : 0;

   if(InpMaxSpreadPoints > 0 && spreadPoints > InpMaxSpreadPoints)
   {
      PrintFormat("%s skipped: spread %d points exceeds %d", symbol, spreadPoints, InpMaxSpreadPoints);
      return false;
   }

   if(InpMaxSpreadAtrPercent > 0.0 && atr > 0.0 && (spread / atr) * 100.0 > InpMaxSpreadAtrPercent)
   {
      PrintFormat("%s skipped: spread %.2f%% of ATR exceeds %.2f%%",
                  symbol, (spread / atr) * 100.0, InpMaxSpreadAtrPercent);
      return false;
   }

   return true;
}

bool VolumePassesFilter(const string symbol, const bool isLong)
{
   if(!InpUseVolumeFilter)
      return true;

   const int required = MaxInt(3, InpVolumeLookbackBars + 2);
   MqlRates rates[];
   if(!GetLatestClosedBars(symbol, rates, required))
      return false;

   const long breakoutVolume = rates[1].tick_volume;
   double average = 0.0;
   int count = 0;

   for(int i = 2; i < required; i++)
   {
      average += (double)rates[i].tick_volume;
      count++;
   }

   if(count <= 0 || average <= 0.0)
      return false;

   average /= (double)count;

   if((double)breakoutVolume < average * InpVolumeMultiplier)
   {
      PrintFormat("%s %s skipped: tick volume %I64d below %.2fx average %.1f",
                  symbol, isLong ? "long" : "short", breakoutVolume, InpVolumeMultiplier, average);
      return false;
   }

   return true;
}

bool TrendPassesFilter(const SymbolState &state, const bool isLong, const MqlRates &lastClosed)
{
   double fastEma = 0.0;
   double slowEma = 0.0;
   double trendEma = 0.0;
   double adx = 0.0;
   double plusDi = 0.0;
   double minusDi = 0.0;

   if(!GetBufferValue(state.fastEmaHandle, 0, 1, fastEma) ||
      !GetBufferValue(state.slowEmaHandle, 0, 1, slowEma) ||
      !GetBufferValue(state.trendEmaHandle, 0, 1, trendEma) ||
      !GetBufferValue(state.adxHandle, 0, 1, adx) ||
      !GetBufferValue(state.adxHandle, 1, 1, plusDi) ||
      !GetBufferValue(state.adxHandle, 2, 1, minusDi))
   {
      return false;
   }

   if(adx < InpMinAdx)
   {
      PrintFormat("%s skipped: ADX %.2f below %.2f", state.symbol, adx, InpMinAdx);
      return false;
   }

   if(isLong)
      return fastEma > slowEma && lastClosed.close > fastEma && lastClosed.close > trendEma && plusDi > minusDi;

   return fastEma < slowEma && lastClosed.close < fastEma && lastClosed.close < trendEma && minusDi > plusDi;
}

bool BreakoutConfirmed(const SymbolState &state, const bool isLong, const double atr)
{
   const int confirmations = MaxInt(1, InpConfirmCloses);
   const int requiredBars = confirmations + 2;
   MqlRates rates[];
   if(!GetLatestClosedBars(state.symbol, rates, requiredBars))
      return false;

   const double buffer = atr * InpBreakoutBufferAtr;
   for(int i = 1; i <= confirmations; i++)
   {
      if(isLong && rates[i].close <= state.rangeHigh + buffer)
         return false;
      if(!isLong && rates[i].close >= state.rangeLow - buffer)
         return false;
   }

   if(InpRequireFreshBreakout)
   {
      const int prior = confirmations + 1;
      if(isLong && rates[prior].close > state.rangeHigh + buffer)
         return false;
      if(!isLong && rates[prior].close < state.rangeLow - buffer)
         return false;
   }

   return true;
}

bool CalculatePositionSize(const string symbol,
                           const ENUM_ORDER_TYPE orderType,
                           const double entry,
                           const double stopLoss,
                           double &volume)
{
   volume = 0.0;

   const double riskMoney = RiskCapital() * InpRiskPercentPerTrade / 100.0;
   if(riskMoney <= 0.0)
      return false;

   double oneLotProfit = 0.0;
   if(!OrderCalcProfit(orderType, symbol, 1.0, entry, stopLoss, oneLotProfit))
   {
      PrintFormat("%s cannot calculate risk: OrderCalcProfit failed, error=%d", symbol, GetLastError());
      return false;
   }

   const double oneLotLoss = MathAbs(oneLotProfit);
   if(oneLotLoss <= 0.0)
      return false;

   const double rawVolume = riskMoney / oneLotLoss;
   const double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   if(rawVolume < minVol && !InpAllowMinLotIfRiskTooLow)
   {
      PrintFormat("%s skipped: calculated volume %.4f below min %.4f; risk cap remains strict",
                  symbol, rawVolume, minVol);
      return false;
   }

   volume = NormalizeVolume(symbol, rawVolume);
   if(volume <= 0.0)
      return false;

   double margin = 0.0;
   if(OrderCalcMargin(orderType, symbol, volume, entry, margin))
   {
      const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin * 0.90)
      {
         PrintFormat("%s skipped: margin %.2f exceeds 90%% of free margin %.2f",
                     symbol, margin, freeMargin);
         return false;
      }
   }

   return true;
}

bool StopsMeetBrokerMinimums(const string symbol, const bool isLong, const double sl, const double tp)
{
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return false;

   const double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   const int stopsLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double minDistance = stopsLevel * point;

   if(minDistance <= 0.0)
      return true;

   if(isLong)
      return (tick.bid - sl) >= minDistance && (tp - tick.bid) >= minDistance;

   return (sl - tick.ask) >= minDistance && (tick.ask - tp) >= minDistance;
}

void OpenBreakoutTrade(SymbolState &state, const bool isLong, const double atr)
{
   if(!InpTradingEnabled || DailyLossLimitReached())
      return;

   if(CountManagedPositions() >= InpMaxPortfolioPositions)
      return;

   if(InpOneTradeTotalPerSymbol && HasManagedPosition(state.symbol))
      return;

   if(InpOneTradePerSymbolDay)
   {
      if(isLong && state.longTaken)
         return;
      if(!isLong && state.shortTaken)
         return;
      if(state.longTaken || state.shortTaken)
         return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(state.symbol, tick))
      return;

   const double entry = isLong ? tick.ask : tick.bid;
   const double rangeStopBuffer = atr * InpStopBufferAtr;
   double stopLoss = isLong ? state.rangeLow - rangeStopBuffer : state.rangeHigh + rangeStopBuffer;
   const double minStopDistance = atr * InpMinStopAtr;

   if(isLong && (entry - stopLoss) < minStopDistance)
      stopLoss = entry - minStopDistance;
   if(!isLong && (stopLoss - entry) < minStopDistance)
      stopLoss = entry + minStopDistance;

   const double riskDistance = MathAbs(entry - stopLoss);
   if(atr <= 0.0 || riskDistance > atr * InpMaxStopAtr)
   {
      PrintFormat("%s %s skipped: stop %.2f ATR exceeds max %.2f",
                  state.symbol, isLong ? "long" : "short", riskDistance / atr, InpMaxStopAtr);
      return;
   }

   double takeProfit = isLong ? entry + riskDistance * InpRewardRisk : entry - riskDistance * InpRewardRisk;
   stopLoss = NormalizePrice(state.symbol, stopLoss);
   takeProfit = NormalizePrice(state.symbol, takeProfit);

   if(!StopsMeetBrokerMinimums(state.symbol, isLong, stopLoss, takeProfit))
   {
      PrintFormat("%s %s skipped: SL/TP too close for broker stop level",
                  state.symbol, isLong ? "long" : "short");
      return;
   }

   double volume = 0.0;
   const ENUM_ORDER_TYPE orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!CalculatePositionSize(state.symbol, orderType, entry, stopLoss, volume))
      return;

   g_trade.SetExpertMagicNumber(state.magic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(state.symbol);

   const string comment = isLong ? "IORG ORB long" : "IORG ORB short";
   const bool sent = isLong
                     ? g_trade.Buy(volume, state.symbol, 0.0, stopLoss, takeProfit, comment)
                     : g_trade.Sell(volume, state.symbol, 0.0, stopLoss, takeProfit, comment);

   if(sent)
   {
      if(isLong)
         state.longTaken = true;
      else
         state.shortTaken = true;

      const int digits = (int)SymbolInfoInteger(state.symbol, SYMBOL_DIGITS);
      PrintFormat("%s %s opened volume=%.4f SL=%s TP=%s risk=%.2f%%",
                  state.symbol, isLong ? "long" : "short", volume,
                  DoubleToString(stopLoss, digits),
                  DoubleToString(takeProfit, digits),
                  InpRiskPercentPerTrade);
   }
   else
   {
      PrintFormat("%s %s order failed. retcode=%d %s",
                  state.symbol, isLong ? "long" : "short",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
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

      const string symbol = PositionGetString(POSITION_SYMBOL);
      const long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic < InpMagicBase || magic >= InpMagicBase + 1000)
         continue;

      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick))
         continue;

      const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const bool isLong = (type == POSITION_TYPE_BUY);
      const double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      const double currentSl = PositionGetDouble(POSITION_SL);
      const double currentTp = PositionGetDouble(POSITION_TP);
      const double mark = isLong ? tick.bid : tick.ask;

      if(dailyLimit && InpCloseOnDailyLossLimit)
      {
         g_trade.SetExpertMagicNumber((int)magic);
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
            g_trade.SetExpertMagicNumber((int)magic);
            g_trade.PositionClose(ticket);
            continue;
         }
      }

      double atr = 0.0;
      for(int s = 0; s < ArraySize(g_states); s++)
      {
         if(g_states[s].symbol == symbol)
         {
            GetBufferValue(g_states[s].atrHandle, 0, 1, atr);
            break;
         }
      }

      if(atr <= 0.0)
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
         {
            newSl = breakeven;
         }
      }

      if(currentR >= InpTrailStartR)
      {
         const double trailing = isLong ? mark - atr * InpTrailAtrMultiplier
                                        : mark + atr * InpTrailAtrMultiplier;
         if((isLong && trailing > newSl) || (!isLong && (newSl <= 0.0 || trailing < newSl)))
            newSl = trailing;
      }

      if(newSl > 0.0 && MathAbs(newSl - currentSl) > SymbolInfoDouble(symbol, SYMBOL_POINT))
      {
         newSl = NormalizePrice(symbol, newSl);
         if(StopsMeetBrokerMinimums(symbol, isLong, newSl, currentTp))
         {
            g_trade.SetExpertMagicNumber((int)magic);
            if(!g_trade.PositionModify(ticket, newSl, currentTp))
            {
               PrintFormat("%s failed to modify position %I64u: %d %s",
                           symbol, ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
            }
         }
      }
   }
}

void ProcessSymbol(SymbolState &state)
{
   if(!state.initialized)
      return;

   MqlRates rates[];
   if(!GetLatestClosedBars(state.symbol, rates, MaxInt(4, InpConfirmCloses + 3)))
      return;

   const datetime currentBarTime = rates[0].time;
   if(state.lastBarTime == currentBarTime)
      return;
   state.lastBarTime = currentBarTime;

   if(state.sessionStart == 0 || currentBarTime >= state.sessionStart + 24 * 60 * 60)
      ResetSession(state, currentBarTime);

   if(currentBarTime < state.sessionStart)
      ResetSession(state, currentBarTime);

   if(currentBarTime < state.rangeEnd || currentBarTime > state.sessionClose)
      return;

   double atr = 0.0;
   if(!GetBufferValue(state.atrHandle, 0, 1, atr) || atr <= 0.0)
      return;

   if(!state.rangeReady && !BuildOpeningRange(state))
      return;

   if(currentBarTime > state.entryCutoff)
      return;

   if(!RangePassesFilters(state, atr) || !SpreadPassesFilters(state.symbol, atr))
      return;

   const MqlRates lastClosed = rates[1];

   if(BreakoutConfirmed(state, true, atr) &&
      TrendPassesFilter(state, true, lastClosed) &&
      VolumePassesFilter(state.symbol, true))
   {
      OpenBreakoutTrade(state, true, atr);
      return;
   }

   if(BreakoutConfirmed(state, false, atr) &&
      TrendPassesFilter(state, false, lastClosed) &&
      VolumePassesFilter(state.symbol, false))
   {
      OpenBreakoutTrade(state, false, atr);
   }
}

void ProcessAllSymbols()
{
   UpdateDailyRiskAnchor();
   ManageOpenPositions();

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

   for(int i = 0; i < ArraySize(g_states); i++)
      ProcessSymbol(g_states[i]);
}

//+------------------------------------------------------------------+
//| Expert lifecycle                                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpOpeningRangeMinutes <= 0 || InpEntryWindowMinutes <= 0)
   {
      Print("Invalid session inputs: opening range and entry window must be positive.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpTradeTimeframe != PERIOD_M5)
      Print("Warning: this EA was designed for PERIOD_M5. Backtest carefully after changing timeframe.");

   string parts[];
   const int count = StringSplit(InpSymbols, ',', parts);
   if(count <= 0)
   {
      Print("No symbols configured.");
      return INIT_PARAMETERS_INCORRECT;
   }

   ArrayResize(g_states, count);

   int active = 0;
   for(int i = 0; i < count; i++)
   {
      const string requested = Trim(parts[i]);
      if(requested == "")
         continue;

      SymbolState state;
      state.requested       = requested;
      state.symbol          = ResolveSymbolName(requested);
      state.magic           = InpMagicBase + i;
      state.fastEmaHandle   = INVALID_HANDLE;
      state.slowEmaHandle   = INVALID_HANDLE;
      state.trendEmaHandle  = INVALID_HANDLE;
      state.atrHandle       = INVALID_HANDLE;
      state.adxHandle       = INVALID_HANDLE;
      state.lastBarTime     = 0;
      state.sessionStart    = 0;
      state.rangeEnd        = 0;
      state.entryCutoff     = 0;
      state.sessionClose    = 0;
      state.rangeHigh       = 0.0;
      state.rangeLow        = 0.0;
      state.rangeReady      = false;
      state.longTaken       = false;
      state.shortTaken      = false;
      state.initialized     = false;

      if(!SymbolSelect(state.symbol, true))
      {
         PrintFormat("Unable to select symbol '%s' resolved from '%s'", state.symbol, requested);
         g_states[i] = state;
         continue;
      }

      state.fastEmaHandle  = iMA(state.symbol, InpTradeTimeframe, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      state.slowEmaHandle  = iMA(state.symbol, InpTradeTimeframe, InpSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      state.trendEmaHandle = iMA(state.symbol, InpTrendTimeframe, InpTrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      state.atrHandle      = iATR(state.symbol, InpTradeTimeframe, InpAtrPeriod);
      state.adxHandle      = iADX(state.symbol, InpTradeTimeframe, InpAdxPeriod);

      if(state.fastEmaHandle == INVALID_HANDLE ||
         state.slowEmaHandle == INVALID_HANDLE ||
         state.trendEmaHandle == INVALID_HANDLE ||
         state.atrHandle == INVALID_HANDLE ||
         state.adxHandle == INVALID_HANDLE)
      {
         PrintFormat("Indicator initialization failed for %s. error=%d", state.symbol, GetLastError());
         g_states[i] = state;
         continue;
      }

      ResetSession(state, TimeCurrent());
      state.initialized = true;
      g_states[i] = state;
      active++;

      PrintFormat("Initialized %s (requested %s), magic=%d", state.symbol, state.requested, state.magic);
   }

   if(active <= 0)
   {
      Print("No active symbols initialized.");
      return INIT_FAILED;
   }

   UpdateDailyRiskAnchor();
   EventSetTimer(MaxInt(1, InpTimerSeconds));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   for(int i = 0; i < ArraySize(g_states); i++)
   {
      if(g_states[i].fastEmaHandle != INVALID_HANDLE)
         IndicatorRelease(g_states[i].fastEmaHandle);
      if(g_states[i].slowEmaHandle != INVALID_HANDLE)
         IndicatorRelease(g_states[i].slowEmaHandle);
      if(g_states[i].trendEmaHandle != INVALID_HANDLE)
         IndicatorRelease(g_states[i].trendEmaHandle);
      if(g_states[i].atrHandle != INVALID_HANDLE)
         IndicatorRelease(g_states[i].atrHandle);
      if(g_states[i].adxHandle != INVALID_HANDLE)
         IndicatorRelease(g_states[i].adxHandle);
   }
}

void OnTick()
{
   ProcessAllSymbols();
}

void OnTimer()
{
   ProcessAllSymbols();
}
//+------------------------------------------------------------------+
