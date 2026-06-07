import { readFileSync } from 'fs';
import { join } from 'path';

export default function handler(req, res) {
  try {
    const file = readFileSync(join(process.cwd(), 'GoldTerminalEA.mq4'), 'utf8');
    res.setHeader('Content-Type', 'application/octet-stream');
    res.setHeader('Content-Disposition', 'attachment; filename="GoldTerminalEA.mq4"');
    res.send(file);
  } catch (e) {
    res.status(500).json({ error: 'File not found' });
  }
}
