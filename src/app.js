import './style.css';
const app = document.querySelector('#app');
app.innerHTML = `<main class="setup"><a class="brand" href="./"><span class="brand-icon">✓</span> PillCheck</a><p class="eyebrow">PROJECT SETUP</p><h1>A little more<br>peace of mind.</h1><p class="lede">A medication schedule companion for older adults and the people who care for them.</p><section class="setup-card"><h2>Connecting the essentials</h2><p>This is the infrastructure verification page. The medication workflows are under construction.</p><div class="setup-row"><span>Public source repository</span><a href="https://github.com/HimanshuGarg701/PillCheck" target="_blank" rel="noreferrer">View GitHub ↗</a></div><div class="setup-row"><span>Server configuration</span><strong id="config-state">Checking…</strong></div><div class="setup-row"><span>Model</span><strong id="model-state">Muse Spark 1.3</strong></div><button id="verify" class="primary" disabled>Verify live Meta connection</button><p id="result" role="status" aria-live="polite">The credential stays on the server. This test sends only a short synthetic connection request.</p></section><p class="disclaimer">Informational only, not medical advice. Confirm with your doctor or pharmacist.</p><footer>Indie Developer · Build for Your World</footer></main>`;
async function configure() {
  try {
    const response = await fetch('/api/status');
    if (!response.ok) throw new Error('Server status could not be loaded.');
    const data = await response.json();
    document.querySelector('#config-state').textContent = data.configured ? 'Credential configured' : 'Credential needed';
    document.querySelector('#model-state').textContent = data.model;
    document.querySelector('#verify').disabled = !data.configured;
  } catch (error) { document.querySelector('#config-state').textContent = 'Not connected'; document.querySelector('#result').textContent = error.message; }
}
document.querySelector('#verify').addEventListener('click', async event => {
  event.target.disabled = true; document.querySelector('#result').textContent = 'Calling Meta Model API through the PillCheck server…';
  try {
    const response = await fetch('/api/ai', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({task:'connection'}) });
    const data = await response.json(); if (!response.ok) throw new Error(data.error || 'Connection failed.');
    document.querySelector('#result').textContent = `${data.message} Model: ${data.model}. Live request: ${data.requestId || 'completed'}.`;
    document.querySelector('#config-state').textContent = 'Live connection verified';
  } catch (error) { document.querySelector('#result').textContent = error.message; }
  finally { event.target.disabled = false; }
});
configure();
