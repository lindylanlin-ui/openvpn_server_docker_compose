#!/usr/bin/env sh
set -eu

# 先切回專案根目錄，避免相對路徑判斷錯誤。
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found in PATH" >&2
  exit 1
fi

if [ ! -f ".env" ]; then
  echo ".env is missing" >&2
  exit 1
fi

. ./.env

# 從 .env 讀取部署參數，缺值時套用安全預設值。
SERVER_HOST=${OVPN_HOSTNAME_OR_IP:-}
SERVER_PROTO=${OVPN_PROTO:-udp}
SERVER_PORT=${OVPN_PORT:-1194}
VPN_NETWORK=${OVPN_NETWORK:-10.8.0.0/24}

# 避免直接用預設範例主機名誤做初始化。
if [ -z "$SERVER_HOST" ] || [ "$SERVER_HOST" = "vpn.example.com" ]; then
  echo "Please update OVPN_HOSTNAME_OR_IP in .env before initialization." >&2
  exit 1
fi

# 若已初始化過，就停止執行，避免覆蓋既有 PKI 資料。
if [ -f "openvpn-data/openvpn.conf" ]; then
  echo "openvpn-data/openvpn.conf already exists."
  echo "Remove openvpn-data if you really want to re-initialize everything."
  exit 1
fi

mkdir -p openvpn-data clients

SERVER_URL="${SERVER_PROTO}://${SERVER_HOST}:${SERVER_PORT}"

echo "Generating server config for ${SERVER_URL} ..."
# 在掛載資料夾中產生 /etc/openvpn/openvpn.conf。
docker compose run --rm openvpn \
  ovpn_genconfig \
  -u "$SERVER_URL" \
  -s "$VPN_NETWORK"

echo "Initializing PKI ..."
# 建立 CA、server 憑證與初始 PKI 檔案，且不設定密碼。
docker compose run --rm openvpn ovpn_initpki nopass

echo
echo "Initialization complete."
echo "Next step: docker compose up -d"
