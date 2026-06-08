import { readFileSync, writeFileSync } from 'fs';
import { join } from 'path';

const FILE = join('/tmp', 'gt_command.json');
const TTL  = 120000; // 2 minutes

function load() {
  try { return JSON.parse(readFileSync(FILE, 'utf8')); } catch { return { trade: null, ts: 0 }; }
}
function save(data) {
  try { writeFileSync(FILE, JSON.stringify(data)); } catch {}
}

export default function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 'no-store');

  if (req.method === 'POST') {
    const dir = req.query.dir || req.body?.dir;
    if (dir !== 'LONG' && dir !== 'SHORT')
      return res.status(400).json({ error: 'dir must be LONG or SHORT' });
    const data = { trade: dir, ts: Date.now() };
    save(data);
    return res.json({ ok: true, ...data });
  }

  if (req.method === 'DELETE') {
    save({ trade: null, ts: 0 });
    return res.json({ ok: true, cleared: true });
  }

  // GET
  const data = load();
  if (data.trade && (Date.now() - data.ts) < TTL)
    return res.json({ trade: data.trade, ts: data.ts, age: Date.now() - data.ts });

  return res.json({ trade: null });
}
