# 📢 VPS 通知系統 (tgvsdd3)

**輕量級 VPS 監控腳本**，通過 *Telegram* 和 *釘釘* 發送 IP 變動、SSH 登錄和資源使用通知。提供兩個版本：

- **普通版（Debian、Ubuntu、CentOS 等）(`tgvsdd3.sh`)**：適用於通用 Linux 系統，支持完整功能。
- **Alpine 版 (`tgvsdd3-alpine.sh`)**：專為 Alpine Linux 設計，依賴精簡，適配輕量環境（如 Docker）。

## ✨ 主要特性

| 功能 | 普通版（Debian、Ubuntu、CentOS 等） | Alpine 版 |
| --- | --- | --- |
| **IP 變動監控** | 實時檢測 IPv4 變化並通知 | 同左 |
| **SSH 登錄通知** | 記錄用戶名和來源 IP | 同左 |
| **資源監控** | 內存和 CPU 超閾值警報 | 同左 |
| **Telegram 通知** | HTML 格式，換行正常 | 純文本，換行正常（v3.0.7 修復） |
| **釘釘通知** | 支持關鍵詞保護和加簽 | 同左 |
| **依賴** | `curl`, `gawk`, `coreutils`, `openssl`, `iputils-ping` | `curl`, `gawk`, `coreutils`, `openssl`, `procps` |
| **其他特性** | 彩色終端、網絡診斷 | 精簡功能，支持彩色終端（v3.0.5+） |
| **一鍵安裝** | 支持 | 支持 |

## 🔧 安裝指南

### 🚀 一鍵安裝

#### 普通版（Debian、Ubuntu、CentOS 等）
```bash
curl -o tgvsdd3.sh -fsSL https://raw.githubusercontent.com/MEILOI/scripts/main/tgvsdd3.sh && chmod +x tgvsdd3.sh && ./tgvsdd3.sh
```

#### Alpine 版
```bash
curl -o tgvsdd3-alpine.sh -fsSL https://raw.githubusercontent.com/MEILOI/scripts/main/tgvsdd3-alpine.sh && chmod +x tgvsdd3-alpine.sh && ./tgvsdd3-alpine.sh
```

### 手動安裝

#### 普通版（Debian、Ubuntu、CentOS 等）
- [ ] **下載腳本**：
  ```bash
  wget https://raw.githubusercontent.com/MEILOI/scripts/main/tgvsdd3.sh -O tgvsdd3.sh
  ```
- [ ] **設置權限**：
  ```bash
  chmod +x tgvsdd3.sh
  ```
- [ ] **運行安裝**：
  ```bash
  ./tgvsdd3.sh install
  ```

#### Alpine 版
- [ ] **下載腳本**：
  ```bash
  wget https://raw.githubusercontent.com/MEILOI/scripts/main/tgvsdd3-alpine.sh -O tgvsdd3-alpine.sh
  ```
- [ ] **設置權限**：
  ```bash
  chmod +x tgvsdd3-alpine.sh
  ```
- [ ] **運行安裝**：
  ```bash
  ./tgvsdd3-alpine.sh install
  ```

### Docker 環境安裝（Alpine 版）
```bash
docker run -it alpine:latest sh
apk add bash curl
curl -o tgvsdd3-alpine.sh -fsSL https://raw.githubusercontent.com/MEILOI/scripts/main/tgvsdd3-alpine.sh
chmod +x tgvsdd3-alpine.sh
./tgvsdd3-alpine.sh install
```

**注意**：確保 Alpine 軟件源包含 `community` 倉庫：
```bash
echo "http://dl-cdn.alpinelinux.org/alpine/v$(cat /etc/alpine-release | cut -d. -f1,2)/community" >> /etc/apk/repositories
apk update
```

## 🛠️ 配置教程

### 1. Telegram 機器人設置
1. **創建機器人**：
   - 搜索 Telegram 的 `@BotFather`，發送 `/start` 和 `/newbot`。
   - 設置名稱和用戶名，記錄 **Bot Token**（如 `123456789:ABCDEF...`）。
2. **獲取 Chat ID**：
   - 將機器人加入聊天，發送消息（如 `Hello`）。
   - 訪問：
     ```
     https://api.telegram.org/botYOUR_BOT_TOKEN/getUpdates
     ```
   - 查找 `"chat":{"id":YOUR_CHAT_ID,...}`，記錄 ID。
3. **配置腳本**：
   - 運行 `vps_notify.sh menu`，選擇“配置 Telegram”。
   - 輸入 Token 和 Chat ID，自動驗證。
   - **普通版**：通知使用 HTML 格式，換行正常。
   - **Alpine 版**：通知使用純文本，v3.0.7 起換行正常。

### 2. 釘釘機器人設置
1. **創建機器人**：
   - 在釘釘群設置中添加“自定義”機器人。
   - 記錄 **Webhook**（如 `https://oapi.dingtalk.com/robot/send?access_token=xxx`）。
   - 啟用加簽（可選），記錄 **Secret**。
   - 檢查是否啟用關鍵詞保護，記錄 **關鍵詞**（如“警報”）。
2. **配置腳本**：
   - 運行 `vps_notify.sh menu`，選擇“配置釘釘”。
   - 輸入 Webhook、關鍵詞（若啟用保護）和 Secret（可選）。
   - 腳本自動在消息中包含關鍵詞。

## 📖 使用說明

### 運行腳本
腳本位於 `/usr/local/bin/vps_notify.sh`：
```bash
vps_notify.sh [命令]
```

**命令**：
- `install`：安裝腳本。
- `uninstall`：卸載腳本。
- `boot`：發送開機通知。
- `ssh`：發送 SSH 通知。
- `monitor`：監控資源和 IP 變化。
- `menu`：交互式菜單（默認）。

### 日誌查看
查看操作日誌（`/var/log/vps_notify.log`）：
```bash
cat /var/log/vps_notify.log
```

## 🐞 已知問題

- **Alpine 版 SSH 通知可能無效**：
  - 問題：若系統未配置日誌文件（`/var/log/auth.log`、`/var/log/secure`、`/var/log/messages`），SSH 通知無法觸發。
  - 影響版本：所有版本。
  - 解決方法：安裝並配置 `syslog` 或 `rsyslog`：
    ```bash
    apk add busybox-syslogd
    setup-syslog
    ```

## 📜 變更日誌

### 普通版（Debian、Ubuntu、CentOS 等）(`tgvsdd3.sh`)
- **v3.0.1 (2025-05-18)**：
  - 初始版本，支持 IP 監控、SSH 通知、資源監控。
  - Telegram 使用 HTML 模式，釘釘支持加簽。
- **v3.0.2 (2025-05-18)**：
  - 優化 Telegram 推送，修復換行問題。
  - 增強釘釘加簽穩定性。
- **v3.0.3 (2025-05-18)**：
  - 添加網絡診斷（`ping`），增強錯誤提示。

### Alpine 版 (`tgvsdd3-alpine.sh`)
- **v3.0.1 (2025-05-18)**：
  - 初始 Alpine 專屬版本，基於普通版 v3.0.1。
- **v3.0.2 (2025-05-18)**：
  - 嘗試修復 Telegram 推送不換行，切換到 HTML 模式（未完全解決）。
  - 修復釘釘推送失敗，優化加簽生成。
- **v3.0.3 (2025-05-18)**：
  - 修復日誌旋轉錯誤（`integer expression expected`），使用 `stat -c %s`。
- **v3.0.4 (2025-05-18)**：
  - 簡化依賴，移除 `iputils-ping`。
  - 添加彩色終端支持，移除網絡診斷。
  - 增強 `apk` 錯誤提示。
- **v3.0.5 (2025-05-19)**：
  - 修復語法錯誤（`validate_dingtalk` 中的 `[ -z "$token",last_response)`）。
  - 添加 `vmstat` 依賴（用於 CPU 使用率），但未正確指定 `procps`。
  - 嘗試修復 Telegram 換行（使用 `$"$message"`，未完全解決）。
  - 修復釘釘推送，使用 POST 請求。
- **v3.0.6 (2025-05-19)**：
  - 修復依賴安裝，將 `vmstat` 替換為 `procps` 包。
  - 優化安裝流程，確保 Alpine 3.21 兼容性。
  - Telegram 換行仍未完全修復（`$"$message"` 無效）。
- **v3.0.7 (2025-05-19)**：
  - 修復 Telegram 換行，使用 `printf '%b'` 處理消息，確保 `\n` 正確解析。
  - 修復釘釘推送失敗，添加關鍵詞輸入並嵌入消息（解決 `errcode:310000`）。
  - 修復 SSH 通知，檢查多種日誌路徑（`/var/log/auth.log`、`/var/log/secure`、`/var/log/messages`）並添加錯誤處理。
  - 改進菜單，支持關鍵詞輸入（`install`, `log` 等）。
  - 增強日誌，記錄詳細的 Telegram 和釘釘錯誤。

## 📄 許可
**MIT 許可證**，僅限學習和個人使用。詳見 [LICENSE](LICENSE)。

## 🙏 致謝
感謝所有測試和反饋的用戶！

## ❓ 問題與反饋
檢查日誌（`/var/log/vps_notify.log`）或提交 Issue：
- GitHub: https://github.com/MEILOI/scripts

### 常見問題
- **Telegram 通知失敗**：
  - 檢查 `/etc/vps_notify.conf` 中的 `TELEGRAM_TOKEN` 和 `TELEGRAM_CHAT_IDS`：
    ```bash
    cat /etc/vps_notify.conf
    ```
  - 查看日誌中的 HTTP 狀態碼：
    - `401`：無效 Token。
    - `400`：格式錯誤。
    - `429`：請求過多。
  - 測試連通性：
    ```bash
    curl -v https://api.telegram.org
    ```
- **釘釘通知失敗**：
  - 檢查 Webhook URL（瀏覽器訪問應返回錯誤碼）。
  - 確保關鍵詞正確（在釘釘群設置中查看）。
  - 查看日誌中的 `errcode`：
    - `310000`：關鍵詞不匹配。
    - `400`：無效 Webhook。
    - `300001`：加簽錯誤。
  - 測試 Webhook：
    ```bash
    curl -v https://oapi.dingtalk.com/robot/send?access_token=<YOUR_TOKEN>
    ```
- **SSH 通知無效**：
  - 確保日誌文件存在（`/var/log/auth.log`、`/var/log/secure`、`/var/log/messages`）：
    ```bash
    apk add busybox-syslogd
    setup-syslog
    ```
- **Alpine 版依賴安裝失敗**：
  - 確保軟件源正確：
    ```bash
    echo "http://dl-cdn.alpinelinux.org/alpine/v$(cat /etc/alpine-release | cut -d. -f1,2)/community" >> /etc/apk/repositories
    apk update
    apk add bash curl gawk coreutils openssl procps
    ```