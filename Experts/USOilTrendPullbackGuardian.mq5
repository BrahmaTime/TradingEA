//+------------------------------------------------------------------+
//|                                      USOilTrendPullbackGuardian.mq5 |
//| Conservative M5 trend-pullback EA for USOIL CFDs                  |
//+------------------------------------------------------------------+
#property copyright "Generated for TradingEA"
#property version   "1.00"
#property strict
#property description "Single-symbol USOIL M5 trend-pullback EA with ATR stops and account-currency risk sizing."

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
input string          InpSymbol                      = "USOIL";     // Tickmill symbol; suffixes are auto-detected when possible
input bool            InpAutoResolveSymbol           = true;
input bool            InpUseChartSymbolOnlyInTester  = true;        // Safer single-symbol Strategy Tester runs
input bool            InpStrictTesterSymbolGuard     = true;        // Abort tester if chart symbol is not USOIL-like
input ENUM_TIMEFRAMES InpTradeTimeframe              = PERIOD_M5;   // Strategy timeframe

input group "Session - broker/server time"
input int             InpSessionStartHour            = 15;          // Tune to Tickmill server time for the liquid US oil session
input int             InpSessionStartMinute          = 0;
input int             InpSessionCloseHour            = 22;
input int             InpSessionCloseMinute          = 45;
input bool            InpCloseAtSessionEnd           = true;
input int             InpForcedCloseBufferMin        = 10;

input group "News guard"
input bool            InpUseWeeklyOilNewsGuard       = true;        // Default targets Wednesday EIA Petroleum Status Report window
input int             InpOilNewsDayOfWeek            = 3;           // 0=Sunday, 3=Wednesday
input int             InpOilNewsHour                 = 17;
input int             InpOilNewsMinute               = 30;
input int             InpOilNewsMinutesBefore        = 30;
input int             InpOilNewsMinutesAfter         = 45;
input bool            InpCloseBeforeOilNews          = true;

input group "Trend and pullback filters"
input int             InpFastEmaPeriod               = 20;
input int             InpSlowEmaPeriod               = 50;
input ENUM_TIMEFRAMES InpTrendTimeframe              = PERIOD_M15;
input int             InpTrendEmaPeriod              = 200;
input int             InpAtrPeriod                   = 14;
input int             InpAdxPeriod                   = 14;
input double          InpMinAdx                      = 22.0;
input double          InpPullbackTouchAtr            = 0.25;        // Prior candle must trade this close to EMA20
input double          InpMaxPullbackBeyondSlowAtr    = 0.45;        // Reject pullbacks that pierce too far beyond EMA50
input double          InpConfirmBufferAtr            = 0.04;        // Confirmation close beyond pullback high/low
input double          InpMinConfirmBodyAtr           = 0.08;
input int             InpMinBarsBetweenTrades        = 6;
input ENUM_TRADE_DIRECTION InpTradeDirection         = TRADE_BOTH;

input group "Cost and volatility filters"
input int             InpMaxSpreadPoints             = 0;           // 0 disables fixed points spread check
input double          InpMaxSpreadAtrPercent         = 7.0;
input double          InpMinAtrPrice                 = 0.05;        // Skip dead conditions; price units, not points
input double          InpMaxAtrPrice                 = 1.20;        // Skip abnormal volatility spikes

input group "Risk and orders"
input bool            InpTradingEnabled              = true;
input ENUM_RISK_BASIS InpRiskBasis                   = RISK_BASIS_EQUITY;
input double          InpRiskPercentPerTrade         = 0.35;        // MT5 calculates risk in deposit currency, e.g. ZAR
input double          InpMaxDailyLossPercent         = 1.20;
input bool            InpCloseOnDailyLossLimit       = false;
input bool            InpOneTradePerDay              = true;
input int             InpMaxTradesPerDay             = 2;
input double          InpStopAtrMultiplier           = 1.25;
input double          InpStructureBufferAtr          = 0.10;
input double          InpMaxStopAtr                  = 2.75;
input double          InpRewardRisk                  = 1.75;
input bool            InpAllowMinLotIfRiskTooLow     = true;
input double          InpMaxMinLotRiskPercent        = 0.75;
input int             InpSlippagePoints              = 30;
input int             InpMagicNumber                 = 604024;
input int             InpTimerSeconds                = 2;

input group "Trade management"
input double          InpBreakevenAtR                = 1.00;
input double          InpBreakevenBufferAtr          = 0.05;
input double          InpTrailStartR                 = 1.35;
input double          InpTrailAtrMultiplier          = 1.20;

input group "Diagnostics"
input bool            InpPrintDiagnostics            = true;

CTrade   g_trade;
string   g_symbol = "";
int      g_fastEmaHandle = INVALID_HANDLE;
int      g_slowEmaHandle = INVALID_HANDLE;
int      g_trendEmaHandle = INVALID_HANDLE;
int      g_atrHandle = INVALID_HANDLE;
int      g_adxHandle = INVALID_HANDLE;
datetime g_lastBarTime = 0;
datetime g_riskDayStart = 0;
double   g_dayStartEquity = 0.0;
int      g_tradesToday = 0;
datetime g_lastTradeBarTime = 0;

long     g_barsProcessed = 0;
long     g_newsRejected = 0;
long     g_spreadRejected = 0;
long     g_volatilityRejected = 0;
long     g_trendRejectedLong = 0;
long     g_trendRejectedShort = 0;
long     g_pullbackRejectedLong = 0;
long     g_pullbackRejectedShort = 0;
long     g_signalLong = 0;
long     g_signalShort = 0;
long     g_sizeRejected = 0;
long     g_orderAttempts = 0;
long     g_ordersOpened = 0;

//+------------------------------------------------------------------+
//| Utility functions                                                |
//+------------------------------------------------------------------+
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

double NormalizePrice(const string symbol, const double price)
{
   const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

int MaxInt(const int left, const int right)
{
   return left > right ? left : right;
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

bool SymbolNameMatchesRequest(const string symbolName, const string requested)
{
   if(symbolName == requested)
      return true;

   const int requestedLength = StringLen(requested);
   if(requestedLength <= 0 || StringLen(symbolName) < requestedLength)
      return false;

   string upperSymbol = symbolName;
   string upperRequest = requested;
   StringToUpper(upperSymbol);
   StringToUpper(upperRequest);

   if(upperSymbol == upperRequest)
      return true;

   return StringFind(upperSymbol, upperRequest) >= 0;
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
   double data[];
   ArraySetAsSeries(data, true);
   if(CopyBuffer(handle, buffer, shift, 1, data) != 1)
      return false;

   value = data[0];
   return value != EMPTY_VALUE;
}

bool GetBufferValues(const int handle, const int buffer, const int shift, const int count, double &values[])
{
   ArrayResize(values, count);
   ArraySetAsSeries(values, true);
   const int copied = CopyBuffer(handle, buffer, shift, count, values);
   return copied == count;
}

bool GetLatestClosedBars(MqlRates &rates[], const int count)
{
   ArrayResize(rates, count);
   ArraySetAsSeries(rates, true);
   const int copied = CopyRates(g_symbol, InpTradeTimeframe, 0, count, rates);
   return copied == count;
}

double RiskCapital()
{
   if(InpRiskBasis == RISK_BASIS_BALANCE)
      return AccountInfoDouble(ACCOUNT_BALANCE);
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

void UpdateDailyRiskAnchor()
{
   const datetime today = DayStart(TimeCurrent());
   if(g_riskDayStart != today)
   {
      g_riskDayStart = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_tradesToday = 0;
   }
}

bool DailyLossLimitReached()
{
   if(InpMaxDailyLossPercent <= 0.0 || g_dayStartEquity <= 0.0)
      return false;

   const double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double lossPercent = (g_dayStartEquity - currentEquity) / g_dayStartEquity * 100.0;
   return lossPercent >= InpMaxDailyLossPercent;
}

bool DirectionAllowed(const bool isLong)
{
   if(InpTradeDirection == TRADE_BOTH)
      return true;
   if(InpTradeDirection == TRADE_LONG_ONLY)
      return isLong;
   if(InpTradeDirection == TRADE_SHORT_ONLY)
      return !isLong;
   return true;
}

bool IsWithinSession(const datetime now)
{
   const datetime sessionStart = BuildTimeForDay(now, InpSessionStartHour, InpSessionStartMinute);
   const datetime sessionClose = BuildTimeForDay(now, InpSessionCloseHour, InpSessionCloseMinute);
   return now >= sessionStart && now <= sessionClose;
}

bool IsOilNewsWindow(const datetime now)
{
   if(!InpUseWeeklyOilNewsGuard)
      return false;

   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(dt.day_of_week != InpOilNewsDayOfWeek)
      return false;

   const datetime newsTime = BuildTimeForDay(now, InpOilNewsHour, InpOilNewsMinute);
   return now >= newsTime - InpOilNewsMinutesBefore * 60 &&
          now <= newsTime + InpOilNewsMinutesAfter * 60;
}

bool SpreadPassesFilter(const double atr)
{
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return false;

   const double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   const double spread = tick.ask - tick.bid;
   if(point <= 0.0 || spread <= 0.0)
      return false;

   if(InpMaxSpreadPoints > 0 && spread / point > InpMaxSpreadPoints)
   {
      g_spreadRejected++;
      return false;
   }

   if(atr > 0.0 && InpMaxSpreadAtrPercent > 0.0)
   {
      const double spreadPercent = spread / atr * 100.0;
      if(spreadPercent > InpMaxSpreadAtrPercent)
      {
         g_spreadRejected++;
         return false;
      }
   }

   return true;
}

bool HasManagedPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == g_symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return true;
   }
   return false;
}

bool StopsMeetBrokerMinimums(const bool isLong, const double sl, const double tp)
{
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return false;

   const double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   const int stopsLevel = (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double minDistance = stopsLevel * point;

   if(minDistance <= 0.0)
      return true;

   if(isLong)
      return (tick.bid - sl) >= minDistance && (tp - tick.bid) >= minDistance;
   return (sl - tick.ask) >= minDistance && (tick.ask - tp) >= minDistance;
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
   if(!OrderCalcProfit(orderType, g_symbol, 1.0, entry, stopLoss, oneLotProfit))
   {
      PrintFormat("%s cannot calculate risk: OrderCalcProfit failed, error=%d", g_symbol, GetLastError());
      return false;
   }

   const double oneLotLoss = MathAbs(oneLotProfit);
   if(oneLotLoss <= 0.0)
      return false;

   const double rawVolume = riskMoney / oneLotLoss;
   const double minVol = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);

   if(rawVolume < minVol && !InpAllowMinLotIfRiskTooLow)
   {
      PrintFormat("%s skipped: calculated volume %.4f below min %.4f", g_symbol, rawVolume, minVol);
      return false;
   }

   if(rawVolume < minVol && InpAllowMinLotIfRiskTooLow)
   {
      const double maxMinLotRiskMoney = RiskCapital() * InpMaxMinLotRiskPercent / 100.0;
      const double minLotRiskMoney = oneLotLoss * minVol;
      if(maxMinLotRiskMoney <= 0.0 || minLotRiskMoney > maxMinLotRiskMoney)
      {
         PrintFormat("%s skipped: min lot risk %.2f exceeds cap %.2f (%.2f%%)",
                     g_symbol, minLotRiskMoney, maxMinLotRiskMoney, InpMaxMinLotRiskPercent);
         return false;
      }

      PrintFormat("%s using minimum lot %.4f: target risk %.2f, estimated risk %.2f",
                  g_symbol, minVol, riskMoney, minLotRiskMoney);
   }

   volume = NormalizeVolume(g_symbol, rawVolume);
   if(volume <= 0.0)
      return false;

   double margin = 0.0;
   if(OrderCalcMargin(orderType, g_symbol, volume, entry, margin))
   {
      const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin * 0.90)
      {
         PrintFormat("%s skipped: margin %.2f exceeds 90%% of free margin %.2f",
                     g_symbol, margin, freeMargin);
         return false;
      }
   }

   return true;
}

bool TrendPasses(const bool isLong,
                 const MqlRates &confirmBar,
                 const double fastNow,
                 const double fastOlder,
                 const double slowNow,
                 const double trendEma,
                 const double adx,
                 const double plusDi,
                 const double minusDi,
                 const double atr)
{
   if(!DirectionAllowed(isLong))
      return false;

   if(adx < InpMinAdx)
      return false;

   const double slope = fastNow - fastOlder;
   const double minSlope = atr * 0.02;

   if(isLong)
   {
      if(fastNow <= slowNow || confirmBar.close <= trendEma || plusDi <= minusDi || slope < minSlope)
      {
         g_trendRejectedLong++;
         return false;
      }
      return true;
   }

   if(fastNow >= slowNow || confirmBar.close >= trendEma || minusDi <= plusDi || slope > -minSlope)
   {
      g_trendRejectedShort++;
      return false;
   }
   return true;
}

bool PullbackSignalPasses(const bool isLong,
                          const MqlRates &pullbackBar,
                          const MqlRates &confirmBar,
                          const double fastPullback,
                          const double slowPullback,
                          const double atr)
{
   const double touchDistance = atr * InpPullbackTouchAtr;
   const double confirmBuffer = atr * InpConfirmBufferAtr;
   const double minBody = atr * InpMinConfirmBodyAtr;
   const double body = MathAbs(confirmBar.close - confirmBar.open);

   if(body < minBody)
   {
      if(isLong)
         g_pullbackRejectedLong++;
      else
         g_pullbackRejectedShort++;
      return false;
   }

   if(isLong)
   {
      const bool touchedFast = pullbackBar.low <= fastPullback + touchDistance;
      const bool heldSlow = pullbackBar.close >= slowPullback - atr * InpMaxPullbackBeyondSlowAtr;
      const bool confirmed = confirmBar.close > pullbackBar.high + confirmBuffer &&
                             confirmBar.close > confirmBar.open;
      if(touchedFast && heldSlow && confirmed)
         return true;

      g_pullbackRejectedLong++;
      return false;
   }

   const bool touchedFast = pullbackBar.high >= fastPullback - touchDistance;
   const bool heldSlow = pullbackBar.close <= slowPullback + atr * InpMaxPullbackBeyondSlowAtr;
   const bool confirmed = confirmBar.close < pullbackBar.low - confirmBuffer &&
                          confirmBar.close < confirmBar.open;
   if(touchedFast && heldSlow && confirmed)
      return true;

   g_pullbackRejectedShort++;
   return false;
}

bool TradeSpacingAllows(const datetime confirmBarTime)
{
   if(InpOneTradePerDay && g_tradesToday > 0)
      return false;

   if(g_tradesToday >= InpMaxTradesPerDay)
      return false;

   if(g_lastTradeBarTime <= 0 || InpMinBarsBetweenTrades <= 0)
      return true;

   return confirmBarTime - g_lastTradeBarTime >= InpMinBarsBetweenTrades * PeriodSeconds(InpTradeTimeframe);
}

void OpenTrade(const bool isLong, const MqlRates &pullbackBar, const double atr)
{
   if(!InpTradingEnabled || DailyLossLimitReached() || HasManagedPosition())
      return;

   if(!TradeSpacingAllows(pullbackBar.time))
      return;

   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return;

   const double entry = isLong ? tick.ask : tick.bid;
   const double atrStop = atr * InpStopAtrMultiplier;
   const double structureStop = isLong
                                ? pullbackBar.low - atr * InpStructureBufferAtr
                                : pullbackBar.high + atr * InpStructureBufferAtr;
   double stopLoss = isLong ? MathMin(entry - atrStop, structureStop)
                            : MathMax(entry + atrStop, structureStop);

   const double riskDistance = MathAbs(entry - stopLoss);
   if(atr <= 0.0 || riskDistance <= 0.0 || riskDistance > atr * InpMaxStopAtr)
   {
      g_sizeRejected++;
      PrintFormat("%s %s skipped: stop distance %.2f ATR exceeds limits",
                  g_symbol, isLong ? "long" : "short", riskDistance / atr);
      return;
   }

   const double takeProfit = isLong ? entry + riskDistance * InpRewardRisk
                                    : entry - riskDistance * InpRewardRisk;
   stopLoss = NormalizePrice(g_symbol, stopLoss);
   const double normalizedTp = NormalizePrice(g_symbol, takeProfit);

   if(!StopsMeetBrokerMinimums(isLong, stopLoss, normalizedTp))
   {
      g_sizeRejected++;
      PrintFormat("%s %s skipped: SL/TP too close for broker stop level", g_symbol, isLong ? "long" : "short");
      return;
   }

   double volume = 0.0;
   const ENUM_ORDER_TYPE orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!CalculatePositionSize(orderType, entry, stopLoss, volume))
   {
      g_sizeRejected++;
      return;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(g_symbol);

   const string comment = isLong ? "UTPG pullback long" : "UTPG pullback short";
   g_orderAttempts++;
   const bool sent = isLong
                     ? g_trade.Buy(volume, g_symbol, 0.0, stopLoss, normalizedTp, comment)
                     : g_trade.Sell(volume, g_symbol, 0.0, stopLoss, normalizedTp, comment);

   if(sent)
   {
      g_tradesToday++;
      g_lastTradeBarTime = pullbackBar.time;
      g_ordersOpened++;
      PrintFormat("%s %s opened volume=%.4f SL=%s TP=%s risk=%.2f%%",
                  g_symbol, isLong ? "long" : "short", volume,
                  DoubleToString(stopLoss, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
                  DoubleToString(normalizedTp, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
                  InpRiskPercentPerTrade);
   }
   else
   {
      PrintFormat("%s %s order failed. retcode=%d %s",
                  g_symbol, isLong ? "long" : "short",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }
}

void ManageOpenPositions()
{
   const bool dailyLimit = DailyLossLimitReached();
   const datetime now = TimeCurrent();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != g_symbol ||
         PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if(dailyLimit && InpCloseOnDailyLossLimit)
      {
         g_trade.SetExpertMagicNumber(InpMagicNumber);
         g_trade.PositionClose(ticket);
         continue;
      }

      if(InpCloseAtSessionEnd)
      {
         const datetime closeTime = BuildTimeForDay(now, InpSessionCloseHour, InpSessionCloseMinute)
                                    - InpForcedCloseBufferMin * 60;
         if(now >= closeTime)
         {
            g_trade.SetExpertMagicNumber(InpMagicNumber);
            g_trade.PositionClose(ticket);
            continue;
         }
      }

      if(InpCloseBeforeOilNews && IsOilNewsWindow(now))
      {
         g_trade.SetExpertMagicNumber(InpMagicNumber);
         g_trade.PositionClose(ticket);
         continue;
      }

      double atr = 0.0;
      if(!GetBufferValue(g_atrHandle, 0, 1, atr) || atr <= 0.0)
         continue;

      MqlTick tick;
      if(!SymbolInfoTick(g_symbol, tick))
         continue;

      const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const bool isLong = (type == POSITION_TYPE_BUY);
      const double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      const double currentSl = PositionGetDouble(POSITION_SL);
      const double currentTp = PositionGetDouble(POSITION_TP);
      const double mark = isLong ? tick.bid : tick.ask;

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

      if(newSl > 0.0 && MathAbs(newSl - currentSl) > SymbolInfoDouble(g_symbol, SYMBOL_POINT))
      {
         newSl = NormalizePrice(g_symbol, newSl);
         if(StopsMeetBrokerMinimums(isLong, newSl, currentTp))
         {
            g_trade.SetExpertMagicNumber(InpMagicNumber);
            if(!g_trade.PositionModify(ticket, newSl, currentTp))
            {
               PrintFormat("%s failed to modify position %I64u: %d %s",
                           g_symbol, ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
            }
         }
      }
   }
}

void ProcessNewBar()
{
   MqlRates rates[];
   if(!GetLatestClosedBars(rates, 5))
      return;

   const datetime currentBarTime = rates[0].time;
   if(g_lastBarTime == currentBarTime)
      return;
   g_lastBarTime = currentBarTime;
   g_barsProcessed++;

   const MqlRates confirmBar = rates[1];
   const MqlRates pullbackBar = rates[2];

   if(!IsWithinSession(confirmBar.time))
      return;

   if(IsOilNewsWindow(confirmBar.time))
   {
      g_newsRejected++;
      return;
   }

   double atr = 0.0;
   if(!GetBufferValue(g_atrHandle, 0, 1, atr) || atr <= 0.0)
      return;

   if(atr < InpMinAtrPrice || atr > InpMaxAtrPrice)
   {
      g_volatilityRejected++;
      return;
   }

   if(!SpreadPassesFilter(atr))
      return;

   double fastValues[];
   double slowValues[];
   if(!GetBufferValues(g_fastEmaHandle, 0, 1, 4, fastValues) ||
      !GetBufferValues(g_slowEmaHandle, 0, 1, 3, slowValues))
      return;

   double trendEma = 0.0;
   double adx = 0.0;
   double plusDi = 0.0;
   double minusDi = 0.0;
   if(!GetBufferValue(g_trendEmaHandle, 0, 1, trendEma) ||
      !GetBufferValue(g_adxHandle, 0, 1, adx) ||
      !GetBufferValue(g_adxHandle, 1, 1, plusDi) ||
      !GetBufferValue(g_adxHandle, 2, 1, minusDi))
      return;

   const double fastNow = fastValues[0];
   const double fastPullback = fastValues[1];
   const double fastOlder = fastValues[3];
   const double slowNow = slowValues[0];
   const double slowPullback = slowValues[1];

   if(TrendPasses(true, confirmBar, fastNow, fastOlder, slowNow, trendEma, adx, plusDi, minusDi, atr) &&
      PullbackSignalPasses(true, pullbackBar, confirmBar, fastPullback, slowPullback, atr))
   {
      g_signalLong++;
      OpenTrade(true, pullbackBar, atr);
      return;
   }

   if(TrendPasses(false, confirmBar, fastNow, fastOlder, slowNow, trendEma, adx, plusDi, minusDi, atr) &&
      PullbackSignalPasses(false, pullbackBar, confirmBar, fastPullback, slowPullback, atr))
   {
      g_signalShort++;
      OpenTrade(false, pullbackBar, atr);
   }
}

void Process()
{
   UpdateDailyRiskAnchor();
   ManageOpenPositions();

   if(DailyLossLimitReached())
   {
      static datetime lastPrint = 0;
      if(TimeCurrent() - lastPrint > 300)
      {
         PrintFormat("Daily loss limit reached. New USOIL entries paused. Start equity=%.2f current equity=%.2f",
                     g_dayStartEquity, AccountInfoDouble(ACCOUNT_EQUITY));
         lastPrint = TimeCurrent();
      }
      return;
   }

   ProcessNewBar();
}

void PrintDiagnostics()
{
   if(!InpPrintDiagnostics)
      return;

   Print("==== USOilTrendPullbackGuardian diagnostics ====");
   PrintFormat("%s diagnostics: bars=%I64d news_reject=%I64d spread_reject=%I64d volatility_reject=%I64d",
               g_symbol, g_barsProcessed, g_newsRejected, g_spreadRejected, g_volatilityRejected);
   PrintFormat("%s diagnostics: trend_reject_long=%I64d trend_reject_short=%I64d pullback_reject_long=%I64d pullback_reject_short=%I64d",
               g_symbol, g_trendRejectedLong, g_trendRejectedShort,
               g_pullbackRejectedLong, g_pullbackRejectedShort);
   PrintFormat("%s diagnostics: signal_long=%I64d signal_short=%I64d size_reject=%I64d order_attempts=%I64d orders_opened=%I64d",
               g_symbol, g_signalLong, g_signalShort, g_sizeRejected, g_orderAttempts, g_ordersOpened);
   Print("==== End diagnostics ====");
}

//+------------------------------------------------------------------+
//| Expert lifecycle                                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpTradeTimeframe != PERIOD_M5)
      Print("Warning: this EA was designed for PERIOD_M5. Backtest carefully after changing timeframe.");

   if(InpRiskPercentPerTrade <= 0.0 || InpRewardRisk <= 0.0 || InpStopAtrMultiplier <= 0.0)
   {
      Print("Invalid risk inputs: risk percent, reward-risk and stop ATR multiplier must be positive.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpSessionStartHour < 0 || InpSessionStartHour > 23 || InpSessionCloseHour < 0 || InpSessionCloseHour > 23)
   {
      Print("Invalid session inputs: hours must be between 0 and 23.");
      return INIT_PARAMETERS_INCORRECT;
   }

   string requestedSymbol = InpSymbol;
   if(InpUseChartSymbolOnlyInTester && (bool)MQLInfoInteger(MQL_TESTER))
   {
      if(InpStrictTesterSymbolGuard && !SymbolNameMatchesRequest(_Symbol, InpSymbol))
      {
         PrintFormat("Tester symbol guard stopped the EA: chart/tester symbol '%s' does not match configured USOIL symbol '%s'.",
                     _Symbol, InpSymbol);
         return INIT_PARAMETERS_INCORRECT;
      }

      requestedSymbol = _Symbol;
      PrintFormat("Tester mode detected. Using chart symbol only: %s", requestedSymbol);
   }

   g_symbol = ResolveSymbolName(requestedSymbol);
   if(!SymbolSelect(g_symbol, true))
   {
      PrintFormat("Unable to select USOIL symbol '%s' resolved from '%s'", g_symbol, requestedSymbol);
      return INIT_FAILED;
   }

   g_fastEmaHandle = iMA(g_symbol, InpTradeTimeframe, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_slowEmaHandle = iMA(g_symbol, InpTradeTimeframe, InpSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_trendEmaHandle = iMA(g_symbol, InpTrendTimeframe, InpTrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_atrHandle = iATR(g_symbol, InpTradeTimeframe, InpAtrPeriod);
   g_adxHandle = iADX(g_symbol, InpTradeTimeframe, InpAdxPeriod);

   if(g_fastEmaHandle == INVALID_HANDLE ||
      g_slowEmaHandle == INVALID_HANDLE ||
      g_trendEmaHandle == INVALID_HANDLE ||
      g_atrHandle == INVALID_HANDLE ||
      g_adxHandle == INVALID_HANDLE)
   {
      PrintFormat("Indicator initialization failed for %s. error=%d", g_symbol, GetLastError());
      return INIT_FAILED;
   }

   UpdateDailyRiskAnchor();
   EventSetTimer(MaxInt(1, InpTimerSeconds));

   PrintFormat("Initialized USOilTrendPullbackGuardian on %s, magic=%d, account currency=%s",
               g_symbol, InpMagicNumber, AccountInfoString(ACCOUNT_CURRENCY));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintDiagnostics();
   EventKillTimer();

   if(g_fastEmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_fastEmaHandle);
   if(g_slowEmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_slowEmaHandle);
   if(g_trendEmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_trendEmaHandle);
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   if(g_adxHandle != INVALID_HANDLE)
      IndicatorRelease(g_adxHandle);
}

void OnTick()
{
   Process();
}

void OnTimer()
{
   Process();
}
//+------------------------------------------------------------------+
