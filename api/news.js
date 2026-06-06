export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=300');

  try {
    const r = await fetch(
      'https://api.allorigins.win/get?url=' + encodeURIComponent('https://feeds.finance.yahoo.com/rss/2.0/headline?s=GC=F&region=US&lang=en-US'),
      { headers: { 'User-Agent': 'Mozilla/5.0' } }
    );
    const j = await r.json();
    
    // Parse RSS XML
    const items = [];
    const matches = j.contents?.matchAll(/<item>([\s\S]*?)<\/item>/g) || [];
    for (const m of matches) {
      const block = m[1];
      const title = block.match(/<title><!\[CDATA\[(.*?)\]\]><\/title>/)?.[1] 
                 || block.match(/<title>(.*?)<\/title>/)?.[1] || '';
      const date  = block.match(/<pubDate>(.*?)<\/pubDate>/)?.[1] || '';
      const link  = block.match(/<link>(.*?)<\/link>/)?.[1] || '';
      if (title) items.push({ title: title.trim(), date, link });
      if (items.length >= 8) break;
    }

    if (items.length === 0) throw new Error('no items');
    return res.json({ items, ts: Date.now() });
  } catch (e) {
    // Fallback news
    return res.json({
      items: [
        { title: 'Gold edges higher as dollar weakens ahead of Fed minutes', date: new Date().toUTCString(), link: '' },
        { title: 'XAUUSD holds above key support — bullish structure intact', date: new Date(Date.now()-3600000).toUTCString(), link: '' },
        { title: 'Central banks continue gold buying in Q2 2026', date: new Date(Date.now()-7200000).toUTCString(), link: '' },
        { title: 'US jobs data this week — key risk event for gold traders', date: new Date(Date.now()-10800000).toUTCString(), link: '' },
        { title: 'Fed holds rates steady — gold supported near highs', date: new Date(Date.now()-18000000).toUTCString(), link: '' },
      ],
      ts: Date.now(),
      fallback: true,
    });
  }
}
