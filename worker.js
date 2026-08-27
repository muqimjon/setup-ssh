// setup-ssh Worker.
// Hech qanday statik ma'lumot yo'q - hammasi wrangler.toml [vars] / secrets orqali.
//
//   REPO          "foydalanuvchi/repo"  (majburiy)   - skriptlar va keys/ shu repodan
//   BRANCH        default "main"
//   TS_API_TOKEN  (secret, ixtiyoriy)   - /ts-key uchun Tailscale API tokeni
//   TS_TAILNET    default "-"
//   KEY_TTL       default 600           - bir martalik kalit muddati (soniya)

const rawBase = (env) => {
  if (!env.REPO) return null;
  return `https://raw.githubusercontent.com/${env.REPO}/${env.BRANCH || 'main'}`;
};

async function mintTsKey(env, tag) {
  // tag berilsa -> qurilma tag:<tag> bilan qo'shiladi (ACL izolyatsiya).
  // tagsiz -> user-identity qurilma (Device Approval yoqiq bo'lsa tasdiq kutadi).
  const create = { reusable: false, ephemeral: false, preauthorized: !!tag };
  if (tag) create.tags = ['tag:' + tag];
  const tailnet = encodeURIComponent(env.TS_TAILNET || '-');
  const r = await fetch(`https://api.tailscale.com/api/v2/tailnet/${tailnet}/keys`, {
    method: 'POST',
    headers: { authorization: `Bearer ${env.TS_API_TOKEN}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      description: tag ? `setup-ssh ${tag}` : 'setup-ssh',
      expirySeconds: Number(env.KEY_TTL || 600),
      capabilities: { devices: { create } },
    }),
  }).then((x) => x.json());
  if (!r.key) throw new Error('auth key yasalmadi: ' + JSON.stringify(r));
  return r.key;
}

const page = (origin) => `<!doctype html><meta charset=utf-8><title>setup-ssh</title>
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:44rem;margin:5rem auto;padding:0 1.5rem;
background:#0d1117;color:#c9d1d9}h1{font-size:1.4rem}code{display:block;background:#161b22;
border:1px solid #30363d;border-radius:8px;padding:.9rem 1.1rem;margin:.6rem 0 1.6rem;
overflow-x:auto;white-space:pre;color:#79c0ff}p{color:#8b949e}</style>
<h1>SSH Setup</h1>
<p>Linux / macOS / Termux:</p><code>curl -fsSL ${origin} | bash</code>
<p>Windows (PowerShell, administrator):</p><code>irm ${origin} | iex</code>
<p>Kalit bilan:</p><code>curl -fsSL ${origin} | bash -s -- --key &lt;nom&gt;</code>
<p>Ochiq kalitlar reyestri: <code style="display:inline;padding:.15rem .4rem">${origin}/keys/&lt;nom&gt;.pub</code></p>`;

const txt = (body, extra = {}) =>
  new Response(body, { headers: { 'content-type': 'text/plain; charset=utf-8', ...extra } });

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const ua = (req.headers.get('user-agent') || '').toLowerCase();
    const path = url.pathname.toLowerCase();
    const RAW = rawBase(env);

    // ---- bir martalik Tailscale kaliti ----
    if (path === '/ts-key') {
      if (!env.TS_API_TOKEN) return txt('ts-key sozlanmagan\n', { status: 501 });
      const tag = url.searchParams.get('tag');
      if (tag && !/^[a-z0-9-]{1,32}$/.test(tag)) return txt("# tag noto'g'ri\n", { status: 400 });
      try {
        return txt((await mintTsKey(env, tag)) + '\n', { 'cache-control': 'no-store' });
      } catch (e) {
        return new Response('# ' + e.message + '\n', { status: 502 });
      }
    }

    if (!RAW) return txt('# REPO sozlanmagan (wrangler.toml [vars] REPO)\n', { status: 501 });

    // ---- ochiq kalitlar reyestri: /keys/<nom>.pub ----
    if (path.startsWith('/keys/')) {
      if (!/^\/keys\/[a-z0-9._-]+\.pub$/.test(path)) return txt('not found\n', { status: 404 });
      const r = await fetch(`${RAW}${path}`, { cf: { cacheTtl: 300 } });
      if (!r.ok) return txt('not found\n', { status: 404 });
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

    if (!file) {
      return new Response(page(url.origin), { headers: { 'content-type': 'text/html; charset=utf-8' } });
    }

    const r = await fetch(`${RAW}/${file}`, { cf: { cacheTtl: 60 } });
    if (!r.ok) return txt(`# ${file} yuklanmadi (${r.status})\n`, { status: 502 });
    // Skript qaysi domendan olinganini bilsin (ko'p-tenant: har domen o'z tailneti)
    const body = (await r.text()).replaceAll('__BASE__', url.origin);
    return txt(body, { 'cache-control': 'public, max-age=60' });
  },
};
