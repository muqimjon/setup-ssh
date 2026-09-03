// setup-ssh Worker - to'liq generic, kodda statik ma'lumot yo'q.
// Skriptlar deploy paytida shu Worker ichiga bog'lanadi (repoga bog'liq emas).
//
// Sozlamalar (wrangler.toml [vars] / secrets) - hammasi IXTIYORIY:
//   TS_API_TOKEN  (secret)  Tailscale API tokeni -> /ts-key ishlaydi. Yo'q bo'lsa 501.
//   TS_TAILNET    default "-"
//   KEY_TTL       default 600   bir martalik kalit muddati (soniya)
//   KEYS_REPO     "user/repo"   -> /keys/<nom>.pub shu repodan. Yo'q bo'lsa /keys 404.
//   KEYS_BRANCH   default "main"
//   DEFAULT_KEY   "nom"  -> --key berilmasa shu ishlatiladi (qo'shimcha --key lar ustiga qo'shiladi)
//   DEFAULT_MODE  "lan" | "tailscale" | "all" -> --mode berilmasa savol o'rniga shu
//   DEFAULT_USER  "nom"  -> shu nomli admin/sudo hisobi ochiladi, kirish doim shu nom bilan
import setupSh from './setup.sh';
import setupPs1 from './setup.ps1';

async function mintTsKey(env, tag) {
  // tag berilsa -> qurilma tag:<tag> bilan qo'shiladi (ACL izolyatsiya, preauthorized).
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

const page = (o) => `<!doctype html><meta charset=utf-8><title>setup-ssh</title>
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:44rem;margin:5rem auto;padding:0 1.5rem;
background:#0d1117;color:#c9d1d9}h1{font-size:1.4rem}code{display:block;background:#161b22;
border:1px solid #30363d;border-radius:8px;padding:.9rem 1.1rem;margin:.6rem 0 1.6rem;
overflow-x:auto;white-space:pre;color:#79c0ff}p{color:#8b949e}</style>
<h1>SSH Setup</h1>
<p>Linux / macOS / Termux:</p><code>curl -fsSL ${o} | bash</code>
<p>Windows (PowerShell, administrator):</p><code>irm ${o} | iex</code>
<p>Ochiq kalit bilan:</p><code>curl -fsSL ${o} | bash -s -- --key gh:&lt;github-user&gt;</code>`;

const txt = (b, h = {}, status = 200) =>
  new Response(b, { status, headers: { 'content-type': 'text/plain; charset=utf-8', ...h } });

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const ua = (req.headers.get('user-agent') || '').toLowerCase();
    const path = url.pathname.toLowerCase();

    // ---- bir martalik Tailscale kaliti ----
    if (path === '/ts-key') {
      if (!env.TS_API_TOKEN) return txt('# ts-key sozlanmagan (TS_API_TOKEN yo\'q)\n', {}, 501);
      const tag = url.searchParams.get('tag');
      if (tag && !/^[a-z0-9-]{1,32}$/.test(tag)) return txt("# tag noto'g'ri\n", {}, 400);
      try {
        return txt((await mintTsKey(env, tag)) + '\n', { 'cache-control': 'no-store' });
      } catch (e) {
        return txt('# ' + e.message + '\n', {}, 502);
      }
    }

    // ---- ochiq kalitlar reyestri (ixtiyoriy) ----
    if (path.startsWith('/keys/')) {
      if (!env.KEYS_REPO) return txt('# keys reyestri sozlanmagan (KEYS_REPO yo\'q)\n', {}, 501);
      if (!/^\/keys\/[a-z0-9._-]+\.pub$/.test(path)) return txt('not found\n', {}, 404);
      const raw = `https://raw.githubusercontent.com/${env.KEYS_REPO}/${env.KEYS_BRANCH || 'main'}`;
      const r = await fetch(`${raw}${path}`, { cf: { cacheTtl: 300 } });
      if (!r.ok) return txt('not found\n', {}, 404);
      return new Response(r.body, {
        headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'public, max-age=300' },
      });
    }

    // ---- o'rnatuvchi skript (Worker ichiga bog'langan) ----
    let body = null;
    if (path.endsWith('.ps1')) body = setupPs1;
    else if (path.endsWith('.sh')) body = setupSh;
    else if (/powershell|iwr|invoke-webrequest/.test(ua)) body = setupPs1;
    else if (/curl|wget|libfetch|httpie/.test(ua)) body = setupSh;

    if (body === null) {
      return new Response(page(url.origin), { headers: { 'content-type': 'text/html; charset=utf-8' } });
    }
    // Skript qaysi domendan olinganini bilsin (ko'p-tenant: har domen o'z tailneti)
    return txt(
      body
        .replaceAll('__BASE__', url.origin)
        .replaceAll('__DEFAULT_KEY__', env.DEFAULT_KEY || '')
        .replaceAll('__DEFAULT_MODE__', env.DEFAULT_MODE || '')
        .replaceAll('__DEFAULT_USER__', env.DEFAULT_USER || ''),
      { 'cache-control': 'public, max-age=60' },
    );
  },
};
