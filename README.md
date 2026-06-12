# OpenVPN Server with Docker Compose

這個專案使用 `docker compose` 搭配 `kylemanna/openvpn` 建立一個基本可用的 OpenVPN Server。

## 需求

- Linux 主機
- Docker 與 Docker Compose v2
- 主機有 `/dev/net/tun`
- 對外防火牆或雲端 security group 已開放 `UDP/1194`

## 1. 調整設定

編輯 `.env`，至少修改這些值：

- `OVPN_HOSTNAME_OR_IP`: 你的公開 IP 或網域名稱
- `OVPN_PORT`: 對外 OpenVPN port，預設 `1194`
- `OVPN_NETWORK`: VPN client 位址池，預設 `10.8.0.0/24`
- `OVPN_SERVER_CN`: 憑證 Common Name

## 2. 初始化 OpenVPN 與 PKI

```bash
./scripts/init-openvpn.sh
```

這一步會：

- 生成 `openvpn-data/openvpn.conf`
- 建立 CA / server certificate / client certificate infrastructure

## 3. 啟動 OpenVPN Server

```bash
docker compose up -d
```

查看狀態：

```bash
docker compose ps
docker compose logs -f openvpn
```

## 4. 建立 Client 設定檔

```bash
./scripts/create-client.sh alice
```

輸出檔案會在：

```text
clients/alice.ovpn
```

把這個 `.ovpn` 匯入 OpenVPN Connect 或其他 OpenVPN client 即可連線。

## 5. 主機設定提醒

若你的 Linux 主機尚未開啟 IPv4 forwarding，先執行：

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

若在雲端或家用路由器後面，也要確認：

- 外部 `UDP/1194` 已放行
- 若主機在 NAT 後面，已做好 port forwarding

## 常用指令

停止服務：

```bash
docker compose down
```

重新啟動服務：

```bash
docker compose restart openvpn
```

## 備註

- 目前的 client 憑證是用 `nopass` 方式建立，適合先快速完成部署。
- 如果你想改成 client certificate 需要密碼、加上帳密驗證、或只讓特定內網走 VPN，我可以再幫你把設定補上。
