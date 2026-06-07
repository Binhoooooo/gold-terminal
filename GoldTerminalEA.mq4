//+------------------------------------------------------------------+
//|                                            GoldTerminalEA.mq4    |
//|                              Gold Terminal — Auto Trade Bot       |
//|                        gold-terminal-silk.vercel.app              |
//+------------------------------------------------------------------+
#property copyright "Gold Terminal"
#property link      "https://gold-terminal-silk.vercel.app"
#property version   "1.00"
#property strict

//--- Paramètres configurables
input string   API_URL      = "https://gold-terminal-silk.vercel.app/api/signal?symbol=GC%3DF";
input string   Symbole      = "XAUUSD";   // Symbole MT4 de l'or
input double   Lots         = 0.0;        // 0 = utilise les lots du signal, sinon fixe
input int      CheckEvery   = 30;         // Vérification toutes les X secondes
input int      Slippage     = 5;          // Slippage en points
input int      MagicNumber  = 77777;      // Numéro magique unique
input bool     AutoTP2      = true;       // Utiliser TP2 comme Take Profit
input bool     ShowAlerts   = true;       // Alertes popup MT4
input bool     PushNotif    = true;       // Notifications push sur téléphone
input int      MinConfiance = 65;         // Confiance minimum pour trader (%)

//--- Variables internes
string   lastSignalId  = "";
datetime lastCheck     = 0;
bool     eaActive      = true;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("╔══════════════════════════════════════╗");
   Print("║      GOLD TERMINAL EA — DÉMARRÉ      ║");
   Print("╚══════════════════════════════════════╝");
   Print("▸ Symbole   : ", Symbole);
   Print("▸ API URL   : ", API_URL);
   Print("▸ Intervalle: ", CheckEvery, "s");
   Print("▸ Magic#    : ", MagicNumber);
   Print("▸ Confiance : >= ", MinConfiance, "%");

   EventSetTimer(CheckEvery);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTimer()
{
   if(!eaActive) return;
   CheckSignal();
}

void OnTick()
{
   // Garde OnTick comme fallback si OnTimer non dispo
}

//+------------------------------------------------------------------+
void CheckSignal()
{
   string headers = "";
   char   post[], result[];
   string resultHeaders;

   ResetLastError();
   int res = WebRequest("GET", API_URL, headers, 8000, post, result, resultHeaders);

   if(res == -1)
   {
      int err = GetLastError();
      if(err == 4014)
         Print("❌ WebRequest bloqué — active-le dans Outils → Options → Expert Advisors");
      else
         Print("❌ Erreur connexion API: ", err);
      return;
   }

   string json = CharArrayToString(result);

   //--- Parse les champs
   string signal    = ParseStr(json, "\"signal\":\"",    "\"");
   string direction = ParseStr(json, "\"direction\":\"", "\"");
   int    confiance = (int)ParseNum(json, "\"confidence\":");
   double price     = ParseNum(json, "\"price\":");
   double sl        = ParseNum(json, "\"sl\":");
   double tp1       = ParseNum(json, "\"tp1\":");
   double tp2       = ParseNum(json, "\"tp2\":");
   double lots_sig  = ParseNum(json, "\"lots\":");

   //--- Log du statut
   string status = StringFormat("[%s] Signal: %s | Dir: %s | Conf: %d%% | Prix: %.2f | SL: %.2f | TP1: %.2f | TP2: %.2f",
      TimeToStr(TimeCurrent(), TIME_MINUTES), signal, direction == "" ? "WAIT" : direction,
      confiance, price, sl, tp1, tp2);
   Print(status);

   //--- Pas de signal de trade
   if(signal != "TRADE") return;
   if(direction != "LONG" && direction != "SHORT") return;

   //--- Confiance insuffisante
   if(confiance < MinConfiance)
   {
      Print("⚠ Confiance ", confiance, "% < minimum ", MinConfiance, "% — trade ignoré");
      return;
   }

   //--- Identifiant unique du signal (évite les doublons)
   string sigId = direction + DoubleToStr(price, 2) + IntegerToString(confiance);
   if(sigId == lastSignalId)
   {
      Print("◷ Signal déjà traité, attente du prochain...");
      return;
   }

   //--- Vérifie si un trade est déjà ouvert
   if(CountOpenTrades() > 0)
   {
      Print("⚠ Trade déjà ouvert sur ", Symbole, " — nouveau signal ignoré");
      return;
   }

   //--- Taille des lots
   double lotSize = (Lots > 0) ? Lots : lots_sig;
   if(lotSize <= 0) lotSize = 0.1;
   lotSize = NormalizeLots(lotSize);

   //--- Take Profit
   double takeProfit = AutoTP2 ? tp2 : tp1;

   //--- Exécution du trade
   int ticket = -1;
   string msg  = "";

   // Retry jusqu'à 3 fois en cas de requote (erreur 135/136/138)
   for(int attempt = 1; attempt <= 3; attempt++)
   {
      if(direction == "LONG")
      {
         double ask = MarketInfo(Symbole, MODE_ASK);
         ticket = OrderSend(Symbole, OP_BUY, lotSize, ask, Slippage, sl, takeProfit,
                            "GoldTerminal", MagicNumber, 0, clrLime);
         msg = StringFormat("▲ BUY %s | %.2f lots | SL: %.2f | TP: %.2f | Conf: %d%%",
                            Symbole, lotSize, sl, takeProfit, confiance);
      }
      else if(direction == "SHORT")
      {
         double bid = MarketInfo(Symbole, MODE_BID);
         ticket = OrderSend(Symbole, OP_SELL, lotSize, bid, Slippage, sl, takeProfit,
                            "GoldTerminal", MagicNumber, 0, clrRed);
         msg = StringFormat("▼ SELL %s | %.2f lots | SL: %.2f | TP: %.2f | Conf: %d%%",
                            Symbole, lotSize, sl, takeProfit, confiance);
      }
      if(ticket > 0) break;
      int err = GetLastError();
      if(err != 135 && err != 136 && err != 138) break; // Pas une requote, inutile de retry
      Print("⚠ Requote erreur ", err, " — tentative ", attempt, "/3");
      Sleep(500);
   }

   if(ticket > 0)
   {
      lastSignalId = sigId;
      Print("✅ TRADE EXÉCUTÉ — Ticket #", ticket, " | ", msg);
      if(ShowAlerts)
         Alert("✅ GOLD TERMINAL — Trade exécuté!\n\n" + msg + "\n\nTicket: #" + IntegerToString(ticket));
      if(PushNotif)
         SendNotification("🥇 GOLD TERMINAL\n" + msg + "\nTicket #" + IntegerToString(ticket));
   }
   else
   {
      int err = GetLastError();
      Print("❌ ÉCHEC du trade — Erreur: ", err, " | ", msg);
      Print("   Code erreur MT4: ", ErrorDescription(err));
      if(ShowAlerts)
         Alert("❌ GOLD TERMINAL — Échec du trade!\nErreur: " + IntegerToString(err) + "\n" + ErrorDescription(err));
   }
}

//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbole && OrderMagicNumber() == MagicNumber)
            count++;
   }
   return count;
}

//+------------------------------------------------------------------+
double NormalizeLots(double lots)
{
   double minLot  = MarketInfo(Symbole, MODE_MINLOT);
   double maxLot  = MarketInfo(Symbole, MODE_MAXLOT);
   double lotStep = MarketInfo(Symbole, MODE_LOTSTEP);
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
string ParseStr(string json, string key, string endChar)
{
   int start = StringFind(json, key);
   if(start == -1) return "";
   start += StringLen(key);
   // Saute les espaces
   while(start < StringLen(json) && StringSubstr(json, start, 1) == " ") start++;
   int end = StringFind(json, endChar, start);
   if(end == -1) return "";
   return StringSubstr(json, start, end - start);
}

//+------------------------------------------------------------------+
double ParseNum(string json, string key)
{
   int start = StringFind(json, key);
   if(start == -1) return 0;
   start += StringLen(key);
   // Saute espaces et ":"
   while(start < StringLen(json))
   {
      string c = StringSubstr(json, start, 1);
      if(c != " " && c != ":") break;
      start++;
   }
   string val = "";
   for(int i = start; i < start + 20; i++)
   {
      string c = StringSubstr(json, i, 1);
      if(c == "," || c == "}" || c == "]" || c == " " || c == "\n" || c == "\r") break;
      if(c == "n" || c == "N") return 0; // null/NaN
      val += c;
   }
   if(StringLen(val) == 0) return 0;
   return StringToDouble(val);
}

//+------------------------------------------------------------------+
string ErrorDescription(int code)
{
   switch(code)
   {
      case 0:   return "Pas d'erreur";
      case 2:   return "Erreur générale";
      case 3:   return "Paramètres invalides";
      case 4:   return "Serveur occupé";
      case 64:  return "Compte bloqué";
      case 130: return "Stop Loss/TP invalide";
      case 131: return "Volume invalide";
      case 132: return "Marché fermé";
      case 133: return "Trading désactivé";
      case 134: return "Fonds insuffisants";
      case 135: return "Prix changé — réessaie";
      case 136: return "Pas de prix disponible";
      case 138: return "Requote — prix changé";
      case 145: return "Modification refusée — stop trop proche";
      case 146: return "File d'attente pleine";
      default:  return "Erreur inconnue";
   }
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("Gold Terminal EA — Arrêté (raison: ", reason, ")");
}
