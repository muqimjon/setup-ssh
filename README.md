# ssh-setup

Bitta buyruq bilan istalgan kompyuterni SSH orqali boshqariladigan qiladi.
Operatsion tizimni (Windows / Linux / macOS / Termux), paket menejerini va qobiqni
o'zi aniqlaydi, keyin qadamma-qadam so'raydi.

## Ishlatish

**Linux / macOS / Termux**
```bash
curl -fsSL https://setup-ssh.muqimjon.uz | bash
```

**Windows** — PowerShell, *Run as administrator*
```powershell
irm https://setup-ssh.muqimjon.uz | iex
```

**Windows cmd**
```cmd
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://setup-ssh.muqimjon.uz | iex"
```

## Kalit bilan (parametr orqali)

`irm | iex` parametr qabul qilmaydi — skript blokiga o'rab beriladi:

```powershell
& ([scriptblock]::Create((irm https://setup-ssh.muqimjon.uz/setup.ps1))) -Key muqimjon,telefon
```
```bash
curl -fsSL https://setup-ssh.muqimjon.uz | bash -s -- --key muqimjon telefon ish-pc
```

`--key` / `-Key` to'rt xil qiymatni tushunadi:

| Yozuv | Manba |
|---|---|
| `muqimjon` | `setup-ssh.muqimjon.uz/keys/muqimjon.pub` |
| `gh:muqimjon` | `github.com/muqimjon.keys` |
| `https://...` | istalgan URL |
| `ssh-ed25519 AAAA...` | to'g'ridan-to'g'ri matn |

## Bayroqlar

| Parametr | Ma'nosi |
|---|---|
| `--yes` / `-Yes` | savol bermaydi, default javob |
| `--mode` / `-Mode` | `lan` \| `tailscale` \| `tailscale-only` |
| `--key` / `-Key` | joylanadigan kalit(lar) |
| `--no-key` / `-NoKey` | kalit joylamaydi |
| `--port` / `-Port` | SSH porti (default 22, Termux 8022) |
| `--disable-password` / `-DisablePassword` | parol bilan kirishni o'chiradi |
| `--ts-key` / `-TailscaleAuthKey` | Tailscale auth key |

## Default javoblar (faqat Enter)

| Savol | Default | Nega |
|---|---|---|
| Qayerdan kirasan | **Faqat LAN** | eng kam ochiqlik |
| Kim kira oladi | **Faqat parol** | begona kalit taklif qilinmaydi |

Parolni o'chirish oxirida alohida buyruq bilan beriladi — kalit ishlaganini
tekshirgandan keyin.

## Tailscale bir martalik kalit

`--mode tailscale` da kalit berilmasa, skript `setup-ssh.muqimjon.uz/ts-key`
dan **bir martalik, kutish rejimidagi** auth key oladi (Worker OAuth orqali yasaydi).
Qurilma tailnetga *pending* holatda qo'shiladi — admin panelda tasdiqlanadi.

Worker sozlanmagan bo'lsa `/ts-key` 501 qaytaradi va skript brauzer login'ga o'tadi.

### Worker secretlari

```
wrangler secret put TS_OAUTH_CLIENT_ID
wrangler secret put TS_OAUTH_SECRET
wrangler secret put TS_TAILNET
```

Tailscale admin da:
- OAuth client — scope `auth_keys: write`, tag `tag:setup`
- ACL: `"tagOwners": { "tag:setup": ["autogroup:admin"] }`
- Settings → Device management → **Device approval: ON**

## Deploy

```bash
npx wrangler deploy
```

CI/CD: `main` ga push qilinganda `.github/workflows/deploy.yml` avtomat deploy qiladi
(GitHub secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`).
