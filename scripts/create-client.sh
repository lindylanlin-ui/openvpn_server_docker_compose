#!/usr/bin/env sh
set -eu

# 先切回專案根目錄，確保輸出檔案位置正確。
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

CLIENT_NAME=${1:-}
PASS_MODE=${2:-}

prompt_hidden() {
  label=${1:-}
  printf '%s' "$label" >&2
  stty -echo
  IFS= read -r value
  stty echo
  printf '\n' >&2
  printf '%s' "$value"
}

is_running() {
  docker compose ps --status running --services | grep -qx 'openvpn'
}

get_container_id() {
  docker compose ps -q openvpn
}

cert_exists_in_container() {
  docker exec "$1" test -f "/etc/openvpn/pki/issued/$2.crt"
}

if [ -z "$CLIENT_NAME" ]; then
  echo "用法：$0 <client-name> [--no-pass]" >&2
  exit 1
fi

# 預設建立有密碼保護的 client 私鑰；需要相容舊行為時才用 --no-pass。
if [ -n "$PASS_MODE" ] && [ "$PASS_MODE" != "--no-pass" ]; then
  echo "不支援的參數：$PASS_MODE" >&2
  echo "可用參數只有 --no-pass" >&2
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

# 匯出 .ovpn 時需要讀取正在執行中的 OpenVPN 容器內容。
if ! is_running; then
  echo "OpenVPN 服務尚未啟動，先自動啟動 openvpn 服務 ..."
  docker compose up -d openvpn
fi

OPENVPN_CONTAINER_ID=$(get_container_id)
if [ -z "$OPENVPN_CONTAINER_ID" ]; then
  echo "找不到 openvpn 容器，請確認 docker compose up -d openvpn 是否成功。" >&2
  exit 1
fi

if cert_exists_in_container "$OPENVPN_CONTAINER_ID" "$CLIENT_NAME"; then
  echo "client 憑證 ${CLIENT_NAME} 已存在，請改用新的名稱，或先撤銷舊憑證。" >&2
  exit 1
fi

mkdir -p clients

echo "正在為 ${CLIENT_NAME} 建立 client 憑證 ..."
# 透過 EasyRSA 建立 client 憑證與私鑰，預設使用密碼保護私鑰。
if [ "$PASS_MODE" = "--no-pass" ]; then
  docker compose run --rm -T --entrypoint /bin/sh openvpn \
    -c 'exec easyrsa build-client-full "$1" nopass' sh "$CLIENT_NAME"
else
  if [ -z "${CLIENT_CERT_PASSWORD:-}" ]; then
    if [ ! -t 0 ] || [ ! -t 1 ]; then
      echo "目前不是互動式終端，無法安全輸入憑證密碼。" >&2
      echo "請直接在終端機執行此腳本，或暫時改用 --no-pass。" >&2
      exit 1
    fi

    PASSWORD_1=$(prompt_hidden "請輸入 ${CLIENT_NAME} 憑證密碼：")
    PASSWORD_2=$(prompt_hidden "請再次輸入 ${CLIENT_NAME} 憑證密碼：")

    if [ -z "$PASSWORD_1" ]; then
      echo "憑證密碼不可為空白。" >&2
      exit 1
    fi

    if [ "$PASSWORD_1" != "$PASSWORD_2" ]; then
      echo "兩次輸入的憑證密碼不一致。" >&2
      exit 1
    fi

    CLIENT_CERT_PASSWORD=$PASSWORD_1
    unset PASSWORD_1 PASSWORD_2
  fi

  docker compose run --rm -T --entrypoint /bin/sh \
    -e CLIENT_CERT_PASSWORD="$CLIENT_CERT_PASSWORD" \
    openvpn \
    sh -c 'exec easyrsa --batch --passout=env:CLIENT_CERT_PASSWORD build-client-full "$1"' sh "$CLIENT_NAME"
fi

echo "正在匯出 ${CLIENT_NAME} 的 .ovpn 設定檔 ..."
# 將憑證、私鑰與連線端點封裝成單一 .ovpn 設定檔。
TMP_CONTAINER_OVPN="/tmp/${CLIENT_NAME}.ovpn"
docker compose exec -T openvpn sh -c "OPENVPN=/etc/openvpn ovpn_getclient \"$CLIENT_NAME\" > \"$TMP_CONTAINER_OVPN\""
docker cp "${OPENVPN_CONTAINER_ID}:${TMP_CONTAINER_OVPN}" "clients/${CLIENT_NAME}.ovpn"
chmod 600 "clients/${CLIENT_NAME}.ovpn"
docker exec "$OPENVPN_CONTAINER_ID" rm -f "$TMP_CONTAINER_OVPN"

echo "已輸出 client 設定檔：clients/${CLIENT_NAME}.ovpn"
if [ "$PASS_MODE" = "--no-pass" ]; then
  echo "這份 client 憑證沒有密碼保護，請特別妥善保管。" 
else
  echo "這份 client 憑證有密碼保護，匯入後連線時會需要輸入密碼。"
fi
