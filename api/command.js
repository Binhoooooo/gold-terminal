// Stockage en mémoire (persiste entre les requêtes sur la même instance Vercel)
let pendingTrade = null;
let pendingTs = 0;
const TTL = 120000; // 2 minutes

export default function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 'no-store');

  // POST → crée une commande de trade manuel
  if (req.method === 'POST') {
    const dir = req.query.dir || req.body?.dir;
    if (dir !== 'LONG' && dir !== 'SHORT') {
      return res.status(400).json({ error: 'dir must be LONG or SHORT' });
    }
    pendingTrade = dir;
    pendingTs = Date.now();
    return res.json({ ok: true, trade: pendingTrade, ts: pendingTs });
  }

  // DELETE → efface la commande (après exécution par l'EA)
  if (req.method === 'DELETE') {
    pendingTrade = null;
    pendingTs = 0;
    return res.json({ ok: true, cleared: true });
  }

  // GET → retourne la commande si encore fraîche (< 2min)
  if (pendingTrade && (Date.now() - pendingTs) < TTL) {
    return res.json({ trade: pendingTrade, ts: pendingTs, age: Date.now() - pendingTs });
  }

  return res.json({ trade: null });
}
