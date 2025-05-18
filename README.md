VPS 通知系統 (tgvsdd3.sh) v3.0.1
tgvsdd3.sh 是一個輕量級的 VPS 監控腳本，旨在監控 VPS 的 IP 變動、SSH 登錄、內存和 CPU 使用情況，並通過 Telegram 和釘釘發送通知。腳本提供交互式彩色菜單，支持一鍵安裝和靈活的配置，適合個人和學習用途。
特性

IP 變動監控：檢測公網 IPv4 變化並發送通知。
SSH 登錄通知：記錄並通知每次 SSH 登錄（用戶名和來源 IP）。
資源監控：監控內存和 CPU 使用率，超過閾值時發送警報。
多渠道通知：支持 Telegram 和釘釘，包含驗證和重試機制。
交互式菜單：彩色界面，簡化安裝、配置和測試。
日誌管理：記錄操作詳情，自動旋轉日誌（最大 1MB）。
一鍵安裝：快速部署，無需手動編輯文件。

依賴

curl, grep, awk, systemctl, openssl
支持的系統：Debian/Ubuntu、CentOS/Fedora（支持 apt、yum、dnf）

安裝
一鍵安裝
在您的 VPS 上運行以下命令，自動下載並安裝最新版本（v3.0.1）：
curl -o tgvsdd3.sh -fsSL https://raw.githubusercontent.com/meiloi/scripts/main/tgvsdd3.sh && chmod +x tgvsdd3.sh && ./tgvsdd3.sh

注意：

確保您的 VPS 已連接到互聯網。
安裝過程會提示您配置 Telegram 和釘釘通知。

手動安裝

下載腳本：wget https://raw.githubusercontent.com/meiloi/scripts/main/tgvsdd3.sh -O tgvsdd3.sh


設置執行權限：chmod +x tgvsdd3.sh


運行安裝：./tgvsdd3.sh install


按照提示配置通知渠道和其他選項。

配置教程
1. Telegram 機器人設置

創建 Telegram 機器人：
打開 Telegram，搜索 @BotFather。
發送 /start，然後發送 /newbot。
按照提示設置機器人名稱和用戶名（例如 @MyVPSBot）。
記錄 BotFather 返回的 Bot Token（格式如 123456789:ABCDEF...）。


獲取 Chat ID：
將機器人添加到您的個人聊天或群組。
發送一條消息給機器人（例如 Hello）。
訪問以下 URL（替換 YOUR_BOT_TOKEN）：https://api.telegram.org/botYOUR_BOT_TOKEN/getUpdates


在返回的 JSON 中查找 "chat":{"id":YOUR_CHAT_ID,...}，記錄 YOUR_CHAT_ID。
如果需要多個 Chat ID，用逗號分隔（例如 12345678,-98765432）。


腳本配置：
運行 ./vps_notify.sh menu，選擇“配置設置”。
輸入 Bot Token 和 Chat ID，腳本會自動驗證 Token 有效性。



2. 釘釘機器人設置

創建釘釘機器人：
登錄釘釘管理後台，進入您的工作群。
點擊“群設置” > “智能群助手” > “添加機器人” > “自定義”。
設置機器人名稱（例如 VPS監控）。
啟用“加簽”選項（推薦），記錄生成的 Secret。
複製機器人的 Webhook 地址（格式如 https://oapi.dingtalk.com/robot/send?access_token=xxx）。


腳本配置：
運行 ./vps_notify.sh menu，選擇“配置設置”。
輸入 Webhook 和 Secret（如果不使用加簽，可留空 Secret）。
腳本會自動驗證 Webhook 是否有效（包含 3 次重試）。



使用說明
運行腳本
腳本安裝後，默認部署在 /usr/local/bin/vps_notify.sh。您可以通過以下命令運行：
vps_notify.sh [命令]

可用命令：

install：安裝或重新安裝腳本。
uninstall：卸載腳本並刪除所有配置文件。
boot：發送開機通知。
ssh：發送 SSH 登錄通知（由 PAM 自動調用）。
monitor：監控資源（由 cron 每 5 分鐘調用）。
menu：顯示交互式菜單（默認）。

交互式菜單
運行以下命令進入彩色菜單：
vps_notify.sh menu

菜單選項：

安裝/重新安裝：設置通知渠道、SSH 通知和資源監控。
配置設置：修改 Telegram/釘釘配置、閾值等。
測試通知：發送測試開機、SSH、資源或 IP 變動通知。
卸載：移除腳本和所有相關文件。
退出：關閉菜單。

日誌查看
腳本記錄所有操作詳情至 /var/log/vps_notify.log，最大 1MB，自動旋轉。查看日誌：
cat /var/log/vps_notify.log

變更日誌

v3.0.1 (2025-05-18)：
修復 modify_config 函數中的三元運算符語法錯誤，使用 Bash 條件語句。
修正釘釘 URL 拼接中的 timestamp 錯誤。
添加 Telegram 配置驗證功能，確保 Bot Token 有效。
增強依賴檢查，支持 dnf 等包管理器。
優化卸載邏輯，清理日誌目錄。


v3.0 (2025-05-18)：
更新釘釘通知，移植 v2.8 的重試機制和加簽支持。


v2.9 (2025-05-17)：
增強彩色菜單（黃色標題，綠色選項編號）。
添加終端顏色支持檢測，提示設置 TERM=xterm-256color。
優化日誌，記錄顏色支持狀態。


v2.8：
添加釘釘驗證/發送重試機制（3 次）。
增強日誌，屏蔽 access_token。


v2.7：
補充 validate_dingtalk 邏輯說明。


v2.2：
新增釘釘加簽支持。


v2.1：
新增腳本更新功能。


v2.0：
初始優化版本，添加菜單和多渠道通知。



許可
本項目採用 MIT 許可證，僅限學習和個人使用。詳情見 LICENSE 文件。
致謝
感謝所有測試和反饋的用戶！您的支持幫助我們改進腳本。
問題與反饋
如遇到問題，請檢查 /var/log/vps_notify.log 或提交 Issue 至 GitHub 倉庫。聯繫方式：

GitHub: https://github.com/MEILOI/scripts/blob/main/tgvsdd3.sh

