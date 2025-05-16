#!/bin/bash

# =======================================
# Telegram VPS 通知安裝腳本
# 適用於 Debian 系統
# 作者：ChatGPT + 用戶優化需求整合
# =======================================

set -e

SCRIPT_PATH="/usr/local/bin/vps_notify.sh"
SERVICE_PATH="/etc/systemd/system/vps_notify.service"
PROFILE_PATH="/etc/profile.d/vps_notify_env.sh"

function install_dependencies() {
    echo "[INFO] 正在安裝依賴項..."
    apt update -y && apt install -y curl sudo bash coreutils lsb-release
}

function get_user_input() {
    echo "請輸入您的 Telegram Bot Token："
    read -rp "BOT_TOKEN: " BOT_TOKEN
    echo "請輸入您的 Telegram Chat ID："
    read -rp "CHAT_ID: " CHAT_ID

    echo "export TELEGRAM_BOT_TOKEN=\"${BOT_TOKEN}\"" > "$PROFILE_PATH"
    echo "export TELEGRAM_CHAT_ID=\"${CHAT_ID}\"" >> "$PROFILE_PATH"
    chmod +x "$PROFILE_PATH"
    source "$PROFILE_PATH"
}

function write_script() {
    cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash

source /etc/profile.d/vps_notify_env.sh

BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
CHAT_ID="$TELEGRAM_CHAT_ID"

HOSTNAME=$(hostname)
IPV4=$(curl -s --max-time 5 https://api64.ipify.org || echo "獲取失敗")
IPV6=$(curl -s --max-time 5 https://api6.ipify.org || echo "獲取失敗")
TIME=$(date +"%Y年 %m月 %d日 %A %T %Z")

MESSAGE="✅ VPS 已上線\n\n🖥️ 主機名: ${HOSTNAME}\n🌐 公網IP:\nIPv4: ${IPV4}\nIPv6: ${IPV6}\n🕒 時間: ${TIME}"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
     -d chat_id="${CHAT_ID}" \
     -d text="${MESSAGE}" \
     -d parse_mode="Markdown"
EOF
    chmod +x "$SCRIPT_PATH"
}

function write_service() {
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=VPS Telegram Notify
After=network.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH}
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable vps_notify.service
}

function uninstall() {
    echo "[INFO] 卸載中..."
    systemctl disable vps_notify.service 2>/dev/null || true
    rm -f "$SCRIPT_PATH" "$SERVICE_PATH" "$PROFILE_PATH"
    systemctl daemon-reload
    echo "[OK] 已卸載完成。"
    exit 0
}

function menu() {
    echo "============================="
    echo " Telegram VPS 通知腳本"
    echo "============================="
    echo "1) 安裝腳本"
    echo "2) 卸載腳本"
    echo "0) 退出"
    echo "============================="
    read -rp "請選擇 [0-2]: " OPTION

    case $OPTION in
        1)
            install_dependencies
            get_user_input
            write_script
            write_service
            echo "[OK] 安裝完成，重啟 VPS 可測試通知是否成功。"
            ;;
        2)
            uninstall
            ;;
        *)
            echo "[INFO] 退出。"
            exit 0
            ;;
    esac
}

menu
