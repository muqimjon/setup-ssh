# setup-ssh

Bitta buyruq bilan istalgan kompyuterni SSH orqali boshqariladigan qiladi.
OS'ni (Windows / Linux / macOS / Termux), paket menejerini va qobiqni o'zi aniqlaydi.
Ixtiyoriy: Tailscale bilan istalgan joydan ulanish.

**Kodda statik ma'lumot yo'q** — domen, repo, token: hammasi sozlamadan keladi.

## O'zingizga deploy qilish

```bash
git clone <bu-repo> && cd setup-ssh
npx wrangler deploy
npx wrangler secret put TS_API_TOKEN     # Tailscale API tokeni
```

Tayyor: `https://setup-ssh.<akkauntingiz>.workers.dev`

Kodga tegish shart emas. Skriptlar Worker ichiga bog'lanadi — repo public bo'lishi ham shart emas.

### Sozlamalar (hammasi ixtiyoriy)

| Nom | Turi | Ma'nosi |
|---|---|---|
| `TS_API_TOKEN` | secret | Tailscale API tokeni → `/ts-key` ishlaydi. Yo'q bo'lsa 501 |
| `TS_TAILNET` | var | default `-` |
| `KEY_TTL` | var | bir martalik kalit muddati, soniya (default 600) |
| `KEYS_REPO` | var | `user/repo` → `/keys/<nom>.pub` reyestri. Yo'q bo'lsa `/keys` 501 |
| `KEYS_BRANCH` | var | default `main` |

Amalda **bitta** narsa yetarli: `TS_API_TOKEN`. Ochiq kalitlarni `gh:<github-user>`,
URL yoki matn ko'rinishida bergani uchun `KEYS_REPO` ham majburiy emas.

### O'z domeningiz (ixtiyoriy)

`wrangler.toml` da `[env.<nom>]` bloki qo'shing:

```toml
[env.prod]
name = "setup-ssh"
routes = [{ pattern = "ssh.example.com", custom_domain = true }]
```
```bash
npx wrangler deploy --env prod
npx wrangler secret put TS_API_TOKEN --env prod
```

## Ishlatish

**Linux / macOS / Termux**
```bash
curl -fsSL <sizning-manzil> | bash
```

**Windows** — PowerShell, *Run as administrator*
```powershell
irm <sizning-manzil> | iex
```

`irm | iex` parametr qabul qilmaydi — parametr kerak bo'lsa:
```powershell
& ([scriptblock]::Create((irm <manzil>/setup.ps1))) -Key gh:username
```
```bash
curl -fsSL <manzil> | bash -s -- --key gh:username
```

### Ochiq kalit manbalari

| Yozuv | Manba |
|---|---|
| `gh:username` | `github.com/username.keys` |
| `https://...` | istalgan URL (bir yoki ko'p qatorli) |
| `ssh-ed25519 AAAA...` | to'g'ridan matn |
| `nom` | `<manzil>/keys/nom.pub` (`KEYS_REPO` sozlangan bo'lsa) |

Bir nechta: `--key a b c` (bash) / `-Key a,b,c` (PowerShell).

### Bayroqlar

| Parametr | Ma'nosi |
|---|---|
| `--yes` / `-y` / `-Yes` | savol bermaydi |
| `--mode` / `-Mode` | `lan` | `tailscale` | `all` — bir nechta: `--mode lan tailscale` |
| `--key` / `-Key` | joylanadigan ochiq kalit(lar) |
| `--no-key` / `-NoKey` | kalit joylamaydi |
| `--port` / `-Port` | SSH porti (default 22, Termux 8022) |
| `--disable-password` / `--keep-password` | parolni majburan o'chirish / qoldirish (default: kalit bo'lsa o'chadi) |
| `--ts-key` / `-TailscaleAuthKey` | o'z Tailscale auth key'ingiz |
| `--ts-tag` / `-TsTag` | qurilma tegi (default `client`) |
| `--member` / `-Member` | teglanmagan (member) qo'shilish — tasdiq kutadi |
| `--base` / `-Base` | manba manzili (Worker'siz ishlatilganda) |

### Default javoblar (faqat Enter)

| Savol | Default | Nega |
|---|---|---|
| Qayerdan kirasan | Faqat LAN | eng kam ochiqlik |
| Kim kira oladi | Faqat parol | begona kalit taklif qilinmaydi |
| Parol bilan kirish | kalit joylansa **o'chadi** | kalit ishlagach parol keraksiz |

Parolni o'chirish oxirida alohida buyruq bilan beriladi — kalit ishlaganini
tekshirgandan keyin.

## Tailscale: kim kimga ulanadi

`/ts-key` bir martalik kalit beradi:

- **`?tag=client`** (skript defaulti) — qurilma `tag:client` bilan qo'shiladi
- **tegsiz** (`--member`) — user-identity, Device Approval yoqiq bo'lsa tasdiq kutadi

Asimmetrik kirish uchun tailnet ACL:

```json
{
  "tagOwners": { "tag:client": ["autogroup:admin"] },
  "grants": [ {"src": ["autogroup:member"], "dst": ["*"], "ip": ["*"]} ]
}
```

Natija: siz mijoz qurilmalariga kirasiz, ular sizning qurilmalaringizni ko'rmaydi.

## Ochiq kalitlar reyestri

`KEYS_REPO` sozlangan bo'lsa, `keys/<nom>.pub` — **ko'p qatorli** ro'yxat:

```
ssh-ed25519 AAAA... ali@ovoza
ssh-ed25519 BBB... vali@ovoza
```

`--key <nom>` desangiz hammasi joylanadi. Xodim ketsa — qatorini o'chirib,
skriptni qayta ishga tushirasiz.

> Yopiq kalitni hech qachon tarqatmang. Har kishi o'z kalitini yasaydi,
> faqat ochiq qismi ro'yxatga tushadi — shunda bekor qilish va audit ishlaydi.
