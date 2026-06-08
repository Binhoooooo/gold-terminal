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
input int      CheckEvery   = 5;          // Vérification toutes les X secondes
input int      Slippage     = 5;          // Slippage en points
input int      MagicNumber  = 77777;      // Numéro magique unique
input bool     AutoTP2      = true;       // Utiliser TP2 comme Take Profit
input bool     ShowAlerts   = true;       // Alertes popup MT4
input bool     PushNotif    = true;       // Notifications push sur téléphone
input int      MinConfiance = 55;         // Confiance minimum pour trader (%)
input int      MaxTrades    = 2;          // Nombre max de trades simultanés
input string   WAPhone      = "+33623041830"; // Ton numéro WhatsApp
input string   WAApiKey     = "6406801";     // API key CallMeBot

//--- Variables internes
string   lastSignalId  = "";
datetime lastCheck     = 0;
bool     eaActive      = true;
string   CMD_URL       = "https://gold-terminal-silk.vercel.app/api/command";
int      lastOpenTickets[10];
int      lastOpenCount  = 0;

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
   CheckClosedTrades();
   CheckManualCommand();
   CheckSignal();
}

//+------------------------------------------------------------------+
void CheckClosedTrades()
{
   // Récupère les tickets actuellement ouverts
   int currentTickets[10];
   int currentCount = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbole && OrderMagicNumber() == MagicNumber && currentCount < 10)
            currentTickets[currentCount++] = OrderTicket();
   }

   // Compare avec la liste précédente — cherche les tickets fermés
   for(int j = 0; j < lastOpenCount; j++)
   {
      bool stillOpen = false;
      for(int k = 0; k < currentCount; k++)
         if(currentTickets[k] == lastOpenTickets[j]) { stillOpen = true; break; }

      if(!stillOpen)
      {
         // Ce ticket vient de se fermer — cherche dans l'historique
         for(int h = OrdersHistoryTotal()-1; h >= 0; h--)
         {
            if(OrderSelect(h, SELECT_BY_POS, MODE_HISTORY))
            {
               if(OrderTicket() == lastOpenTickets[j])
               {
                  double profit = OrderProfit() + OrderSwap() + OrderCommission();
                  string dir    = (OrderType() == OP_BUY) ? "BUY" : "SELL";
                  string result = (profit >= 0) ? "✅ PROFIT" : "❌ PERTE";
                  string msg    = StringFormat("%s %s ferme | %s %+.2f$ | Entry: %.2f | Close: %.2f",
                     dir, Symbole, result, profit, OrderOpenPrice(), OrderClosePrice());
                  Print("📊 TRADE FERME — ", msg);
                  if(PushNotif) SendNotification("📊 GOLD TERMINAL\n" + msg);
                  SendWhatsApp("GOLD TERMINAL - Trade ferme! " + msg);
                  break;
               }
            }
         }
      }
   }

   // Met à jour la liste
   lastOpenCount = currentCount;
   for(int m = 0; m < currentCount; m++) lastOpenTickets[m] = currentTickets[m];
}

//+------------------------------------------------------------------+
void CheckManualCommand()
{
   string headers = "", resultHeaders;
   char   post[], result[];
   int res = WebRequest("GET", CMD_URL, headers, 5000, post, result, resultHeaders);
   if(res == -1) return;

   string json = CharArrayToString(result);
   string trade = ParseStr(json, "\"trade\":\"", "\"");
   if(trade != "LONG" && trade != "SHORT") return;

   // Commande manuelle détectée !
   Print("📱 COMMANDE MANUELLE REÇUE: ", trade);

   double ask = MarketInfo(Symbole, MODE_ASK);
   double bid = MarketInfo(Symbole, MODE_BID);
   double atr = iATR(Symbole, PERIOD_H1, 14, 0);
   if(atr <= 0) atr = 50;

   double sl, tp, entryPrice;
   int ticket = -1;
   string msg = "";

   if(trade == "LONG") {
      entryPrice = ask;
      sl = NormalizeDouble(entryPrice - atr * 0.8, 2);
      tp = NormalizeDouble(entryPrice + atr * 2.5, 2);
      ticket = OrderSend(Symbole, OP_BUY, 0.1, entryPrice, Slippage, sl, tp, "GoldTerminal-MANUAL", MagicNumber, 0, clrLime);
      msg = StringFormat("▲ BUY MANUEL %s | 0.10 lots | SL: %.2f | TP: %.2f", Symbole, sl, tp);
   } else {
      entryPrice = bid;
      sl = NormalizeDouble(entryPrice + atr * 0.8, 2);
      tp = NormalizeDouble(entryPrice - atr * 2.5, 2);
      ticket = OrderSend(Symbole, OP_SELL, 0.1, entryPrice, Slippage, sl, tp, "GoldTerminal-MANUAL", MagicNumber, 0, clrRed);
      msg = StringFormat("▼ SELL MANUEL %s | 0.10 lots | SL: %.2f | TP: %.2f", Symbole, sl, tp);
   }

   if(ticket > 0) {
      Print("✅ TRADE MANUEL EXÉCUTÉ — Ticket #", ticket, " | ", msg);
      if(ShowAlerts) Alert("✅ GOLD TERMINAL — Trade Manuel!\n\n" + msg);
      if(PushNotif) SendNotification("📱 TRADE MANUEL\n" + msg);
      SendWhatsApp("GOLD TERMINAL - Trade MANUEL ouvert! " + msg);
      // Efface la commande sur le serveur
      char delPost[], delResult[];
      string delHeaders = "", delResultHeaders;
      WebRequest("DELETE", CMD_URL, delHeaders, 3000, delPost, delResult, delResultHeaders);
   } else {
      Print("❌ Échec trade manuel — Erreur: ", GetLastError(), " | ", msg);
   }
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
   string ts        = ParseRaw(json, "\"ts\":");

   //--- Log du statut
   string status = StringFormat("[%s] Signal: %s | Dir: %s | Conf: %d%% | Prix: %.2f | SL: %.2f | TP1: %.2f | TP2: %.2f",
      TimeToStr(TimeCurrent(), TIME_MINUTES), signal, direction == "" ? "WAIT" : direction,
      confiance, price, sl, tp1, tp2);
   Print(status);

   //--- Pas de signal de trade
   if(signal != "TRADE") { Print("◌ Signal=", signal, " — en attente"); return; }
   if(direction != "LONG" && direction != "SHORT") { Print("◌ Direction inconnue: '", direction, "'"); return; }

   //--- Confiance insuffisante
   if(confiance < MinConfiance)
   {
      Print("⚠ BLOQUÉ — Confiance ", confiance, "% < minimum requis ", MinConfiance, "% | Dir: ", direction);
      return;
   }

   //--- Identifiant unique du signal basé sur le timestamp API (pas le prix)
   string sigId = (ts != "") ? ts : direction + DoubleToStr(price, 2);
   if(sigId == lastSignalId)
   {
      Print("◷ Signal déjà traité (ts=", sigId, ") — attente du prochain...");
      return;
   }

   //--- Vérifie si le max de trades est atteint
   int openTrades = CountOpenTrades();
   if(openTrades >= MaxTrades)
   {
      Print("⚠ BLOQUÉ — ", openTrades, "/", MaxTrades, " trades ouverts sur ", Symbole, " — signal ignoré");
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
      SendWhatsApp("GOLD TERMINAL - Trade ouvert! " + msg + " Ticket #" + IntegerToString(ticket));
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
void SendWhatsApp(string msg)
{
   if(WAPhone == "" || WAApiKey == "") return;
   // Simplifie le message — supprime les caractères spéciaux
   StringReplace(msg, "▲", "BUY");
   StringReplace(msg, "▼", "SELL");
   StringReplace(msg, "|", "-");
   StringReplace(msg, "#", "");
   StringReplace(msg, " ", "+");
   StringReplace(msg, "\n", "+");
   string url = "https://api.callmebot.com/whatsapp.php?phone=" + WAPhone + "&text=" + msg + "&apikey=" + WAApiKey;
   string headers = "", resultHeaders;
   char post[], result[];
   int res = WebRequest("GET", url, headers, 8000, post, result, resultHeaders);
   if(res == -1)
      Print("❌ WhatsApp erreur: ", GetLastError(), " — vérifie api.callmebot.com dans les URLs autorisées");
   else
      Print("✅ WhatsApp envoyé");
}

//+------------------------------------------------------------------+
// Extrait un nombre brut (pour ts qui est un entier large sans guillemets)
string ParseRaw(string json, string key)
{
   int start = StringFind(json, key);
   if(start == -1) return "";
   start += StringLen(key);
   while(start < StringLen(json) && StringSubstr(json, start, 1) == " ") start++;
   string val = "";
   for(int i = start; i < start + 20; i++)
   {
      string c = StringSubstr(json, i, 1);
      if(c == "," || c == "}" || c == "]" || c == " " || c == "\n") break;
      val += c;
   }
   return val;
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
