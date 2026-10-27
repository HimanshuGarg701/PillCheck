import http from 'node:http';
import { createServer } from 'vite';
import ai from '../api/ai.js';
import status from '../api/status.js';
const vite = await createServer({ server: { middlewareMode: true } });
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (!['/api/ai','/api/status'].includes(url.pathname)) return vite.middlewares(req, res);
  res.status = code => { res.statusCode = code; return res; };
  res.json = data => { res.setHeader('Content-Type','application/json'); res.end(JSON.stringify(data)); };
  if (url.pathname === '/api/status') return status(req, res);
  let size = 0; const chunks = [];
  for await (const chunk of req) { size += chunk.length; if (size > 3700000) return res.status(413).json({ error:'The image is too large.' }); chunks.push(chunk); }
  req.body = Buffer.concat(chunks).toString('utf8');
  await ai(req, res);
});
server.listen(5173,'127.0.0.1', () => console.log('PillCheck: http://127.0.0.1:5173'));
process.on('SIGINT', async () => { await vite.close(); server.close(); });
