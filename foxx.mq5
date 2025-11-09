//+------------------------------------------------------------------+
//|                                                   foxx.mq5       |
//|                 Maiso Auto Symbol Scalper EA (MQL5)              |
//+------------------------------------------------------------------+
#property strict
#property version   "1.30"
#property copyright "Maiso"

#include <Trade/Trade.mqh>

CTrade trade;

//--- Input parameters
input int     FastMAPeriod     = 50;         // Fast EMA
input int     SlowMAPeriod     = 200;         // Slow EMA
input int     ADXPeriod        = 7;         // ADX period
input double  ADXMinLevel      = 15.0;      // Minimum ADX value to confirm trend
input double  LotSize          = 0.05;      // Lot size
input int     StopLossPips     = 100;        // Stop Loss (pips)
input int     TakeProfitPips   = 5;        // Take Profit (pips)
input int     TrailingStopPips = 20;         // Trailing Stop (pips)
input int     Slippage         = 1;         // Slippage (points)

//--- Global variables
string TradeSymbol;
int fastHandle, slowHandle, adxHandle;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   TradeSymbol = _Symbol; // Automatically detect the symbol

   Print("Maiso Scalper initialized for symbol: ", TradeSymbol);

   fastHandle = iMA(TradeSymbol, PERIOD_M1, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(TradeSymbol, PERIOD_M1, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   adxHandle  = iADX(TradeSymbol, PERIOD_M1, ADXPeriod);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE)
     {
      Print("Error creating indicator handles!");
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
   IndicatorRelease(adxHandle);
   Print("EA stopped. Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Check if trading is allowed
   long tradeMode;
   SymbolInfoInteger(TradeSymbol, SYMBOL_TRADE_MODE, tradeMode);
   if(tradeMode != SYMBOL_TRADE_MODE_FULL)
     {
      Print("Trading not allowed on ", TradeSymbol);
      return;
     }

//--- Get indicator values
   double fastBuf[], slowBuf[], adxBuf[];
   if(CopyBuffer(fastHandle, 0, 0, 1, fastBuf) <= 0)
      return;
   if(CopyBuffer(slowHandle, 0, 0, 1, slowBuf) <= 0)
      return;
   if(CopyBuffer(adxHandle, 0, 0, 1, adxBuf) <= 0)
      return;

   double fastMA = fastBuf[0];
   double slowMA = slowBuf[0];
   double adxValue = adxBuf[0];

   double ask   = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
   double point = SymbolInfoDouble(TradeSymbol, SYMBOL_POINT);

   bool hasPosition = PositionSelect(TradeSymbol);
   long posType = -1;
   if(hasPosition)
      posType = PositionGetInteger(POSITION_TYPE);

//--- BUY logic
  if(fastMA > slowMA && adxValue > ADXMinLevel)
    {
    if(!hasPosition || posType == POSITION_TYPE_SELL)
     {
      if(posType == POSITION_TYPE_SELL)
         trade.PositionClose(TradeSymbol);

      double point = SymbolInfoDouble(TradeSymbol, SYMBOL_POINT);
      double sl = ask - StopLossPips * point;
      double tp = ask + TakeProfitPips * point;

      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      trade.SetDeviationInPoints(Slippage);
      if(trade.Buy(LotSize, TradeSymbol, ask, sl, tp, "Maiso Buy"))
         Print("Buy order opened on ", TradeSymbol);
      else
         Print("Buy order failed. Error: ", _LastError);
     }
  }


//--- SELL logic
if(fastMA < slowMA && adxValue > ADXMinLevel)
  {
   if(!hasPosition || posType == POSITION_TYPE_BUY)
     {
      if(posType == POSITION_TYPE_BUY)
         trade.PositionClose(TradeSymbol);

      double point = SymbolInfoDouble(TradeSymbol, SYMBOL_POINT);
      double sl = bid + StopLossPips * point;
      double tp = bid - TakeProfitPips * point;

      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      trade.SetDeviationInPoints(Slippage);
      if(trade.Sell(LotSize, TradeSymbol, bid, sl, tp, "Maiso Sell"))
         Print("Sell order opened on ", TradeSymbol);
      else
         Print("Sell order failed. Error: ", _LastError);
     }
  }


//--- Apply trailing stop
   ApplyTrailingStop(TrailingStopPips);
  }

//+------------------------------------------------------------------+
//| Normalize stop levels                                            |
//+------------------------------------------------------------------+
void NormalizeStops(double &sl, double &tp)
  {
   int digits = (int)SymbolInfoInteger(TradeSymbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
  }

//+------------------------------------------------------------------+
//| Trailing stop                                                    |
//+------------------------------------------------------------------+
void ApplyTrailingStop(int trailingPips)
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      string symbol = PositionGetSymbol(i);
      if(symbol != TradeSymbol)
         continue;

      if(PositionSelect(symbol))
        {
         long posType = PositionGetInteger(POSITION_TYPE);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double currentPrice = 0.0;
         double newSL;

         if(posType == POSITION_TYPE_BUY)
           {
            currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
            newSL = currentPrice - trailingPips * point;
            if(newSL > sl || sl == 0)
               trade.PositionModify(symbol, newSL, tp);
           }
         else
            if(posType == POSITION_TYPE_SELL)
              {
               currentPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
               newSL = currentPrice + trailingPips * point;
               if(newSL < sl || sl == 0)
                  trade.PositionModify(symbol, newSL, tp);
              }
        }
     }
  }
//+------------------------------------------------------------------+
