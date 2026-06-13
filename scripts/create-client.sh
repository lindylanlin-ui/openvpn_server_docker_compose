#!/usr/bin/env sh
set -eu

# 先切回專案根目錄，確保輸出檔案位置正確。
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

CLIENT_NAME=${1:-}

if [ -z "$CLIENT_NAME" ]; then
  echo "用法：$0 <client-name>" >&2
  exit 1
fi

# 限制 client 名稱格式，避免憑證名稱與檔名出現問題。
case "$CLIENT_NAME" in
  *[!A-Za-z0-9._-]*)
    echo "client 名稱只能包含英文字母、數字、點、底線與連字號。" >&2
    exit 1
    ;;
esac

# 用 server 設定檔是否存在，判斷是否已完成初始化。
if [ ! -f "openvpn-data/openvpn.conf" ]; then
  echo "OpenVPN server 尚未初始化，請先執行 ./scripts/init-openvpn.sh。" >&2
  exit 1
fi

mkdir -p clients

echo "正在為 ${CLIENT_NAME} 建立 client 憑證 ..."
# 透過 EasyRSA 建立 client 憑證與私鑰，採用憑證驗證方式。
docker compose run --rm openvpn easyrsa build-client-full "$CLIENT_NAME" nopass

echo "正在匯出 ${CLIENT_NAME} 的 .ovpn 設定檔 ..."
# 將憑證、私鑰與連線端點封裝成單一 .ovpn 設定檔。
docker compose run --rm openvpn ovpn_getclient "$CLIENT_NAME" > "clients/${CLIENT_NAME}.ovpn"

echo "已輸出 client 設定檔：clients/${CLIENT_NAME}.ovpn"
