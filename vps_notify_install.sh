#!/bin/bash

# 设置目标路径
SCRIPT_PATH="/usr/local/bin/vps_notify.sh"
CONFIG_PATH="/etc/vps_notify.conf"
SERVICE_PATH="/etc/systemd/system/vps_notify_boot.service"

# 输入参数
read -p "请输入 Telegram Bot Token: " BOT_TOKEN
read -p "请输入 Telegram Chat ID: " CHAT_ID

# 创建配置文件
cat > "$CONFIG_PATH" <<EOF
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
EOF

chmod 600 "$CONFIG_PATH"

# 下载主脚本
cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash

# Load config
CONFIG="/etc/vps_notify.conf"
[ -f "$CONFIG" ] && source "$CONFIG" || exit 1

BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"

HOSTNAME=$(hostname 2>/dev/null)
IP_ADDR=$(curl -s --max-time 5 https://api.ipify.org || echo "未知")
[ -z "$HOSTNAME" ] && HOSTNAME="未知"
[ -z "$IP_ADDR" ] && IP_ADDR="未知"
TIME_NOW=$(date "+%Y年 %m月 %d日 %A %T %Z")

send_message() {
    local MSG="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="$MSG" \
        -d parse_mode="Markdown"
}

case "$1" in
    boot)
        MSG="✅ *VPS 已上線*\n\n🖥️ *主機名:* \`$HOSTNAME\`\n🌐 *公網IP:* \`$IP_ADDR\`\n🕒 *時間:* $TIME_NOW"
        send_message "$MSG"
        ;;
    ssh)
        SSH_USER=$(whoami)
        SSH_IP=$(last -i | grep "still logged in" | grep "$SSH_USER" | head -n 1 | awk '{print $3}')
        [ -z "$SSH_IP" ] && SSH_IP="未知"
        MSG="🔐 *SSH 登錄通知*\n\n👤 *用戶:* \`$SSH_USER\`\n🖥️ *主機:* \`$HOSTNAME\`\n🌐 *來源 IP:* \`$SSH_IP\`\n🕒 *時間:* $TIME_NOW"
        send_message "$MSG"
        ;;
    memcheck)
        LOG=/tmp/vps_mem_warn_time
        MEM_USED=$(free | awk '/Mem:/ { printf("%.0f", $3/$2 * 100) }')
        NOW_TS=$(date +%s)

        if [ "$MEM_USED" -ge 90 ]; then
            LAST_TS=0
            [ -f "$LOG" ] && LAST_TS=$(cat "$LOG")
            ELAPSED=$((NOW_TS - LAST_TS))

            if [ "$ELAPSED" -ge 21600 ]; then
                echo "$NOW_TS" > "$LOG"
                MSG="⚠️ *內存警告*\n\n🖥️ *主機:* \`$HOSTNAME\`\n📈 *使用率:* ${MEM_USED}%\n🕒 *時間:* $TIME_NOW"
                send_message "$MSG"
            fi
        fi
        ;;
    *)
        echo "Usage: $0 [boot|ssh|memcheck]"
        ;;
esac
EOF

chmod +x "$SCRIPT_PATH"

# 创建 systemd 服务用于开机启动通知
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=VPS Telegram 通知腳本
After=network.target

[Service]
ExecStart=${SCRIPT_PATH} boot
Type=oneshot

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable vps_notify_boot.service

# 设置 pam_exec 用于 SSH 登录通知
PAM_EXEC_LINE="session optional pam_exec.so /usr/local/bin/vps_notify.sh ssh"
if ! grep -Fxq "$PAM_EXEC_LINE" /etc/pam.d/sshd; then
    echo "$PAM_EXEC_LINE" >> /etc/pam.d/sshd
fi

# 添加定时任务检查内存
CRON_LINE="*/5 * * * * /usr/local/bin/vps_notify.sh memcheck"
( crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH memcheck"; echo "$CRON_LINE" ) | crontab -

echo "✅ 安裝完成，可重啟 VPS 測試開機推送。"
