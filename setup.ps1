<#
    setup-ssh  -  Windows
    SSH serverni o'rnatadi va (ixtiyoriy) Tailscale bilan istalgan joydan
    ulanadigan qiladi. Manba manzili Worker tomonidan yoziladi (-Base bilan ham beriladi).

    Ishga tushirish (PowerShell, "Run as administrator"):
        irm <manzil> | iex

    Parametr bilan (irm|iex parametr qabul qilmaydi):
        & ([scriptblock]::Create((irm <manzil>/setup.ps1))) -Key gh:username
        ... -Key nom1,nom2  |  -Key "ssh-ed25519 AAAA... izoh"

    Savolsiz:
        ... -Yes -Mode tailscale-only -Key gh:username
#>
[CmdletBinding()]
param(
    [Alias('y')][switch]$Yes,
    [ValidateSet('lan','tailscale','all')][string[]]$Mode,
    [string[]]$Key,
    [switch]$NoKey,
    [int]$Port = 22,
    [switch]$DisablePassword,
    [switch]$KeepPassword,
    [string]$TailscaleAuthKey,
    [string]$TsTag,
    [switch]$Member,
    [string]$Base
)

$ErrorActionPreference = 'Stop'

$BaseUrl = '__BASE__'; if ($BaseUrl -notmatch '^https?://') { $BaseUrl = '' }
# Worker tomonidan to'ldiriladi (env: DEFAULT_KEY / DEFAULT_MODE). Bo'sh bo'lsa - e'tiborsiz.
$DefKey  = '__DEFAULT_KEY__';  if ($DefKey  -like '*DEFAULT_KEY*')  { $DefKey  = '' }
$DefMode = '__DEFAULT_MODE__'; if ($DefMode -like '*DEFAULT_MODE*') { $DefMode = '' }
if ($Base) { $BaseUrl = $Base.TrimEnd("/") }
$KEYS_BASE = if ($BaseUrl) { "$BaseUrl/keys" } else { "" }
$TS_URL    = if ($BaseUrl) { "$BaseUrl/ts-key" } else { "" }

function Hd ($t) { Write-Host "`n$t" -ForegroundColor Cyan }
function Ok ($t) { Write-Host "   [ok] $t" -ForegroundColor Green }
function Wa ($t) { Write-Host "   [!]  $t" -ForegroundColor Yellow }
function Er ($t) { Write-Host "`n   [xato] $t" -ForegroundColor Red; exit 1 }
function Line { Write-Host ("-" * 58) -ForegroundColor DarkGray }
# Kalit izohi (GitHub .keys izohsiz beradi) - bo'sh bo'lsa qisqa barmoq izi
function KeyLabel([string]$k) {
    $p = $k -split "s+"
    if ($p.Count -ge 3 -and $p[2]) { return $p[2] }
    if ($p.Count -ge 2) { return $p[0] + " ..." + $p[1].Substring([Math]::Max(0, $p[1].Length - 10)) }
    return "?"
}

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
    $d = if ($Def) { "yes" } else { "no" }
    while ($true) {
        $a = Read-Host "  $Q (yes/no) [$d]"
        if ([string]::IsNullOrWhiteSpace($a)) { return $Def }
        switch -Regex ($a.Trim().ToLower()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
        }
        Wa "'yes' yoki 'no' deb yozing"
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
    irm <manzil> | iex
"@
}

$os  = (Get-CimInstance Win32_OperatingSystem).Caption
$ips = Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.IPAddress -notlike '127.*' -and $_.InterfaceAlias -notlike 'vEthernet*' }

Clear-Host
Line
Write-Host "  SSH SETUP" -ForegroundColor Cyan -NoNewline
Write-Host "   $(if ($BaseUrl) { $BaseUrl } else { "setup-ssh" })"
Line
Write-Host "  Tizim        : $os ($env:PROCESSOR_ARCHITECTURE)"
Write-Host "  Kompyuter    : $env:COMPUTERNAME          Foydalanuvchi: $env:USERNAME"
Write-Host "  IP           : $(($ips | ForEach-Object { $_.IPAddress }) -join ', ')"
Line

# ---------- 1-savol ----------
# Rejim: bir yoki bir nechta (-Mode lan,tailscale) yoki 'all'. Berilmasa - so'raladi.
$useLan = $false; $useTs = $false
if (-not $Mode -and $DefMode) { $Mode = $DefMode -split '[ ,]+' | Where-Object { $_ } }
if ($Mode) {
    foreach ($m in $Mode) {
        switch ($m) {
            'lan'       { $useLan = $true }
            'tailscale' { $useTs  = $true }
            'all'       { $useLan = $true; $useTs = $true }
        }
    }
} else {
    switch (Ask "Qayerdan kirasan?" @(
        'Faqat shu tarmoqdan (LAN)'
        'Faqat istalgan joydan (Tailscale)'
        'Ikkalasi (LAN + Tailscale)'
    ) 0) {
        0 { $useLan = $true }
        1 { $useTs  = $true }
        2 { $useLan = $true; $useTs = $true }
    }
}

# ---------- kalitlar ----------
# Kalitlar: DEFAULT_KEY (env) + -Key bilan berilganlar. Ikkalasi ham qo'shiladi.
$keys = @()
if (-not $NoKey) {
    $allk = @()
    if ($DefKey) { $allk += $DefKey }
    if ($Key)    { $allk += $Key }
    # LAN rejimida kalit yo'q bo'lsa - faqat shunda so'raymiz
    if ($allk.Count -eq 0 -and $useLan -and -not $Yes) {
        if ((Ask "Kim kira oladi?" @('Faqat parol bilan', 'Ochiq kalit qo''shaman') 0) -eq 1) {
            $t = AskText "Kalit nomlari (probel bilan bir nechta: gh:user nom https://...)"
            if ($t -match '^(ssh-|ecdsa-)') { $allk += $t }
            elseif ($t) { $allk += ($t -split '[\s,]+' | Where-Object { $_ }) }
        }
    }
    foreach ($k in $allk) { $keys += Resolve-Key $k }
}
$keys = $keys | Select-Object -Unique

# Parol bilan kirish: bayroq berilmagan bo'lsa AVTOMAT.
# Kalit joylansa -> parol O'CHADI. Kalit yo'q bo'lsa -> QOLADI (qulf ichida qolmaslik uchun).
$noPass = if ($KeepPassword) { $false } elseif ($DisablePassword) { $true } else { [bool]$keys }

if ($useTs -and -not $TailscaleAuthKey -and -not $TS_URL -and -not $Yes) {
    Wa "Bu rejim uchun Tailscale auth key kerak (yoki -TailscaleAuthKey bilan bering)"
    $TailscaleAuthKey = AskText "Tailscale auth key (bo'sh = avtomatik yoki brauzer)"
}

Line
Write-Host "  BAJARILADIGAN ISHLAR" -ForegroundColor Yellow
Write-Host "    - OpenSSH Server o'rnatiladi, avtomatik ishga tushadi (port $Port)"
if ($keys) { foreach ($k in $keys) { Write-Host "    - Kalit: $(KeyLabel $k)" } }
else       { Write-Host "    - Kalit joylanmaydi (parol bilan kiriladi)" }
if ($noPass) { Write-Host "    - Parol bilan kirish O'CHIRILADI" -ForegroundColor Yellow }
if ($useLan) { Write-Host "    - Firewall LAN uchun ochiladi, tarmoq Private qilinadi" }
else         { Write-Host "    - Firewall LAN uchun OCHILMAYDI" }
if ($useTs)  { Write-Host "    - Tailscale o'rnatiladi va ulanadi" }
Line
if (-not (AskYN "Davom etamizmi?" $true)) { Write-Host "  Bekor qilindi."; exit 0 }

# ================= BAJARISH =================

Hd "1) OpenSSH Server"
$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
if ($cap.State -ne 'Installed') {
    Write-Host "   o'rnatilmoqda..."
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
    Ok "o'rnatildi"
} else { Ok "allaqachon o'rnatilgan" }
Set-Service sshd -StartupType Automatic
if ((Get-Service sshd).Status -ne 'Running') { Start-Service sshd }
Ok "sshd ishlayapti"

Hd "2) sshd_config"
$cfg = "$env:ProgramData\ssh\sshd_config"
Copy-Item $cfg "$cfg.bak" -Force -ErrorAction SilentlyContinue
$txt = Get-Content $cfg -Raw
function SetD([string]$T, [string]$N, [string]$V) {
    if ($T -match "(?m)^\s*#?\s*$N\s+.*$") { return $T -replace "(?m)^\s*#?\s*$N\s+.*$", "$N $V" }
    return $T.TrimEnd() + "`r`n$N $V`r`n"
}
$txt = SetD $txt 'Port'                   "$Port"
$txt = SetD $txt 'PubkeyAuthentication'   'yes'
$txt = SetD $txt 'PasswordAuthentication' $(if ($noPass) { 'no' } else { 'yes' })
Set-Content $cfg $txt -Encoding utf8
Ok "port=$Port, kalit=yoq, parol=$(if($noPass){"yo'q"}else{'ha'})"

Hd "3) Ochiq kalitlar"
if (-not $keys) { Wa "joylanmadi - parol bilan kiriladi" }
else {
    $kf = "$env:ProgramData\ssh\administrators_authorized_keys"
    $cur = if (Test-Path $kf) { Get-Content $kf -Raw } else { "" }
    foreach ($k in $keys) {
        $body = ($k -split ' ')[1]
        if ($cur -notmatch [regex]::Escape($body)) {
            Add-Content $kf $k -Encoding utf8; $cur += "`n$k"
            Ok "qo'shildi: $(KeyLabel $k)"
        } else { Ok "allaqachon bor: $(KeyLabel $k)" }
    }
    icacls $kf /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
    Ok "huquqlar to'g'irlandi"
}

Hd "4) Firewall va tarmoq"
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
    Hd "5) Tailscale"
    if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
        winget install --id tailscale.tailscale --silent --accept-package-agreements --accept-source-agreements
        $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine')
    }
    if (-not $TailscaleAuthKey) {
        try {
            $u = if ($Member) { $TS_URL } elseif ($TsTag) { "$TS_URL`?tag=$TsTag" } else { "$TS_URL`?tag=client" }
            $mk = (Invoke-RestMethod -Uri $u -TimeoutSec 20).Trim()
            if ($mk -match '^tskey-') { $TailscaleAuthKey = $mk; Ok "bir martalik kalit olindi (kutish rejimi)" }
        } catch { }
    }
    $a = @('up','--accept-dns=false','--unattended')
    if ($TailscaleAuthKey) { $a += "--authkey=$TailscaleAuthKey" } else { Wa "brauzer ochiladi - hisobingga kir" }
    & tailscale @a
    Ok "Tailscale ulandi (servis fonda)"

    # GUI/tray oynasini yopish va avtostartdan olib tashlash - faqat servis (ulanish) qoladi
    Start-Sleep -Seconds 2
    Get-Process -Name 'tailscale-ipn' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($rk in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
                      'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')) {
        if (Test-Path $rk) {
            (Get-Item $rk).Property | Where-Object { $_ -match 'tailscale' } |
                ForEach-Object { Remove-ItemProperty -Path $rk -Name $_ -ErrorAction SilentlyContinue }
        }
    }
    Ok "Tailscale UI yopildi (fonda ishlaydi)"
}

Hd "6) Tekshiruv"
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
if ($keys -and -not $noPass) {
    Write-Host ""
    Wa "Kalit bilan kirganingni tekshirgach parolni o'chir:"
    Write-Host '      (gc $env:ProgramData\ssh\sshd_config) -replace "^#?PasswordAuthentication.*","PasswordAuthentication no" | sc $env:ProgramData\ssh\sshd_config; Restart-Service sshd' -ForegroundColor DarkGray
}
Write-Host ""

# Fayldan ishga tushirilgan bo'lsa skript o'zini o'chiradi.
# irm | iex da $PSCommandPath bo'sh - tegmaydi.
if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
