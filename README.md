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
| `DEFAULT_KEY` | var | `--key` berilmasa shu ishlatiladi |
| `DEFAULT_MODE` | var | `--mode` berilmasa savol o'rniga shu |
| `DEFAULT_USER` | var | shu nomli admin/sudo hisobi ochiladi, kirish doim shu nom bilan |

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

Manzil bitta — qaysi skript kerakligini o'zi aniqlaydi. Quyida har bir muhit uchun tayyor buyruq.

### Windows

Deyarli hamma holatda **Administrator** kerak.

**PowerShell / Windows Terminal / PowerShell 7** — eng qisqa yo'l:
```powershell
irm <manzil> | iex
```

**cmd.exe** — `irm | iex` bu yerda ishlamaydi, cmd'da PowerShell chaqiriladi:
```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (irm <manzil>)"
```

> `|` o'rniga `iex (irm ...)` yozilgani bejiz emas: cmd qo'shtirnoq ichidagi `|` ni
> o'zining quvuri deb qabul qilib buyruqni buzadi. Qavsli shakl hamma joyda ishlaydi.

**Admin emas cmd yoki Win+R** — o'zi Administrator so'raydi (UAC oynasi chiqadi):
```bat
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command \"iex (irm <manzil>)\"'"
```

**curl bilan (cmd yoki PowerShell)** — `/setup.ps1` yo'lini **aniq** yozish shart:
```bat
curl -fsSL -o "%TEMP%\s.ps1" <manzil>/setup.ps1 && powershell -ExecutionPolicy Bypass -File "%TEMP%\s.ps1"
```

**Parametr bilan** — `irm | iex` parametr qabul qilmaydi, shuning uchun:
```powershell
& ([scriptblock]::Create((irm <manzil>/setup.ps1))) -Mode all -Key gh:username
```

### Linux / macOS / Termux

```bash
curl -fsSL <manzil> | bash
```

`curl` yo'q bo'lsa:
```bash
wget -qO- <manzil> | bash
```

Parametr bilan:
```bash
curl -fsSL <manzil> | bash -s -- --mode all --key gh:username
```

> Qobiq **zsh, fish, dash** bo'lsa ham buyruq o'zgarmaydi — skript `bash` ga
> uzatiladi, qobiqning o'zi emas. `| sh` deb yozmang: skriptda bash massivlari bor.

### Manzil qaysi skriptni beradi?

Yo'l ko'rsatilmasa Worker `User-Agent` ga qarab tanlaydi:

| So'rov | Natija |
|---|---|
| `curl` / `wget` bilan `<manzil>` | `setup.sh` (bash) |
| PowerShell (`irm`/`iwr`) bilan `<manzil>` | `setup.ps1` |
| Brauzer bilan `<manzil>` | qisqa yo'riqnoma sahifasi |
| `<manzil>/setup.sh` | doim bash skripti |
| `<manzil>/setup.ps1` | doim PowerShell skripti |

**Tuzoq:** Windows'da `curl` ishlatsangiz, `<manzil>` sizga **bash** skriptini
beradi — chunki User-Agent `curl`. Shuning uchun Windows'da curl bilan doim
`<manzil>/setup.ps1` deb yozing.

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
| `--user` / `-SshUser` | boshqaruv hisobi nomi (`DEFAULT_USER` ni bekor qiladi) |
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

## Boshqaruv hisobi (`DEFAULT_USER`)

`DEFAULT_USER` sozlangan bo'lsa, skript mijoz qurilmasida **o'sha nomli alohida
hisob** ochadi va kalitlarni o'shanga joylaydi. Ulanish doim bir xil bo'ladi:

```bash
ssh ovoza@<IP>
```

Mijozning Windows/Linux useri nima ekanini bilish, so'rash yoki eslab qolish shart emas.

| | Windows | Linux |
|---|---|---|
| Hisob | `Administrators` guruhida | `sudo`/`wheel` + `NOPASSWD` |
| Huquq | to'liq admin (elevated token) | `sudo` bilan to'liq root |
| Parol | tasodifiy, hech qayerda saqlanmaydi | qulflangan (`passwd -l`) |
| Kirish | faqat ochiq kalit bilan | faqat ochiq kalit bilan |
| Kalit fayli | `administrators_authorized_keys` | `~ovoza/.ssh/authorized_keys` |

Sozlanmasa — eski xatti-harakat: skriptni ishga tushirgan foydalanuvchi nomi bilan kiriladi.

### Bilib qo'yish kerak

- **Standart qobiq — PowerShell.** Skript `HKLM:\SOFTWARE\OpenSSH\DefaultShell`
  ni PowerShell qilib qo'yadi, aks holda SSH sizni `cmd.exe` ga tashlaydi.
- **Tarmoq resurslari ishlamaydi ("double-hop").** Kalit bilan kirilgan SSH
  sessiyasida tarmoq credentiali bo'lmaydi, shuning uchun sessiya ichidan
  `\server\share` yoki boshqa mashinaga kirib bo'lmaydi. Lokal ishlarga
  (loglar, xizmatlar, fayllar, registry) ta'sir qilmaydi. Bu Windows'ning
  Kerberos dizayni — hisob nomiga bog'liq emas.
- **Tailscale qurilma nomida mijozning haqiqiy useri turadi:**
  `nout-plus-win-rge54s2vpdd`. Ulanish uchun kerak emas, lekin admin konsolda
  qaysi qurilma kimniki ekani darrov ko'rinadi.

### Bekor qilish

Xodim ketsa — `keys/<nom>.pub` dan qatorini o'chirib, skriptni qayta ishlating.
Hisobning o'zini butunlay olib tashlash:

```powershell
Remove-LocalUser ovoza                                        # Windows
```
```bash
sudo userdel -r ovoza && sudo rm -f /etc/sudoers.d/ovoza      # Linux
```

Hisob kirish oynasida ko'rinmasin desangiz (Windows, ixtiyoriy):

```powershell
$k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
New-Item $k -Force | Out-Null
New-ItemProperty $k -Name ovoza -Value 0 -PropertyType DWord -Force
```

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
