import { runTask, RequestError } from './meta.mjs';

// Per-instance burst limiting. Production-wide quotas must also be configured at the provider/WAF.
const calls = new Map();
export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ error: 'Use POST.' }); }
  const origin = req.headers.origin;
  if (origin) {
    try { if (new URL(origin).host !== req.headers.host) return res.status(403).json({ error: 'Cross-origin requests are not allowed.' }); } catch { return res.status(403).json({ error: 'Invalid origin.' }); }
  }
  if (!String(req.headers['content-type'] || '').includes('application/json')) return res.status(415).json({ error: 'Use application/json.' });
  if (Number(req.headers['content-length']) > 3700000) return res.status(413).json({ error: 'The label image is too large.' });
  const id = req.headers['x-forwarded-for']?.split(',')[0] || req.socket?.remoteAddress || 'local';
  const now = Date.now(); for (const [key,value] of calls) if (now - value.start > 60000) calls.delete(key);
  const bucket = calls.get(id) || { start: now, count: 0 }; bucket.count++; calls.set(id, bucket);
  if (bucket.count > 15) { res.setHeader('Retry-After','60'); return res.status(429).json({ error: 'Please wait a minute before more AI requests.' }); }
  try {
    let body = req.body;
    if (typeof body === 'string') { if (body.length > 3700000) throw new RequestError('The image is too large.',413); try { body = JSON.parse(body); } catch { throw new RequestError('Invalid JSON.'); } }
    return res.status(200).json(await runTask(body));
  } catch (err) {
    return res.status(err instanceof RequestError ? err.status : 502).json({ error: err instanceof RequestError ? err.message : 'The AI request timed out or could not complete. Please retry; no schedule was changed.' });
  }
}
