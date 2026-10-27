export default function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'GET') return res.status(405).json({ error: 'Use GET.' });
  return res.status(200).json({ configured: !!process.env.MODEL_API_KEY, provider: 'Meta Model API', model: process.env.MODEL_ID || 'muse-spark-1.3' });
}
