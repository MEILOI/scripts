# 📢 VPS 通知系統 (tgvsdd3-alpine.sh) v3.0.1

**輕量級 VPS 監控腳本**，專為 Alpine Linux 設計，通過 *Telegram* 和 *釘釘* 發送 IP 變動、SSH 登錄和資源使用通知。支持交互式彩色菜單，適合個人和學習用途。

## ✨ 主要特性

| 功能 | 描述 |
| --- | --- |
| **IP 變動監控** | 實時檢測 IPv4 變化並發送通知 |
| **SSH 登錄通知** | 記錄用戶名和來源 IP |
| **資源監控** | 內存和 CPU 超閾值警報 |
| **多渠道通知** | 支持 Telegram 和釘釘 |
| **一鍵安裝** | 快速部署，交互式配置 |

## 🔧 安裝指南

### 🚀 一鍵安裝

**快速部署**（推薦）：

```bash
curl -o tgvsdd3-alpine.sh -fsSL https://raw.githubusercontent.com/meiloi/scripts/main/tgvsdd3-alpine.sh && chmod +x tgvsdd3-alpine.sh && ./tgvsdd3-alpine.sh
```

### 手動安裝

- [ ] **下載腳本**：
  ```bash
  wget https://raw.githubusercontent.com/meiloi/scripts/main/tgvsdd3-alpine.sh -O tgvsdd3-alpine.sh
  ```
- [ ] **設置權限**：
  ```bash
  chmod +x tgvsdd3-alpine.sh
  ```
- [ ] **運行安裝**：
  ```bash
  ./tgvsdd3-alpine.sh install
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
   - 運行 `vps_notify.sh menu`，選擇“配置設置”。
   - 輸入 Token 和 Chat ID，自動驗證。

### 2. 釘釘機器人設置
1. **創建機器人**：
   - 在釘釘群設置中添加“自定義”機器人。
   - 記錄 **Webhook**（如 `https://oapi.dingtalk.com/robot/send?access_token=xxx`）。
   - 啟用加簽，記錄 **Secret**（可選）。
2. **配置腳本**：
   - 運行 `vps_notify.sh menu`，選擇“配置設置”。
   - 輸入 Webhook 和 Secret，自動驗證。

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
- `monitor`：監控資源。
- `menu`：交互式菜單（默認）。

### 日誌查看
查看操作日誌（`/var/log/vps_notify.log`）：
```bash
cat /var/log/vps_notify.log
```

## 📜 變更日誌
- **v3.0.1 (2025-05-18)**：
  - 初始 Alpine 專屬版本，基於 tgvsdd3.sh v3.0.1。
  - 使用 `apk` 和 `openrc`，移除 `systemd` 依賴。
  - 適配 SSH 通知，兼容 `/var/log/messages` 或 `/var/log/auth.log`。
  - 修復 Telegram 和釘釘驗證邏輯。
- **v3.0 (2025-05-18)**：
  - 更新釘釘通知，重試和加簽支持。
- **v2.9 (2025-05-17)**：
  - 增強彩色菜單（黃色標題，綠色編號）。
  - 添加終端顏色檢測，提示 `TERM=xterm-256color`。
- **v2.8**：
  - 添加釘釘驗證/重試（3 次）。
  - 屏蔽 `access_token`。
- **v2.7**：
  - 補充 `validate_dingtalk` 說明。
- **v2.2**：
  - 新增釘釘加簽支持。
- **v2.1**：
  - 新增腳本更新功能。
- **v2.0**：
  - 初始版本，添加菜單和多渠道通知。

## 📄 許可
**MIT 許可證**，僅限學習和個人使用。詳見 [LICENSE](LICENSE)。

## 🙏 致謝
感謝所有測試和反饋的用戶！

## ❓ 問題與反饋
檢查日誌（`/var/log/vps_notify.log`）或提交 Issue：
- GitHub: https://github.com/MEILOI/scripts/blob/main/tgvsdd3-alpine.sh
