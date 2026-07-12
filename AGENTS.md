# AGENTS.md

本文件適用於整個 repository，供在此專案中工作的自動化代理與協作者使用。

## 專案目標

這是一個家用 OpenVPN Server 部署專案，使用 `kylemanna/openvpn` 與 Docker Compose，提供：

- UDP port forwarding 後的遠端 VPN 連線
- VPN client 存取家中 LAN
- Full Tunnel（client 的外網流量由家中主機送出）
- 每台裝置獨立的憑證建立、匯出與撤銷流程

安全性與可恢復性優先於操作方便。任何變更都不得意外覆蓋 PKI、洩漏私鑰，或在未獲授權時改動正在運行的 VPN 服務。

## Repository 結構

- `docker-compose.yml`：OpenVPN 服務、port、volume、capability 與 sysctl 設定。
- `.env.example`：可提交的部署參數範本，也是環境變數文件的主要來源。
- `scripts/init-openvpn.sh`：產生 server 設定並初始化 PKI；屬於有狀態且高影響的操作。
- `scripts/create-client.sh`：建立 client 憑證並匯出 `.ovpn`。
- `scripts/revoke-client.sh`：撤銷憑證、更新 CRL，並可能重啟服務。
- `logrotate/openvpn_server_docker_compose`：主機端的 logrotate 設定；其中使用者名稱與路徑可能依部署主機而異。
- `README.md`：面向使用者的安裝與操作說明。
- `openvpn-data/`、`clients/`、`logs/`：本機執行時資料；除 `.gitkeep` 外不得提交。

## 敏感資料與操作安全

- 不得讀取、輸出、提交或貼入回覆中的內容：`.env`、`openvpn-data/`、`clients/*.ovpn`、私鑰、憑證密碼及實際 DDNS／公開 IP 等部署資訊。
- 需要了解設定格式時，只讀 `.env.example`；不可用真實 `.env` 的值更新範例或測試快照。
- 不得放寬 `.gitignore` 對 `.env`、`openvpn-data/`、`clients/`、`logs/` 的保護。
- 除非使用者明確要求執行部署操作，否則不要執行初始化、建立 client、撤銷 client、啟動／重啟服務等會改變狀態的命令。
- 絕對不要為了測試而清除或重建 `openvpn-data/`。若重建 PKI 確實是目標，先說明所有既有 client 憑證將失效並取得明確確認。
- 不要把密碼直接寫入命令、程式碼、文件、log 或 Git history。保留腳本既有的隱藏式互動輸入與環境變數傳遞方式。
- `revoke-client.sh` 的確認提示是安全邊界；不可在一般重構中移除或預設略過。

## 程式碼與文件慣例

### Shell scripts

- 維持 POSIX `sh` 相容性；使用 `#!/usr/bin/env sh`，不要引入 Bash-only 語法。
- 保留 `set -eu`，並引用所有可能含空白或 glob 字元的變數。
- 腳本應從任意工作目錄皆可執行；沿用先解析 repository root、再 `cd` 的模式。
- 所有輸入都必須先驗證，再傳給 shell、Docker、EasyRSA 或檔案路徑。
- 錯誤訊息寫到 stderr，失敗時回傳非零狀態；使用者可見文字維持繁體中文。
- 優先使用可在常見 Linux 環境執行的標準工具，避免無必要的新依賴。
- 涉及憑證或暫存檔時，必須考慮中途失敗後的殘留與清理，不可讓秘密出現在主機或容器的非預期位置。

### Compose 與環境變數

- 環境變數新增或改名時，同步更新 `.env.example`、`README.md`、相關 shell script 與 `docker-compose.yml`。
- 保留 Compose 的參數預設值與腳本預設值一致，避免文件、初始化結果與 runtime 行為分歧。
- 修改 port 或 protocol 時，同時檢查 OpenVPN server URL、Compose port mapping 與 README 的 router forwarding 說明。
- `openvpn-data:/etc/openvpn` 是持久化與 PKI 邊界；不可隨意改成匿名 volume 或非持久化儲存。
- OpenVPN 需要 `/dev/net/tun`、`NET_ADMIN` 與 IPv4 forwarding；若調整，必須說明對 VPN routing 的影響。

### 文件

- README 與註解使用繁體中文，命令、檔名、環境變數及技術名詞可保留英文。
- 文件中的 hostname、IP、client 名稱與密碼只能使用明顯的範例值。
- 行為、CLI 參數、預設值或輸出路徑改變時，同一變更內更新 README。
- 保持指令可直接複製執行，並區分一般操作與具有破壞性的操作。

## 驗證方式

專案目前沒有自動化整合測試。對一般變更，至少執行：

```sh
for file in scripts/*.sh; do sh -n "$file"; done
shellcheck -e SC1007,SC1091 scripts/*.sh
docker compose config -q
git diff --check
```

說明：

- `SC1007` 對本專案用來清空 `CDPATH` 的 `CDPATH= cd ...` 模式會產生既有警告。
- `SC1091` 來自 runtime 才存在且刻意不納入版控的 `.env`。
- `docker compose config -q` 只做設定驗證，不要執行會把展開後設定（可能含本機值）印出的 `docker compose config`。
- 若 Docker daemon、Compose plugin 或目前執行環境不可用，清楚回報未執行的檢查及原因，不要以啟動實際服務取代靜態驗證。

依變更範圍補充檢查：

- Shell 行為變更：涵蓋無參數、無效名稱、無效 option、缺少初始化資料等不需改動 PKI 的失敗路徑。
- Compose 變更：確認 volume、UDP port、TUN device、capability、restart policy 與 log 路徑仍符合預期。
- 文件／設定變更：搜尋舊變數名、舊預設值與舊指令，確保沒有殘留。

不要用真實 client 憑證或現有 `openvpn-data/` 做測試。需要整合測試時，使用獨立的暫存目錄與明確標示的假資料，且不得接觸正式部署。

## 變更原則

- 先閱讀受影響的腳本、Compose 設定、`.env.example` 與 README，再修改。
- 以最小且聚焦的 patch 完成需求；不要順手重寫無關的部署或安全設定。
- 保留工作樹中既有的使用者變更，不覆蓋、不還原、不提交無關檔案。
- 除非使用者明確要求，不建立 commit、不 push，也不對外發布任何設定或產物。
- 完成時摘要列出修改檔案、行為影響、已執行的驗證，以及因環境限制未能執行的檢查。
