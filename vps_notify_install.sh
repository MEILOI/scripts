#!/bin/bash

set -e

NOTIFY_PATH="/usr/local/bin/vps_notify.sh"
SERVICE_PATH="/etc/systemd/system/vps-notify.service"
PROFILED_PATH="/etc/profile.d/vps_ssh_notify.sh"

check_requirements() {
    echo "[檢查] 開始檢測依賴與環境..."
    apt update -y && apt install -y curl jq net-tools lsb-release
    echo "[完成] 所需依賴已安裝。"
}

get_public_ip() {
    ipv4=$(curl -s4 https://api.ip.sb/ip || true)
    ipv6=$(curl -s6 https://api64.ip.sb/ip || true)
    echo -e "IPv4: ${ipv4:-無}
IPv6: ${ipv6:-無}"
}

create_notify_script() {
    cat > "$NOTIFY_PATH" << 'EOF'
#!/bin/bash
BOT_TOKEN="{{BOT_TOKEN}}"
CHAT_ID="{{CHAT_ID}}"

HOSTNAME=$(hostname)
IPV4=$(curl -s4 https://api.ip.sb/ip)
IPV6=$(curl -s6 https://api64.ip.sb/ip)
DATETIME=$(date '+%Y年 %m月 %d日 %A %T %Z')

MESSAGE="✅ VPS 已上線\n\n🖥️ 主機名: ${HOSTNAME}\n🌐 公網IP:\nIPv4: ${IPV4}\nIPv6: ${IPV6}\n🕒 時間: ${DATETIME}"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
     -d chat_id="${CHAT_ID}" \
     -d text="$MESSAGE" \
     -d parse_mode="Markdown"
EOF
    sed -i "s|{{BOT_TOKEN}}|$1|" "$NOTIFY_PATH"
    sed -i "s|{{CHAT_ID}}|$2|" "$NOTIFY_PATH"
    chmod +x "$NOTIFY_PATH"
}

create_service() {
    cat > "$SERVICE_PATH" << EOF
[Unit]
Description=VPS Telegram 開機通知
After=network.target

[Service]
Type=oneshot
ExecStart=$NOTIFY_PATH

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable vps-notify.service
}

create_ssh_login_notify() {
    cat > "$PROFILED_PATH" << 'EOF'
#!/bin/bash
BOT_TOKEN="{{BOT_TOKEN}}"
CHAT_ID="{{CHAT_ID}}"

USER=$(whoami)
HOST=$(hostname)
SRC_IP=$(who | awk 'NR==1{print $5}' | tr -d '()')
DATETIME=$(date '+%Y年 %m月 %d日 %A %T %Z')

MESSAGE="🔐 SSH 登錄通知\n\n👤 用戶: ${USER}\n🖥️ 主機: ${HOST}\n🌐 來源 IP: ${SRC_IP}\n🕒 時間: ${DATETIME}"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
     -d chat_id="${CHAT_ID}" \
     -d text="$MESSAGE" \
     -d parse_mode="Markdown"
EOF
    sed -i "s|{{BOT_TOKEN}}|$1|" "$PROFILED_PATH"
    sed -i "s|{{CHAT_ID}}|$2|" "$PROFILED_PATH"
    chmod +x "$PROFILED_PATH"
}

create_memory_monitor() {
    cat > /usr/local/bin/mem_monitor.sh << 'EOF'
#!/bin/bash
THRESHOLD=90
FLAG_FILE="/tmp/mem_alert_sent.flag"

used_percent=$(free | awk '/Mem:/ { printf("%.0f", $3/$2*100) }')

if [ "$used_percent" -ge "$THRESHOLD" ]; then
    if [ ! -f "$FLAG_FILE" ] || [ "$(( $(date +%s) - $(cat "$FLAG_FILE" 2>/dev/null) ))" -ge 21600 ]; then
        echo "$(date +%s)" > "$FLAG_FILE"
        MESSAGE="⚠️ 記憶體使用警告\n\n已使用: ${used_percent}%"
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d chat_id="${CHAT_ID}" \
            -d text="$MESSAGE" \
            -d parse_mode="Markdown"
    fi
fi
EOF
    sed -i "s|{{BOT_TOKEN}}|$1|" /usr/local/bin/mem_monitor.sh
    sed -i "s|{{CHAT_ID}}|$2|" /usr/local/bin/mem_monitor.sh
    chmod +x /usr/local/bin/mem_monitor.sh

    echo "*/5 * * * * root /usr/local/bin/mem_monitor.sh" > /etc/cron.d/mem_monitor
}

main() {
    echo "================ VPS Telegram 一鍵通知安裝器 ================"
    echo "1. 安裝通知腳本"
    echo "2. 卸載通知腳本"
    read -p "請輸入選項 [1-2]: " option

    case $option in
        1)
            check_requirements
            read -p "請輸入 Telegram Bot Token: " bot
            read -p "請輸入 Telegram Chat ID: " chat

            create_notify_script "$bot" "$chat"
            create_service
            create_ssh_login_notify "$bot" "$chat"

            echo
            read -p "是否啟用記憶體使用率通知（>90% 警告）？[y/N]: " memopt
            if [[ "$memopt" =~ ^[Yy]$ ]]; then
                create_memory_monitor "$bot" "$chat"
            fi
            echo
            echo "✅ 安裝完成！請重啟 VPS 測試是否收到開機通知。"
            ;;
        2)
            echo "🔧 正在卸載通知腳本..."
            systemctl disable --now vps-notify.service 2>/dev/null || true
            rm -f "$NOTIFY_PATH" "$SERVICE_PATH" "$PROFILED_PATH"
            rm -f /usr/local/bin/mem_monitor.sh /etc/cron.d/mem_monitor
            systemctl daemon-reload
            echo "✅ 已卸載通知功能。"
            ;;
        *)
            echo "❌ 無效的選項"
            ;;
    esac
}

main
