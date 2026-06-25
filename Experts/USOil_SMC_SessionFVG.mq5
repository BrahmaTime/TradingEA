//+------------------------------------------------------------------+
//|                                      USOil_SMC_SessionFVG.mq5    |
//| NY-session SMC EA: liquidity sweep -> MSS -> FVG entry (USOIL)   |
//+------------------------------------------------------------------+
#property copyright "Generated for TradingEA"
#property version   "1.00"
#property strict
#property description "USOIL/XTIUSD M5 SMC EA. NY session liquidity sweep, MSS, FVG entry, EIA blackout, ZAR/account-currency sizing."

#include <Trade/Trade.mqh>

enum ENUM_ENTRY_MODE
{
   ENTRY_MARKET         = 0, // Market on confirmed FVG fill
   ENTRY_LIMIT_FVG_EDGE = 1, // Buy/sell limit at proximal FVG edge
   ENTRY_LIMIT_FVG_CE   = 2  // Buy/sell limit at FVG 50% (consequent encroachment)
};

enum ENUM_TP_MODE
{
   TP_SESSION_LIQUIDITY = 0, // Target opposite session liquidity pool
   TP_FIXED_RR          = 1  // Fixed reward:risk multiple (InpMinRR)
};

struct SwingPoint
{
   double   price;
   datetime time;
   int      barShift;
};

struct FVGZone
{
   bool     valid;
   bool     isBullish;
   double   top;
   double   bottom;
   double   ce;
   datetime formedTime;
   int      formedBarShift;
   bool     isFallback;
};

struct PendingSetup
{
   bool     active;
   bool     isLong;
   datetime sweepTime;
   int      sweepBarShift;
   double   sweepExtreme;
   double   liquidityLevel;
   int      barsSinceSweep;
   bool     mssConfirmed;
   bool     mssLight;
   FVGZone  fvg;
   datetime expiryTime;
   bool     entrySubmitted;
};

struct EAState
{
   string            symbol;
   int               atrHandle;
   datetime          lastBarTime;
   datetime          sessionDay;
   datetime          nySessionStart;
   datetime          nySessionEnd;
   double            preSessionHigh;
   double            preSessionLow;
   bool              preSessionReady;
   double            sessionHigh;
   double            sessionLow;
   PendingSetup      setup;
   ulong             pendingTicket;
   datetime          pendingPlacedTime;
   int               pendingPlacedBarShift;
   datetime          lastTradeBarTime;
   datetime          currentDay;
   int               tradesToday;
   long              barsProcessed;
   long              sessionBlocked;
   long              spreadBlocked;
   long              eiaBlocked;
   long              fridayBlocked;
   long              sweepDetectedLong;
   long              sweepDetectedShort;
   long              mssConfirmedLong;
   long              mssConfirmedShort;
   long              fvgFoundLong;
   long              fvgFoundShort;
   long              setupExpired;
   long              pendingExpired;
   long              cooldownBlocked;
   long              sizeRejected;
   long              orderAttempts;
   long              ordersOpened;
};

CTrade   g_trade;
EAState  g_state;

input group "=== Symbol ===="
input string          InpSymbolOverride      = "";       // Empty = chart symbol
input bool            InpAutoSelectOil       = true;     // Resolve XTIUSD/USOIL aliases

input group "=== NY Session (America/New_York) ===="
input bool            InpUseAutoEST          = true;     // Auto EST/EDT conversion to server time
input int             InpNYStartHour         = 9;
input int             InpNYStartMinute       = 0;
input int             InpNYEndHour           = 14;
input int             InpNYEndMinute         = 30;
input string          InpManualSessionStart  = "14:00";  // Used when InpUseAutoEST=false (server time)
input string          InpManualSessionEnd    = "19:30";

input group "=== Risk Management ===="
input bool            InpUseFixedLot         = false;
input double          InpFixedLot              = 0.10;
input double          InpRiskPercent           = 1.00;   // Account-currency risk when fixed lot disabled
input double          InpMinRR                 = 3.00;
input int             InpSLBufferPoints        = 50;
input int             InpSweepMinPoints        = 20;
input int             InpSweepCloseTolPoints   = 15;
input int             InpSweepScanBars         = 4;
input bool            InpUsePreSessionLiq      = true;

input group "=== Structure & FVG ===="
input ENUM_TIMEFRAMES InpSessionTF             = PERIOD_M15;
input ENUM_TIMEFRAMES InpStructureTF           = PERIOD_M5;
input int             InpSwingLookback         = 5;
input double          InpDisplacementBodyPct   = 0.55;
input int             InpMSSMaxBarsAfterSweep    = 24;
input bool            InpUseAtrDisplacement    = false;
input double          InpAtrDisplacementMult   = 0.50;
input int             InpFVGMinPoints          = 30;
input bool            InpUseMSSFallback        = true;
input bool            InpUseMSSLight             = false;
input bool            InpUseFVGFallback          = true;
input bool            InpRequireFormalFVGShorts  = true;
input bool            InpRequireFormalFVGLongs   = true;
input bool            InpAllowFallbackFVGLongs   = false;
input int             InpFallbackFVGMinPoints    = 40;
input bool            InpAllowShorts             = true;
input bool            InpShortsStrictMSS          = true;
input bool            InpLongsStrictMSS          = true;
input bool            InpSweepOnStructureTF      = true;
input int             InpPendingExpiryBars       = 12;
input int             InpSweepSetupExpiryBars    = 24;

input group "=== Entry & Trade Control ===="
input ENUM_ENTRY_MODE InpEntryMode             = ENTRY_LIMIT_FVG_CE;
input int             InpCooldownBars          = 6;
input int             InpMaxTradesPerDay       = 3;
input int             InpMagic                   = 20260625;
input int             InpSlippagePoints        = 30;
input int             InpMaxSpreadPoints         = 80;
input int             InpMaxPositions            = 1;
input ENUM_TP_MODE    InpTPMode                  = TP_FIXED_RR;
input bool            InpUseBreakEven            = true;
input double          InpBreakEvenRR             = 1.00;
input int             InpBreakEvenBufferPoints   = 5;

input group "=== Oil Protections (optional) ===="
input bool            InpUseEIABlock             = true;
input int             InpEIADayOfWeek            = 3;    // 0=Sun..3=Wed
input string          InpEIATime                 = "17:30"; // Server time
input int             InpEIABlockBeforeMin       = 45;
input int             InpEIABlockAfterMin        = 60;
input bool            InpFridayFlatten             = true;
input string          InpFridayFlattenTime       = "21:30"; // Server time

input group "=== Diagnostics ===="
input bool            InpVerboseLog                = true;

//+------------------------------------------------------------------+
//| Helpers                                                          |
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

double NormalizePrice(const double price)
{
   const int digits = (int)SymbolInfoInteger(g_state.symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

double PointSize()
{
   return SymbolInfoDouble(g_state.symbol, SYMBOL_POINT);
}

double PointsToPrice(const int points)
{
   return (double)points * PointSize();
}

int PriceToPoints(const double distance)
{
   const double point = PointSize();
   if(point <= 0.0)
      return 0;
   return (int)MathRound(MathAbs(distance) / point);
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

double NormalizeVolume(const double requestedVolume)
{
   const double minVol = SymbolInfoDouble(g_state.symbol, SYMBOL_VOLUME_MIN);
   const double maxVol = SymbolInfoDouble(g_state.symbol, SYMBOL_VOLUME_MAX);
   const double step   = SymbolInfoDouble(g_state.symbol, SYMBOL_VOLUME_STEP);
   if(minVol <= 0.0 || maxVol <= 0.0 || step <= 0.0)
      return 0.0;

   double volume = MathMax(minVol, MathMin(maxVol, requestedVolume));
   volume = MathFloor(volume / step) * step;
   volume = NormalizeDouble(volume, VolumeDigits(step));
   return volume >= minVol ? volume : 0.0;
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

bool ParseHourMinute(const string text, int &hour, int &minute)
{
   hour = 0;
   minute = 0;
   const string cleaned = Trim(text);
   const int colon = StringFind(cleaned, ":");
   if(colon < 0)
      return false;
   hour = (int)StringToInteger(StringSubstr(cleaned, 0, colon));
   minute = (int)StringToInteger(StringSubstr(cleaned, colon + 1));
   return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
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

string ResolveOilSymbol()
{
   string requested = Trim(InpSymbolOverride);
   if(StringLen(requested) == 0)
      requested = _Symbol;

   if(SymbolSelect(requested, true))
      return requested;

   if(!InpAutoSelectOil)
      return requested;

   const string candidates[] = {"XTIUSD", "USOIL", "WTI", "CL", "OIL", "Crude"};
   for(int c = 0; c < ArraySize(candidates); c++)
   {
      if(SymbolSelect(candidates[c], true))
         return candidates[c];
   }

   const int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
   {
      const string name = SymbolName(i, false);
      for(int c = 0; c < ArraySize(candidates); c++)
      {
         if(SymbolNameMatchesRequest(name, candidates[c]) && SymbolSelect(name, true))
            return name;
      }
   }
   return requested;
}

bool IsUsDaylightSaving(const int year, const int month, const int day)
{
   if(month < 3 || month > 11)
      return false;
   if(month > 3 && month < 11)
      return true;

   if(month == 3)
   {
      int sundays = 0;
      for(int d = 1; d <= day; d++)
      {
         MqlDateTime probe;
         probe.year = year;
         probe.mon = 3;
         probe.day = d;
         probe.hour = 12;
         probe.min = 0;
         probe.sec = 0;
         TimeToStruct(StructToTime(probe), probe);
         if(probe.day_of_week == 0)
            sundays++;
      }
      return sundays >= 2;
   }

   int sundays = 0;
   for(int d = 1; d <= day; d++)
   {
      MqlDateTime probe;
      probe.year = year;
      probe.mon = 11;
      probe.day = d;
      probe.hour = 12;
      probe.min = 0;
      probe.sec = 0;
      TimeToStruct(StructToTime(probe), probe);
      if(probe.day_of_week == 0)
         sundays++;
   }
   return sundays < 1;
}

int NewYorkUtcOffsetHours(const datetime when)
{
   MqlDateTime dt;
   TimeToStruct(when, dt);
   return IsUsDaylightSaving(dt.year, dt.mon, dt.day) ? -4 : -5;
}

datetime ConvertNewYorkToServer(const datetime nyDay, const int nyHour, const int nyMinute)
{
   MqlDateTime dt;
   TimeToStruct(nyDay, dt);
   dt.hour = nyHour;
   dt.min = nyMinute;
   dt.sec = 0;
   const datetime nyTime = StructToTime(dt);

   const int serverOffset = (int)((TimeCurrent() - TimeGMT()) / 3600);
   const int nyOffset = NewYorkUtcOffsetHours(nyTime);
   return nyTime + (serverOffset - nyOffset) * 3600;
}

void UpdateSessionWindow(const datetime now)
{
   const datetime day = DayStart(now);
   if(g_state.sessionDay == day && g_state.nySessionEnd > g_state.nySessionStart)
      return;

   g_state.sessionDay = day;

   if(InpUseAutoEST)
   {
      g_state.nySessionStart = ConvertNewYorkToServer(day, InpNYStartHour, InpNYStartMinute);
      g_state.nySessionEnd   = ConvertNewYorkToServer(day, InpNYEndHour, InpNYEndMinute);
   }
   else
   {
      int startHour = 0;
      int startMinute = 0;
      int endHour = 0;
      int endMinute = 0;
      ParseHourMinute(InpManualSessionStart, startHour, startMinute);
      ParseHourMinute(InpManualSessionEnd, endHour, endMinute);
      g_state.nySessionStart = BuildTimeForDay(day, startHour, startMinute);
      g_state.nySessionEnd     = BuildTimeForDay(day, endHour, endMinute);
   }

   if(g_state.nySessionEnd <= g_state.nySessionStart)
      g_state.nySessionEnd += 24 * 60 * 60;

   g_state.preSessionHigh = 0.0;
   g_state.preSessionLow = 0.0;
   g_state.preSessionReady = false;
   g_state.sessionHigh = 0.0;
   g_state.sessionLow = 0.0;
}

bool IsInNySession(const datetime when)
{
   UpdateSessionWindow(when);
   return when >= g_state.nySessionStart && when < g_state.nySessionEnd;
}

bool IsInEiaBlock(const datetime when)
{
   if(!InpUseEIABlock)
      return false;

   MqlDateTime dt;
   TimeToStruct(when, dt);
   if(dt.day_of_week != InpEIADayOfWeek)
      return false;

   int eiaHour = 0;
   int eiaMinute = 0;
   if(!ParseHourMinute(InpEIATime, eiaHour, eiaMinute))
      return false;

   const datetime eiaTime = BuildTimeForDay(when, eiaHour, eiaMinute);
   const datetime blockStart = eiaTime - InpEIABlockBeforeMin * 60;
   const datetime blockEnd   = eiaTime + InpEIABlockAfterMin * 60;
   return when >= blockStart && when <= blockEnd;
}

bool ShouldFridayFlatten(const datetime when)
{
   if(!InpFridayFlatten)
      return false;

   MqlDateTime dt;
   TimeToStruct(when, dt);
   if(dt.day_of_week != 5)
      return false;

   int flatHour = 0;
   int flatMinute = 0;
   if(!ParseHourMinute(InpFridayFlattenTime, flatHour, flatMinute))
      return false;

   const datetime flatTime = BuildTimeForDay(when, flatHour, flatMinute);
   return when >= flatTime;
}

bool SpreadPasses()
{
   if(InpMaxSpreadPoints <= 0)
      return true;

   MqlTick tick;
   if(!SymbolInfoTick(g_state.symbol, tick))
      return false;

   const double point = PointSize();
   const int spreadPoints = point > 0.0 ? (int)MathRound((tick.ask - tick.bid) / point) : 0;
   return spreadPoints <= InpMaxSpreadPoints;
}

bool GetRates(const ENUM_TIMEFRAMES tf, MqlRates &rates[], const int count)
{
   ArraySetAsSeries(rates, true);
   return CopyRates(g_state.symbol, tf, 0, count, rates) >= count;
}

bool GetAtr(const int shift, double &atr)
{
   double values[];
   ArraySetAsSeries(values, true);
   if(CopyBuffer(g_state.atrHandle, 0, shift, 1, values) != 1)
      return false;
   atr = values[0];
   return atr > 0.0 && atr != EMPTY_VALUE;
}

void ResetSetup()
{
   g_state.setup.active = false;
   g_state.setup.mssConfirmed = false;
   g_state.setup.mssLight = false;
   g_state.setup.fvg.valid = false;
   g_state.setup.barsSinceSweep = 0;
   g_state.setup.entrySubmitted = false;
}

void ResetDailyCounters(const datetime now)
{
   const datetime day = DayStart(now);
   if(g_state.currentDay != day)
   {
      g_state.currentDay = day;
      g_state.tradesToday = 0;
   }
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

int CountManagedPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_state.symbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      count++;
   }
   return count;
}

bool HasManagedPending()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != g_state.symbol)
         continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      const ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT ||
         type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP)
         return true;
   }
   return false;
}

void CancelManagedPending()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != g_state.symbol)
         continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      g_trade.OrderDelete(ticket);
   }
   g_state.pendingTicket = 0;
}

bool UpdatePreSessionLiquidity()
{
   if(!InpUsePreSessionLiq)
      return true;

   const datetime now = TimeCurrent();
   UpdateSessionWindow(now);
   if(now >= g_state.nySessionStart)
   {
      if(g_state.preSessionReady)
         return true;

      MqlRates rates[];
      ArraySetAsSeries(rates, false);
      const datetime from = g_state.nySessionStart - 12 * 60 * 60;
      const int copied = CopyRates(g_state.symbol, InpSessionTF, from, g_state.nySessionStart - 1, rates);
      if(copied <= 0)
         return false;

      double high = 0.0;
      double low = 0.0;
      int count = 0;
      for(int i = 0; i < copied; i++)
      {
         if(rates[i].time >= g_state.nySessionStart)
            continue;
         if(count == 0)
         {
            high = rates[i].high;
            low = rates[i].low;
         }
         else
         {
            high = MathMax(high, rates[i].high);
            low = MathMin(low, rates[i].low);
         }
         count++;
      }

      if(count > 0 && high > low)
      {
         g_state.preSessionHigh = high;
         g_state.preSessionLow = low;
         g_state.preSessionReady = true;
         if(InpVerboseLog)
            PrintFormat("Pre-session liquidity ready H=%.5f L=%.5f", high, low);
      }
      return g_state.preSessionReady;
   }
   return false;
}

void UpdateSessionLiquidity(const MqlRates &bar)
{
   if(!IsInNySession(bar.time))
      return;

   if(g_state.sessionHigh <= 0.0 || g_state.sessionLow <= 0.0)
   {
      g_state.sessionHigh = bar.high;
      g_state.sessionLow = bar.low;
      return;
   }

   g_state.sessionHigh = MathMax(g_state.sessionHigh, bar.high);
   g_state.sessionLow = MathMin(g_state.sessionLow, bar.low);
}

SwingPoint FindSwingHigh(const MqlRates &rates[], const int startShift, const int lookback)
{
   SwingPoint result;
   result.price = 0.0;
   result.time = 0;
   result.barShift = -1;

   const int size = ArraySize(rates);
   for(int i = startShift + 1; i < size - lookback; i++)
   {
      bool isSwing = true;
      const double pivot = rates[i].high;
      for(int j = 1; j <= lookback; j++)
      {
         if(rates[i - j].high >= pivot || rates[i + j].high >= pivot)
         {
            isSwing = false;
            break;
         }
      }
      if(isSwing)
      {
         result.price = pivot;
         result.time = rates[i].time;
         result.barShift = i;
         return result;
      }
   }
   return result;
}

SwingPoint FindSwingLow(const MqlRates &rates[], const int startShift, const int lookback)
{
   SwingPoint result;
   result.price = 0.0;
   result.time = 0;
   result.barShift = -1;

   const int size = ArraySize(rates);
   for(int i = startShift + 1; i < size - lookback; i++)
   {
      bool isSwing = true;
      const double pivot = rates[i].low;
      for(int j = 1; j <= lookback; j++)
      {
         if(rates[i - j].low <= pivot || rates[i + j].low <= pivot)
         {
            isSwing = false;
            break;
         }
      }
      if(isSwing)
      {
         result.price = pivot;
         result.time = rates[i].time;
         result.barShift = i;
         return result;
      }
   }
   return result;
}

bool IsDisplacementCandle(const MqlRates &bar, const double atr, const bool bullish)
{
   const double range = bar.high - bar.low;
   if(range <= 0.0)
      return false;

   const double body = MathAbs(bar.close - bar.open);
   if(body / range < InpDisplacementBodyPct)
      return false;

   if(InpUseAtrDisplacement && body < atr * InpAtrDisplacementMult)
      return false;

   if(bullish)
      return bar.close > bar.open;
   return bar.close < bar.open;
}

FVGZone DetectFVG(const MqlRates &rates[], const int shift, const int minPoints, const bool allowFallback)
{
   FVGZone zone;
   zone.valid = false;
   zone.isFallback = allowFallback;

   if(shift + 2 >= ArraySize(rates))
      return zone;

   const MqlRates c0 = rates[shift];
   const MqlRates c1 = rates[shift + 1];
   const MqlRates c2 = rates[shift + 2];

   if(c2.high < c0.low)
   {
      const double gap = c0.low - c2.high;
      if(PriceToPoints(gap) >= minPoints)
      {
         zone.valid = true;
         zone.isBullish = true;
         zone.bottom = c2.high;
         zone.top = c0.low;
         zone.ce = (zone.top + zone.bottom) / 2.0;
         zone.formedTime = c1.time;
         zone.formedBarShift = shift + 1;
      }
   }

   if(c2.low > c0.high)
   {
      const double gap = c2.low - c0.high;
      if(PriceToPoints(gap) >= minPoints)
      {
         zone.valid = true;
         zone.isBullish = false;
         zone.top = c2.low;
         zone.bottom = c0.high;
         zone.ce = (zone.top + zone.bottom) / 2.0;
         zone.formedTime = c1.time;
         zone.formedBarShift = shift + 1;
      }
   }

   return zone;
}

bool DetectLiquiditySweep(const bool wantLong, const MqlRates &rates[], double &sweepExtreme, double &liquidityLevel)
{
   if(!g_state.preSessionReady && InpUsePreSessionLiq)
      return false;

   const double tol = PointsToPrice(InpSweepCloseTolPoints);
   const double minSweep = PointsToPrice(InpSweepMinPoints);
   const int scan = MaxInt(1, InpSweepScanBars);

   for(int i = 1; i <= scan && i < ArraySize(rates); i++)
   {
      const MqlRates bar = rates[i];
      if(wantLong)
      {
         const double liq = g_state.preSessionLow;
         if(liq <= 0.0)
            continue;
         if(bar.low <= liq - minSweep && bar.close >= liq - tol)
         {
            sweepExtreme = bar.low;
            liquidityLevel = liq;
            return true;
         }
      }
      else
      {
         const double liq = g_state.preSessionHigh;
         if(liq <= 0.0)
            continue;
         if(bar.high >= liq + minSweep && bar.close <= liq + tol)
         {
            sweepExtreme = bar.high;
            liquidityLevel = liq;
            return true;
         }
      }
   }
   return false;
}

bool ConfirmMSS(const bool wantLong, const MqlRates &rates[], const double atr, const double sweepExtreme, bool &lightMss)
{
   lightMss = false;
   const int lookback = MaxInt(2, InpSwingLookback);
   const SwingPoint swing = wantLong ? FindSwingHigh(rates, 1, lookback)
                                     : FindSwingLow(rates, 1, lookback);
   if(swing.barShift < 0)
   {
      if(!InpUseMSSFallback)
         return false;
      if(wantLong)
      {
         if(rates[1].close <= sweepExtreme)
            return false;
         lightMss = true;
         return IsDisplacementCandle(rates[1], atr, true);
      }
      if(rates[1].close >= sweepExtreme)
         return false;
      lightMss = true;
      return IsDisplacementCandle(rates[1], atr, false);
   }

   const MqlRates bar = rates[1];
   if(wantLong)
   {
      const bool strictBreak = bar.close > swing.price && IsDisplacementCandle(bar, atr, true);
      if(InpLongsStrictMSS && !strictBreak)
      {
         if(InpUseMSSFallback && bar.close > sweepExtreme && IsDisplacementCandle(bar, atr, true))
         {
            lightMss = true;
            return true;
         }
         return false;
      }
      return strictBreak || (InpUseMSSFallback && bar.close > sweepExtreme);
   }

   const bool strictBreak = bar.close < swing.price && IsDisplacementCandle(bar, atr, false);
   if(InpShortsStrictMSS && !strictBreak)
   {
      if(InpUseMSSFallback && bar.close < sweepExtreme && IsDisplacementCandle(bar, atr, false))
      {
         lightMss = true;
         return true;
      }
      return false;
   }
   return strictBreak || (InpUseMSSFallback && bar.close < sweepExtreme);
}

bool FindSetupFVG(const bool wantLong, const MqlRates &rates[], FVGZone &zone)
{
   zone.valid = false;
   for(int i = 1; i <= 8 && i + 2 < ArraySize(rates); i++)
   {
      FVGZone formal = DetectFVG(rates, i, InpFVGMinPoints, false);
      if(formal.valid && formal.isBullish == wantLong)
      {
         zone = formal;
         return true;
      }
   }

   if(!InpUseFVGFallback)
      return false;

   if(wantLong && !InpAllowFallbackFVGLongs && InpRequireFormalFVGLongs)
      return false;

   if((wantLong && InpRequireFormalFVGLongs) || (!wantLong && InpRequireFormalFVGShorts))
      return false;

   for(int i = 1; i <= 8 && i + 2 < ArraySize(rates); i++)
   {
      FVGZone fallback = DetectFVG(rates, i, InpFallbackFVGMinPoints, true);
      if(fallback.valid && fallback.isBullish == wantLong)
      {
         zone = fallback;
         return true;
      }
   }
   return false;
}

bool StopsMeetBrokerMinimum(const bool isLong, const double sl, const double tp)
{
   MqlTick tick;
   if(!SymbolInfoTick(g_state.symbol, tick))
      return false;

   const double point = PointSize();
   const int stopsLevel = (int)SymbolInfoInteger(g_state.symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double minDist = stopsLevel * point;
   if(minDist <= 0.0)
      return true;

   if(isLong)
      return (tick.bid - sl) >= minDist && (tp <= 0.0 || (tp - tick.bid) >= minDist);
   return (sl - tick.ask) >= minDist && (tp <= 0.0 || (tick.ask - tp) >= minDist);
}

bool CalculateVolume(const ENUM_ORDER_TYPE orderType,
                     const double entry,
                     const double stopLoss,
                     double &volume)
{
   volume = 0.0;
   if(InpUseFixedLot)
   {
      volume = NormalizeVolume(InpFixedLot);
      return volume > 0.0;
   }

   const double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   if(riskMoney <= 0.0)
      return false;

   double oneLotProfit = 0.0;
   if(!OrderCalcProfit(orderType, g_state.symbol, 1.0, entry, stopLoss, oneLotProfit))
      return false;

   const double oneLotLoss = MathAbs(oneLotProfit);
   if(oneLotLoss <= 0.0)
      return false;

   volume = NormalizeVolume(riskMoney / oneLotLoss);
   return volume > 0.0;
}

double BuildStopLoss(const bool isLong, const double sweepExtreme)
{
   const double buffer = PointsToPrice(InpSLBufferPoints);
   if(isLong)
      return NormalizePrice(sweepExtreme - buffer);
   return NormalizePrice(sweepExtreme + buffer);
}

double BuildTakeProfit(const bool isLong, const double entry, const double stopLoss)
{
   const double risk = MathAbs(entry - stopLoss);
   if(risk <= 0.0)
      return 0.0;

   if(InpTPMode == TP_FIXED_RR)
   {
      if(isLong)
         return NormalizePrice(entry + risk * InpMinRR);
      return NormalizePrice(entry - risk * InpMinRR);
   }

   if(isLong)
   {
      if(g_state.preSessionHigh > entry)
         return NormalizePrice(g_state.preSessionHigh);
      return NormalizePrice(entry + risk * InpMinRR);
   }

   if(g_state.preSessionLow > 0.0 && g_state.preSessionLow < entry)
      return NormalizePrice(g_state.preSessionLow);
   return NormalizePrice(entry - risk * InpMinRR);
}

double EntryPriceForSetup(const bool isLong, const FVGZone &zone)
{
   if(InpEntryMode == ENTRY_MARKET)
      return 0.0;
   if(InpEntryMode == ENTRY_LIMIT_FVG_EDGE)
      return isLong ? zone.bottom : zone.top;
   return zone.ce;
}

bool RiskRewardAcceptable(const bool isLong, const double entry, const double sl, const double tp)
{
   const double risk = MathAbs(entry - sl);
   const double reward = MathAbs(tp - entry);
   if(risk <= 0.0)
      return false;
   return (reward / risk) >= InpMinRR - 0.01;
}

bool CooldownActive(const datetime barTime)
{
   if(InpCooldownBars <= 0 || g_state.lastTradeBarTime <= 0)
      return false;

   const int elapsed = (int)((barTime - g_state.lastTradeBarTime) / PeriodSeconds(InpStructureTF));
   return elapsed < InpCooldownBars;
}

bool PlaceEntry(const bool isLong, const double entryOverride, const double stopLoss, const double takeProfit)
{
   if(CountManagedPositions() >= InpMaxPositions)
      return false;
   if(InpMaxTradesPerDay > 0 && g_state.tradesToday >= InpMaxTradesPerDay)
      return false;

   MqlTick tick;
   if(!SymbolInfoTick(g_state.symbol, tick))
      return false;

   double entry = entryOverride;
   if(entry <= 0.0)
      entry = isLong ? tick.ask : tick.bid;

   if(!RiskRewardAcceptable(isLong, entry, stopLoss, takeProfit))
   {
      if(InpVerboseLog)
         PrintFormat("Skip: RR below minimum %.2f", InpMinRR);
      g_state.sizeRejected++;
      return false;
   }

   const ENUM_ORDER_TYPE orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double volume = 0.0;
   if(!CalculateVolume(orderType, entry, stopLoss, volume))
   {
      g_state.sizeRejected++;
      return false;
   }

   if(!StopsMeetBrokerMinimum(isLong, stopLoss, takeProfit))
   {
      g_state.sizeRejected++;
      return false;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(g_state.symbol);

   g_state.orderAttempts++;
   bool sent = false;
   const string comment = isLong ? "SMC FVG long" : "SMC FVG short";

   if(InpEntryMode == ENTRY_MARKET)
   {
      sent = isLong
             ? g_trade.Buy(volume, g_state.symbol, 0.0, stopLoss, takeProfit, comment)
             : g_trade.Sell(volume, g_state.symbol, 0.0, stopLoss, takeProfit, comment);
   }
   else
   {
      CancelManagedPending();
      const ENUM_ORDER_TYPE pendingType = isLong ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
      const datetime expiry = TimeCurrent() + InpPendingExpiryBars * PeriodSeconds(InpStructureTF);
      sent = g_trade.OrderOpen(g_state.symbol, pendingType, volume, entry, 0, stopLoss, takeProfit,
                               ORDER_TIME_SPECIFIED, expiry, comment);
      if(sent)
         g_state.pendingTicket = g_trade.ResultOrder();
   }

   if(sent)
   {
      g_state.ordersOpened++;
      g_state.tradesToday++;
      g_state.lastTradeBarTime = iTime(g_state.symbol, InpStructureTF, 0);
      if(InpVerboseLog)
         PrintFormat("%s order placed entry=%.5f SL=%.5f TP=%.5f vol=%.2f",
                     isLong ? "Long" : "Short", entry, stopLoss, takeProfit, volume);
      ResetSetup();
      return true;
   }

   if(InpVerboseLog)
      PrintFormat("Order failed: %d %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return false;
}

void ManagePositions()
{
   if(ShouldFridayFlatten(TimeCurrent()))
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
         g_trade.PositionClose(ticket);
      }
      CancelManagedPending();
   }

   if(!InpUseBreakEven)
      return;

   const double beBuffer = PointsToPrice(InpBreakEvenBufferPoints);
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

      const bool isLong = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      const double open = PositionGetDouble(POSITION_PRICE_OPEN);
      const double sl = PositionGetDouble(POSITION_SL);
      const double tp = PositionGetDouble(POSITION_TP);
      const double mark = isLong ? tick.bid : tick.ask;
      const double risk = MathAbs(open - sl);
      if(risk <= 0.0)
         continue;

      const double progress = isLong ? mark - open : open - mark;
      if(progress / risk < InpBreakEvenRR)
         continue;

      const double newSl = isLong ? open + beBuffer : open - beBuffer;
      if((isLong && newSl <= sl) || (!isLong && sl > 0.0 && newSl >= sl))
         continue;
      if(!StopsMeetBrokerMinimum(isLong, newSl, tp))
         continue;

      g_trade.PositionModify(ticket, NormalizePrice(newSl), tp);
   }
}

void EvaluateSetupPipeline(const MqlRates &rates[], const double atr)
{
   if(g_state.setup.active)
   {
      g_state.setup.barsSinceSweep++;
      if(g_state.setup.barsSinceSweep > InpSweepSetupExpiryBars)
      {
         if(InpVerboseLog)
            Print("Setup expired after sweep window");
         g_state.setupExpired++;
         ResetSetup();
         return;
      }

      if(!g_state.setup.mssConfirmed)
      {
         bool light = false;
         if(ConfirmMSS(g_state.setup.isLong, rates, atr, g_state.setup.sweepExtreme, light))
         {
            g_state.setup.mssConfirmed = true;
            g_state.setup.mssLight = light;
            if(g_state.setup.isLong)
               g_state.mssConfirmedLong++;
            else
               g_state.mssConfirmedShort++;
         }
         else
            return;
      }

      if(!g_state.setup.fvg.valid)
      {
         FVGZone zone;
         if(!FindSetupFVG(g_state.setup.isLong, rates, zone))
            return;

         g_state.setup.fvg = zone;
         if(g_state.setup.isLong)
            g_state.fvgFoundLong++;
         else
            g_state.fvgFoundShort++;
      }

      if(g_state.setup.entrySubmitted || HasManagedPosition() || HasManagedPending())
         return;

      const double sl = BuildStopLoss(g_state.setup.isLong, g_state.setup.sweepExtreme);
      const double entry = EntryPriceForSetup(g_state.setup.isLong, g_state.setup.fvg);
      const double tp = BuildTakeProfit(g_state.setup.isLong, entry > 0.0 ? entry : rates[1].close, sl);
      g_state.setup.entrySubmitted = true;
      PlaceEntry(g_state.setup.isLong, entry, sl, tp);
      return;
   }

   if(CooldownActive(rates[1].time))
   {
      g_state.cooldownBlocked++;
      return;
   }

   if(HasManagedPosition() || HasManagedPending())
      return;

   const bool directions[] = {true, false};
   for(int d = 0; d < 2; d++)
   {
      const bool wantLong = directions[d];
      if(!wantLong && !InpAllowShorts)
         continue;

      double sweepExtreme = 0.0;
      double liquidityLevel = 0.0;
      if(!DetectLiquiditySweep(wantLong, rates, sweepExtreme, liquidityLevel))
         continue;

      if(wantLong)
         g_state.sweepDetectedLong++;
      else
         g_state.sweepDetectedShort++;

      g_state.setup.active = true;
      g_state.setup.isLong = wantLong;
      g_state.setup.sweepTime = rates[1].time;
      g_state.setup.sweepBarShift = 1;
      g_state.setup.sweepExtreme = sweepExtreme;
      g_state.setup.liquidityLevel = liquidityLevel;
      g_state.setup.barsSinceSweep = 0;
      g_state.setup.mssConfirmed = false;
      g_state.setup.fvg.valid = false;
      g_state.setup.entrySubmitted = false;

      if(InpVerboseLog)
         PrintFormat("%s sweep detected at %.5f (liq %.5f)",
                     wantLong ? "Bullish" : "Bearish", sweepExtreme, liquidityLevel);
      return;
   }
}

void ProcessNewBar()
{
   const ENUM_TIMEFRAMES tf = InpSweepOnStructureTF ? InpStructureTF : InpSessionTF;
   MqlRates rates[];
   const int required = MaxInt(40, InpSwingLookback * 4 + InpSweepScanBars + 10);
   if(!GetRates(tf, rates, required))
      return;

   const datetime barTime = rates[1].time;
   g_state.barsProcessed++;

   ResetDailyCounters(barTime);
   UpdateSessionWindow(barTime);
   UpdatePreSessionLiquidity();
   UpdateSessionLiquidity(rates[1]);

   if(!IsInNySession(barTime))
   {
      g_state.sessionBlocked++;
      ResetSetup();
      return;
   }

   if(IsInEiaBlock(barTime))
   {
      g_state.eiaBlocked++;
      return;
   }

   if(ShouldFridayFlatten(barTime))
   {
      g_state.fridayBlocked++;
      return;
   }

   if(!SpreadPasses())
   {
      g_state.spreadBlocked++;
      return;
   }

   double atr = 0.0;
   if(!GetAtr(1, atr))
      atr = rates[1].high - rates[1].low;

   EvaluateSetupPipeline(rates, atr);
}

void PrintDiagnostics()
{
   Print("==== USOil_SMC_SessionFVG diagnostics ====");
   PrintFormat("bars=%I64d session_block=%I64d spread_block=%I64d eia_block=%I64d friday_block=%I64d",
               g_state.barsProcessed, g_state.sessionBlocked, g_state.spreadBlocked,
               g_state.eiaBlocked, g_state.fridayBlocked);
   PrintFormat("sweep_long=%I64d sweep_short=%I64d mss_long=%I64d mss_short=%I64d",
               g_state.sweepDetectedLong, g_state.sweepDetectedShort,
               g_state.mssConfirmedLong, g_state.mssConfirmedShort);
   PrintFormat("fvg_long=%I64d fvg_short=%I64d setup_expired=%I64d cooldown_block=%I64d",
               g_state.fvgFoundLong, g_state.fvgFoundShort, g_state.setupExpired,
               g_state.cooldownBlocked);
   PrintFormat("size_reject=%I64d order_attempts=%I64d orders_opened=%I64d",
               g_state.sizeRejected, g_state.orderAttempts, g_state.ordersOpened);
}

int OnInit()
{
   g_state.symbol = ResolveOilSymbol();
   if(!SymbolSelect(g_state.symbol, true))
   {
      PrintFormat("Failed to select symbol %s", g_state.symbol);
      return INIT_FAILED;
   }

   g_state.atrHandle = iATR(g_state.symbol, InpStructureTF, 14);
   if(g_state.atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(g_state.symbol);

   g_state.lastBarTime = 0;
   g_state.currentDay = 0;
   g_state.tradesToday = 0;
   ResetSetup();
   ResetDiagnostics();

   EventSetTimer(2);

   PrintFormat("USOil_SMC_SessionFVG initialized on %s (%s)",
               g_state.symbol, EnumToString(InpStructureTF));
   return INIT_SUCCEEDED;
}

void ResetDiagnostics()
{
   g_state.barsProcessed = 0;
   g_state.sessionBlocked = 0;
   g_state.spreadBlocked = 0;
   g_state.eiaBlocked = 0;
   g_state.fridayBlocked = 0;
   g_state.sweepDetectedLong = 0;
   g_state.sweepDetectedShort = 0;
   g_state.mssConfirmedLong = 0;
   g_state.mssConfirmedShort = 0;
   g_state.fvgFoundLong = 0;
   g_state.fvgFoundShort = 0;
   g_state.setupExpired = 0;
   g_state.pendingExpired = 0;
   g_state.cooldownBlocked = 0;
   g_state.sizeRejected = 0;
   g_state.orderAttempts = 0;
   g_state.ordersOpened = 0;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_state.atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_state.atrHandle);
   PrintDiagnostics();
}

void OnTick()
{
   ManagePositions();

   const datetime barTime = iTime(g_state.symbol, InpStructureTF, 0);
   if(barTime == 0 || barTime == g_state.lastBarTime)
      return;

   g_state.lastBarTime = barTime;
   ProcessNewBar();
}

void OnTimer()
{
   ManagePositions();
}
