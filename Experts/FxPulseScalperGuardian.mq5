//+------------------------------------------------------------------+
//|                                           FxPulseScalperGuardian.mq5 |
//| Conservative MT5 FX scalping EA for major currency pairs           |
//+------------------------------------------------------------------+
#property copyright "Generated for TradingEA"
#property version   "1.00"
#property strict
#property description "Major-FX M1 pullback scalper with account-currency risk sizing and strict spread/session controls."

#include <Trade/Trade.mqh>

enum ENUM_FX_RISK_BASIS
{
   FX_RISK_BALANCE = 0,
   FX_RISK_EQUITY  = 1
};

enum ENUM_FX_DIRECTION
{
   FX_TRADE_BOTH       = 0,
   FX_TRADE_LONG_ONLY  = 1,
   FX_TRADE_SHORT_ONLY = 2
};

input group "Symbols"
input string          InpSymbols                 = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD";
input bool            InpAutoResolveSymbols      = true;
input bool            InpUseChartSymbolOnlyInTester = true;
input bool            InpStrictTesterSymbolList  = true;
input ENUM_TIMEFRAMES InpTradeTimeframe          = PERIOD_M1;

input group "Session - broker/server time"
input int             InpSessionStartHour        = 8;
input int             InpSessionStartMinute      = 0;
input int             InpSessionEndHour          = 20;
input int             InpSessionEndMinute        = 0;
input bool            InpCloseAtSessionEnd       = true;
input int             InpForcedCloseBufferMin    = 5;

input group "Signal"
input ENUM_FX_DIRECTION InpTradeDirection        = FX_TRADE_BOTH;
input ENUM_TIMEFRAMES InpTrendTimeframe          = PERIOD_M15;
input int             InpTrendEmaPeriod          = 200;
input int             InpFastEmaPeriod           = 20;
input int             InpSlowEmaPeriod           = 50;
input int             InpRsiPeriod               = 14;
input double          InpLongPullbackRsi         = 45.0;
input double          InpLongEntryRsi            = 52.0;
input double          InpShortPullbackRsi        = 55.0;
input double          InpShortEntryRsi           = 48.0;
input int             InpAtrPeriod               = 14;
input double          InpMinAtrPoints            = 40.0;
input double          InpMaxAtrPoints            = 250.0;
input double          InpPullbackToleranceAtr    = 0.18;
input double          InpMinBodyAtr              = 0.04;

input group "Spread and execution"
input int             InpMaxSpreadPoints         = 25;
input double          InpMaxSpreadAtrPercent     = 18.0;
input int             InpSlippagePoints          = 20;
input int             InpCooldownMinutes         = 20;
input int             InpMaxTradesPerSymbolDay   = 3;
input int             InpMaxPortfolioPositions   = 5;
input bool            InpOnePositionPerSymbol    = true;

input group "Risk"
input bool            InpTradingEnabled          = true;
input ENUM_FX_RISK_BASIS InpRiskBasis            = FX_RISK_EQUITY;
input double          InpRiskPercentPerTrade     = 0.20;
input double          InpMaxDailyLossPercent     = 1.00;
input bool            InpCloseOnDailyLossLimit   = false;
input bool            InpAllowMinLotIfRiskTooLow = true;
input double          InpMaxMinLotRiskPercent    = 0.50;
input int             InpMagicBase               = 601024;
input int             InpTimerSeconds            = 2;

input group "Stops and exits"
input double          InpStopAtrMultiplier       = 1.15;
input double          InpRewardRisk              = 1.10;
input double          InpBreakevenAtR            = 0.80;
input double          InpBreakevenBufferAtr      = 0.05;
input double          InpTrailStartR             = 1.10;
input double          InpTrailAtrMultiplier      = 0.90;
input int             InpMaxPositionMinutes      = 90;

input group "Diagnostics"
input bool            InpPrintDiagnostics        = true;

struct FxSymbolState
{
   string   requested;
   string   symbol;
   int      magic;
   int      fastEmaHandle;
   int      slowEmaHandle;
   int      trendEmaHandle;
   int      rsiHandle;
   int      atrHandle;
   datetime lastBarTime;
   datetime dayStart;
   datetime lastTradeTime;
   int      tradesToday;
   bool     initialized;
   long     barsProcessed;
   long     atrRejected;
   long     spreadRejected;
   long     sessionRejected;
   long     trendRejectedLong;
   long     trendRejectedShort;
   long     pullbackRejectedLong;
   long     pullbackRejectedShort;
   long     cooldownRejected;
   long     sizeRejected;
   long     orderAttempts;
   long     ordersOpened;
};

CTrade        g_trade;
FxSymbolState g_states[];
datetime      g_riskDayStart = 0;
double        g_dayStartEquity = 0.0;

//+------------------------------------------------------------------+
//| Utility functions                                                |
//+------------------------------------------------------------------+
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

bool TesterChartSymbolAllowed(const string chartSymbol, const string configuredSymbols)
{
   string parts[];
   const int count = StringSplit(configuredSymbols, ',', parts);
   for(int i = 0; i < count; i++)
   {
      const string requested = Trim(parts[i]);
      if(requested != "" && SymbolNameMatchesRequest(chartSymbol, requested))
         return true;
   }
   return false;
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

bool GetRates(const string symbol, MqlRates &rates[], const int barsRequired)
{
   ArraySetAsSeries(rates, true);
   const int copied = CopyRates(symbol, InpTradeTimeframe, 0, barsRequired, rates);
   return copied >= barsRequired;
}

double RiskCapital()
{
   if(InpRiskBasis == FX_RISK_BALANCE)
      return AccountInfoDouble(ACCOUNT_BALANCE);
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

void UpdateDailyRiskAnchor()
{
   const datetime today = DayStart(TimeCurrent());
   if(g_riskDayStart != today || g_dayStartEquity <= 0.0)
   {
      g_riskDayStart = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      PrintFormat("FX daily risk anchor reset. Account currency=%s, start equity=%.2f",
                  AccountInfoString(ACCOUNT_CURRENCY), g_dayStartEquity);
   }
}

bool DailyLossLimitReached()
{
   if(InpMaxDailyLossPercent <= 0.0 || g_dayStartEquity <= 0.0)
      return false;

   const double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double maxLossMoney = g_dayStartEquity * InpMaxDailyLossPercent / 100.0;
   return (g_dayStartEquity - currentEquity) >= maxLossMoney;
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

bool IsSessionOpen(const datetime now)
{
   datetime start = BuildTimeForDay(now, InpSessionStartHour, InpSessionStartMinute);
   datetime end = BuildTimeForDay(now, InpSessionEndHour, InpSessionEndMinute);

   if(end <= start)
   {
      if(now < start)
         start -= 24 * 60 * 60;
      else
         end += 24 * 60 * 60;
   }

   return now >= start && now <= end;
}

bool IsForcedCloseTime(const datetime now)
{
   datetime end = BuildTimeForDay(now, InpSessionEndHour, InpSessionEndMinute);
   datetime start = BuildTimeForDay(now, InpSessionStartHour, InpSessionStartMinute);

   if(end <= start && now >= start)
      end += 24 * 60 * 60;

   return now >= end - InpForcedCloseBufferMin * 60;
}

void ResetStateDay(FxSymbolState &state, const datetime now)
{
   const datetime today = DayStart(now);
   if(state.dayStart != today)
   {
      state.dayStart = today;
      state.tradesToday = 0;
   }
}

//+------------------------------------------------------------------+
//| Position and risk helpers                                        |
//+------------------------------------------------------------------+
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
      PrintFormat("%s cannot calculate FX risk: OrderCalcProfit failed, error=%d", symbol, GetLastError());
      return false;
   }

   const double oneLotLoss = MathAbs(oneLotProfit);
   if(oneLotLoss <= 0.0)
      return false;

   const double rawVolume = riskMoney / oneLotLoss;
   const double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   if(rawVolume < minVol && !InpAllowMinLotIfRiskTooLow)
   {
      PrintFormat("%s skipped: calculated volume %.4f below min %.4f", symbol, rawVolume, minVol);
      return false;
   }

   if(rawVolume < minVol && InpAllowMinLotIfRiskTooLow)
   {
      const double maxMinLotRiskMoney = RiskCapital() * InpMaxMinLotRiskPercent / 100.0;
      const double minLotRiskMoney = oneLotLoss * minVol;
      if(maxMinLotRiskMoney <= 0.0 || minLotRiskMoney > maxMinLotRiskMoney)
      {
         PrintFormat("%s skipped: min lot risk %.2f exceeds cap %.2f (%.2f%%)",
                     symbol, minLotRiskMoney, maxMinLotRiskMoney, InpMaxMinLotRiskPercent);
         return false;
      }
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

//+------------------------------------------------------------------+
//| Filters and signals                                              |
//+------------------------------------------------------------------+
bool SpreadPasses(FxSymbolState &state, const double atr)
{
   MqlTick tick;
   if(!SymbolInfoTick(state.symbol, tick))
   {
      state.spreadRejected++;
      return false;
   }

   const double point = SymbolInfoDouble(state.symbol, SYMBOL_POINT);
   const double spread = MathMax(0.0, tick.ask - tick.bid);
   const int spreadPoints = point > 0.0 ? (int)MathRound(spread / point) : 0;

   if(InpMaxSpreadPoints > 0 && spreadPoints > InpMaxSpreadPoints)
   {
      state.spreadRejected++;
      return false;
   }

   if(InpMaxSpreadAtrPercent > 0.0 && atr > 0.0 && (spread / atr) * 100.0 > InpMaxSpreadAtrPercent)
   {
      state.spreadRejected++;
      return false;
   }

   return true;
}

bool AtrPasses(FxSymbolState &state, const double atr)
{
   const double point = SymbolInfoDouble(state.symbol, SYMBOL_POINT);
   if(point <= 0.0 || atr <= 0.0)
   {
      state.atrRejected++;
      return false;
   }

   const double atrPoints = atr / point;
   if((InpMinAtrPoints > 0.0 && atrPoints < InpMinAtrPoints) ||
      (InpMaxAtrPoints > 0.0 && atrPoints > InpMaxAtrPoints))
   {
      state.atrRejected++;
      return false;
   }

   return true;
}

bool DirectionAllowed(const bool isLong)
{
   if(InpTradeDirection == FX_TRADE_BOTH)
      return true;
   if(isLong)
      return InpTradeDirection == FX_TRADE_LONG_ONLY;
   return InpTradeDirection == FX_TRADE_SHORT_ONLY;
}

bool TrendPasses(FxSymbolState &state, const bool isLong, const MqlRates &lastClosed)
{
   double fast = 0.0;
   double slow = 0.0;
   double trend = 0.0;

   if(!GetBufferValue(state.fastEmaHandle, 0, 1, fast) ||
      !GetBufferValue(state.slowEmaHandle, 0, 1, slow) ||
      !GetBufferValue(state.trendEmaHandle, 0, 1, trend))
   {
      return false;
   }

   if(isLong)
   {
      const bool passed = fast > slow && lastClosed.close > fast && lastClosed.close > trend;
      if(!passed)
         state.trendRejectedLong++;
      return passed;
   }

   const bool passed = fast < slow && lastClosed.close < fast && lastClosed.close < trend;
   if(!passed)
      state.trendRejectedShort++;
   return passed;
}

bool PullbackSignal(FxSymbolState &state, const bool isLong, const MqlRates &lastClosed, const double atr)
{
   double rsi1 = 0.0;
   double rsi2 = 0.0;
   double fast = 0.0;

   if(!GetBufferValue(state.rsiHandle, 0, 1, rsi1) ||
      !GetBufferValue(state.rsiHandle, 0, 2, rsi2) ||
      !GetBufferValue(state.fastEmaHandle, 0, 1, fast))
   {
      return false;
   }

   const double tolerance = atr * InpPullbackToleranceAtr;
   const double body = MathAbs(lastClosed.close - lastClosed.open);
   if(InpMinBodyAtr > 0.0 && body < atr * InpMinBodyAtr)
   {
      if(isLong)
         state.pullbackRejectedLong++;
      else
         state.pullbackRejectedShort++;
      return false;
   }

   if(isLong)
   {
      const bool touchedFastEma = lastClosed.low <= fast + tolerance;
      const bool rsiRecovered = rsi2 <= InpLongPullbackRsi && rsi1 >= InpLongEntryRsi;
      const bool bullishClose = lastClosed.close > lastClosed.open;
      const bool passed = touchedFastEma && rsiRecovered && bullishClose;
      if(!passed)
         state.pullbackRejectedLong++;
      return passed;
   }

   const bool touchedFastEma = lastClosed.high >= fast - tolerance;
   const bool rsiRolled = rsi2 >= InpShortPullbackRsi && rsi1 <= InpShortEntryRsi;
   const bool bearishClose = lastClosed.close < lastClosed.open;
   const bool passed = touchedFastEma && rsiRolled && bearishClose;
   if(!passed)
      state.pullbackRejectedShort++;
   return passed;
}

//+------------------------------------------------------------------+
//| Trading                                                          |
//+------------------------------------------------------------------+
void OpenTrade(FxSymbolState &state, const bool isLong, const double atr)
{
   if(!InpTradingEnabled || DailyLossLimitReached())
      return;

   if(!DirectionAllowed(isLong))
      return;

   if(InpMaxPortfolioPositions > 0 && CountManagedPositions() >= InpMaxPortfolioPositions)
      return;

   if(InpOnePositionPerSymbol && CountManagedPositions(state.symbol) > 0)
      return;

   if(InpMaxTradesPerSymbolDay > 0 && state.tradesToday >= InpMaxTradesPerSymbolDay)
      return;

   if(InpCooldownMinutes > 0 && state.lastTradeTime > 0 &&
      TimeCurrent() - state.lastTradeTime < InpCooldownMinutes * 60)
   {
      state.cooldownRejected++;
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(state.symbol, tick))
      return;

   const double entry = isLong ? tick.ask : tick.bid;
   const double stopDistance = atr * InpStopAtrMultiplier;
   double sl = isLong ? entry - stopDistance : entry + stopDistance;
   double tp = isLong ? entry + stopDistance * InpRewardRisk : entry - stopDistance * InpRewardRisk;
   sl = NormalizePrice(state.symbol, sl);
   tp = NormalizePrice(state.symbol, tp);

   if(!StopsMeetBrokerMinimums(state.symbol, isLong, sl, tp))
   {
      state.sizeRejected++;
      return;
   }

   double volume = 0.0;
   const ENUM_ORDER_TYPE orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!CalculatePositionSize(state.symbol, orderType, entry, sl, volume))
   {
      state.sizeRejected++;
      return;
   }

   g_trade.SetExpertMagicNumber(state.magic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(state.symbol);

   const string comment = isLong ? "FPSG pullback long" : "FPSG pullback short";
   state.orderAttempts++;
   const bool sent = isLong
                     ? g_trade.Buy(volume, state.symbol, 0.0, sl, tp, comment)
                     : g_trade.Sell(volume, state.symbol, 0.0, sl, tp, comment);

   if(sent)
   {
      state.ordersOpened++;
      state.tradesToday++;
      state.lastTradeTime = TimeCurrent();
      PrintFormat("%s FX %s opened volume=%.4f SL=%s TP=%s",
                  state.symbol,
                  isLong ? "long" : "short",
                  volume,
                  DoubleToString(sl, (int)SymbolInfoInteger(state.symbol, SYMBOL_DIGITS)),
                  DoubleToString(tp, (int)SymbolInfoInteger(state.symbol, SYMBOL_DIGITS)));
   }
   else
   {
      PrintFormat("%s FX %s order failed. retcode=%d %s",
                  state.symbol, isLong ? "long" : "short",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }
}

void ManagePositions()
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
      const datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      const double mark = isLong ? tick.bid : tick.ask;

      if(dailyLimit && InpCloseOnDailyLossLimit)
      {
         g_trade.SetExpertMagicNumber((int)magic);
         g_trade.PositionClose(ticket);
         continue;
      }

      if(InpCloseAtSessionEnd && IsForcedCloseTime(TimeCurrent()))
      {
         g_trade.SetExpertMagicNumber((int)magic);
         g_trade.PositionClose(ticket);
         continue;
      }

      if(InpMaxPositionMinutes > 0 && TimeCurrent() - openTime >= InpMaxPositionMinutes * 60)
      {
         g_trade.SetExpertMagicNumber((int)magic);
         g_trade.PositionClose(ticket);
         continue;
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
               PrintFormat("%s failed to modify FX position %I64u: %d %s",
                           symbol, ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
            }
         }
      }
   }
}

void ProcessSymbol(FxSymbolState &state)
{
   if(!state.initialized)
      return;

   MqlRates rates[];
   if(!GetRates(state.symbol, rates, 4))
      return;

   const datetime currentBarTime = rates[0].time;
   if(state.lastBarTime == currentBarTime)
      return;
   state.lastBarTime = currentBarTime;
   state.barsProcessed++;

   ResetStateDay(state, currentBarTime);

   if(!IsSessionOpen(currentBarTime))
   {
      state.sessionRejected++;
      return;
   }

   double atr = 0.0;
   if(!GetBufferValue(state.atrHandle, 0, 1, atr))
      return;

   if(!AtrPasses(state, atr) || !SpreadPasses(state, atr))
      return;

   const MqlRates lastClosed = rates[1];

   if(DirectionAllowed(true) && TrendPasses(state, true, lastClosed) && PullbackSignal(state, true, lastClosed, atr))
   {
      OpenTrade(state, true, atr);
      return;
   }

   if(DirectionAllowed(false) && TrendPasses(state, false, lastClosed) && PullbackSignal(state, false, lastClosed, atr))
   {
      OpenTrade(state, false, atr);
   }
}

void ProcessAllSymbols()
{
   UpdateDailyRiskAnchor();
   ManagePositions();

   if(DailyLossLimitReached())
   {
      static datetime lastPrint = 0;
      if(TimeCurrent() - lastPrint > 300)
      {
         PrintFormat("FX daily loss limit reached. New entries paused. Start equity=%.2f current equity=%.2f",
                     g_dayStartEquity, AccountInfoDouble(ACCOUNT_EQUITY));
         lastPrint = TimeCurrent();
      }
      return;
   }

   for(int i = 0; i < ArraySize(g_states); i++)
      ProcessSymbol(g_states[i]);
}

void PrintDiagnostics()
{
   if(!InpPrintDiagnostics)
      return;

   Print("==== FxPulseScalperGuardian diagnostics ====");
   for(int i = 0; i < ArraySize(g_states); i++)
   {
      FxSymbolState state = g_states[i];
      if(!state.initialized)
      {
         PrintFormat("%s diagnostics: not initialized", state.requested);
         continue;
      }

      PrintFormat("%s diagnostics: bars=%I64d session_reject=%I64d atr_reject=%I64d spread_reject=%I64d cooldown_reject=%I64d",
                  state.symbol, state.barsProcessed, state.sessionRejected, state.atrRejected,
                  state.spreadRejected, state.cooldownRejected);
      PrintFormat("%s diagnostics: trend_reject_long=%I64d trend_reject_short=%I64d pullback_reject_long=%I64d pullback_reject_short=%I64d",
                  state.symbol, state.trendRejectedLong, state.trendRejectedShort,
                  state.pullbackRejectedLong, state.pullbackRejectedShort);
      PrintFormat("%s diagnostics: trades_today=%d size_reject=%I64d order_attempts=%I64d orders_opened=%I64d",
                  state.symbol, state.tradesToday, state.sizeRejected, state.orderAttempts, state.ordersOpened);
   }
   Print("==== End FX diagnostics ====");
}

//+------------------------------------------------------------------+
//| Expert lifecycle                                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpTradeTimeframe != PERIOD_M1 && InpTradeTimeframe != PERIOD_M5)
      Print("Warning: this FX scalper was designed for M1/M5 testing. Backtest carefully after changing timeframe.");

   string symbolList = InpSymbols;
   if(InpUseChartSymbolOnlyInTester && (bool)MQLInfoInteger(MQL_TESTER))
   {
      PrintFormat("FX tester mode detected. MT5 chart/tester symbol=%s, configured symbols=%s", _Symbol, InpSymbols);
      if(InpStrictTesterSymbolList && !TesterChartSymbolAllowed(_Symbol, InpSymbols))
      {
         PrintFormat("FX tester symbol guard stopped the EA: chart/tester symbol '%s' is not listed in InpSymbols '%s'.",
                     _Symbol, InpSymbols);
         return INIT_PARAMETERS_INCORRECT;
      }
      symbolList = _Symbol;
   }

   string parts[];
   const int count = StringSplit(symbolList, ',', parts);
   if(count <= 0)
   {
      Print("No FX symbols configured.");
      return INIT_PARAMETERS_INCORRECT;
   }

   ArrayResize(g_states, count);
   int active = 0;

   for(int i = 0; i < count; i++)
   {
      const string requested = Trim(parts[i]);
      if(requested == "")
         continue;

      FxSymbolState state;
      state.requested = requested;
      state.symbol = ResolveSymbolName(requested);
      state.magic = InpMagicBase + i;
      state.fastEmaHandle = INVALID_HANDLE;
      state.slowEmaHandle = INVALID_HANDLE;
      state.trendEmaHandle = INVALID_HANDLE;
      state.rsiHandle = INVALID_HANDLE;
      state.atrHandle = INVALID_HANDLE;
      state.lastBarTime = 0;
      state.dayStart = 0;
      state.lastTradeTime = 0;
      state.tradesToday = 0;
      state.initialized = false;
      state.barsProcessed = 0;
      state.atrRejected = 0;
      state.spreadRejected = 0;
      state.sessionRejected = 0;
      state.trendRejectedLong = 0;
      state.trendRejectedShort = 0;
      state.pullbackRejectedLong = 0;
      state.pullbackRejectedShort = 0;
      state.cooldownRejected = 0;
      state.sizeRejected = 0;
      state.orderAttempts = 0;
      state.ordersOpened = 0;

      if(!SymbolSelect(state.symbol, true))
      {
         PrintFormat("Unable to select FX symbol '%s' resolved from '%s'", state.symbol, requested);
         g_states[i] = state;
         continue;
      }

      state.fastEmaHandle = iMA(state.symbol, InpTradeTimeframe, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      state.slowEmaHandle = iMA(state.symbol, InpTradeTimeframe, InpSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      state.trendEmaHandle = iMA(state.symbol, InpTrendTimeframe, InpTrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      state.rsiHandle = iRSI(state.symbol, InpTradeTimeframe, InpRsiPeriod, PRICE_CLOSE);
      state.atrHandle = iATR(state.symbol, InpTradeTimeframe, InpAtrPeriod);

      if(state.fastEmaHandle == INVALID_HANDLE ||
         state.slowEmaHandle == INVALID_HANDLE ||
         state.trendEmaHandle == INVALID_HANDLE ||
         state.rsiHandle == INVALID_HANDLE ||
         state.atrHandle == INVALID_HANDLE)
      {
         PrintFormat("FX indicator initialization failed for %s. error=%d", state.symbol, GetLastError());
         g_states[i] = state;
         continue;
      }

      ResetStateDay(state, TimeCurrent());
      state.initialized = true;
      g_states[i] = state;
      active++;
      PrintFormat("Initialized FX scalper on %s (requested %s), magic=%d", state.symbol, state.requested, state.magic);
   }

   if(active <= 0)
   {
      Print("No active FX symbols initialized.");
      return INIT_FAILED;
   }

   UpdateDailyRiskAnchor();
   EventSetTimer(MaxInt(1, InpTimerSeconds));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintDiagnostics();
   EventKillTimer();

   for(int i = 0; i < ArraySize(g_states); i++)
   {
      if(g_states[i].fastEmaHandle != INVALID_HANDLE)
         IndicatorRelease(g_states[i].fastEmaHandle);
      if(g_states[i].slowEmaHandle != INVALID_HANDLE)
         IndicatorRelease(g_states[i].slowEmaHandle);
      if(g_states[i].trendEmaHandle != INVALID_HANDLE)
         IndicatorRelease(g_states[i].trendEmaHandle);
      if(g_states[i].rsiHandle != INVALID_HANDLE)
         IndicatorRelease(g_states[i].rsiHandle);
      if(g_states[i].atrHandle != INVALID_HANDLE)
         IndicatorRelease(g_states[i].atrHandle);
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
