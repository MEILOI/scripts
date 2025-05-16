#!/bin/bash

CONFIG_FILE="/etc/vps_notify.conf"
SCRIPT_PATH="/usr/local/bin/vps_notify.sh"
SERVICE_PATH="/etc/systemd/system/vps_notify.service"
CRON_JOB="*/5 * * * * root /usr/local/bin/vps_notify.sh monitor >/dev/null 2>&1"

TG_API="https://api.telegram.org/bot"

# 获取公网 IP
get_ip() {
    ipv4=$(curl -s4m 3 ip.sb || curl -s4m 3 ifconfig.me || echo "获取失败")
    ipv6=$(curl -s6m 3 ip.sb || curl -s6m 3 ifconfig.me || echo "获取失败")
    echo -e "IPv4: $ipv4\\nIPv6: $ipv6"
}

# 发送 Telegram 通知
send_tg() {
    local message="$1"
    IFS=',' read -ra IDS <<< "$TG_CHAT_IDS"
    for id in "${IDS[@]}"; do
        curl -s -X POST "${TG_API}${TG_BOT_TOKEN}/sendMessage" \
            -d chat_id="$id" \
            -d text="$message" \
            -d parse_mode="Markdown"
    done
}

# VPS 上线通知
notify_boot() {
    ip_info=$(get_ip)
    hostname=$(hostname)
    time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    message="✅ *VPS 已上線*\\n\\n🖥️ 主機名: $hostname\\n🌐 公網IP:\\n$ip_info\\n🕒 時間: $time"
    send_tg "$message"
}

# SSH 登录通知
notify_ssh() {
    user="$PAM_USER"
    ip="$PAM_RHOST"
    hostname=$(hostname)
    time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    message="🔐 *SSH 登錄通知*\\n\\n👤 用戶: $user\\n🖥️ 主機: $hostname\\n🌐 來源 IP: $ip\\n🕒 時間: $time"
    send_tg "$message"
}

# 资源监控
monitor_usage() {
    memory=$(free | awk '/Mem:/ {printf("%.0f", $3/$2*100)}')
    load=$(awk '{print int($1)}' /proc/loadavg)

    now=$(date +%s)
    last_warn=0
    [ -f /tmp/vps_notify_last ] && last_warn=$(cat /tmp/vps_notify_last)

    if (( now - last_warn < 21600 )); then
        return
    fi

    alert=""
    [[ $ENABLE_MEM_MONITOR == "Y" && $memory -ge 90 ]] && alert+="🧠 *內存使用率過高*：${memory}%\\n"
    [[ $ENABLE_CPU_MONITOR == "Y" && $load -ge 4 ]] && alert+="🔥 *CPU 負載過高*：${load}\\n"

    if [[ -n "$alert" ]]; then
        echo "$now" > /tmp/vps_notify_last
        message="⚠️ *VPS 資源警報*\\n\\n$alert"
        send_tg "$message"
    fi
}

install_script() {
    echo "[1/5] 檢查依賴..."
    apt update -y && apt install -y curl cron || yum install -y curl cronie

    echo "[2/5] 輸入 TG Bot Token:"
    read -rp "Token: " TG_BOT_TOKEN

    echo "[3/5] 輸入接收通知的 TG Chat ID（支持多個，逗號分隔）:"
    read -rp "Chat ID(s): " TG_CHAT_IDS

    echo "[4/5] 啟用 SSH 登錄通知？[Y/n]"
    read -rp "(預設 Y): " SSH_NOTIFY
    SSH_NOTIFY=${SSH_NOTIFY:-Y}

    echo "[5/5] 啟用內存使用率過高提示？[Y/n]"
    read -rp "(預設 Y): " ENABLE_MEM_MONITOR
    ENABLE_MEM_MONITOR=${ENABLE_MEM_MONITOR:-Y}

    echo "啟用 CPU 負載過高提示？[Y/n]"
    read -rp "(預設 Y): " ENABLE_CPU_MONITOR
    ENABLE_CPU_MONITOR=${ENABLE_CPU_MONITOR:-Y}

    cat <<EOF > "$CONFIG_FILE"
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_CHAT_IDS="$TG_CHAT_IDS"
SSH_NOTIFY="$SSH_NOTIFY"
ENABLE_MEM_MONITOR="$ENABLE_MEM_MONITOR"
ENABLE_CPU_MONITOR="$ENABLE_CPU_MONITOR"
EOF

    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"

    cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=VPS Notify Boot Service
After=network.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH boot

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable vps_notify.service

    echo "$CRON_JOB" >> /etc/crontab

    if [[ $SSH_NOTIFY == "Y" ]]; then
        mkdir -p /etc/security
        pam_script="/etc/security/pam_exec_notify.sh"
        cat <<PAM > "$pam_script"
#!/bin/bash
PAM_USER="\$PAM_USER" PAM_RHOST="\$PAM_RHOST" $SCRIPT_PATH ssh
PAM
        chmod +x "$pam_script"

        if ! grep -q pam_exec.so /etc/pam.d/sshd; then
            echo "session optional pam_exec.so seteuid $pam_script" >> /etc/pam.d/sshd
        fi
    fi

    echo "✅ 安裝完成。重啟 VPS 測試開機通知。"
}

uninstall_script() {
    echo "正在卸載..."
    systemctl disable vps_notify.service 2>/dev/null
    rm -f "$SERVICE_PATH" "$SCRIPT_PATH" "$CONFIG_FILE"
    sed -i '/vps_notify.sh monitor/d' /etc/crontab
    sed -i '/pam_exec.so.*pam_exec_notify.sh/d' /etc/pam.d/sshd
    rm -f /etc/security/pam_exec_notify.sh /tmp/vps_notify_last
    echo "✅ 卸載完成。"
}

load_config() {
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
}

main() {
    case "$1" in
        boot)
            load_config
            notify_boot
            ;;
        ssh)
            load_config
            notify_ssh
            ;;
        monitor)
            load_config
            monitor_usage
            ;;
        install|"")
            install_script
            ;;
        uninstall)
            uninstall_script
            ;;
        *)
            echo "用法: $0 [install|uninstall|boot|ssh|monitor]"
            ;;
    esac
}

main "$1"
