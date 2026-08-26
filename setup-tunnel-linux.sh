#!/usr/bin/env bash
# Linux kompyuterni Cloudflare Tunnel orqali GLOBAL SSH ga ulanadigan qiladi.
# Router sozlanmaydi, port ochilmaydi, statik IP kerak emas.
#
# Foydalanish:
#     bash setup-tunnel-linux.sh ssh.mijoz.uz "ssh-ed25519 AAAA..."
#
# Shart: domen Cloudflare da (nameserverlar Cloudflare ga qaratilgan).

set -euo pipefail
HOSTNAME_FQDN="${1:-}"
PUBKEY="${2:-}"
TUNNEL_NAME="$(hostname | tr '[:upper:]' '[:lower:]')"

[ -z "$HOSTNAME_FQDN" ] && { echo "Foydalanish: bash $0 <hostname> [pubkey]"; exit 1; }
[ "$(id -u)" -eq 0 ] && SUDO="" || SUDO="sudo"

step() { printf "\n\033[36m>> %s\033[0m\n" "$1"; }
ok()   { printf "   \033[32mOK: %s\033[0m\n" "$1"; }
die()  { printf "\n   \033[31mXATO: %s\033[0m\n" "$1"; exit 1; }

step "0/6 Mavjud cloudflared xizmatini tekshirish"
if systemctl list-units --all 2>/dev/null | grep -q 'cloudflared.service'; then
    die "cloudflared xizmati ALLAQACHON ishlayapti.
   Ikkinchi tunnel uni buzadi. Buning o'rniga Cloudflare dashboard da
   mavjud tunnelga Public Hostname qo'sh: Type=SSH, URL=localhost:22"
fi
ok "mavjud xizmat yo'q"

step "1/6 SSH server"
if ! [ -x /usr/sbin/sshd ] && ! command -v sshd >/dev/null 2>&1; then
    if   command -v apt-get >/dev/null; then $SUDO apt-get update -qq && $SUDO apt-get install -y openssh-server
    elif command -v dnf     >/dev/null; then $SUDO dnf install -y openssh-server
    elif command -v pacman  >/dev/null; then $SUDO pacman -S --noconfirm openssh
    else die "paket menejeri topilmadi"; fi
fi
SVC=ssh; systemctl list-unit-files | grep -q '^sshd\.service' && SVC=sshd
$SUDO systemctl enable --now "$SVC"
ok "$SVC ishlayapti (localhost:22)"

step "2/6 Ochiq kalitni joylash"
if [ -z "$PUBKEY" ]; then
    printf "   \033[33m! kalit berilmadi - parol bilan kiriladi\033[0m\n"
else
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
    if ! grep -qF "$(echo "$PUBKEY" | awk '{print $2}')" ~/.ssh/authorized_keys; then
        echo "$PUBKEY" >> ~/.ssh/authorized_keys
    fi
    ok "authorized_keys tayyor"
fi

step "3/6 cloudflared o'rnatish"
if ! command -v cloudflared >/dev/null 2>&1; then
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$ARCH" in
        amd64|x86_64) CFARCH=amd64 ;;
        arm64|aarch64) CFARCH=arm64 ;;
        *) die "qo'llab-quvvatlanmagan arxitektura: $ARCH" ;;
    esac
    URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CFARCH}"
    $SUDO curl -fsSL "$URL" -o /usr/local/bin/cloudflared
    $SUDO chmod +x /usr/local/bin/cloudflared
fi
ok "$(cloudflared --version)"

step "4/6 Cloudflare hisobiga kirish"
if [ ! -f ~/.cloudflared/cert.pem ]; then
    printf "   \033[33mQuyidagi havolani brauzerda och va domenni tanla:\033[0m\n"
    cloudflared tunnel login
    [ -f ~/.cloudflared/cert.pem ] || die "login bajarilmadi"
fi
ok "cert.pem mavjud"

step "5/6 Tunnel yaratish va DNS"
if ! cloudflared tunnel list | awk '{print $2}' | grep -qx "$TUNNEL_NAME"; then
    cloudflared tunnel create "$TUNNEL_NAME"
else
    echo "   tunnel allaqachon bor"
fi
UUID=$(cloudflared tunnel list --output json | grep -B2 "\"name\": *\"$TUNNEL_NAME\"" | grep '"id"' | head -1 | cut -d'"' -f4)
[ -z "$UUID" ] && UUID=$(cloudflared tunnel list | awk -v n="$TUNNEL_NAME" '$2==n {print $1}' | head -1)
[ -z "$UUID" ] && die "tunnel UUID topilmadi"

cat > ~/.cloudflared/config.yml <<EOF
tunnel: $UUID
credentials-file: $HOME/.cloudflared/$UUID.json

ingress:
  - hostname: $HOSTNAME_FQDN
    service: ssh://localhost:22
  - service: http_status:404
EOF

cloudflared tunnel route dns "$TUNNEL_NAME" "$HOSTNAME_FQDN"
ok "$HOSTNAME_FQDN -> $TUNNEL_NAME ($UUID)"

step "6/6 Xizmat sifatida o'rnatish"
$SUDO cloudflared --config "$HOME/.cloudflared/config.yml" service install
$SUDO systemctl enable --now cloudflared
ok "cloudflared xizmati ishlayapti"

printf "\n\033[32m===== TAYYOR =====\033[0m\n"
echo "Hostname : $HOSTNAME_FQDN"
echo "Tunnel   : $TUNNEL_NAME"
echo "User     : $(whoami)"
cat <<EOF

KEYINGI QADAM - HIMOYA (tashlab ketma!):
  Zero Trust -> Access -> Applications -> Add -> Self-hosted
    Application domain : $HOSTNAME_FQDN
    Policy: Action=Allow, Include -> Emails -> sening@email.com
  O'sha yerda "Browser rendering -> SSH" ni yoqsang,
  hech narsa o'rnatmasdan brauzerdan terminal ochiladi.

ULANISH (o'z kompyuteringdan):
  Host mijoz1
      HostName $HOSTNAME_FQDN
      User $(whoami)
      ProxyCommand cloudflared access ssh --hostname %h
EOF
