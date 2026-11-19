//+------------------------------------------------------------------+
//| XAU_SmartZones.mq5                                               |
//| Personal XAUUSD indicator: Demand/Supply zones + zone signals    |
//|                                                                  |
//| Logic (all on CLOSED bars, no repaint):                          |
//|  1) Impulse leg  : consecutive candles moving >= N x ATR         |
//|  2) Base         : the small/opposite candle(s) right before it  |
//|                    -> Demand (before up-move) / Supply (down)    |
//|  3) Zone life    : touches counted, broken on close beyond,      |
//|                    retired after too many touches or too old     |
//|  4) Signal       : price returns to a fresh zone + rejection     |
//|                    candle + HTF EMA trend + session + room to TP |
//|  5) Score 0-100  : BOS, impulse strength, freshness, trend,      |
//|                    rejection strength -> grade A / B / C         |
//|                                                                  |
//| Buffers for EAs (iCustom): 0 Buy arrow, 1 Sell arrow,            |
//|  2 Direction (+1/-1/0), 3 SL, 4 TP, 5 Score, 6 ATR               |
//+------------------------------------------------------------------+
#property copyright "Nattawat"
#property version   "1.00"
#property description "Demand/Supply zones + buy/sell signals for XAUUSD (non-repainting, closed-bar logic)"
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   2

#property indicator_label1  "Buy Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  3

#property indicator_label2  "Sell Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  3

enum ENUM_TREND_FILTER
{
   TREND_OFF       = 0, // ไม่กรองเทรนด์ (สัญญาณเยอะ แต่เสี่ยงสวนเทรนด์)
   TREND_EMA       = 1, // EMA เร็ว > EMA ช้า บน TF ใหญ่ (แนะนำ)
   TREND_EMA_PRICE = 2  // EMA + ราคาต้องอยู่ฝั่งเดียวกับ EMA ช้า (เข้มสุด)
};

input group "=== โซน Demand / Supply ==="
input int    InpMaxBars        = 3000;  // จำนวนแท่งย้อนหลังที่คำนวณ
input int    InpATRPeriod      = 14;    // ATR period (ใช้วัดทุกอย่างให้ปรับตามความผันผวน)
input double InpImpulseATR     = 1.8;   // ขาวิ่งต้องยาวอย่างน้อยกี่ ATR ถึงนับเป็นโซน
input int    InpMaxLegBars     = 5;     // ขาวิ่งยาวได้ไม่เกินกี่แท่ง
input int    InpMaxBaseBars    = 3;     // ฐานโซน (base) ได้ไม่เกินกี่แท่ง
input double InpBaseBodyATR    = 0.6;   // แท่งฐานเพิ่มเติมต้องตัวเล็กกว่ากี่ ATR
input double InpMinZoneATR     = 0.15;  // ความหนาโซนขั้นต่ำ (ATR)
input double InpMaxZoneATR     = 1.5;   // ความหนาโซนสูงสุด (ATR) เกินนี้จะตัดให้บางลง
input double InpBreakBufferATR = 0.10;  // ปิดทะลุโซนเกินกี่ ATR = โซนแตก
input int    InpMaxTouches     = 3;     // แตะเกินกี่ครั้ง = โซนหมดแรง ลบทิ้ง
input int    InpZoneMaxAge     = 600;   // โซนอายุเกินกี่แท่ง = ลบทิ้ง
input bool   InpRequireBOS     = false; // ต้องเบรกโครงสร้าง (BOS) เท่านั้นถึงสร้างโซน
input int    InpSwingLeft      = 3;     // Swing: แท่งซ้าย
input int    InpSwingRight     = 3;     // Swing: แท่งขวา (ยืนยัน)
input int    InpZonesPerSide   = 4;     // แสดงโซนใกล้ราคาสุดฝั่งละกี่โซน
input int    InpExtendBars     = 15;    // ยืดโซนไปทางขวากี่แท่ง
input bool   InpShowBroken     = false; // แสดงโซนที่แตกแล้ว (สีเทา)

input group "=== สัญญาณ Buy / Sell ==="
input bool   InpShowSignals    = true;  // แสดงสัญญาณ
input int    InpMinScore       = 60;    // คะแนนขั้นต่ำ (60=B ขึ้นไป, 80=A เท่านั้น)
input int    InpMaxTouchSignal = 2;     // ให้สัญญาณเฉพาะการแตะครั้งที่ 1..N
input double InpWickRatio      = 0.35;  // ไส้เทียนปฏิเสธขั้นต่ำ (สัดส่วนของทั้งแท่ง)
input double InpSLBufferATR    = 0.25;  // SL ห่างขอบโซนกี่ ATR
input double InpMinRiskATR     = 0.5;   // SL ใกล้สุด (ATR)
input double InpMaxRiskATR     = 3.0;   // SL ไกลเกินนี้ = ไม่ให้สัญญาณ
input double InpMinRR          = 1.5;   // ต้องมีที่ว่างถึงโซนฝั่งตรงข้ามอย่างน้อยกี่ R
input double InpTargetRR       = 2.0;   // TP2 สูงสุดกี่ R (ถ้าโซนตรงข้ามใกล้กว่าจะใช้โซนนั้น)
input int    InpCooldownBars   = 6;     // เว้นกี่แท่งก่อนสัญญาณทิศเดิมครั้งถัดไป
input int    InpShowLevels     = 3;     // วาดเส้น Entry/SL/TP ของสัญญาณล่าสุดกี่อัน
input int    InpLevelBars      = 12;    // ความยาวเส้น Entry/SL/TP (แท่ง)

input group "=== กรองเทรนด์ (TF ใหญ่) ==="
input ENUM_TREND_FILTER InpTrendFilter = TREND_EMA;
input ENUM_TIMEFRAMES   InpHTF         = PERIOD_H1; // TF ใหญ่ที่ใช้ดูเทรนด์
input int               InpFastEMA     = 50;
input int               InpSlowEMA     = 200;

input group "=== ช่วงเวลาเทรด (เวลาเซิร์ฟเวอร์ MT5) ==="
input bool   InpUseSession     = true;  // ให้สัญญาณเฉพาะช่วงตลาดลอนดอน-นิวยอร์ก
input int    InpSessionStart   = 9;     // ชั่วโมงเริ่ม (เวลาเซิร์ฟเวอร์)
input int    InpSessionEnd     = 23;    // ชั่วโมงสิ้นสุด (เวลาเซิร์ฟเวอร์)

input group "=== แจ้งเตือน ==="
input bool   InpAlertPopup     = true;  // หน้าต่าง Alert
input bool   InpAlertSound     = true;  // เสียง
input bool   InpAlertPush      = false; // ส่งเข้ามือถือ (ต้องตั้ง MetaQuotes ID)

input group "=== หน้าตา ==="
input bool   InpShowPanel      = true;
input int    InpPanelX         = 10;
input int    InpPanelY         = 30;
input color  InpDemandColor    = C'24,92,72';   // Demand สด
input color  InpDemandTested   = C'22,62,54';   // Demand ถูกแตะแล้ว
input color  InpSupplyColor    = C'112,34,46';  // Supply สด
input color  InpSupplyTested   = C'74,32,40';   // Supply ถูกแตะแล้ว
input color  InpBrokenColor    = C'60,60,60';   // โซนแตก
input color  InpTextColor      = clrWhite;

//--- buffers
double BufBuy[], BufSell[], BufDir[], BufSL[], BufTP[], BufScore[], BufATR[];

struct SZone
{
   int      type;        // +1 demand, -1 supply
   double   top;
   double   bottom;
   datetime baseTime;
   int      createdBar;
   double   impulse;     // leg size in ATR
   bool     bos;
   int      touches;
   bool     inside;
   bool     signaled;
   bool     dead;
   int      id;
};

struct SSignal
{
   int      dir;
   datetime t;
   double   entry, sl, tp1, tp2;
   int      score;
};

const string PFX = "XSZ_";
SZone    g_z[];
SSignal  g_sig[];
int      g_nextId     = 0;
int      g_last       = -1;
datetime g_lastTime   = 0;
bool     g_ready      = false;
int      g_shBar = -1, g_slBar = -1;
double   g_shPrice = 0, g_shPrev = 0, g_slPrice = 0, g_slPrev = 0;
int      g_lastBullLeg = -1, g_lastBearLeg = -1;
int      g_lastBuyBar = -100000, g_lastSellBar = -100000;
int      g_hFast = INVALID_HANDLE, g_hSlow = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufBuy,   INDICATOR_DATA);
   SetIndexBuffer(1, BufSell,  INDICATOR_DATA);
   SetIndexBuffer(2, BufDir,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, BufSL,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufTP,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, BufScore, INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, BufATR,   INDICATOR_CALCULATIONS);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "XAU SmartZones");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   g_hFast = iMA(_Symbol, InpHTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_hSlow = iMA(_Symbol, InpHTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hFast == INVALID_HANDLE || g_hSlow == INVALID_HANDLE)
   {
      Print("XAU SmartZones: cannot create HTF EMA handles");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PFX);
   if(g_hFast != INVALID_HANDLE) IndicatorRelease(g_hFast);
   if(g_hSlow != INVALID_HANDLE) IndicatorRelease(g_hSlow);
   ChartRedraw();
}

//+------------------------------------------------------------------+
void ResetState()
{
   ObjectsDeleteAll(0, PFX);
   ArrayResize(g_z, 0);
   ArrayResize(g_sig, 0);
   g_nextId = 0; g_last = -1; g_lastTime = 0; g_ready = false;
   g_shBar = -1; g_slBar = -1;
   g_shPrice = g_shPrev = g_slPrice = g_slPrev = 0;
   g_lastBullLeg = -1; g_lastBearLeg = -1;
   g_lastBuyBar = -100000; g_lastSellBar = -100000;
}

string TFName(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_CURRENT) tf = (ENUM_TIMEFRAMES)_Period;
   return StringSubstr(EnumToString(tf), 7);
}

bool InSession(datetime t)
{
   if(!InpUseSession) return true;
   MqlDateTime dt; TimeToStruct(t, dt);
   if(InpSessionStart < InpSessionEnd) return dt.hour >= InpSessionStart && dt.hour < InpSessionEnd;
   return dt.hour >= InpSessionStart || dt.hour < InpSessionEnd;
}

// +1 bull, -1 bear, 0 unknown. Uses the last CLOSED higher-TF bar at time t (no look-ahead).
int HTFTrend(datetime t, double price, bool strict)
{
   int sh = iBarShift(_Symbol, InpHTF, t, false);
   if(sh < 0) return 0;
   double f[1], s[1];
   if(CopyBuffer(g_hFast, 0, sh + 1, 1, f) != 1) return 0;
   if(CopyBuffer(g_hSlow, 0, sh + 1, 1, s) != 1) return 0;
   if(f[0] == EMPTY_VALUE || s[0] == EMPTY_VALUE || f[0] <= 0 || s[0] <= 0) return 0;
   int dir = (f[0] > s[0]) ? 1 : ((f[0] < s[0]) ? -1 : 0);
   if(strict)
   {
      if(dir == 1  && price < s[0]) return 0;
      if(dir == -1 && price > s[0]) return 0;
   }
   return dir;
}

//+------------------------------------------------------------------+
void UpdateSwings(const int i, const double &high[], const double &low[])
{
   int j = i - InpSwingRight;
   if(j - InpSwingLeft < 0) return;
   bool isH = true, isL = true;
   for(int k = j - InpSwingLeft; k <= j + InpSwingRight; k++)
   {
      if(k == j) continue;
      if(k < j) { if(high[k] > high[j]) isH = false; if(low[k] < low[j]) isL = false; }
      else      { if(high[k] >= high[j]) isH = false; if(low[k] <= low[j]) isL = false; }
   }
   if(isH) { g_shPrev = g_shPrice; g_shPrice = high[j]; g_shBar = j; }
   if(isL) { g_slPrev = g_slPrice; g_slPrice = low[j];  g_slBar = j; }
}

int FindOverlap(int type, double top, double bottom)
{
   for(int k = 0; k < ArraySize(g_z); k++)
   {
      if(g_z[k].dead || g_z[k].type != type) continue;
      if(top >= g_z[k].bottom && bottom <= g_z[k].top) return k;
   }
   return -1;
}

void AddZone(int type, double top, double bottom, datetime baseTime, int bar, double impulse, bool bos)
{
   int ov = FindOverlap(type, top, bottom);
   if(ov >= 0)
   {
      // same area already mapped: just upgrade its quality, do not refresh touches
      if(bos) g_z[ov].bos = true;
      if(impulse > g_z[ov].impulse) g_z[ov].impulse = impulse;
      return;
   }
   int n = ArraySize(g_z);
   ArrayResize(g_z, n + 1);
   g_z[n].type = type; g_z[n].top = top; g_z[n].bottom = bottom;
   g_z[n].baseTime = baseTime; g_z[n].createdBar = bar;
   g_z[n].impulse = impulse; g_z[n].bos = bos;
   g_z[n].touches = 0; g_z[n].inside = false; g_z[n].signaled = false; g_z[n].dead = false;
   g_z[n].id = g_nextId++;
}

void DetectZones(const int i, const datetime &time[], const double &open[], const double &high[],
                 const double &low[], const double &close[])
{
   double atr = BufATR[i];
   if(atr <= 0) return;

   //--- bullish impulse -> DEMAND
   if(close[i] > open[i])
   {
      int ls = i;
      while(ls - 1 >= 1 && close[ls - 1] > open[ls - 1] && i - (ls - 1) < InpMaxLegBars) ls--;
      double move = close[i] - open[ls];
      if(move >= InpImpulseATR * atr && ls != g_lastBullLeg && ls - 1 >= 0)
      {
         g_lastBullLeg = ls;
         int b = ls - 1, bs = b;
         while(bs - 1 >= 0 && (b - (bs - 1)) < InpMaxBaseBars &&
               MathAbs(close[bs - 1] - open[bs - 1]) <= InpBaseBodyATR * atr) bs--;
         double bottom = low[ls], top = 0, hi = 0;
         for(int k = bs; k <= b; k++)
         {
            bottom = MathMin(bottom, low[k]);
            top    = MathMax(top, MathMax(open[k], close[k]));
            hi     = MathMax(hi, high[k]);
         }
         if(top - bottom < InpMinZoneATR * atr) top = hi;
         if(top - bottom < InpMinZoneATR * atr) top = bottom + InpMinZoneATR * atr;
         if(top - bottom > InpMaxZoneATR * atr) top = bottom + InpMaxZoneATR * atr;
         bool bos = (g_shPrice > 0 && g_shBar < i && close[i] > g_shPrice);
         if(!InpRequireBOS || bos)
            AddZone(1, top, bottom, time[bs], i, move / atr, bos);
      }
   }

   //--- bearish impulse -> SUPPLY
   if(close[i] < open[i])
   {
      int ls = i;
      while(ls - 1 >= 1 && close[ls - 1] < open[ls - 1] && i - (ls - 1) < InpMaxLegBars) ls--;
      double move = open[ls] - close[i];
      if(move >= InpImpulseATR * atr && ls != g_lastBearLeg && ls - 1 >= 0)
      {
         g_lastBearLeg = ls;
         int b = ls - 1, bs = b;
         while(bs - 1 >= 0 && (b - (bs - 1)) < InpMaxBaseBars &&
               MathAbs(close[bs - 1] - open[bs - 1]) <= InpBaseBodyATR * atr) bs--;
         double top = high[ls], bottom = DBL_MAX, lo = DBL_MAX;
         for(int k = bs; k <= b; k++)
         {
            top    = MathMax(top, high[k]);
            bottom = MathMin(bottom, MathMin(open[k], close[k]));
            lo     = MathMin(lo, low[k]);
         }
         if(top - bottom < InpMinZoneATR * atr) bottom = lo;
         if(top - bottom < InpMinZoneATR * atr) bottom = top - InpMinZoneATR * atr;
         if(top - bottom > InpMaxZoneATR * atr) bottom = top - InpMaxZoneATR * atr;
         bool bos = (g_slPrice > 0 && g_slBar < i && close[i] < g_slPrice);
         if(!InpRequireBOS || bos)
            AddZone(-1, top, bottom, time[bs], i, move / atr, bos);
      }
   }
}

int ZoneScore(const SZone &z, bool strongReject, bool trendAligned)
{
   int s = 40;
   if(z.bos) s += 15;
   if(z.impulse >= 2.5) s += 10; else if(z.impulse >= 2.0) s += 5;
   if(z.touches <= 1) s += 10;
   if(trendAligned) s += 15;
   if(strongReject) s += 10;
   return MathMin(s, 100);
}

string Grade(int score) { return score >= 80 ? "A" : (score >= 65 ? "B" : "C"); }

int Stars(const SZone &z)
{
   int s = 1;
   if(z.bos) s++;
   if(z.impulse >= 2.5) s++;
   return s;
}

// nearest opposite zone edge in the trade direction (0 = none)
double NearestOpposite(int dir, double price)
{
   double best = 0;
   for(int k = 0; k < ArraySize(g_z); k++)
   {
      if(g_z[k].dead) continue;
      if(dir == 1 && g_z[k].type == -1 && g_z[k].bottom > price)
         if(best == 0 || g_z[k].bottom < best) best = g_z[k].bottom;
      if(dir == -1 && g_z[k].type == 1 && g_z[k].top < price)
         if(best == 0 || g_z[k].top > best) best = g_z[k].top;
   }
   return best;
}

void MarkBroken(int k, datetime t)
{
   g_z[k].dead = true;
   if(!InpShowBroken) return;
   string nm = PFX + "B_" + IntegerToString(g_z[k].id);
   ObjectCreate(0, nm, OBJ_RECTANGLE, 0, g_z[k].baseTime, g_z[k].top, t, g_z[k].bottom);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, InpBrokenColor);
   ObjectSetInteger(0, nm, OBJPROP_FILL, true);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
}

void FireAlert(const SSignal &s)
{
   string msg = StringFormat("XAU SmartZones %s %s: %s @%s  SL %s  TP1 %s  TP2 %s  (%s %d)",
                             _Symbol, TFName((ENUM_TIMEFRAMES)_Period), s.dir == 1 ? "BUY" : "SELL",
                             DoubleToString(s.entry, _Digits), DoubleToString(s.sl, _Digits),
                             DoubleToString(s.tp1, _Digits), DoubleToString(s.tp2, _Digits),
                             Grade(s.score), s.score);
   if(InpAlertPopup) Alert(msg);
   else Print(msg);
   if(InpAlertSound) PlaySound("alert.wav");
   if(InpAlertPush) SendNotification(msg);
}

// returns true when a signal was produced
bool TrySignal(int dir, int zi, int score, const int i, const datetime &time[],
               const double &high[], const double &low[], const double &close[], bool live)
{
   double atr = BufATR[i];
   double entry = close[i];
   double sl = (dir == 1) ? g_z[zi].bottom - InpSLBufferATR * atr : g_z[zi].top + InpSLBufferATR * atr;
   double risk = (entry - sl) * dir;
   if(risk < InpMinRiskATR * atr) { risk = InpMinRiskATR * atr; sl = entry - dir * risk; }
   if(risk > InpMaxRiskATR * atr) return false;

   double tp2 = entry + dir * InpTargetRR * risk;
   double opp = NearestOpposite(dir, entry);
   if(opp > 0)
   {
      double room = (opp - entry) * dir;
      if(room < InpMinRR * risk) return false;           // opposite zone too close: no room
      if(room < InpTargetRR * risk) tp2 = opp;             // take profit in front of it
   }

   SSignal s;
   s.dir = dir; s.t = time[i]; s.entry = entry; s.sl = sl;
   s.tp1 = entry + dir * risk; s.tp2 = tp2; s.score = score;
   int n = ArraySize(g_sig);
   ArrayResize(g_sig, n + 1);
   g_sig[n] = s;
   if(n + 1 > 50) ArrayRemove(g_sig, 0, 1);

   if(dir == 1) { BufBuy[i]  = low[i]  - 0.3 * atr; g_lastBuyBar  = i; }
   else         { BufSell[i] = high[i] + 0.3 * atr; g_lastSellBar = i; }
   BufDir[i] = dir; BufSL[i] = sl; BufTP[i] = tp2; BufScore[i] = score;
   g_z[zi].signaled = true;
   if(live) FireAlert(s);
   return true;
}

//+------------------------------------------------------------------+
void ProcessBar(const int i, const bool live, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[])
{
   BufBuy[i] = EMPTY_VALUE; BufSell[i] = EMPTY_VALUE;
   BufDir[i] = 0; BufSL[i] = 0; BufTP[i] = 0; BufScore[i] = 0;
   double atr = BufATR[i];
   if(atr <= 0 || i < 2) return;

   UpdateSwings(i, high, low);

   double range = high[i] - low[i];
   double body  = MathAbs(close[i] - open[i]);
   double upW   = high[i] - MathMax(open[i], close[i]);
   double loW   = MathMin(open[i], close[i]) - low[i];
   bool bullEngulf = close[i] > open[i] && close[i - 1] < open[i - 1] && close[i] >= open[i - 1] && open[i] <= close[i - 1];
   bool bearEngulf = close[i] < open[i] && close[i - 1] > open[i - 1] && close[i] <= open[i - 1] && open[i] >= close[i - 1];
   bool bullReject = range > 0 && ((loW >= InpWickRatio * range && close[i] >= low[i] + 0.5 * range) || bullEngulf);
   bool bearReject = range > 0 && ((upW >= InpWickRatio * range && close[i] <= high[i] - 0.5 * range) || bearEngulf);
   bool strongBull = bullEngulf || (range > 0 && loW >= 0.55 * range) || (close[i] > open[i] && body >= 0.8 * atr);
   bool strongBear = bearEngulf || (range > 0 && upW >= 0.55 * range) || (close[i] < open[i] && body >= 0.8 * atr);

   int trend = HTFTrend(time[i], close[i], InpTrendFilter == TREND_EMA_PRICE);
   int bestBuy = -1, bestSell = -1, buyScore = -1, sellScore = -1;

   for(int k = 0; k < ArraySize(g_z); k++)
   {
      if(g_z[k].dead || g_z[k].createdBar >= i) continue;
      if(g_z[k].type == 1)
      {
         if(close[i] < g_z[k].bottom - InpBreakBufferATR * atr) { MarkBroken(k, time[i]); continue; }
         if(low[i] <= g_z[k].top) { if(!g_z[k].inside) { g_z[k].touches++; g_z[k].inside = true; g_z[k].signaled = false; } }
         else g_z[k].inside = false;
         if(g_z[k].inside && !g_z[k].signaled && g_z[k].touches <= InpMaxTouchSignal && bullReject && close[i] > g_z[k].bottom)
         {
            int sc = ZoneScore(g_z[k], strongBull, trend == 1);
            if(sc > buyScore) { buyScore = sc; bestBuy = k; }
         }
      }
      else
      {
         if(close[i] > g_z[k].top + InpBreakBufferATR * atr) { MarkBroken(k, time[i]); continue; }
         if(high[i] >= g_z[k].bottom) { if(!g_z[k].inside) { g_z[k].touches++; g_z[k].inside = true; g_z[k].signaled = false; } }
         else g_z[k].inside = false;
         if(g_z[k].inside && !g_z[k].signaled && g_z[k].touches <= InpMaxTouchSignal && bearReject && close[i] < g_z[k].top)
         {
            int sc = ZoneScore(g_z[k], strongBear, trend == -1);
            if(sc > sellScore) { sellScore = sc; bestSell = k; }
         }
      }
   }

   if(InpShowSignals && InSession(time[i]) && !(bestBuy >= 0 && bestSell >= 0))
   {
      bool trendOkBuy  = (InpTrendFilter == TREND_OFF) || trend == 1;
      bool trendOkSell = (InpTrendFilter == TREND_OFF) || trend == -1;
      if(bestBuy >= 0 && trendOkBuy && buyScore >= InpMinScore && i - g_lastBuyBar >= InpCooldownBars)
         TrySignal(1, bestBuy, buyScore, i, time, high, low, close, live);
      if(bestSell >= 0 && trendOkSell && sellScore >= InpMinScore && i - g_lastSellBar >= InpCooldownBars)
         TrySignal(-1, bestSell, sellScore, i, time, high, low, close, live);
   }

   // retire exhausted / old zones
   for(int k = 0; k < ArraySize(g_z); k++)
   {
      if(g_z[k].dead) continue;
      if(g_z[k].touches > InpMaxTouches || i - g_z[k].createdBar > InpZoneMaxAge) g_z[k].dead = true;
   }

   DetectZones(i, time, open, high, low, close);

   // compact
   int w = 0, n = ArraySize(g_z);
   for(int r = 0; r < n; r++)
      if(!g_z[r].dead) { if(w != r) g_z[w] = g_z[r]; w++; }
   if(w != n) ArrayResize(g_z, w);
}

//+------------------------------------------------------------------+
//| Drawing                                                          |
//+------------------------------------------------------------------+
void MakeRect(string nm, datetime t1, double p1, datetime t2, double p2, color c)
{
   ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_FILL, true);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
}

void MakeText(string nm, datetime t, double p, string txt, color c, int size, ENUM_ANCHOR_POINT anchor)
{
   ObjectCreate(0, nm, OBJ_TEXT, 0, t, p);
   ObjectSetString(0, nm, OBJPROP_TEXT, txt);
   ObjectSetString(0, nm, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
}

void MakeLevel(string nm, datetime t1, datetime t2, double p, color c, ENUM_LINE_STYLE st)
{
   ObjectCreate(0, nm, OBJ_TREND, 0, t1, p, t2, p);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, st);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
}

void DrawZones(const datetime tEnd, const double px)
{
   ObjectsDeleteAll(0, PFX + "Z_");
   for(int side = 1; side >= -1; side -= 2)
   {
      int    idx[]; double dist[];
      int    m = 0;
      for(int k = 0; k < ArraySize(g_z); k++)
      {
         if(g_z[k].dead || g_z[k].type != side) continue;
         ArrayResize(idx, m + 1); ArrayResize(dist, m + 1);
         idx[m] = k;
         dist[m] = (side == 1) ? MathMax(0, px - g_z[k].top) : MathMax(0, g_z[k].bottom - px);
         m++;
      }
      for(int a = 0; a < m - 1; a++)            // selection sort by distance
         for(int b = a + 1; b < m; b++)
            if(dist[b] < dist[a])
            {
               double td = dist[a]; dist[a] = dist[b]; dist[b] = td;
               int ti = idx[a]; idx[a] = idx[b]; idx[b] = ti;
            }
      for(int a = 0; a < m && a < InpZonesPerSide; a++)
      {
         SZone z = g_z[idx[a]];
         color c = (side == 1) ? (z.touches == 0 ? InpDemandColor : InpDemandTested)
                               : (z.touches == 0 ? InpSupplyColor : InpSupplyTested);
         string id = IntegerToString(z.id);
         MakeRect(PFX + "Z_R" + id, z.baseTime, z.top, tEnd, z.bottom, c);
         string stars = StringSubstr("***", 0, Stars(z));
         string txt = StringFormat("%s %s  T%d  %s-%s", side == 1 ? "DEMAND" : "SUPPLY", stars, z.touches,
                                   DoubleToString(z.bottom, _Digits), DoubleToString(z.top, _Digits));
         if(side == 1) MakeText(PFX + "Z_T" + id, tEnd, z.top,    txt, InpTextColor, 8, ANCHOR_RIGHT_UPPER);
         else          MakeText(PFX + "Z_T" + id, tEnd, z.bottom, txt, InpTextColor, 8, ANCHOR_RIGHT_LOWER);
      }
   }
}

void DrawSignals()
{
   ObjectsDeleteAll(0, PFX + "S_");
   int n = ArraySize(g_sig);
   int ps = PeriodSeconds();
   for(int k = MathMax(0, n - InpShowLevels); k < n; k++)
   {
      SSignal s = g_sig[k];
      string id = IntegerToString((long)s.t);
      datetime t2 = s.t + (datetime)(ps * InpLevelBars);
      MakeLevel(PFX + "S_E" + id, s.t, t2, s.entry, clrSilver, STYLE_DOT);
      MakeLevel(PFX + "S_L" + id, s.t, t2, s.sl,    clrTomato, STYLE_SOLID);
      MakeLevel(PFX + "S_1" + id, s.t, t2, s.tp1,   clrDeepSkyBlue, STYLE_DASH);
      MakeLevel(PFX + "S_2" + id, s.t, t2, s.tp2,   clrDodgerBlue, STYLE_SOLID);
      MakeText(PFX + "S_tL" + id, t2, s.sl,  "SL "  + DoubleToString(s.sl,  _Digits), clrTomato, 7, ANCHOR_LEFT);
      MakeText(PFX + "S_t1" + id, t2, s.tp1, "TP1 " + DoubleToString(s.tp1, _Digits), clrDeepSkyBlue, 7, ANCHOR_LEFT);
      MakeText(PFX + "S_t2" + id, t2, s.tp2, "TP2 " + DoubleToString(s.tp2, _Digits), clrDodgerBlue, 7, ANCHOR_LEFT);
      MakeText(PFX + "S_tE" + id, t2, s.entry,
               StringFormat("%s %s%d", s.dir == 1 ? "BUY" : "SELL", Grade(s.score), s.score),
               s.dir == 1 ? clrLime : clrRed, 8, ANCHOR_LEFT);
   }
}

void PanelLine(int row, string txt, color c)
{
   string nm = PFX + "P_" + IntegerToString(row);
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, InpPanelX + 10);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, InpPanelY + 8 + row * 17);
      ObjectSetString(0, nm, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, nm, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
}

void DrawPanel(datetime tNow, double px, double atr)
{
   if(!InpShowPanel) return;
   const int rows = 10;
   string bg = PFX + "P_BG";
   if(ObjectFind(0, bg) < 0)
   {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, InpPanelX);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, InpPanelY);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE, 330);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE, rows * 17 + 14);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'18,20,26');
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, C'60,64,76');
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   }

   int trend = HTFTrend(tNow, px, false);
   string ts = trend == 1 ? "BULLISH (UP)" : (trend == -1 ? "BEARISH (DOWN)" : "UNKNOWN");
   color  tc = trend == 1 ? clrLime : (trend == -1 ? clrTomato : clrSilver);

   string st = "RANGE";
   if(g_shPrev > 0 && g_slPrev > 0)
   {
      if(g_shPrice > g_shPrev && g_slPrice > g_slPrev) st = "UPTREND (HH/HL)";
      else if(g_shPrice < g_shPrev && g_slPrice < g_slPrev) st = "DOWNTREND (LH/LL)";
   }

   // nearest zones
   int dz = -1, sz = -1; double dd = DBL_MAX, sd = DBL_MAX;
   bool inDemand = false, inSupply = false;
   for(int k = 0; k < ArraySize(g_z); k++)
   {
      if(g_z[k].type == 1)
      {
         double d = MathMax(0, px - g_z[k].top);
         if(px >= g_z[k].bottom && px <= g_z[k].top) inDemand = true;
         if(d < dd) { dd = d; dz = k; }
      }
      else
      {
         double d = MathMax(0, g_z[k].bottom - px);
         if(px >= g_z[k].bottom && px <= g_z[k].top) inSupply = true;
         if(d < sd) { sd = d; sz = k; }
      }
   }
   string dtx = dz >= 0 ? StringFormat("%s-%s (%.1f away)", DoubleToString(g_z[dz].bottom, _Digits),
                                       DoubleToString(g_z[dz].top, _Digits), dd) : "-";
   string stx = sz >= 0 ? StringFormat("%s-%s (%.1f away)", DoubleToString(g_z[sz].bottom, _Digits),
                                       DoubleToString(g_z[sz].top, _Digits), sd) : "-";

   string plan; color pc = clrSilver;
   if(InpTrendFilter == TREND_OFF)
   {
      plan = inDemand ? "IN DEMAND: wait BUY trigger" : (inSupply ? "IN SUPPLY: wait SELL trigger" : "Wait for price to reach a zone");
      pc = inDemand ? clrLime : (inSupply ? clrTomato : clrSilver);
   }
   else if(trend == 1)  { plan = inDemand ? ">> IN DEMAND: watch BUY trigger" : "Bias BUY: wait pullback to DEMAND"; pc = clrLime; }
   else if(trend == -1) { plan = inSupply ? ">> IN SUPPLY: watch SELL trigger" : "Bias SELL: wait rally to SUPPLY"; pc = clrTomato; }
   else plan = "No clear HTF trend: stand aside";
   if(!InSession(tNow)) { plan = "Out of session: no signals"; pc = clrGray; }

   string ls1 = "Last signal : none", ls2 = "";
   color lc = clrSilver;
   int n = ArraySize(g_sig);
   if(n > 0)
   {
      SSignal s = g_sig[n - 1];
      ls1 = StringFormat("Last signal : %s %s%d @%s", s.dir == 1 ? "BUY" : "SELL", Grade(s.score), s.score,
                         DoubleToString(s.entry, _Digits));
      ls2 = StringFormat("  %s  SL %s  TP %s", TimeToString(s.t, TIME_DATE | TIME_MINUTES),
                         DoubleToString(s.sl, _Digits), DoubleToString(s.tp2, _Digits));
      lc = s.dir == 1 ? clrLime : clrTomato;
   }

   PanelLine(0, "XAU SMART ZONES  " + _Symbol + " " + TFName((ENUM_TIMEFRAMES)_Period), clrGold);
   PanelLine(1, "HTF " + TFName(InpHTF) + " trend: " + ts, tc);
   PanelLine(2, "Structure   : " + st, clrWhite);
   PanelLine(3, StringFormat("ATR(%d)     : %.2f", InpATRPeriod, atr), clrWhite);
   PanelLine(4, "Demand near : " + dtx, C'90,200,150');
   PanelLine(5, "Supply near : " + stx, C'230,110,120');
   PanelLine(6, ls1, lc);
   PanelLine(7, ls2, lc);
   PanelLine(8, "Session     : " + (InSession(tNow) ? "OPEN" : "CLOSED"), InSession(tNow) ? clrWhite : clrGray);
   PanelLine(9, plan, pc);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(rates_total < 300) return 0;
   if(BarsCalculated(g_hFast) <= 0 || BarsCalculated(g_hSlow) <= 0) return 0;

   ArraySetAsSeries(time, false);  ArraySetAsSeries(open, false);
   ArraySetAsSeries(high, false);  ArraySetAsSeries(low, false);
   ArraySetAsSeries(close, false);

   bool full = (prev_calculated == 0 || g_last < 0 || g_last >= rates_total || time[g_last] != g_lastTime);
   int atrFrom;
   if(full)
   {
      ResetState();
      ArrayInitialize(BufBuy, EMPTY_VALUE); ArrayInitialize(BufSell, EMPTY_VALUE);
      ArrayInitialize(BufDir, 0); ArrayInitialize(BufSL, 0); ArrayInitialize(BufTP, 0);
      ArrayInitialize(BufScore, 0); ArrayInitialize(BufATR, 0);
      atrFrom = 0;
      g_last = MathMax(InpSwingLeft + InpSwingRight + 2, rates_total - InpMaxBars) - 1;
   }
   else
   {
      atrFrom = MathMax(1, g_last);
      for(int k = g_last + 1; k < rates_total; k++)
      {
         BufBuy[k] = EMPTY_VALUE; BufSell[k] = EMPTY_VALUE;
         BufDir[k] = 0; BufSL[k] = 0; BufTP[k] = 0; BufScore[k] = 0;
      }
   }

   //--- Wilder ATR (own calculation, always in sync with the chart)
   for(int k = atrFrom; k < rates_total; k++)
   {
      double tr = (k == 0) ? high[k] - low[k]
                           : MathMax(high[k], close[k - 1]) - MathMin(low[k], close[k - 1]);
      if(k == 0) BufATR[k] = tr;
      else if(k < InpATRPeriod) BufATR[k] = (BufATR[k - 1] * k + tr) / (k + 1);
      else BufATR[k] = (BufATR[k - 1] * (InpATRPeriod - 1) + tr) / InpATRPeriod;
   }

   //--- process each newly CLOSED bar exactly once
   bool changed = false;
   for(int i = g_last + 1; i <= rates_total - 2; i++)
   {
      ProcessBar(i, g_ready && i == rates_total - 2, time, open, high, low, close);
      changed = true;
   }
   g_last = rates_total - 2;
   g_lastTime = time[g_last];
   g_ready = true;

   if(changed)
   {
      datetime tEnd = time[rates_total - 1] + (datetime)(PeriodSeconds() * InpExtendBars);
      DrawZones(tEnd, close[rates_total - 1]);
      DrawSignals();
   }
   DrawPanel(time[rates_total - 1], close[rates_total - 1], BufATR[rates_total - 2]);
   if(changed) ChartRedraw();
   return rates_total;
}
//+------------------------------------------------------------------+
