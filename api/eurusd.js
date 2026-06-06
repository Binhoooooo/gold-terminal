export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 'no-store');

  try {
    const r = await fetch(
      'https://query1.finance.yahoo.com/v8/finance/chart/EURUSD=X?interval=1m&range=1d',
      { headers: { 'User-Agent': 'Mozilla/5.0' } }
    );
    const j = await r.json();
    const meta = j?.chart?.result?.[0]?.meta;
    if (!meta?.regularMarketPrice) throw new Error('no data');

    const price  = meta.regularMarketPrice;
    const prev   = meta.chartPreviousClose || price;
    const change = +(price - prev).toFixed(5);

    return res.json({
      price:  +price.toFixed(5),
      change,
      pct:    +(change / prev * 100).toFixed(3),
      high:   meta.regularMarketDayHigh || price,
      low:    meta.regularMarketDayLow  || price,
      open:   prev,
      source: 'yahoo',
      ts:     Date.now(),
    });
  } catch (e) {
    return res.status(503).json({ error: 'Feed unavailable' });
  }
}
