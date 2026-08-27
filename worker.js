const RAW = 'https://raw.githubusercontent.com/muqimjon/setup-ssh/main';

const HTML = `<!doctype html><meta charset=utf-8><title>setup-ssh.muqimjon.uz</title>
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:44rem;margin:5rem auto;padding:0 1.5rem;
background:#0d1117;color:#c9d1d9}h1{font-size:1.4rem}code{display:block;background:#161b22;
border:1px solid #30363d;border-radius:8px;padding:.9rem 1.1rem;margin:.6rem 0 1.6rem;
overflow-x:auto;white-space:pre;color:#79c0ff}p{color:#8b949e}</style>
<h1>SSH Setup</h1>
<p>Linux / macOS / Termux:</p><code>curl -fsSL https://setup-ssh.muqimjon.uz | bash</code>
<p>Windows (PowerShell, administrator):</p><code>irm https://setup-ssh.muqimjon.uz | iex</code>
<p>Kalit bilan:</p><code>curl -fsSL https://setup-ssh.muqimjon.uz | bash -s -- --key muqimjon</code>
<p>Ochiq kalitlar reyestri: <code style="display:inline;padding:.15rem .4rem">/keys/&lt;nom&gt;.pub</code></p>`;

// Tailscale API access token orqali BIR MARTALIK, KUTISH rejimidagi key yasaydi.
// Env (Worker secrets): TS_API_TOKEN, TS_TAILNET (masalan '-')
async function mintTsKey(env, tag) {
  // tag berilsa (masalan 'client') -> qurilma tag:client bilan qo'shiladi (ACL izolyatsiya).
  // tagsiz -> o'z qurilmang (to'liq kirish).
  const create = { reusable: false, ephemeral: false, preauthorized: !!tag };
  if (tag) create.tags = ['tag:' + tag];
  const tailnet = encodeURIComponent(env.TS_TAILNET || '-');
  const r = await fetch(`https://api.tailscale.com/api/v2/tailnet/${tailnet}/keys`, {
    method: 'POST',
    headers: { authorization: `Bearer ${env.TS_API_TOKEN}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      description: tag ? `setup-ssh ${tag}` : 'setup-ssh one-time',
      expirySeconds: 600, // 10 daqiqa
      capabilities: { devices: { create } },
    }),
  }).then((x) => x.json());
  if (!r.key) throw new Error('auth key yasalmadi: ' + JSON.stringify(r));
  return r.key;
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const ua = (req.headers.get('user-agent') || '').toLowerCase();
    const path = url.pathname.toLowerCase();

    // ---- bir martalik Tailscale kaliti ----
    if (path === '/ts-key') {
      if (!env.TS_API_TOKEN) return new Response('ts-key sozlanmagan\n', { status: 501 });
      let tag = url.searchParams.get('tag');
      if (tag && !/^[a-z0-9-]{1,32}$/.test(tag)) return new Response('# tag noto\'g\'ri\n', { status: 400 });
      try {
        const key = await mintTsKey(env, tag);
        return new Response(key + '\n', {
          headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' },
        });
      } catch (e) {
        return new Response('# ' + e.message + '\n', { status: 502 });
      }
    }

    // ---- ochiq kalitlar reyestri: /keys/muqimjon.pub ----
    if (path.startsWith('/keys/')) {
      if (!/^\/keys\/[a-z0-9._-]+\.pub$/.test(path)) return new Response('not found\n', { status: 404 });
      const r = await fetch(`${RAW}${path}`, { cf: { cacheTtl: 300 } });
      if (!r.ok) return new Response('not found\n', { status: 404 });
      return new Response(r.body, {
        headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'public, max-age=300' },
      });
    }

    // ---- o'rnatuvchi skript ----
    let file = null;
    if (path.endsWith('.ps1')) file = 'setup.ps1';
    else if (path.endsWith('.sh')) file = 'setup.sh';
    else if (/powershell|iwr|invoke-webrequest/.test(ua)) file = 'setup.ps1';
    else if (/curl|wget|libfetch|httpie/.test(ua)) file = 'setup.sh';

    if (!file) return new Response(HTML, { headers: { 'content-type': 'text/html; charset=utf-8' } });

    const r = await fetch(`${RAW}/${file}`, { cf: { cacheTtl: 60 } });
    if (!r.ok) return new Response(`# ${file} yuklanmadi (${r.status})\n`, { status: 502 });
    // Skript o'zini qaysi domendan olinganini bilsin (shaxsiy / kompaniya tailnet)
    const body = (await r.text()).replaceAll('__BASE__', url.origin);
    return new Response(body, {
      headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'public, max-age=60' },
    });
  },
};
