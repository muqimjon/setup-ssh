#!/usr/bin/env bash
# setup-ssh.muqimjon.uz  -  Linux / macOS / Termux (Android)
#
#   curl -fsSL https://setup-ssh.muqimjon.uz | bash
#
# Kalit bilan (faqat bitta savol beriladi):
#   ... | bash -s -- --key muqimjon
#   ... | bash -s -- --key muqimjon telefon ish-pc
#   ... | bash -s -- --key "ssh-ed25519 AAAA... izoh"
#
# Savolsiz:
#   ... | bash -s -- --key muqimjon --mode tailscale --ts-key tskey-auth-xxx --yes

set -uo pipefail

# Nom bo'yicha kalit shu manzildan olinadi (forkda o'zgartirasan).
BASE='__BASE__'; case "$BASE" in http*) ;; *) BASE='' ;; esac
KEYS_BASE=""; TS_URL=""

# ---------- Termux? ----------
TERMUX=0
case "${PREFIX:-}" in *com.termux*) TERMUX=1 ;; esac
[ -d /data/data/com.termux/files ] && TERMUX=1

YES=0; MODE=""; NOKEY=0; DISABLE_PW=0; TS_KEY=""; TSTAG=""; MEMBER=0
PORT=$([ "$TERMUX" = "1" ] && echo 8022 || echo 22)
KEYARGS=()
NL=$'\n'
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y)           YES=1 ;;
        --mode)             MODE="$2"; shift ;;
        --key)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in -*) break ;; esac
                KEYARGS+=("$1"); shift
            done
            continue ;;
        --no-key)           NOKEY=1 ;;
        --port)             PORT="$2"; shift ;;
        --disable-password) DISABLE_PW=1 ;;
        --ts-key)           TS_KEY="$2"; shift ;;
        --ts-tag)           TSTAG="$2"; shift ;;
        --base)             BASE="$2"; shift ;;
        --member)           MEMBER=1 ;;
        *) echo "noma'lum parametr: $1"; exit 1 ;;
    esac
    shift
done
[ -n "$BASE" ] && { KEYS_BASE="$BASE/keys"; TS_URL="$BASE/ts-key"; }

C_CY=$'\033[36m'; C_GR=$'\033[32m'; C_YL=$'\033[33m'; C_RD=$'\033[31m'
C_GY=$'\033[90m'; C_WH=$'\033[97m'; C_0=$'\033[0m'
H()    { printf "\n%s%s%s\n" "$C_CY" "$1" "$C_0"; }
ok()   { printf "   %s[ok]%s %s\n" "$C_GR" "$C_0" "$1"; }
wa()   { printf "   %s[!]%s  %s\n"  "$C_YL" "$C_0" "$1"; }
er()   { printf "\n   %s[xato]%s %s\n" "$C_RD" "$C_0" "$1"; exit 1; }
line() { printf "%s%s%s\n" "$C_GY" "----------------------------------------------------------" "$C_0"; }
# Kalit izohi (GitHub .keys izohsiz beradi)
key_label() {
    local c; c=$(printf "%s" "$1" | cut -d" " -f3-)
    if [ -n "$c" ]; then printf "%s
" "$c"
    else printf "%s ...%s
" "$(printf "%s" "$1" | cut -d" " -f1)" "$(printf "%s" "$1" | cut -d" " -f2 | tail -c 11)"; fi
}

TTY=/dev/tty
[ -r $TTY ] || { TTY=""; YES=1; }
rd() { if [ -n "$TTY" ]; then read -r "$@" <$TTY; else return 1; fi; }

ask() {
    local q="$1" def="$2"; shift 2
    local opts=("$@") i ans
    [ "$YES" = "1" ] && { ASK_RESULT="$def"; return; }
    printf "\n  %s%s%s\n" "$C_WH" "$q" "$C_0"
    for i in "${!opts[@]}"; do
        local mark=""; [ "$i" = "$def" ] && mark=" <- default"
        printf "    %s[%d] %s%s%s\n" "$C_GY" "$((i+1))" "${opts[$i]}" "$mark" "$C_0"
    done
    while true; do
        printf "  Tanlov [%d]: " "$((def+1))"
        rd ans || { ASK_RESULT="$def"; return; }
        [ -z "$ans" ] && { ASK_RESULT="$def"; return; }
        if [[ "$ans" =~ ^[0-9]+$ ]] && [ "$ans" -ge 1 ] && [ "$ans" -le "${#opts[@]}" ]; then
            ASK_RESULT="$((ans-1))"; return
        fi
        wa "1..${#opts[@]} oralig'ida raqam"
    done
}
ask_text() {
    local ans
    [ "$YES" = "1" ] && { ASK_RESULT=""; return; }
    printf "  %s: " "$1"
    rd ans || ans=""
    ASK_RESULT="$ans"
}
ask_yn() {
    local q="$1" def="$2" ans hint
    [ "$YES" = "1" ] && { ASK_RESULT="$def"; return; }
    [ "$def" = "1" ] && hint="yes" || hint="no"
    while true; do
        printf "  %s (yes/no) [%s]: " "$q" "$hint"
        rd ans || { ASK_RESULT="$def"; return; }
        [ -z "$ans" ] && { ASK_RESULT="$def"; return; }
        case "$(echo "$ans" | tr '[:upper:]' '[:lower:]')" in
            y|yes) ASK_RESULT=1; return ;;
            n|no)  ASK_RESULT=0; return ;;
        esac
        wa "'yes' yoki 'no' deb yozing"
    done
}

resolve_key() {  # bir yoki bir nechta kalit qatorini chiqaradi
    local v="$1" u
    case "$v" in
        ssh-*|ecdsa-*) echo "$v"; return ;;
        http://*|https://*) u="$v" ;;
        gh:*) u="https://github.com/${v#gh:}.keys" ;;
        *)    u="$KEYS_BASE/$v.pub" ;;
    esac
    curl -fsSL --max-time 20 "$u" | grep -E '^(ssh-|ecdsa-)' || er "kalit olinmadi: $u"
}

if [ "$TERMUX" = "1" ]; then SUDO=""
elif [ "$(id -u)" -eq 0 ]; then SUDO=""
else SUDO="sudo"; command -v sudo >/dev/null 2>&1 || er "sudo topilmadi va root emassan"; fi

# ---------- muhit ----------
if [ "$TERMUX" = "1" ]; then
    OS_NAME="Termux (Android $(getprop ro.build.version.release 2>/dev/null || echo '?'))"
    PM=pkg
else
    OS_NAME=$( . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -s )
    if   command -v apt-get >/dev/null 2>&1; then PM=apt
    elif command -v dnf     >/dev/null 2>&1; then PM=dnf
    elif command -v pacman  >/dev/null 2>&1; then PM=pacman
    elif command -v apk     >/dev/null 2>&1; then PM=apk
    else PM=""; fi
fi
ARCH=$(uname -m)
IPS=$(ip -4 -o addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}' | tr '\n' ' ')
[ -z "$IPS" ] && IPS=$(hostname -I 2>/dev/null || echo "-")

clear 2>/dev/null || true
line
printf "  %sSSH SETUP%s   setup-ssh.muqimjon.uz\n" "$C_CY" "$C_0"
line
echo "  Tizim        : $OS_NAME ($ARCH)   paket: ${PM:-aniqlanmadi}"
echo "  Kompyuter    : $(hostname)          Foydalanuvchi: $(whoami)"
echo "  IP           : $IPS"
[ "$TERMUX" = "1" ] && echo "  Port         : $PORT (Android'da 1024 dan kichik port mumkin emas)"
line

# ---------- 1-savol ----------
MODE_KEYS=(lan tailscale tailscale-only)
if [ -n "$MODE" ]; then
    mi=-1; for i in "${!MODE_KEYS[@]}"; do [ "${MODE_KEYS[$i]}" = "$MODE" ] && mi=$i; done
    [ "$mi" = "-1" ] && er "noma'lum rejim: $MODE"
else
    ask "Qayerdan kirasan?" 0 \
        "Faqat shu tarmoqdan (LAN)" \
        "LAN + istalgan joydan (Tailscale)" \
        "Faqat istalgan joydan (Tailscale, LAN yopiq)"
    mi="$ASK_RESULT"
fi
USE_LAN=0; USE_TS=0
case "${MODE_KEYS[$mi]}" in
    lan)            USE_LAN=1 ;;
    tailscale)      USE_LAN=1; USE_TS=1 ;;
    tailscale-only) USE_TS=1 ;;
esac

# ---------- kalitlar ----------
KEYS=""
if [ "$NOKEY" = "1" ]; then :
elif [ "${#KEYARGS[@]}" -gt 0 ]; then
    for k in "${KEYARGS[@]}"; do KEYS="$KEYS$(resolve_key "$k")"$'\n'; done
else
    ask "Kim kira oladi?" 0 "Faqat parol bilan" "Ochiq kalit qo'shaman"
    if [ "$ASK_RESULT" = "1" ]; then
        ask_text "Kalit nomlari (probel bilan bir nechta: muqimjon telefon https://...)"
        case "$ASK_RESULT" in
            "") ;;
            ssh-*|ecdsa-*) KEYS="$(resolve_key "$ASK_RESULT")$NL" ;;
            *) for x in $(echo "$ASK_RESULT" | tr ',' ' '); do
                   KEYS="$KEYS$(resolve_key "$x")$NL"
               done ;;
        esac
    fi
fi
KEYS=$(echo "$KEYS" | grep -E '^(ssh-|ecdsa-)' | awk '!seen[$2]++' || true)

if [ "$USE_TS" = "1" ] && [ -z "$TS_KEY" ] && [ "$YES" = "0" ] && [ "$TERMUX" = "0" ]; then
    ask_text "Tailscale auth key (bo'sh = avtomatik yoki brauzer)"; TS_KEY="$ASK_RESULT"
fi

# ---------- xulosa ----------
line
printf "  %sBAJARILADIGAN ISHLAR%s\n" "$C_YL" "$C_0"
echo "    - openssh-server o'rnatiladi, port $PORT"
if [ -n "$KEYS" ]; then printf '%s
' "$KEYS" | while IFS= read -r l; do [ -n "$l" ] && echo "    - Kalit: $(key_label "$l")"; done
else echo "    - Kalit joylanmaydi (parol bilan kiriladi)"; fi
[ "$DISABLE_PW" = "1" ] && echo "    - Parol bilan kirish O'CHIRILADI"
if [ "$TERMUX" = "1" ]; then
    echo "    - Termux: firewall/systemd yo'q, sshd qo'lda ishga tushadi"
    [ "$USE_TS" = "1" ] && echo "    - Tailscale: Android ilovasi orqali (pastda yo'riqnoma)"
else
    [ "$USE_LAN" = "1" ] && echo "    - Firewall LAN uchun ochiladi" || echo "    - Firewall LAN uchun OCHILMAYDI"
    [ "$USE_TS" = "1" ] && echo "    - Tailscale o'rnatiladi va ulanadi"
fi
line
ask_yn "Davom etamizmi?" 1
[ "$ASK_RESULT" = "0" ] && { echo "  Bekor qilindi."; exit 0; }

# ================= BAJARISH =================

H "1) openssh-server"
if [ "$TERMUX" = "1" ]; then
    command -v sshd >/dev/null 2>&1 || pkg install -y openssh
    ok "o'rnatildi"
elif [ -x /usr/sbin/sshd ] || command -v sshd >/dev/null 2>&1; then
    ok "allaqachon o'rnatilgan"
else
    case "$PM" in
        apt)    $SUDO apt-get update -qq && $SUDO apt-get install -y openssh-server ;;
        dnf)    $SUDO dnf install -y openssh-server ;;
        pacman) $SUDO pacman -S --noconfirm openssh ;;
        apk)    $SUDO apk add --no-cache openssh ;;
        *)      er "paket menejeri topilmadi - openssh-server ni qo'lda o'rnat" ;;
    esac
    ok "o'rnatildi"
fi

H "2) sshd_config"
if [ "$TERMUX" = "1" ]; then CFG="$PREFIX/etc/ssh/sshd_config"; else CFG=/etc/ssh/sshd_config; fi
$SUDO cp "$CFG" "$CFG.bak" 2>/dev/null || true
set_d() {
    if $SUDO grep -qE "^\s*#?\s*$1\s+" "$CFG"; then
        $SUDO sed -i -E "s|^\s*#?\s*$1\s+.*|$1 $2|" "$CFG"
    else
        echo "$1 $2" | $SUDO tee -a "$CFG" >/dev/null
    fi
}
set_d Port "$PORT"
set_d PubkeyAuthentication yes
[ "$TERMUX" = "0" ] && set_d PermitRootLogin prohibit-password
[ "$DISABLE_PW" = "1" ] && set_d PasswordAuthentication no || set_d PasswordAuthentication yes
ok "port=$PORT, kalit=yoq, parol=$([ "$DISABLE_PW" = "1" ] && echo "yo'q" || echo ha)"

H "3) Ochiq kalitlar"
if [ -z "$KEYS" ]; then wa "joylanmadi - parol bilan kiriladi"
else
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
    while IFS= read -r k; do
        [ -z "$k" ] && continue
        b=$(echo "$k" | awk '{print $2}')
        if grep -qF "$b" ~/.ssh/authorized_keys 2>/dev/null; then ok "allaqachon bor: $(key_label "$k")"
        else echo "$k" >> ~/.ssh/authorized_keys; ok "qo'shildi: $(key_label "$k")"; fi
    done <<< "$KEYS"
fi

H "4) Ishga tushirish"
if [ "$TERMUX" = "1" ]; then
    pkill sshd 2>/dev/null || true
    sshd && ok "sshd ishga tushdi (port $PORT)"
    mkdir -p ~/.termux/boot
    printf '#!/data/data/com.termux/files/usr/bin/sh\ntermux-wake-lock\nsshd\n' > ~/.termux/boot/start-sshd.sh
    chmod +x ~/.termux/boot/start-sshd.sh
    ok "avtostart skripti yozildi (~/.termux/boot/start-sshd.sh)"
    wa "Telefon yonganda o'zi ishga tushishi uchun 'Termux:Boot' ilovasi kerak"
    wa "Termux'ni batareya optimizatsiyasidan chiqarib qo'y - aks holda Android uni o'ldiradi"
else
    SVC=ssh; systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service' && SVC=sshd
    $SUDO systemctl enable --now "$SVC" >/dev/null 2>&1 || $SUDO service ssh start
    if [ "$USE_LAN" = "1" ]; then
        if command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
            $SUDO ufw allow "$PORT/tcp" >/dev/null && ok "ufw: $PORT ochildi"
        elif command -v firewall-cmd >/dev/null 2>&1 && $SUDO firewall-cmd --state >/dev/null 2>&1; then
            $SUDO firewall-cmd --permanent --add-port="$PORT/tcp" >/dev/null
            $SUDO firewall-cmd --reload >/dev/null && ok "firewalld: $PORT ochildi"
        else ok "faol firewall yo'q"; fi
    else ok "LAN yopiq qoldi - faqat Tailscale orqali kiriladi"; fi
    $SUDO systemctl restart "$SVC" 2>/dev/null || $SUDO service ssh restart
    ok "$SVC ishlayapti"
fi

if [ "$USE_TS" = "1" ]; then
    H "5) Tailscale"
    if [ "$TERMUX" = "1" ]; then
        wa "Android'da Tailscale Play Store ilovasi orqali o'rnatiladi (Termux'dan emas)"
        wa "Ilovani o'rnatib, o'sha hisobga kirsang - bu sshd Tailscale IP'da ham ochiladi"
    else
        command -v tailscale >/dev/null 2>&1 || curl -fsSL https://tailscale.com/install.sh | $SUDO sh
        if [ -z "$TS_KEY" ]; then
            if [ "$MEMBER" = "1" ]; then u="$TS_URL"; else u="$TS_URL?tag=${TSTAG:-client}"; fi
            TS_KEY=$(curl -fsSL --max-time 20 "$u" 2>/dev/null | grep -E '^tskey-' || true)
            [ -n "$TS_KEY" ] && ok "bir martalik kalit olindi (kutish rejimi)"
        fi
        if [ -n "$TS_KEY" ]; then $SUDO tailscale up --authkey="$TS_KEY"
        else wa "quyidagi havolani brauzerda och:"; $SUDO tailscale up; fi
        ok "Tailscale ulandi"
    fi
fi

H "6) Tekshiruv"
if (command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ":$PORT ") ||
   (command -v netstat >/dev/null 2>&1 && netstat -ltn 2>/dev/null | grep -q ":$PORT "); then
    ok "$PORT-port tinglanmoqda"
else
    wa "$PORT-port tinglanmayapti"
fi

# ---------- yakun ----------
echo ""; line
printf "  %sTAYYOR%s\n" "$C_GR" "$C_0"
line
printf "  %sULANISH:%s\n" "$C_CY" "$C_0"
P=""; [ "$PORT" != "22" ] && P="-p $PORT "
if [ "$USE_LAN" = "1" ] || [ "$TERMUX" = "1" ]; then
    for ip in $IPS; do echo "    ssh $P$(whoami)@$ip"; done
fi
if [ "$TERMUX" = "1" ]; then
    printf "
  %sTermux bitta foydalanuvchili - istalgan nom bilan kirsa bo'ladi:%s
" "$C_GY" "$C_0"
    for ip in $IPS; do echo "    ssh ${P}muqimjon@$ip"; break; done
    printf "
  %s~/.ssh/config ga qo'shsang - shunchaki 'ssh phone':%s
" "$C_GY" "$C_0"
    echo "    Host phone"
    for ip in $IPS; do echo "        HostName $ip"; break; done
    echo "        Port $PORT"
    echo "        User muqimjon"
fi
if [ "$USE_TS" = "1" ]; then
    TSIP=$(tailscale ip -4 2>/dev/null | head -1)
    [ -n "$TSIP" ] && echo "    ssh $P$(whoami)@$TSIP   (istalgan joydan)"
    [ "$TERMUX" = "1" ] && echo "    ssh $P$(whoami)@<telefonning-tailscale-IP>   (ilovada ko'rasan)"
fi
if [ -n "$KEYS" ] && [ "$DISABLE_PW" = "0" ]; then
    echo ""
    wa "Kalit bilan kirganingni tekshirgach parolni o'chir:"
    printf "      %ssed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' %s%s\n" "$C_GY" "$CFG" "$C_0"
fi
echo ""

# Fayldan ishga tushirilgan bo'lsa (masalan `curl -o s.sh && bash s.sh`),
# skript o'zini o'chiradi. `curl | bash` da $0 fayl emas - tegmaydi.
if [ -f "$0" ] && [ "$0" != "bash" ] && [ "$0" != "sh" ]; then
    rm -f -- "$0" 2>/dev/null || true
fi
