export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 'no-store');

  const symbol = req.query.symbol || 'GC=F'; // GC=F = Gold, EURUSD=X = EUR/USD

  try {
    const r = await fetch(
      `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?interval=1m&range=5d`,
      { headers: { 'User-Agent': 'Mozilla/5.0' } }
    );
    const j = await r.json();
    const result = j?.chart?.result?.[0];
    const meta   = result?.meta;
    const closes = result?.indicators?.quote?.[0]?.close?.filter(Boolean) || [];

    if (!meta?.regularMarketPrice || closes.length < 10) throw new Error('no data');

    const price = meta.regularMarketPrice;
    const prev  = meta.chartPreviousClose || price;
    const high  = meta.regularMarketDayHigh || price;
    const low   = meta.regularMarketDayLow  || price;

    const atr   = high - low;
    const pivot = (high + low + prev) / 3;
    const r1    = 2 * pivot - low;
    const s1    = 2 * pivot - high;

    const recent = closes.slice(-30);

    // Vraie EMA exponentielle
    const calcEMA = (data, period) => {
      const k = 2 / (period + 1);
      let ema = data.slice(0, period).reduce((a,b)=>a+b,0) / period;
      for (let i = period; i < data.length; i++) ema = data[i] * k + ema * (1 - k);
      return ema;
    };
    const ema5  = recent.length >= 5  ? calcEMA(recent, 5)  : recent[recent.length-1];
    const ema20 = recent.length >= 20 ? calcEMA(recent, 20) : recent.reduce((a,b)=>a+b,0)/recent.length;

    const change = price - prev;
    const pct    = (change / prev) * 100;

    // RSI 14 correct
    const gains = [], losses = [];
    for (let i = 1; i < Math.min(15, recent.length); i++) {
      const d = recent[i] - recent[i-1];
      if (d > 0) gains.push(d); else losses.push(Math.abs(d));
    }
    const avgGain = gains.length ? gains.reduce((a,b)=>a+b,0)/14 : 0;
    const avgLoss = losses.length ? losses.reduce((a,b)=>a+b,0)/14 : 0.001;
    const rsi = 100 - (100 / (1 + avgGain/avgLoss));

    const isForex   = symbol.includes('USD=X');
    const atrMin    = isForex ? 0.0005 : 3;
    const atrMax    = isForex ? 0.03   : 250;
    const volatilityOk = atr > atrMin && atr < atrMax;

    let signal = 'WAIT', direction = null, confidence = 0, reasons = [];
    let sl = null, tp1 = null, tp2 = null, lots = null;

    const bullMomentum    = ema5 > ema20;
    const priceAbovePivot = price > pivot;
    const rsiOk           = rsi > 30 && rsi < 82;
    const strongMove      = Math.abs(pct) > (isForex ? 0.03 : 0.05);
    // Score: signal si au moins 3 conditions sur 4
    const bullScore = (bullMomentum?1:0) + (priceAbovePivot?1:0) + (rsiOk?1:0) + (volatilityOk?1:0);
    const bearScore = (!bullMomentum?1:0) + (!priceAbovePivot?1:0) + (rsiOk?1:0) + (volatilityOk?1:0);

    if (bullScore >= 3 && rsiOk && volatilityOk) {
      signal = 'TRADE'; direction = 'LONG';
      confidence = Math.min(92, 55 + bullScore*8 + (strongMove?7:0));
      reasons = [
        bullMomentum ? `EMA5 (${ema5.toFixed(isForex?4:2)}) > EMA20 (${ema20.toFixed(isForex?4:2)}) — momentum haussier` : `Prix proche support`,
        priceAbovePivot ? `Prix au-dessus du pivot ${pivot.toFixed(isForex?4:2)}` : `RSI favorable`,
        `RSI ${rsi.toFixed(0)} — zone neutre`,
        `ATR ${atr.toFixed(isForex?4:1)} — volatilité acceptable`,
      ];
      const atrSl = atr * 0.8;
      sl  = +(price - atrSl).toFixed(isForex?5:2);
      tp1 = +(price + atr * 1.5).toFixed(isForex?5:2);
      tp2 = +(price + atr * 2.5).toFixed(isForex?5:2);
      const risk = 100000 * 0.02;
      const pipVal = isForex ? 10 : 100;
      lots = Math.max(0.01, +(risk / (Math.abs(price - sl) * pipVal * (isForex?10000:1))).toFixed(2));
    } else if (bearScore >= 3 && rsiOk && volatilityOk) {
      signal = 'TRADE'; direction = 'SHORT';
      confidence = Math.min(92, 55 + bearScore*8 + (strongMove?7:0));
      reasons = [
        !bullMomentum ? `EMA5 (${ema5.toFixed(isForex?4:2)}) < EMA20 (${ema20.toFixed(isForex?4:2)}) — momentum baissier` : `Prix proche résistance`,
        !priceAbovePivot ? `Prix en-dessous du pivot ${pivot.toFixed(isForex?4:2)}` : `RSI favorable`,
        `RSI ${rsi.toFixed(0)} — zone neutre`,
        `ATR ${atr.toFixed(isForex?4:1)} — volatilité acceptable`,
      ];
      const atrSl = atr * 0.8;
      sl  = +(price + atrSl).toFixed(isForex?5:2);
      tp1 = +(price - atr * 1.5).toFixed(isForex?5:2);
      tp2 = +(price - atr * 2.5).toFixed(isForex?5:2);
      const risk = 100000 * 0.02;
      const pipVal = isForex ? 10 : 100;
      lots = Math.max(0.01, +(risk / (Math.abs(price - sl) * pipVal * (isForex?10000:1))).toFixed(2));
    } else {
      reasons = [];
      if (!volatilityOk) reasons.push(`ATR ${atr.toFixed(isForex?4:1)} — volatilité ${atr<atrMin?"trop faible":"trop élevée"}`);
      if (rsi >= 78) reasons.push(`RSI ${rsi.toFixed(0)} — zone de surachat, risque de retournement`);
      if (rsi <= 30) reasons.push(`RSI ${rsi.toFixed(0)} — zone de survente, attendre confirmation`);
      if (!strongMove) reasons.push('Momentum insuffisant — pas de signal clair');
      if (!reasons.length) reasons.push('Signaux contradictoires — attendre une confirmation');
      confidence = Math.max(20, 50 - Math.abs(rsi - 52));
    }

    return res.json({
      signal, direction, confidence,
      price: +price.toFixed(isForex?5:2),
      rsi: +rsi.toFixed(1),
      atr: +atr.toFixed(isForex?5:2),
      pivot: +pivot.toFixed(isForex?5:2),
      r1: +r1.toFixed(isForex?5:2),
      s1: +s1.toFixed(isForex?5:2),
      ema5: +ema5.toFixed(isForex?5:2),
      ema20: +ema20.toFixed(isForex?5:2),
      sl, tp1, tp2, lots,
      reasons, ts: Date.now(), symbol,
    });
  } catch (e) {
    return res.status(503).json({ error: e.message });
  }
}
