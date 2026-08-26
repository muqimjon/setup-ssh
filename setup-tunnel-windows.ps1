#Requires -RunAsAdministrator
<#
    Windows kompyuterni Cloudflare Tunnel orqali GLOBAL SSH ga ulanadigan qiladi.
    Router sozlanmaydi, port ochilmaydi, statik IP kerak emas.

    Foydalanish:
        .\setup-tunnel-windows.ps1 -Hostname ssh.mijoz.uz -PublicKey "ssh-ed25519 AAAA..."

    Shart: domen Cloudflare da (nameserverlar Cloudflare ga qaratilgan).
#>
param(
    [Parameter(Mandatory)][string]$Hostname,
    [string]$PublicKey = "",
    [string]$TunnelName = ""
)

$ErrorActionPreference = 'Stop'
function Step($m) { Write-Host "`n>> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "   OK: $m" -ForegroundColor Green }
function Die($m)  { Write-Host "`n   XATO: $m" -ForegroundColor Red; exit 1 }

if (-not $TunnelName) { $TunnelName = ($env:COMPUTERNAME).ToLower() }

Step "0/6 Mavjud cloudflared xizmatini tekshirish"
$svc = Get-Service cloudflared -ErrorAction SilentlyContinue
if ($svc) {
    Die @"
Bu kompyuterda cloudflared xizmati ALLAQACHON ishlayapti.
Ikkinchi tunnel o'rnatish uni buzadi.

Buning o'rniga mavjud tunnelga hostname qo'sh:
  Cloudflare dashboard -> Zero Trust -> Networks -> Tunnels
  -> tunnelni tanla -> Public Hostname -> Add
     Subdomain: $($Hostname.Split('.')[0])
     Type: SSH        URL: localhost:22
"@
}
Ok "mavjud xizmat yo'q, davom etamiz"

Step "1/6 SSH server"
$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
Set-Service sshd -StartupType Automatic
if ((Get-Service sshd).Status -ne 'Running') { Start-Service sshd }
Ok "sshd ishlayapti (localhost:22)"

Step "2/6 Ochiq kalitni joylash"
if (-not $PublicKey) { Write-Host "   ! kalit berilmadi - parol bilan kiriladi" -ForegroundColor Yellow }
else {
    $file = "$env:ProgramData\ssh\administrators_authorized_keys"
    $body = $PublicKey.Split(' ')[1]
    $cur  = if (Test-Path $file) { Get-Content $file -Raw } else { "" }
    if ($cur -notmatch [regex]::Escape($body)) { Add-Content $file $PublicKey -Encoding utf8 }
    icacls $file /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
    Ok "kalit administrators_authorized_keys ga yozildi"
}

Step "3/6 cloudflared o'rnatish"
if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
    winget install --id Cloudflare.cloudflared --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine')
}
Ok (cloudflared --version)

Step "4/6 Cloudflare hisobiga kirish"
$cert = "$env:USERPROFILE\.cloudflared\cert.pem"
if (-not (Test-Path $cert)) {
    Write-Host "   Brauzer ochiladi - domenni tanla va ruxsat ber..." -ForegroundColor Yellow
    cloudflared tunnel login
    if (-not (Test-Path $cert)) { Die "login bajarilmadi" }
}
Ok "cert.pem mavjud"

Step "5/6 Tunnel yaratish va DNS"
$exists = (cloudflared tunnel list 2>$null) -match "\s$TunnelName\s"
if (-not $exists) { cloudflared tunnel create $TunnelName } else { Write-Host "   tunnel allaqachon bor" }

$uuid = ((cloudflared tunnel list --output json | ConvertFrom-Json) |
         Where-Object { $_.name -eq $TunnelName } | Select-Object -First 1).id
if (-not $uuid) { Die "tunnel UUID topilmadi" }

$cfgDir = "$env:USERPROFILE\.cloudflared"
@"
tunnel: $uuid
credentials-file: $cfgDir\$uuid.json

ingress:
  - hostname: $Hostname
    service: ssh://localhost:22
  - service: http_status:404
"@ | Set-Content "$cfgDir\config.yml" -Encoding utf8

cloudflared tunnel route dns $TunnelName $Hostname
Ok "$Hostname -> $TunnelName ($uuid)"

Step "6/6 Xizmat sifatida o'rnatish"
cloudflared service install
Start-Service cloudflared -ErrorAction SilentlyContinue
Ok "cloudflared xizmati ishlayapti, kompyuter yonganda avtomatik tushadi"

Write-Host "`n===== TAYYOR =====" -ForegroundColor Green
Write-Host "Hostname : $Hostname"
Write-Host "Tunnel   : $TunnelName"
Write-Host "User     : $env:USERNAME"
Write-Host @"

KEYINGI QADAM - HIMOYA (tashlab ketma!):
  Zero Trust -> Access -> Applications -> Add -> Self-hosted
    Application domain : $Hostname
    Policy: Action=Allow, Include -> Emails -> sening@email.com
  Xohlasang o'sha yerda "Browser rendering -> SSH" ni yoq
  -> brauzerdan hech narsa o'rnatmasdan terminal ochiladi.

ULANISH (o'z kompyuteringdan):
  Host mijoz1
      HostName $Hostname
      User $env:USERNAME
      ProxyCommand cloudflared access ssh --hostname %h
"@
