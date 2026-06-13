#!/usr/bin/env sh
set -eu

# 先切回專案根目錄，避免相對路徑判斷錯誤。
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

CLIENT_NAME=${1:-}
REVOKE_REASON=${2:-unspecified}
CONFIRM_FLAG=${3:-}

is_running() {
  docker compose ps --status running --services | grep -qx 'openvpn'
}

cert_exists_in_pki() {
  if is_running; then
    CONTAINER_ID=$(docker compose ps -q openvpn)
    [ -n "$CONTAINER_ID" ] && docker exec "$CONTAINER_ID" test -f "/etc/openvpn/pki/issued/$1.crt"
  else
    docker compose run --rm -T openvpn sh -c 'test -f "/etc/openvpn/pki/issued/$1.crt"' sh "$1"
  fi
}

case "$REVOKE_REASON" in
  unspecified|keyCompromise|CACompromise|affiliationChanged|superseded|cessationOfOperation|certificateHold)
    ;;
  *)
    echo "不支援的撤銷原因：$REVOKE_REASON" >&2
    echo "可用原因：unspecified、keyCompromise、CACompromise、affiliationChanged、superseded、cessationOfOperation、certificateHold" >&2
    exit 1
    ;;
esac

if [ -z "$CLIENT_NAME" ]; then
  echo "用法：$0 <client-name> [reason] [--yes]" >&2
  exit 1
fi

if [ -n "$CONFIRM_FLAG" ] && [ "$CONFIRM_FLAG" != "--yes" ]; then
  echo "不支援的參數：$CONFIRM_FLAG" >&2
  echo "第三個參數只能使用 --yes" >&2
  exit 1
fi

case "$CLIENT_NAME" in
  *[!A-Za-z0-9._-]*)
    echo "client 名稱只能包含英文字母、數字、點、底線與連字號。" >&2
    exit 1
    ;;
esac

if [ ! -f "openvpn-data/openvpn.conf" ]; then
  echo "OpenVPN server 尚未初始化，請先執行 ./scripts/init-openvpn.sh。" >&2
  exit 1
fi

if ! cert_exists_in_pki "$CLIENT_NAME"; then
  echo "找不到 ${CLIENT_NAME} 的已簽發憑證，無法撤銷。" >&2
  exit 1
fi

if [ "$CONFIRM_FLAG" != "--yes" ]; then
  printf '你確定要撤銷 client 憑證 %s 嗎？輸入 yes 繼續：' "$CLIENT_NAME" >&2
  IFS= read -r answer
  if [ "$answer" != "yes" ]; then
    echo "已取消撤銷操作。" >&2
    exit 1
  fi
fi

echo "正在撤銷 ${CLIENT_NAME} 憑證 ..."
docker compose run --rm -T openvpn easyrsa --batch revoke "$CLIENT_NAME" "$REVOKE_REASON"

echo "正在重新產生 CRL ..."
docker compose run --rm -T openvpn easyrsa gen-crl
docker compose run --rm -T openvpn sh -c 'cp -f /etc/openvpn/pki/crl.pem /etc/openvpn/crl.pem && chmod 644 /etc/openvpn/crl.pem'

if [ -f "clients/${CLIENT_NAME}.ovpn" ]; then
  rm -f "clients/${CLIENT_NAME}.ovpn"
  echo "已移除本機匯出的 client 設定檔：clients/${CLIENT_NAME}.ovpn"
fi

if is_running; then
  echo "正在重新啟動 OpenVPN 服務，讓最新的 CRL 立即生效 ..."
  docker compose restart openvpn
fi

echo "憑證 ${CLIENT_NAME} 已撤銷完成。"
