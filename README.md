# OpenVPN Server Docker Compose

這個專案的目標是建立一台「家用情境」的 OpenVPN Server，符合以下需求：

- Router 只需要做 `UDP port forward`
- iPhone / Android / MacBook Air 等裝置可從外面連回家
- 連回來後可存取家中的 NAS、桌機、其他內網設備
- Client 連線後的所有流量都走家裡這台 OpenVPN Server 出外網
- 使用憑證認證
- 專案推上 GitHub 時，不把私人資料、憑證、client 設定檔一起上傳

## 架構說明

這份設定採用：

- `kylemanna/openvpn` 作為 OpenVPN server 映像
- `docker compose` 管理容器
- 憑證認證作為 client 驗證方式
- Full Tunnel 模式
  - client 連線後，所有外網流量都會走你家中的 OpenVPN 出口
- 內網路由推送
  - client 連線後，可以直接存取你家裡 LAN 裡的設備

## 這份專案幫你處理了什麼

- OpenVPN server 的容器設定
- PKI 初始化腳本
- client 憑證與 `.ovpn` 匯出腳本
- 把家中 LAN 網段推送給 client
- 把 DNS 推送給 client
- 避免把 `.env`、憑證、client 設定檔提交到 GitHub

## 事前準備

你需要先準備：

- 一台可執行 Docker 的 Linux 主機
- 這台主機在家中 LAN 內有固定 IP 或 DHCP 保留位址
- Router 可設定 `UDP port forward`
- 主機有 `/dev/net/tun`

建議先確認：

- 你的 OpenVPN 主機 LAN IP
  - 例如 `192.168.4.103`
- 你的家中 LAN 網段
  - 例如 `192.168.4.0/24`
- 你的公開 IP 或 DDNS 網域
  - 例如 `myhome.ddns.net`

## Router 設定

你只需要做這一項：

- 把 router 的 `UDP 1194` 轉發到這台 OpenVPN 主機的 LAN IP

例如：

- 外部 Port: `1194/UDP`
- 內部主機: `192.168.4.103`
- 內部 Port: `1194/UDP`

如果你之後在 `.env` 改成別的 `OVPN_PORT`，router 也要跟著改成相同的外部 port。

## 1. 建立 `.env`

先從範本複製：

```bash
cp .env.example .env
```

再編輯 `.env`。

### 範例

```dotenv
OVPN_HOSTNAME_OR_IP=myhome.ddns.net
OVPN_PROTO=udp
OVPN_PORT=1194
OVPN_NETWORK=10.8.0.0/24
OVPN_LAN_SUBNET=192.168.4.0/24
OVPN_DNS_SERVERS=1.1.1.1,1.0.0.1
OVPN_SERVER_CN=MyHomeOpenVPN
OVPN_CLIENT_TO_CLIENT=false
```

### 參數說明

- `OVPN_HOSTNAME_OR_IP`
  - 給外部 client 連線用的公開 IP 或 DDNS 網域
  - 如果你家是浮動 IP，建議用 DDNS
- `OVPN_PROTO`
  - 一般家用情境維持 `udp`
- `OVPN_PORT`
  - OpenVPN 對外 port
  - Router port forward 要跟這個一致
- `OVPN_NETWORK`
  - VPN client 連上後分配到的虛擬網段
  - 建議不要和家中 LAN 網段重疊
- `OVPN_LAN_SUBNET`
  - 你家裡真正的 LAN 網段
  - 例如 `192.168.4.0/24`
  - 這個設定會讓你的手機或筆電連回來後能找到 NAS、桌機、印表機等設備
- `OVPN_DNS_SERVERS`
  - client 連線後使用的 DNS
  - 如果你只要穩定上網，先用 `1.1.1.1,1.0.0.1` 就可以
  - 如果你還想解析內網設備名稱，可改成家中 router 或內部 DNS
- `OVPN_SERVER_CN`
  - 建立 server 憑證時使用的名稱
- `OVPN_CLIENT_TO_CLIENT`
  - 是否允許多個 VPN client 彼此互通
  - 一般家用可維持 `false`

## 2. 初始化 OpenVPN Server 與憑證

```bash
./scripts/init-openvpn.sh
```

這個腳本會幫你完成：

- 依照 `.env` 產生 OpenVPN server 設定
- 啟用 Full Tunnel
- 推送家中 LAN 路由給 client
- 推送 DNS 給 client
- 初始化 CA、server 憑證與 PKI

## 3. 啟動 OpenVPN Server

```bash
docker compose up -d
```

查看狀態：

```bash
docker compose ps
docker compose logs -f openvpn
```

## 4. 建立 client 設定檔

你可以為每一台裝置建立一份獨立憑證，建議一台裝置一個名稱。

例如：

```bash
./scripts/create-client.sh iphone
./scripts/create-client.sh macbook-air
./scripts/create-client.sh ipad
./scripts/create-client.sh work-laptop
```

輸出檔會在：

```text
clients/iphone.ovpn
clients/macbook-air.ovpn
clients/ipad.ovpn
clients/work-laptop.ovpn
```

這種做法很適合你現在提到的 3 到 4 台裝置，而且之後要增加也很直接。

## 5. 匯入到手機或 Mac

### 手機

可使用 OpenVPN Connect 匯入對應的 `.ovpn` 檔。

### MacBook Air

可使用 OpenVPN Connect 或其他支援 OpenVPN 的 client 匯入 `.ovpn`。

建議：

- 不同裝置不要共用同一份 `.ovpn`
- 每台裝置各自建立獨立憑證

## 6. 驗證是否符合你的需求

### 驗證可否連回家

連線成功後，先測試：

- 是否能 ping 到家中 NAS IP
- 是否能打開 NAS web 介面
- 是否能連到桌機或其他內網設備

### 驗證是否走家中外網

client 連上 VPN 後，打開：

- `https://ifconfig.me`
- `https://whatismyipaddress.com`

如果顯示的是你家中的公開 IP，就代表「所有流量都走家裡外網」已經成立。

## 7. 主機端注意事項

### 開啟 IPv4 Forwarding

大多數 Docker 主機本來就會啟用，但若你遇到 client 能連線卻不能上網，可先確認：

```bash
sysctl net.ipv4.ip_forward
```

如果不是 `1`，請執行：

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

若要永久生效，請把設定寫進系統的 `sysctl` 設定檔。

### 避免網段衝突

如果你在外面連線的地方，剛好也使用和你家一樣的 LAN 網段，例如都叫做 `192.168.1.0/24`，那麼存取家中內網設備可能會出現衝突。

比較理想的做法是：

- 讓家中 LAN 使用較不常見的網段
- 例如 `192.168.50.0/24` 或 `10.20.30.0/24`

這不是 OpenVPN 的限制，而是所有 VPN 常見的網段重疊問題。

## 8. 隱私與 GitHub 安全

這個專案目前已經避免把以下內容提交到 GitHub：

- `.env`
- `openvpn-data/` 內的 server 設定、CA、憑證、私鑰
- `clients/` 內匯出的 `.ovpn`

因此你可以把專案推上 GitHub，但請注意：

- 真正的私人資料在 `.env`
- 真正的敏感資料在 `openvpn-data/`
- client 設定檔本身也屬於敏感資料

不要把這些檔案手動改名後再提交。

## 常用指令

初始化：

```bash
./scripts/init-openvpn.sh
```

啟動：

```bash
docker compose up -d
```

查看狀態：

```bash
docker compose ps
```

查看日誌：

```bash
docker compose logs -f openvpn
```

建立 client：

```bash
./scripts/create-client.sh iphone
```

停止服務：

```bash
docker compose down
```

## 目前的認證方式

目前這份專案使用的是：

- 憑證認證
- client 憑證以 `nopass` 方式建立

這代表：

- 你仍然是在使用憑證驗證
- 但 `.ovpn` 一旦外流，別人就可能拿去連線

所以務必妥善保管：

- `clients/*.ovpn`
- `openvpn-data/`

如果你之後想升級成更嚴格的模式，我可以再幫你補：

- 憑證加密碼
- 撤銷遺失裝置的憑證
- 多因素驗證
- 固定 client IP
