//+------------------------------------------------------------------+
//|                                       CrudeOilPullbackTrader.mq5  |
//|  Trend-pullback continuation EA for WTI crude oil (USOIL/XTIUSD)  |
//|  M5 entries, H1 trend bias, ATR risk, account-currency sizing.    |
//+------------------------------------------------------------------+
#property copyright "Generated for TradingEA"
#property version   "1.00"
#property strict
#property description "USOIL/XTIUSD M5 trend-pullback EA. H1 EMA bias, ATR risk, ZAR/account-currency sizing, EIA news blackout."

#include <Trade/Trade.mqh>

//--- Risk basis: size off live equity or static balance
enum ENUM_RISK_BASIS
{
   RISK_BASIS_EQUITY  = 0, // Risk percent of current equity
   RISK_BASIS_BALANCE = 1  // Risk percent of current balance
};

//--- Allowed trade directions
enum ENUM_TRADE_DIRECTION
{
   TRADE_BOTH       = 0, // Long and short
   TRADE_LONG_ONLY  = 1, // Long only
   TRADE_SHORT_ONLY = 2  // Short only
};

input group "Symbol"
input string               InpSymbol               = "";          // Leave empty to use the chart symbol (recommended)
input bool                 InpAutoResolveSymbol    = true;         // Try common WTI aliases (XTIUSD, USOIL, WTI...) if needed
input ENUM_TIMEFRAMES      InpEntryTimeframe       = PERIOD_M5;    // Entry/signal timeframe

input group "Trend bias (higher timeframe)"
input ENUM_TIMEFRAMES      InpBiasTimeframe        = PERIOD_H1;    // Higher timeframe used for directional bias
input int                  InpBiasFastEma          = 50;           // Fast EMA on bias timeframe
input int                  InpBiasSlowEma          = 200;          // Slow EMA on bias timeframe
input ENUM_TRADE_DIRECTION InpTradeDirection       = TRADE_BOTH;   // Restrict trade direction

input group "Entry signal (M5)"
input int                  InpPullbackEma          = 20;           // Dynamic pullback EMA on entry timeframe
input int                  InpPullbackLookback     = 6;            // Bars allowed between pullback touch and trigger
input int                  InpAtrPeriod            = 14;           // ATR period (entry timeframe)
input int                  InpRsiPeriod            = 14;           // RSI period (entry timeframe)
input double               InpRsiLongMin           = 50.0;         // Long trigger requires RSI above this
input double               InpRsiShortMax          = 50.0;         // Short trigger requires RSI below this
input int                  InpAdxPeriod            = 14;           // ADX period (entry timeframe)
input bool                 InpUseAdxFilter         = true;         // Require trending conditions
input double               InpMinAdx               = 20.0;         // Minimum ADX to allow entries
input double               InpMinTriggerBodyAtr    = 0.15;         // Trigger candle body must be >= this * ATR
input double               InpPullbackTouchAtr     = 0.10;         // Touch tolerance around pullback EMA (* ATR)

input group "Stops, targets and management"
input int                  InpSwingLookback        = 8;            // Bars used to find swing low/high for the stop
input double               InpStopBufferAtr        = 0.25;         // Extra distance beyond swing for the stop (* ATR)
input double               InpMinStopAtr           = 0.80;         // Stop is at least this distance (* ATR)
input double               InpMaxStopAtr           = 3.50;         // Skip trade if required stop exceeds this (* ATR)
input double               InpRewardRisk           = 1.60;         // Take-profit reward:risk multiple
input double               InpBreakevenR           = 1.00;         // Move stop to breakeven at this R multiple
input double               InpBreakevenBufferAtr   = 0.05;         // Breakeven offset beyond entry (* ATR)
input double               InpTrailStartR          = 1.30;         // Begin ATR trailing at this R multiple
input double               InpTrailAtrMultiplier   = 1.40;         // ATR trailing distance multiple

input group "Risk and money management"
input bool                 InpTradingEnabled       = true;         // Master switch for opening new trades
input ENUM_RISK_BASIS      InpRiskBasis            = RISK_BASIS_EQUITY;
input double               InpRiskPercentPerTrade  = 0.50;         // Risk per trade in account currency (e.g. ZAR)
input double               InpMaxDailyLossPercent  = 2.00;         // Pause new entries after this daily equity drawdown
input bool                 InpCloseOnDailyLoss     = false;        // Also flatten open trades when the daily limit is hit
input int                  InpMaxOpenPositions     = 1;            // Max concurrent EA positions on this symbol
input int                  InpMaxTradesPerDay      = 4;            // Max new entries per server day (0 = unlimited)
input bool                 InpAllowMinLotIfTooLow  = true;         // Use broker min lot when target risk is below it
input double               InpMaxMinLotRiskPercent = 1.00;         // ... only if min-lot risk stays under this percent

input group "Session and cost filters (server time)"
input bool                 InpUseSessionFilter     = true;         // Only enter within the trade window below
input int                  InpTradeStartHour       = 10;           // Window start hour (server time)
input int                  InpTradeStartMinute     = 0;
input int                  InpTradeEndHour         = 22;           // Window end hour (server time)
input int                  InpTradeEndMinute       = 30;
input bool                 InpCloseAtWindowEnd     = false;        // Flatten EA trades once the window closes
input int                  InpMaxSpreadPoints      = 0;            // Hard spread cap in points (0 disables)
input double               InpMaxSpreadAtrPercent  = 10.0;         // Spread must be <= this percent of ATR (0 disables)

input group "EIA / news blackout (server time)"
input bool                 InpUseNewsBlackout      = true;         // Block entries around the weekly EIA release
input int                  InpNewsDayOfWeek        = 3;            // 0=Sun ... 3=Wed (EIA day)
input int                  InpNewsHour             = 16;           // EIA 14:30 UTC -> set to broker/server hour
input int                  InpNewsMinute           = 30;
input int                  InpNewsBlackoutBeforeMin= 15;           // Block entries this many minutes before
input int                  InpNewsBlackoutAfterMin = 30;           // ... and this many minutes after

input group "Execution and diagnostics"
input int                  InpSlippagePoints       = 30;
input int                  InpMagicNumber          = 770524;
input int                  InpTimerSeconds         = 2;
input bool                 InpPrintDiagnostics     = true;         // Print gate counters on deinit

//+------------------------------------------------------------------+
//| Global state                                                     |
//+------------------------------------------------------------------+
CTrade   g_trade;
string   g_symbol           = "";
int      g_biasFastHandle   = INVALID_HANDLE;
int      g_biasSlowHandle   = INVALID_HANDLE;
int      g_pullbackEmaHandle= INVALID_HANDLE;
int      g_atrHandle        = INVALID_HANDLE;
int      g_rsiHandle        = INVALID_HANDLE;
int      g_adxHandle        = INVALID_HANDLE;
datetime g_lastBarTime      = 0;

// Pullback state machine (per direction)
bool     g_longArmed        = false;
int      g_longArmedBars    = 0;
bool     g_shortArmed       = false;
int      g_shortArmedBars   = 0;

// Daily risk / counters
datetime g_riskDayStart     = 0;
double   g_dayStartEquity   = 0.0;
int      g_tradesToday      = 0;

// Diagnostics
long     g_diagBars         = 0;
long     g_diagNoBias       = 0;
long     g_diagSession      = 0;
long     g_diagNews         = 0;
long     g_diagSpread       = 0;
long     g_diagAdx          = 0;
long     g_diagArmedLong    = 0;
long     g_diagArmedShort   = 0;
long     g_diagTrigLong     = 0;
long     g_diagTrigShort    = 0;
long     g_diagSizeReject   = 0;
long     g_diagOrders       = 0;

//+------------------------------------------------------------------+
//| Small helpers                                                    |
//+------------------------------------------------------------------+
int MaxInt(const int a, const int b) { return a > b ? a : b; }

double NormalizePrice(const double price)
{
   const int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
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

double NormalizeVolume(const double requested)
{
   const double minVol = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   const double maxVol = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   const double step   = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

   if(minVol <= 0.0 || maxVol <= 0.0 || step <= 0.0)
      return 0.0;

   double volume = MathMax(minVol, MathMin(maxVol, requested));
   volume = MathFloor(volume / step) * step;
   volume = NormalizeDouble(volume, VolumeDigits(step));

   if(volume < minVol)
      return 0.0;
   return volume;
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

//+------------------------------------------------------------------+
//| Symbol resolution (handles broker suffixes / WTI aliases)        |
//+------------------------------------------------------------------+
bool NameLooksLikeRequest(const string name, const string request)
{
   if(name == request)
      return true;
   const int reqLen = StringLen(request);
   const int nameLen = StringLen(name);
   if(reqLen <= 0 || nameLen < reqLen)
      return false;
   if(StringFind(name, request) == 0)        // prefix match (e.g. USOIL.cash)
      return true;
   const int suffixPos = nameLen - reqLen;
   return StringFind(name, request, suffixPos) == suffixPos; // suffix match (e.g. m.XTIUSD)
}

string ResolveSymbol(const string request)
{
   if(SymbolSelect(request, true))
      return request;

   if(!InpAutoResolveSymbol)
      return request;

   // Candidate WTI aliases used across brokers.
   string aliases[];
   ArrayResize(aliases, 7);
   aliases[0] = request;
   aliases[1] = "XTIUSD";
   aliases[2] = "USOIL";
   aliases[3] = "WTI";
   aliases[4] = "CL";
   aliases[5] = "OILUSD";
   aliases[6] = "CRUDOIL";

   const int total = SymbolsTotal(false);
   for(int a = 0; a < ArraySize(aliases); a++)
   {
      const string alias = aliases[a];
      if(StringLen(alias) <= 0)
         continue;
      for(int i = 0; i < total; i++)
      {
         const string name = SymbolName(i, false);
         if(NameLooksLikeRequest(name, alias) && SymbolSelect(name, true))
            return name;
      }
   }
   return request;
}

//+------------------------------------------------------------------+
//| Indicator buffer access                                          |
//+------------------------------------------------------------------+
bool GetBuffer(const int handle, const int buffer, const int shift, double &value)
{
   double values[];
   ArraySetAsSeries(values, true);
   if(CopyBuffer(handle, buffer, shift, 1, values) != 1)
      return false;
   value = values[0];
   return value != EMPTY_VALUE;
}

bool GetClosedBars(MqlRates &rates[], const int count)
{
   ArraySetAsSeries(rates, true);
   const int copied = CopyRates(g_symbol, InpEntryTimeframe, 0, count, rates);
   return copied >= count;
}

//+------------------------------------------------------------------+
//| Daily risk anchor                                                |
//+------------------------------------------------------------------+
void UpdateDailyAnchor()
{
   const datetime today = DayStart(TimeCurrent());
   if(g_riskDayStart != today || g_dayStartEquity <= 0.0)
   {
      g_riskDayStart   = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_tradesToday    = 0;
      PrintFormat("New trading day. Account currency=%s, start equity=%.2f",
                  AccountInfoString(ACCOUNT_CURRENCY), g_dayStartEquity);
   }
}

double RiskCapital()
{
   if(InpRiskBasis == RISK_BASIS_BALANCE)
      return AccountInfoDouble(ACCOUNT_BALANCE);
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

bool DailyLossReached()
{
   if(InpMaxDailyLossPercent <= 0.0 || g_dayStartEquity <= 0.0)
      return false;
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double maxLoss = g_dayStartEquity * InpMaxDailyLossPercent / 100.0;
   return (g_dayStartEquity - equity) >= maxLoss;
}

//+------------------------------------------------------------------+
//| Position bookkeeping                                             |
//+------------------------------------------------------------------+
int CountManagedPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Time-based filters                                               |
//+------------------------------------------------------------------+
int MinutesOfDay(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour * 60 + dt.min;
}

bool InSessionWindow(const datetime now)
{
   if(!InpUseSessionFilter)
      return true;

   const int cur   = MinutesOfDay(now);
   const int start = InpTradeStartHour * 60 + InpTradeStartMinute;
   const int end   = InpTradeEndHour   * 60 + InpTradeEndMinute;

   if(start == end)
      return true;                       // 24h window
   if(start < end)
      return cur >= start && cur < end;  // intraday window
   return cur >= start || cur < end;     // overnight window
}

bool InNewsBlackout(const datetime now)
{
   if(!InpUseNewsBlackout)
      return false;

   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(dt.day_of_week != InpNewsDayOfWeek)
      return false;

   const int cur    = dt.hour * 60 + dt.min;
   const int center = InpNewsHour * 60 + InpNewsMinute;
   const int from   = center - InpNewsBlackoutBeforeMin;
   const int to     = center + InpNewsBlackoutAfterMin;
   return cur >= from && cur <= to;
}

//+------------------------------------------------------------------+
//| Filters: spread                                                  |
//+------------------------------------------------------------------+
bool SpreadOk(const double atr)
{
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return false;

   const double point  = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   const double spread = MathMax(0.0, tick.ask - tick.bid);
   const int spreadPts = point > 0.0 ? (int)MathRound(spread / point) : 0;

   if(InpMaxSpreadPoints > 0 && spreadPts > InpMaxSpreadPoints)
   {
      PrintFormat("%s skip: spread %d pts > %d", g_symbol, spreadPts, InpMaxSpreadPoints);
      return false;
   }
   if(InpMaxSpreadAtrPercent > 0.0 && atr > 0.0 &&
      (spread / atr) * 100.0 > InpMaxSpreadAtrPercent)
   {
      PrintFormat("%s skip: spread %.2f%% of ATR > %.2f%%",
                  g_symbol, (spread / atr) * 100.0, InpMaxSpreadAtrPercent);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Trend bias from the higher timeframe                             |
//| returns +1 bullish, -1 bearish, 0 none                           |
//+------------------------------------------------------------------+
int TrendBias()
{
   double fast = 0.0, slow = 0.0;
   if(!GetBuffer(g_biasFastHandle, 0, 1, fast) ||
      !GetBuffer(g_biasSlowHandle, 0, 1, slow))
      return 0;

   double biasClose[];
   ArraySetAsSeries(biasClose, true);
   if(CopyClose(g_symbol, InpBiasTimeframe, 1, 1, biasClose) != 1)
      return 0;
   const double close = biasClose[0];

   if(fast > slow && close > slow)
      return 1;
   if(fast < slow && close < slow)
      return -1;
   return 0;
}

bool DirectionAllowed(const bool isLong)
{
   if(InpTradeDirection == TRADE_BOTH)
      return true;
   return isLong ? (InpTradeDirection == TRADE_LONG_ONLY)
                 : (InpTradeDirection == TRADE_SHORT_ONLY);
}

//+------------------------------------------------------------------+
//| Stop/target sizing helpers                                       |
//+------------------------------------------------------------------+
double SwingLow(const MqlRates &rates[])
{
   double low = rates[1].low;
   const int bars = MathMin(ArraySize(rates) - 1, MaxInt(1, InpSwingLookback));
   for(int i = 1; i <= bars; i++)
      low = MathMin(low, rates[i].low);
   return low;
}

double SwingHigh(const MqlRates &rates[])
{
   double high = rates[1].high;
   const int bars = MathMin(ArraySize(rates) - 1, MaxInt(1, InpSwingLookback));
   for(int i = 1; i <= bars; i++)
      high = MathMax(high, rates[i].high);
   return high;
}

bool StopsMeetBrokerMinimum(const bool isLong, const double sl, const double tp)
{
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return false;
   const double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   const int stopsLevel = (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double minDist = stopsLevel * point;
   if(minDist <= 0.0)
      return true;
   if(isLong)
      return (tick.bid - sl) >= minDist && (tp - tick.bid) >= minDist;
   return (sl - tick.ask) >= minDist && (tick.ask - tp) >= minDist;
}

//+------------------------------------------------------------------+
//| Position size from account-currency risk (ZAR-aware)             |
//+------------------------------------------------------------------+
bool CalculateVolume(const ENUM_ORDER_TYPE orderType,
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
      PrintFormat("%s OrderCalcProfit failed, error=%d", g_symbol, GetLastError());
      return false;
   }
   const double oneLotLoss = MathAbs(oneLotProfit);
   if(oneLotLoss <= 0.0)
      return false;

   const double rawVolume = riskMoney / oneLotLoss;
   const double minVol = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);

   if(rawVolume < minVol)
   {
      if(!InpAllowMinLotIfTooLow)
      {
         PrintFormat("%s skip: target volume %.4f < min %.4f", g_symbol, rawVolume, minVol);
         return false;
      }
      const double maxMinLotRisk = RiskCapital() * InpMaxMinLotRiskPercent / 100.0;
      const double minLotRisk    = oneLotLoss * minVol;
      if(maxMinLotRisk <= 0.0 || minLotRisk > maxMinLotRisk)
      {
         PrintFormat("%s skip: min-lot risk %.2f > cap %.2f (%.2f%%)",
                     g_symbol, minLotRisk, maxMinLotRisk, InpMaxMinLotRiskPercent);
         return false;
      }
      PrintFormat("%s using min lot %.4f: target risk %.2f, min-lot risk %.2f",
                  g_symbol, minVol, riskMoney, minLotRisk);
   }

   volume = NormalizeVolume(rawVolume);
   if(volume <= 0.0)
      return false;

   double margin = 0.0;
   if(OrderCalcMargin(orderType, g_symbol, volume, entry, margin))
   {
      const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin * 0.90)
      {
         PrintFormat("%s skip: margin %.2f > 90%% free margin %.2f", g_symbol, margin, freeMargin);
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Open a trade in the given direction                              |
//+------------------------------------------------------------------+
void OpenTrade(const bool isLong, const double atr, const MqlRates &rates[])
{
   if(!InpTradingEnabled)
      return;
   if(CountManagedPositions() >= InpMaxOpenPositions)
      return;
   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return;

   const double entry = isLong ? tick.ask : tick.bid;

   double stopLoss = isLong ? SwingLow(rates)  - atr * InpStopBufferAtr
                            : SwingHigh(rates) + atr * InpStopBufferAtr;

   const double minStopDist = atr * InpMinStopAtr;
   if(isLong && (entry - stopLoss) < minStopDist)
      stopLoss = entry - minStopDist;
   if(!isLong && (stopLoss - entry) < minStopDist)
      stopLoss = entry + minStopDist;

   const double riskDistance = MathAbs(entry - stopLoss);
   if(atr <= 0.0 || riskDistance > atr * InpMaxStopAtr)
   {
      PrintFormat("%s %s skip: stop %.2f ATR > max %.2f",
                  g_symbol, isLong ? "long" : "short",
                  atr > 0.0 ? riskDistance / atr : 0.0, InpMaxStopAtr);
      g_diagSizeReject++;
      return;
   }

   double takeProfit = isLong ? entry + riskDistance * InpRewardRisk
                              : entry - riskDistance * InpRewardRisk;
   stopLoss   = NormalizePrice(stopLoss);
   takeProfit = NormalizePrice(takeProfit);

   if(!StopsMeetBrokerMinimum(isLong, stopLoss, takeProfit))
   {
      PrintFormat("%s %s skip: SL/TP inside broker stop level", g_symbol, isLong ? "long" : "short");
      g_diagSizeReject++;
      return;
   }

   double volume = 0.0;
   const ENUM_ORDER_TYPE orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!CalculateVolume(orderType, entry, stopLoss, volume))
   {
      g_diagSizeReject++;
      return;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(g_symbol);

   const string comment = isLong ? "COPT pullback long" : "COPT pullback short";
   const bool sent = isLong
                     ? g_trade.Buy(volume, g_symbol, 0.0, stopLoss, takeProfit, comment)
                     : g_trade.Sell(volume, g_symbol, 0.0, stopLoss, takeProfit, comment);

   if(sent)
   {
      g_tradesToday++;
      g_diagOrders++;
      const int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
      PrintFormat("%s %s opened vol=%.4f SL=%s TP=%s risk=%.2f%%",
                  g_symbol, isLong ? "long" : "short", volume,
                  DoubleToString(stopLoss, digits),
                  DoubleToString(takeProfit, digits),
                  InpRiskPercentPerTrade);
   }
   else
   {
      PrintFormat("%s %s order failed retcode=%d %s",
                  g_symbol, isLong ? "long" : "short",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Manage open positions: breakeven + ATR trailing + time close     |
//+------------------------------------------------------------------+
void ManagePositions()
{
   const bool dailyLimit = DailyLossReached();
   const bool windowClosed = InpCloseAtWindowEnd && !InSessionWindow(TimeCurrent());

   double atr = 0.0;
   GetBuffer(g_atrHandle, 0, 1, atr);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;

      if((dailyLimit && InpCloseOnDailyLoss) || windowClosed)
      {
         g_trade.SetExpertMagicNumber(InpMagicNumber);
         g_trade.PositionClose(ticket);
         continue;
      }

      if(atr <= 0.0)
         continue;

      MqlTick tick;
      if(!SymbolInfoTick(g_symbol, tick))
         continue;

      const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const bool isLong   = (type == POSITION_TYPE_BUY);
      const double open    = PositionGetDouble(POSITION_PRICE_OPEN);
      const double curSl   = PositionGetDouble(POSITION_SL);
      const double curTp   = PositionGetDouble(POSITION_TP);
      const double mark    = isLong ? tick.bid : tick.ask;

      double initialRisk = 0.0;
      if(curTp > 0.0 && InpRewardRisk > 0.0)
         initialRisk = MathAbs(curTp - open) / InpRewardRisk;
      if(initialRisk <= 0.0 && curSl > 0.0)
         initialRisk = MathAbs(open - curSl);
      if(initialRisk <= 0.0)
         continue;

      const double progress = isLong ? mark - open : open - mark;
      const double rMultiple = progress / initialRisk;
      double newSl = curSl;

      if(rMultiple >= InpBreakevenR)
      {
         const double be = isLong ? open + atr * InpBreakevenBufferAtr
                                  : open - atr * InpBreakevenBufferAtr;
         if((isLong  && (curSl <= 0.0 || be > newSl)) ||
            (!isLong && (curSl <= 0.0 || be < newSl)))
            newSl = be;
      }

      if(rMultiple >= InpTrailStartR)
      {
         const double trail = isLong ? mark - atr * InpTrailAtrMultiplier
                                     : mark + atr * InpTrailAtrMultiplier;
         if((isLong  && trail > newSl) ||
            (!isLong && (newSl <= 0.0 || trail < newSl)))
            newSl = trail;
      }

      if(newSl > 0.0 && MathAbs(newSl - curSl) > SymbolInfoDouble(g_symbol, SYMBOL_POINT))
      {
         newSl = NormalizePrice(newSl);
         if(StopsMeetBrokerMinimum(isLong, newSl, curTp))
         {
            g_trade.SetExpertMagicNumber(InpMagicNumber);
            if(!g_trade.PositionModify(ticket, newSl, curTp))
               PrintFormat("%s modify failed %I64u: %d %s",
                           g_symbol, ticket, g_trade.ResultRetcode(),
                           g_trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Pullback state machine + trigger evaluation                      |
//+------------------------------------------------------------------+
void UpdateArming(const int bias, const double atr, const MqlRates &rates[], const double pullEma)
{
   const double tol = atr * InpPullbackTouchAtr;
   const MqlRates last = rates[1];

   // Arm long when the last closed bar pulled back into the EMA in an uptrend.
   if(bias > 0 && DirectionAllowed(true))
   {
      if(last.low <= pullEma + tol)
      {
         if(!g_longArmed)
            g_diagArmedLong++;
         g_longArmed = true;
         g_longArmedBars = 0;
      }
   }
   // Arm short when the last closed bar pulled back into the EMA in a downtrend.
   if(bias < 0 && DirectionAllowed(false))
   {
      if(last.high >= pullEma - tol)
      {
         if(!g_shortArmed)
            g_diagArmedShort++;
         g_shortArmed = true;
         g_shortArmedBars = 0;
      }
   }

   // Bias flips invalidate the opposite-side arming.
   if(bias <= 0)
      g_longArmed = false;
   if(bias >= 0)
      g_shortArmed = false;

   // Expire stale arming.
   if(g_longArmed)
   {
      g_longArmedBars++;
      if(g_longArmedBars > InpPullbackLookback)
         g_longArmed = false;
   }
   if(g_shortArmed)
   {
      g_shortArmedBars++;
      if(g_shortArmedBars > InpPullbackLookback)
         g_shortArmed = false;
   }
}

bool LongTrigger(const double atr, const MqlRates &rates[], const double pullEma, const double rsi)
{
   if(!g_longArmed)
      return false;
   const MqlRates last = rates[1];
   const double body = last.close - last.open;
   if(body < atr * InpMinTriggerBodyAtr)        // bullish momentum candle
      return false;
   if(last.close <= pullEma)                     // close back above the EMA
      return false;
   if(rsi < InpRsiLongMin)                        // momentum confirmation
      return false;
   return true;
}

bool ShortTrigger(const double atr, const MqlRates &rates[], const double pullEma, const double rsi)
{
   if(!g_shortArmed)
      return false;
   const MqlRates last = rates[1];
   const double body = last.open - last.close;
   if(body < atr * InpMinTriggerBodyAtr)        // bearish momentum candle
      return false;
   if(last.close >= pullEma)                     // close back below the EMA
      return false;
   if(rsi > InpRsiShortMax)                        // momentum confirmation
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Per-closed-bar strategy evaluation                               |
//+------------------------------------------------------------------+
void EvaluateOnNewBar()
{
   MqlRates rates[];
   const int need = MaxInt(InpSwingLookback + 2, InpPullbackLookback + 3);
   if(!GetClosedBars(rates, need))
      return;

   const datetime barTime = rates[0].time;
   if(g_lastBarTime == barTime)
      return;
   g_lastBarTime = barTime;
   g_diagBars++;

   double atr = 0.0;
   if(!GetBuffer(g_atrHandle, 0, 1, atr) || atr <= 0.0)
      return;

   double pullEma = 0.0;
   if(!GetBuffer(g_pullbackEmaHandle, 0, 1, pullEma))
      return;

   double rsi = 0.0;
   if(!GetBuffer(g_rsiHandle, 0, 1, rsi))
      return;

   const int bias = TrendBias();

   // Keep the pullback arming current regardless of other gates.
   UpdateArming(bias, atr, rates, pullEma);

   if(bias == 0)
   {
      g_diagNoBias++;
      return;
   }

   const datetime now = TimeCurrent();
   if(!InSessionWindow(now))
   {
      g_diagSession++;
      return;
   }
   if(InNewsBlackout(now))
   {
      g_diagNews++;
      return;
   }
   if(!SpreadOk(atr))
   {
      g_diagSpread++;
      return;
   }

   if(InpUseAdxFilter)
   {
      double adx = 0.0;
      if(!GetBuffer(g_adxHandle, 0, 1, adx) || adx < InpMinAdx)
      {
         g_diagAdx++;
         return;
      }
   }

   if(bias > 0 && DirectionAllowed(true) && LongTrigger(atr, rates, pullEma, rsi))
   {
      g_diagTrigLong++;
      OpenTrade(true, atr, rates);
      g_longArmed = false;
      return;
   }

   if(bias < 0 && DirectionAllowed(false) && ShortTrigger(atr, rates, pullEma, rsi))
   {
      g_diagTrigShort++;
      OpenTrade(false, atr, rates);
      g_shortArmed = false;
      return;
   }
}

//+------------------------------------------------------------------+
//| Main processing                                                  |
//+------------------------------------------------------------------+
void Process()
{
   UpdateDailyAnchor();
   ManagePositions();

   if(DailyLossReached())
   {
      static datetime lastPrint = 0;
      if(TimeCurrent() - lastPrint > 300)
      {
         PrintFormat("Daily loss limit reached. Entries paused. start=%.2f current=%.2f",
                     g_dayStartEquity, AccountInfoDouble(ACCOUNT_EQUITY));
         lastPrint = TimeCurrent();
      }
      return;
   }

   EvaluateOnNewBar();
}

//+------------------------------------------------------------------+
//| Diagnostics                                                      |
//+------------------------------------------------------------------+
void PrintDiagnostics()
{
   if(!InpPrintDiagnostics)
      return;
   Print("==== CrudeOilPullbackTrader diagnostics ====");
   PrintFormat("symbol=%s bars=%I64d no_bias=%I64d session_block=%I64d news_block=%I64d spread_block=%I64d adx_block=%I64d",
               g_symbol, g_diagBars, g_diagNoBias, g_diagSession, g_diagNews, g_diagSpread, g_diagAdx);
   PrintFormat("armed_long=%I64d armed_short=%I64d trig_long=%I64d trig_short=%I64d size_reject=%I64d orders=%I64d",
               g_diagArmedLong, g_diagArmedShort, g_diagTrigLong, g_diagTrigShort,
               g_diagSizeReject, g_diagOrders);
   Print("==== End diagnostics ====");
}

//+------------------------------------------------------------------+
//| Lifecycle                                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpBiasFastEma <= 0 || InpBiasSlowEma <= 0 || InpBiasFastEma >= InpBiasSlowEma)
   {
      Print("Invalid bias EMA settings: fast must be > 0 and < slow.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpRewardRisk <= 0.0 || InpRiskPercentPerTrade <= 0.0)
   {
      Print("Invalid risk settings: reward:risk and risk percent must be positive.");
      return INIT_PARAMETERS_INCORRECT;
   }

   const string requested = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;
   g_symbol = ResolveSymbol(requested);

   if(!SymbolSelect(g_symbol, true))
   {
      PrintFormat("Unable to select symbol '%s' (requested '%s').", g_symbol, requested);
      return INIT_FAILED;
   }

   if(InpEntryTimeframe != PERIOD_M5)
      Print("Warning: EA designed for M5 entries. Backtest carefully after changing the timeframe.");

   g_biasFastHandle    = iMA(g_symbol, InpBiasTimeframe, InpBiasFastEma, 0, MODE_EMA, PRICE_CLOSE);
   g_biasSlowHandle    = iMA(g_symbol, InpBiasTimeframe, InpBiasSlowEma, 0, MODE_EMA, PRICE_CLOSE);
   g_pullbackEmaHandle = iMA(g_symbol, InpEntryTimeframe, InpPullbackEma, 0, MODE_EMA, PRICE_CLOSE);
   g_atrHandle         = iATR(g_symbol, InpEntryTimeframe, InpAtrPeriod);
   g_rsiHandle         = iRSI(g_symbol, InpEntryTimeframe, InpRsiPeriod, PRICE_CLOSE);
   g_adxHandle         = iADX(g_symbol, InpEntryTimeframe, InpAdxPeriod);

   if(g_biasFastHandle == INVALID_HANDLE || g_biasSlowHandle == INVALID_HANDLE ||
      g_pullbackEmaHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE ||
      g_rsiHandle == INVALID_HANDLE || g_adxHandle == INVALID_HANDLE)
   {
      PrintFormat("Indicator initialization failed for %s, error=%d", g_symbol, GetLastError());
      return INIT_FAILED;
   }

   g_lastBarTime    = 0;
   g_longArmed      = false;
   g_shortArmed     = false;
   g_longArmedBars  = 0;
   g_shortArmedBars = 0;

   UpdateDailyAnchor();
   EventSetTimer(MaxInt(1, InpTimerSeconds));

   PrintFormat("CrudeOilPullbackTrader initialized on %s (requested %s), magic=%d, currency=%s",
               g_symbol, requested, InpMagicNumber, AccountInfoString(ACCOUNT_CURRENCY));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintDiagnostics();
   EventKillTimer();

   if(g_biasFastHandle    != INVALID_HANDLE) IndicatorRelease(g_biasFastHandle);
   if(g_biasSlowHandle    != INVALID_HANDLE) IndicatorRelease(g_biasSlowHandle);
   if(g_pullbackEmaHandle != INVALID_HANDLE) IndicatorRelease(g_pullbackEmaHandle);
   if(g_atrHandle         != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_rsiHandle         != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_adxHandle         != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
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
