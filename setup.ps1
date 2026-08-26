<#
    setup-ssh.muqimjon.uz  -  Windows
    SSH serverni o'rnatadi va (ixtiyoriy) Tailscale bilan istalgan joydan
    ulanadigan qiladi.

    Ishga tushirish (PowerShell, "Run as administrator"):
        irm https://setup-ssh.muqimjon.uz | iex

    Kalit bilan (faqat bitta savol beriladi):
        & ([scriptblock]::Create((irm https://setup-ssh.muqimjon.uz/setup.ps1))) -Key muqimjon
        ... -Key muqimjon,avazbek,gh:hamkasb
        ... -Key "ssh-ed25519 AAAA... izoh"

    Savolsiz:
        ... -Key muqimjon -Mode tailscale -TailscaleAuthKey tskey-auth-xxx -Yes
#>
[CmdletBinding()]
param(
    [switch]$Yes,
    [ValidateSet('lan','tailscale','tailscale-only')][string]$Mode,
    [string[]]$Key,
    [switch]$NoKey,
    [int]$Port = 22,
    [switch]$DisablePassword,
    [string]$TailscaleAuthKey
)

$ErrorActionPreference = 'Stop'

# Nom bo'yicha kalit shu manzildan olinadi (forkda o'zgartirasan).
$KEYS_BASE = 'https://setup-ssh.muqimjon.uz/keys'
$TS_URL    = 'https://setup-ssh.muqimjon.uz/ts-key'

function H  ($t) { Write-Host "`n$t" -ForegroundColor Cyan }
function Ok ($t) { Write-Host "   [ok] $t" -ForegroundColor Green }
function Wa ($t) { Write-Host "   [!]  $t" -ForegroundColor Yellow }
function Er ($t) { Write-Host "`n   [xato] $t" -ForegroundColor Red; exit 1 }
function Line { Write-Host ("-" * 58) -ForegroundColor DarkGray }

function Ask([string]$Q, [string[]]$Opts, [int]$Def) {
    if ($Yes) { return $Def }
    Write-Host ""
    Write-Host "  $Q" -ForegroundColor White
    for ($i = 0; $i -lt $Opts.Count; $i++) {
        $m = if ($i -eq $Def) { " <- default" } else { "" }
        Write-Host ("    [{0}] {1}{2}" -f ($i+1), $Opts[$i], $m) -ForegroundColor Gray
    }
    while ($true) {
        $a = Read-Host "  Tanlov [$($Def+1)]"
        if ([string]::IsNullOrWhiteSpace($a)) { return $Def }
        if ($a -match '^\d+$' -and [int]$a -ge 1 -and [int]$a -le $Opts.Count) { return [int]$a - 1 }
        Wa "1..$($Opts.Count) oralig'ida raqam kiriting"
    }
}
function AskText([string]$Q) {
    if ($Yes) { return "" }
    $a = Read-Host "  $Q"
    if ([string]::IsNullOrWhiteSpace($a)) { return "" }
    return $a.Trim()
}
function AskYN([string]$Q, [bool]$Def) {
    if ($Yes) { return $Def }
    $d = if ($Def) { "ha" } else { "yo'q" }
    while ($true) {
        $a = Read-Host "  $Q (ha/yo'q) [$d]"
        if ([string]::IsNullOrWhiteSpace($a)) { return $Def }
        switch -Regex ($a.Trim().ToLower()) {
            '^(ha|h|yes)$'      { return $true }
            "^(yo'q|yoq|n|no)$" { return $false }
        }
        Wa "'ha' yoki 'yo''q' deb yozing"
    }
}

# ---------- kalitni yechish ----------
function Resolve-Key([string]$v) {
    if ($v -match '^(ssh-|ecdsa-)') { return @($v) }
    $u = switch -Regex ($v) {
        '^https?://' { $v }
        '^gh:'       { "https://github.com/$($v.Substring(3)).keys" }
        default      { "$KEYS_BASE/$v.pub" }
    }
    try { $t = Invoke-RestMethod -Uri $u -TimeoutSec 20 } catch { Er "kalit olinmadi: $u" }
    $lines = ($t -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^(ssh-|ecdsa-)' }
    if (-not $lines) { Er "kalit topilmadi: $u" }
    return $lines
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Er @"
Administrator huquqi kerak.
PowerShell ni "Run as administrator" bilan ochib qayta urinib ko'r:
    irm https://setup-ssh.muqimjon.uz | iex
"@
}

$os  = (Get-CimInstance Win32_OperatingSystem).Caption
$ips = Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.IPAddress -notlike '127.*' -and $_.InterfaceAlias -notlike 'vEthernet*' }

Clear-Host
Line
Write-Host "  SSH SETUP" -ForegroundColor Cyan -NoNewline
Write-Host "   setup-ssh.muqimjon.uz"
Line
Write-Host "  Tizim        : $os ($env:PROCESSOR_ARCHITECTURE)"
Write-Host "  Kompyuter    : $env:COMPUTERNAME          Foydalanuvchi: $env:USERNAME"
Write-Host "  IP           : $(($ips | ForEach-Object { $_.IPAddress }) -join ', ')"
Line

# ---------- 1-savol ----------
$modeKeys = @('lan','tailscale','tailscale-only')
if ($Mode) { $mi = [array]::IndexOf($modeKeys, $Mode) }
else {
    $mi = Ask "Qayerdan kirasan?" @(
        'Faqat shu tarmoqdan (LAN)'
        'LAN + istalgan joydan (Tailscale)'
        'Faqat istalgan joydan (Tailscale, LAN yopiq)'
    ) 0
}
$useLan = $modeKeys[$mi] -in @('lan','tailscale')
$useTs  = $modeKeys[$mi] -in @('tailscale','tailscale-only')

# ---------- kalitlar ----------
$keys = @()
if ($NoKey) { $keys = @() }
elseif ($Key) { foreach ($k in $Key) { $keys += Resolve-Key $k } }
else {
    # bayroq berilmagan - yagona qo'shimcha savol
    if ((Ask "Kim kira oladi?" @('Faqat parol bilan', 'Ochiq kalit qo''shaman') 0) -eq 1) {
        $t = AskText "Kalit nomlari (probel bilan bir nechta: muqimjon gh:avazbek https://...)"
        if ($t -match '^(ssh-|ecdsa-)') { $keys = Resolve-Key $t }
        elseif ($t) {
            foreach ($x in ($t -split '[\s,]+' | Where-Object { $_ })) { $keys += Resolve-Key $x }
        }
    }
}
$keys = $keys | Select-Object -Unique

if ($useTs -and -not $TailscaleAuthKey -and -not $Yes) {
    $TailscaleAuthKey = AskText "Tailscale auth key (bo'sh = avtomatik yoki brauzer)"
}

Line
Write-Host "  BAJARILADIGAN ISHLAR" -ForegroundColor Yellow
Write-Host "    - OpenSSH Server o'rnatiladi, avtomatik ishga tushadi (port $Port)"
if ($keys) { foreach ($k in $keys) { Write-Host "    - Kalit: $((($k -split ' ')[2]))" } }
else       { Write-Host "    - Kalit joylanmaydi (parol bilan kiriladi)" }
if ($DisablePassword) { Write-Host "    - Parol bilan kirish O'CHIRILADI" -ForegroundColor Yellow }
if ($useLan) { Write-Host "    - Firewall LAN uchun ochiladi, tarmoq Private qilinadi" }
else         { Write-Host "    - Firewall LAN uchun OCHILMAYDI" }
if ($useTs)  { Write-Host "    - Tailscale o'rnatiladi va ulanadi" }
Line
if (-not (AskYN "Davom etamizmi?" $true)) { Write-Host "  Bekor qilindi."; exit 0 }

# ================= BAJARISH =================

H "1) OpenSSH Server"
$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
if ($cap.State -ne 'Installed') {
    Write-Host "   o'rnatilmoqda..."
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
    Ok "o'rnatildi"
} else { Ok "allaqachon o'rnatilgan" }
Set-Service sshd -StartupType Automatic
if ((Get-Service sshd).Status -ne 'Running') { Start-Service sshd }
Ok "sshd ishlayapti"

H "2) sshd_config"
$cfg = "$env:ProgramData\ssh\sshd_config"
Copy-Item $cfg "$cfg.bak" -Force -ErrorAction SilentlyContinue
$txt = Get-Content $cfg -Raw
function SetD([string]$T, [string]$N, [string]$V) {
    if ($T -match "(?m)^\s*#?\s*$N\s+.*$") { return $T -replace "(?m)^\s*#?\s*$N\s+.*$", "$N $V" }
    return $T.TrimEnd() + "`r`n$N $V`r`n"
}
$txt = SetD $txt 'Port'                   "$Port"
$txt = SetD $txt 'PubkeyAuthentication'   'yes'
$txt = SetD $txt 'PasswordAuthentication' $(if ($DisablePassword) { 'no' } else { 'yes' })
Set-Content $cfg $txt -Encoding utf8
Ok "port=$Port, kalit=yoq, parol=$(if($DisablePassword){"yo'q"}else{'ha'})"

H "3) Ochiq kalitlar"
if (-not $keys) { Wa "joylanmadi - parol bilan kiriladi" }
else {
    $kf = "$env:ProgramData\ssh\administrators_authorized_keys"
    $cur = if (Test-Path $kf) { Get-Content $kf -Raw } else { "" }
    foreach ($k in $keys) {
        $body = ($k -split ' ')[1]
        if ($cur -notmatch [regex]::Escape($body)) {
            Add-Content $kf $k -Encoding utf8; $cur += "`n$k"
            Ok "qo'shildi: $((($k -split ' ')[2]))"
        } else { Ok "allaqachon bor: $((($k -split ' ')[2]))" }
    }
    icacls $kf /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
    Ok "huquqlar to'g'irlandi"
}

H "4) Firewall va tarmoq"
Get-NetFirewallRule -DisplayName 'SSH (setup-ssh)' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
if ($useLan) {
    New-NetFirewallRule -DisplayName 'SSH (setup-ssh)' -Direction Inbound -Protocol TCP `
        -LocalPort $Port -Action Allow -Profile Private,Domain | Out-Null
    Ok "$Port-port Private tarmoqda ochildi"
    $ch = @()
    Get-NetConnectionProfile | Where-Object {
        $_.NetworkCategory -eq 'Public' -and $_.InterfaceAlias -notlike 'vEthernet*'
    } | ForEach-Object {
        Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
        $ch += $_.InterfaceAlias
    }
    if ($ch) { Ok "Private qilindi: $($ch -join ', ')" } else { Ok "tarmoq allaqachon Private" }
} else { Ok "LAN yopiq qoldi - faqat Tailscale orqali kiriladi" }
Restart-Service sshd
Ok "sshd qayta ishga tushdi"

if ($useTs) {
    H "5) Tailscale"
    if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
        winget install --id tailscale.tailscale --silent --accept-package-agreements --accept-source-agreements
        $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine')
    }
    if (-not $TailscaleAuthKey) {
        try {
            $mk = (Invoke-RestMethod -Uri $TS_URL -TimeoutSec 20).Trim()
            if ($mk -match '^tskey-') { $TailscaleAuthKey = $mk; Ok "bir martalik kalit olindi (kutish rejimi)" }
        } catch { }
    }
    $a = @('up','--accept-dns=false')
    if ($TailscaleAuthKey) { $a += "--authkey=$TailscaleAuthKey" } else { Wa "brauzer ochiladi - hisobingga kir" }
    & tailscale @a
    Ok "Tailscale ulandi"
}

H "6) Tekshiruv"
if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) {
    Ok "$Port-port tinglanmoqda"
} else { Wa "$Port-port tinglanmayapti - sshd loglarini ko'r" }

Write-Host ""; Line
Write-Host "  TAYYOR" -ForegroundColor Green
Line
Write-Host "  ULANISH:" -ForegroundColor Cyan
$p = if ($Port -eq 22) { "" } else { "-p $Port " }
if ($useLan) { foreach ($ip in $ips) { Write-Host "    ssh $p$env:USERNAME@$($ip.IPAddress)   ($($ip.InterfaceAlias))" } }
if ($useTs) {
    $tsip = (& tailscale ip -4 2>$null | Select-Object -First 1)
    if ($tsip) { Write-Host "    ssh $p$env:USERNAME@$tsip   (istalgan joydan)" }
    Write-Host "    ssh $p$env:USERNAME@$(($env:COMPUTERNAME).ToLower())   (MagicDNS)"
}
if ($keys -and -not $DisablePassword) {
    Write-Host ""
    Wa "Kalit bilan kirganingni tekshirgach parolni o'chir:"
    Write-Host '      (gc $env:ProgramData\ssh\sshd_config) -replace "^#?PasswordAuthentication.*","PasswordAuthentication no" | sc $env:ProgramData\ssh\sshd_config; Restart-Service sshd' -ForegroundColor DarkGray
}
Write-Host ""
