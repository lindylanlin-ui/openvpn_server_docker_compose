#!/usr/bin/env sh
set -eu

# 先切回專案根目錄，避免相對路徑判斷錯誤。
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

cidr_to_mask() {
  prefix=${1#*/}
  octet1=0
  octet2=0
  octet3=0
  octet4=0

  full=$((prefix / 8))
  part=$((prefix % 8))

  index=1
  while [ "$index" -le "$full" ]; do
    eval "octet${index}=255"
    index=$((index + 1))
  done

  if [ "$full" -lt 4 ] && [ "$part" -gt 0 ]; then
    case "$part" in
      1) value=128 ;;
      2) value=192 ;;
      3) value=224 ;;
      4) value=240 ;;
      5) value=248 ;;
      6) value=252 ;;
      7) value=254 ;;
      *) value=0 ;;
    esac
    eval "octet$((full + 1))=${value}"
  fi

  printf '%s.%s.%s.%s\n' "$octet1" "$octet2" "$octet3" "$octet4"
}

cidr_to_network() {
  printf '%s\n' "${1%/*}"
}

is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_cidr() {
  value=${1:-}
  name=${2:-CIDR}

  case "$value" in
    *.*.*.*/*)
      ;;
    *)
      echo "${name} 必須是 CIDR 格式，例如 192.168.4.0/24。" >&2
      exit 1
      ;;
  esac
}

if ! command -v docker >/dev/null 2>&1; then
  echo "找不到 docker，請先確認 Docker 已安裝且可執行。" >&2
  exit 1
fi

if [ ! -f ".env" ]; then
  echo "找不到 .env，請先從 .env.example 複製一份。" >&2
  exit 1
fi

. ./.env

# 從 .env 讀取部署參數，缺值時套用安全預設值。
SERVER_HOST=${OVPN_HOSTNAME_OR_IP:-}
SERVER_PROTO=${OVPN_PROTO:-udp}
SERVER_PORT=${OVPN_PORT:-1194}
VPN_NETWORK=${OVPN_NETWORK:-10.8.0.0/24}
LAN_SUBNET=${OVPN_LAN_SUBNET:-}
DNS_SERVERS=${OVPN_DNS_SERVERS:-1.1.1.1,1.0.0.1}
CLIENT_TO_CLIENT=${OVPN_CLIENT_TO_CLIENT:-false}

# 避免直接用預設範例主機名誤做初始化。
if [ -z "$SERVER_HOST" ] || [ "$SERVER_HOST" = "vpn.example.com" ]; then
  echo "初始化前，請先在 .env 中設定正確的 OVPN_HOSTNAME_OR_IP。" >&2
  exit 1
fi

if [ -z "$LAN_SUBNET" ]; then
  echo "初始化前，請先在 .env 中設定 OVPN_LAN_SUBNET。" >&2
  exit 1
fi

require_cidr "$VPN_NETWORK" "OVPN_NETWORK"
require_cidr "$LAN_SUBNET" "OVPN_LAN_SUBNET"

# 若已初始化過，就停止執行，避免覆蓋既有 PKI 資料。
if [ -f "openvpn-data/openvpn.conf" ]; then
  echo "偵測到 openvpn-data/openvpn.conf 已存在。"
  echo "如果你真的要重建整套憑證與設定，請先手動清除 openvpn-data 內容。"
  exit 1
fi

mkdir -p openvpn-data clients

SERVER_URL="${SERVER_PROTO}://${SERVER_HOST}:${SERVER_PORT}"
LAN_ROUTE="route $(cidr_to_network "$LAN_SUBNET") $(cidr_to_mask "$LAN_SUBNET")"

set -- ovpn_genconfig \
  -u "$SERVER_URL" \
  -s "$VPN_NETWORK" \
  -N \
  -p "$LAN_ROUTE"

if is_true "$CLIENT_TO_CLIENT"; then
  # 若需要多個 client 彼此互通，可透過此選項啟用。
  set -- "$@" -c
fi

OLD_IFS=${IFS}
IFS=','
for dns in $DNS_SERVERS; do
  trimmed_dns=$(printf '%s' "$dns" | tr -d '[:space:]')
  if [ -n "$trimmed_dns" ]; then
    set -- "$@" -n "$trimmed_dns"
  fi
done
IFS=${OLD_IFS}

echo "正在產生 OpenVPN server 設定：${SERVER_URL}"
echo "家中 LAN 網段會推送給 client：${LAN_SUBNET}"
echo "client 連線後的所有流量會預設走家中的 OpenVPN 出口。"

# 產生 /etc/openvpn/openvpn.conf，並把家中 LAN 路由與 DNS 一起寫入。
docker compose run --rm openvpn sh -c 'exec "$@"' sh "$@"

echo "正在初始化 PKI 與 server 憑證 ..."
# 建立 CA、server 憑證與初始 PKI 檔案，採用憑證驗證模式。
docker compose run --rm openvpn ovpn_initpki nopass

echo
echo "初始化完成。"
echo "下一步請執行：docker compose up -d"
