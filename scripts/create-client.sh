#!/usr/bin/env sh
set -eu

# 先切回專案根目錄，確保輸出檔案位置正確。
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

CLIENT_NAME=${1:-}

if [ -z "$CLIENT_NAME" ]; then
  echo "Usage: $0 <client-name>" >&2
  exit 1
fi

# 限制 client 名稱格式，避免憑證名稱與檔名出現問題。
case "$CLIENT_NAME" in
  *[!A-Za-z0-9._-]*)
    echo "Client name may only contain letters, numbers, dot, underscore, and hyphen." >&2
    exit 1
    ;;
esac

# 用 server 設定檔是否存在，判斷是否已完成初始化。
if [ ! -f "openvpn-data/openvpn.conf" ]; then
  echo "Server is not initialized yet. Run ./scripts/init-openvpn.sh first." >&2
  exit 1
fi

mkdir -p clients

echo "Creating certificate for ${CLIENT_NAME} ..."
# 透過 EasyRSA 建立 client 憑證與私鑰。
docker compose run --rm openvpn easyrsa build-client-full "$CLIENT_NAME" nopass

echo "Exporting client profile ..."
# 將憑證、私鑰與連線端點封裝成單一 .ovpn 設定檔。
docker compose run --rm openvpn ovpn_getclient "$CLIENT_NAME" > "clients/${CLIENT_NAME}.ovpn"

echo "Client profile written to clients/${CLIENT_NAME}.ovpn"
