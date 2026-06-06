export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 'no-store');

  try {
    // Yahoo Finance — pas de clé requise
    const r = await fetch(
      'https://query1.finance.yahoo.com/v8/finance/chart/GC=F?interval=1m&range=1d',
      { headers: { 'User-Agent': 'Mozilla/5.0' } }
    );
    const j = await r.json();
    const meta = j?.chart?.result?.[0]?.meta;
    if (!meta?.regularMarketPrice) throw new Error('no data');

    const price  = meta.regularMarketPrice;
    const prev   = meta.chartPreviousClose || price;
    const change = +(price - prev).toFixed(2);

    return res.json({
      price:  +price.toFixed(2),
      change,
      pct:    +(change / prev * 100).toFixed(3),
      high:   meta.regularMarketDayHigh || price,
      low:    meta.regularMarketDayLow  || price,
      open:   prev,
      source: 'yahoo',
      ts:     Date.now(),
    });
  } catch (e) {
    // Fallback metals.live
    try {
      const r2 = await fetch('https://api.metals.live/v1/spot/gold');
      const j2 = await r2.json();
      const price = j2[0]?.gold;
      if (price && price > 1000) {
        return res.json({ price: +price.toFixed(2), change: 0, pct: 0, high: price, low: price, open: price, source: 'metals.live', ts: Date.now() });
      }
    } catch (_) {}

    return res.status(503).json({ error: 'Price feed unavailable' });
  }
}
