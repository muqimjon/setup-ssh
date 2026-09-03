<#
    setup-ssh  -  Windows
    SSH serverni o'rnatadi va (ixtiyoriy) Tailscale bilan istalgan joydan
    ulanadigan qiladi. Manba manzili Worker tomonidan yoziladi (-Base bilan ham beriladi).

    Ishga tushirish (istalgan terminalda - admin huquqini o'zi so'raydi):
        irm <manzil> | iex

    Parametr bilan (irm|iex parametr qabul qilmaydi):
        & ([scriptblock]::Create((irm <manzil>/setup.ps1))) -Key gh:username
        ... -Key nom1,nom2  |  -Key "ssh-ed25519 AAAA... izoh"

    Savolsiz:
        ... -Yes -Mode tailscale -Key gh:username
#>
[CmdletBinding()]
param(
    [Alias('y')][switch]$Yes,
    [string[]]$Mode,
    [string[]]$Key,
    [string]$SshUser,
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
$DefUser = '__DEFAULT_USER__'; if ($DefUser -like '*DEFAULT_USER*') { $DefUser = '' }
if (-not $SshUser) { $SshUser = $DefUser }
if ($Base) { $BaseUrl = $Base.TrimEnd("/") }
$KEYS_BASE = if ($BaseUrl) { "$BaseUrl/keys" } else { "" }
$TS_URL    = if ($BaseUrl) { "$BaseUrl/ts-key" } else { "" }

function Hd ($t) { Write-Host "`n$t" -ForegroundColor Cyan }
function Ok ($t) { Write-Host "   [ok] $t" -ForegroundColor Green }
function Wa ($t) { Write-Host "   [!]  $t" -ForegroundColor Yellow }
function Er ($t) { Write-Host "`n   [xato] $t" -ForegroundColor Red; throw $t }
function Line { Write-Host ("-" * 58) -ForegroundColor DarkGray }
# Kalit izohi (GitHub .keys izohsiz beradi) - bo'sh bo'lsa qisqa barmoq izi
function KeyLabel([string]$k) {
    $p = $k -split '\s+'
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

# Admin emasmiz - o'zimizni admin sifatida qayta ishga tushiramiz (UAC oynasi chiqadi).
# Terminalni yopib, adminlab qayta ochish shart emas.
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $q  = { param($s) "'" + ("$s" -replace "'", "''") + "'" }
    $ar = @()
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        $v = $kv.Value
        if     ($v -is [switch]) { if ($v.IsPresent) { $ar += "-$($kv.Key)" } }
        elseif ($v -is [array])  { $ar += "-$($kv.Key) " + (($v | ForEach-Object { & $q $_ }) -join ',') }
        else                     { $ar += "-$($kv.Key) " + (& $q $v) }
    }
    $src = if ($BaseUrl) { "& ([scriptblock]::Create((irm '$BaseUrl/setup.ps1')))" }
           elseif ($PSCommandPath) { "& $(& $q $PSCommandPath)" }
           else { Er "Administrator huquqi kerak (manba manzili noma'lum)" }
    $enc = [Convert]::ToBase64String(
           [Text.Encoding]::Unicode.GetBytes("$src $($ar -join ' ')"))
    Wa "Administrator huquqi kerak - ruxsat oynasida 'Ha' deng"
    try {
        Start-Process powershell -Verb RunAs -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-EncodedCommand',$enc) | Out-Null
    } catch { Er "Administrator huquqi berilmadi - o'rnatish bekor qilindi" }
    Write-Host "   O'rnatish yangi (administrator) oynada davom etmoqda." -ForegroundColor Cyan
    return
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
            default     { Er "-Mode noto'g'ri: $m (lan | tailscale | all)" }
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
if ($SshUser) { Write-Host "    - '$SshUser' admin hisobi ochiladi (kirish shu nom bilan)" }
if ($keys) { foreach ($k in $keys) { Write-Host "    - Kalit: $(KeyLabel $k)" } }
else       { Write-Host "    - Kalit joylanmaydi (parol bilan kiriladi)" }
if ($noPass) { Write-Host "    - Parol bilan kirish O'CHIRILADI" -ForegroundColor Yellow }
if ($useLan) { Write-Host "    - Firewall LAN uchun ochiladi, tarmoq Private qilinadi" }
else         { Write-Host "    - Firewall LAN uchun OCHILMAYDI" }
if ($useTs)  { Write-Host "    - Tailscale o'rnatiladi va ulanadi" }
Line
if (-not (AskYN "Davom etamizmi?" $true)) { Write-Host "  Bekor qilindi."; return }

# ================= BAJARISH =================

Hd "1) OpenSSH Server"
if (Get-Service sshd -ErrorAction SilentlyContinue) { Ok "allaqachon o'rnatilgan" }
else {
    # Windows komponenti (FoD) Windows Update'ga tayanadi - o'chirilgan tizimlarda
    # "Access is denied" beradi. Bunday holda Microsoft'ning MSI paketiga o'tamiz.
    $cap  = try { Get-WindowsCapability -Online -Name 'OpenSSH.Server*' } catch { $null }
    $done = $false
    if ($cap) {
        Write-Host "   Windows komponenti o'rnatilmoqda..."
        try { Add-WindowsCapability -Online -Name $cap.Name | Out-Null; $done = $true }
        catch { Wa "Windows komponenti o'rnatilmadi: $($_.Exception.Message.Trim())" }
    }
    if (-not $done) {
        Wa "zaxira yo'l: Microsoft Win32-OpenSSH (MSI)"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $msiName = switch ($env:PROCESSOR_ARCHITECTURE) {
            'ARM64' { 'OpenSSH-ARM64.msi' }
            'AMD64' { 'OpenSSH-Win64.msi' }
            default { 'OpenSSH-Win32.msi' }
        }
        $rel = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest' `
                                 -Headers @{ 'user-agent' = 'setup-ssh' } -TimeoutSec 30
        $url = ($rel.assets | Where-Object { $_.name -eq $msiName }).browser_download_url
        if (-not $url) { Er "OpenSSH MSI topilmadi: $msiName" }
        $msi = Join-Path $env:TEMP $msiName
        Invoke-WebRequest $url -OutFile $msi -UseBasicParsing
        $p = Start-Process msiexec -ArgumentList "/i `"$msi`" /qn /norestart ADDLOCAL=Server" -Wait -PassThru
        Remove-Item $msi -Force -ErrorAction SilentlyContinue
        if ($p.ExitCode -ne 0) { Er "MSI o'rnatilmadi (kod $($p.ExitCode))" }
    }
    if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) { Er "sshd xizmati topilmadi" }
    Ok "o'rnatildi"
}
Set-Service sshd -StartupType Automatic
if ((Get-Service sshd).Status -ne 'Running') { Start-Service sshd }
Ok "sshd ishlayapti"

Hd "2) sshd_config"
$cfg = "$env:ProgramData\ssh\sshd_config"
if (-not (Test-Path $cfg)) { Er "sshd_config topilmadi: $cfg" }
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

# Standart qobiq cmd.exe - masofadan boshqarish uchun PowerShell qulayroq
if (-not (Test-Path 'HKLM:\SOFTWARE\OpenSSH')) { New-Item 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null }
New-ItemProperty 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -PropertyType String -Force `
    -Value (Get-Command powershell.exe).Source | Out-Null
Ok "standart qobiq: PowerShell"

Hd "3) Boshqaruv hisobi"
if (-not $SshUser) {
    $SshUser = $env:USERNAME
    Wa "alohida hisob ochilmadi - '$SshUser' bilan kiriladi"
} else {
    $admGrp = (New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'
              ).Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
    if (Get-LocalUser -Name $SshUser -ErrorAction SilentlyContinue) { Ok "hisob bor: $SshUser" }
    else {
        $pw = ConvertTo-SecureString ([Guid]::NewGuid().ToString('N') + '!Aa1') -AsPlainText -Force
        New-LocalUser -Name $SshUser -Password $pw -FullName $SshUser -Description 'setup-ssh' `
            -PasswordNeverExpires -AccountNeverExpires -UserMayNotChangePassword | Out-Null
        Ok "hisob ochildi: $SshUser (tasodifiy parol - faqat kalit bilan kiriladi)"
    }
    $uSid = (Get-LocalUser -Name $SshUser).SID.Value
    $mem  = try { (Get-LocalGroupMember -Group $admGrp -ErrorAction Stop).SID.Value } catch { @() }
    if ($uSid -notin $mem) { Add-LocalGroupMember -Group $admGrp -Member $SshUser }
    Ok "$admGrp guruhida - to'liq huquq"
}

Hd "4) Ochiq kalitlar"
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
    icacls $kf /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null
    Ok "huquqlar to'g'irlandi"
}

Hd "5) Firewall va tarmoq"
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
    Hd "6) Tailscale"
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
    # Qurilma nomiga mijozning haqiqiy Windows useri yoziladi - konsolda kimniki ekani ko'rinsin
    $tsHost = (("$env:USERNAME-$env:COMPUTERNAME" -replace '[^A-Za-z0-9]','-') -replace '-+','-').
              Trim('-').ToLower()
    if ($tsHost.Length -gt 63) { $tsHost = $tsHost.Substring(0, 63).Trim('-') }
    $a = @('up','--accept-dns=false','--unattended',"--hostname=$tsHost")
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

Hd "7) Tekshiruv"
if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) {
    Ok "$Port-port tinglanmoqda"
} else { Wa "$Port-port tinglanmayapti - sshd loglarini ko'r" }

Write-Host ""; Line
Write-Host "  TAYYOR" -ForegroundColor Green
Line
Write-Host "  ULANISH:" -ForegroundColor Cyan
$p = if ($Port -eq 22) { "" } else { "-p $Port " }
if ($useLan) { foreach ($ip in $ips) { Write-Host "    ssh $p$SshUser@$($ip.IPAddress)   ($($ip.InterfaceAlias))" } }
if ($useTs) {
    $tsip = (& tailscale ip -4 2>$null | Select-Object -First 1)
    if ($tsip) { Write-Host "    ssh $p$SshUser@$tsip   (istalgan joydan)" }
    Write-Host "    ssh $p$SshUser@$tsHost   (MagicDNS)"
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
