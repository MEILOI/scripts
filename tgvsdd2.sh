#!/bin/bash

# VPS Notify Script (tgvsdd2.sh)
# Version: 3.0.3 (2025-05-17)
# Purpose: Advanced VPS notification system with Telegram integration
# Fixes: CPU 100% bug, menu display, Telegram newlines, compatibility

# Configuration
LOG_FILE="/var/log/vps_notify.log"
CONFIG_FILE="/etc/vps_notify.conf"
TG_BOT_TOKEN=""
TG_CHAT_ID=""
SCRIPT_NAME="tgvsdd2.sh"
VERSION="3.0.3"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Override with environment variables if set
TG_BOT_TOKEN=${TG_BOT_TOKEN:-$TG_BOT_TOKEN}
TG_CHAT_ID=${TG_CHAT_ID:-$TG_CHAT_ID}

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
}

# Escape Markdown characters for Telegram
escape_markdown() {
    echo "$1" | sed 's/\\([_*\\[]\\[`#+=\\-|.{}()!]\\)/\\\\\\1/g' 2>/dev/null
}

# Send Telegram notification
send_telegram() {
    local message="$1"
    # Replace \n with \n\n for proper newlines
    local final_message=$(echo "$message" | sed 's/\\n/\\n\\n/g')
    local escaped_message=$(escape_markdown "$final_message")
    local json_payload=$(printf '{"chat_id":"%s","text":"%s","parse_mode":"MarkdownV2"}' "$TG_CHAT_ID" "$escaped_message")
    local response
    response=$(curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$json_payload" 2>/dev/null)
    log "Telegram sent: raw='$final_message', response='$response'"
    echo "$response"
}

# Get public IP
get_public_ip() {
    local ipv4=$(curl -s --max-time 5 http://ipinfo.io/ip 2>/dev/null || echo "获取失敗")
    local ipv6=$(curl -s --max-time 5 http://6.ipinfo.io/ip 2>/dev/null || echo "获取失敗")
    echo "$ipv4" "$ipv6"
}

# Sync system time (Alpine/Debian compatible)
sync_time() {
    if command -v ntpdate >/dev/null 2>&1; then
        ntpdate pool.ntp.org >/dev/null 2>&1
        log "Time synced with ntpdate"
    elif command -v ntpd >/dev/null 2>&1; then
        ntpd -q -p pool.ntp.org >/dev/null 2>&1
        log "Time synced with ntpd"
    else
        log "Warning: No NTP client found, using system time"
    fi
}

# Boot notification
boot_notification() {
    local remark="$1"
    local hostname
    hostname=$(hostname 2>/dev/null || echo "未知")
    read ipv4 ipv6 <<< $(get_public_ip)
    local message="✅ VPS 已上线\n备注: $remark\n主机名: $hostname\n公网IP:\nIPv4: $ipv4\nIPv6: $ipv6\n時間: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
    send_telegram "$message"
    log "Boot notification sent for $remark"
}

# Main menu
main_menu() {
    clear
    echo "════════════════════════════════════════"
    echo "║       VPS 通知系统 (高级版)       ║"
    echo "║       Version: $VERSION           ║"
    echo "════════════════════════════════════════"
    echo "1. 安装/重新安装"
    echo "2. 配置设置"
    echo "3. 测试通知"
    echo "4. 启动监控"
    echo "0. 退出"
    echo "请输入选项 [0-4]: "
    read -r choice 2>/dev/null
    case "$choice" in
        1) install_service ;;
        2) configure ;;
        3) test_notification ;;
        4) monitor ;;
        0) log "Script exited by user" ; exit 0 ;;
        *) echo "无效选项" ; sleep 1 ; main_menu ;;
    esac
}

# Test notification
test_notification() {
    boot_notification "Test"
    echo "测试通知已发送，请检查 Telegram"
    sleep 2
    main_menu
}

# Monitor function (fixed CPU 100% bug)
monitor() {
    local max_runs=360  # 1 hour at 10s intervals
    local count=0
    local last_status="online"
    log "Monitor started"
    while [ $count -lt $max_runs ]; do
        local status
        status=$(curl -s --max-time 5 http://ipinfo.io/ip 2>/dev/null || echo "offline")
        if [ "$status" != "$last_status" ]; then
            if [ "$status" = "offline" ]; then
                send_telegram "⚠ VPS 离线\n主机名: $(hostname 2>/dev/null || echo '未知')"
            else
                boot_notification "监控恢复"
            fi
            last_status="$status"
        fi
        count=$((count + 1))
        sleep 10  # Increased interval to reduce CPU load
    done
    log "Monitor stopped after $max_runs runs"
    echo "监控已停止"
    sleep 2
    main_menu
}

# Install service (Debian/Alpine compatible)
install_service() {
    if command -v systemctl >/dev/null 2>&1; then
        cat > /etc/systemd/system/vps-notify.service << EOF
[Unit]
Description=VPS Notify Service
After=network.target

[Service]
Type=oneshot
ExecStart=/root/$SCRIPT_NAME
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable vps-notify >/dev/null 2>&1
        systemctl start vps-notify >/dev/null 2>&1
        log "Systemd service installed"
        echo "Systemd 服务已安装"
    elif command -v rc-update >/dev/null 2>&1; then
        cat > /etc/init.d/vps-notify << EOF
#!/sbin/openrc-run

name="vps_notify"
description="VPS Notification Service"
command="/root/$SCRIPT_NAME"
command_args=""
pidfile="/var/run/vps_notify.pid"
command_background="yes"

depend() {
    need net
    after logger
}
EOF
        chmod +x /etc/init.d/vps-notify >/dev/null 2>&1
        rc-update add vps-notify default >/dev/null 2>&1
        rc-service vps-notify start >/dev/null 2>&1
        log "OpenRC service installed"
        echo "OpenRC 服务已安装"
    else
        log "Error: No supported service manager found"
        echo "错误：未找到支持的服务管理器"
        sleep 2
        main_menu
        return
    fi
    echo "服务安装完成"
    sleep 2
    main_menu
}

# Configure settings
configure() {
    echo "请编辑 $CONFIG_FILE 设置 Telegram 参数："
    echo "TG_BOT_TOKEN=\"您的 Bot Token\""
    echo "TG_CHAT_ID=\"您的 Chat ID\""
    echo "按 Enter 继续..."
    read -r
    nano "$CONFIG_FILE" 2>/dev/null || vi "$CONFIG_FILE" 2>/dev/null || echo "请手动编辑 $CONFIG_FILE"
    log "Configuration edited"
    main_menu
}

# Check dependencies
check_deps() {
    local missing=""
    for cmd in curl sed date hostname; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done
    if [ -n "$missing" ]; then
        log "Error: Missing dependencies:$missing"
        echo "错误：缺少依赖：$missing"
        echo "请安装：apt install -y curl sed coreutils"
        exit 1
    fi
}

# Main function
main() {
    # Initialize log
    mkdir -p /var/log 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null
    chmod 666 "$LOG_FILE" 2>/dev/null
    log "Script started: $SCRIPT_NAME v$VERSION"

    # Check dependencies
    check_deps

    # Sync time
    sync_time

    # Check Telegram configuration
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        log "Error: TG_BOT_TOKEN or TG_CHAT_ID not set"
        echo "错误：未设置 TG_BOT_TOKEN 或 TG_CHAT_ID"
        echo "请编辑 $CONFIG_FILE"
        exit 1
    fi

    # Handle arguments
    case "$1" in
        menu) main_menu ;;
        test) test_notification ;;
        monitor) monitor ;;
        "") boot_notification "香港" ;;
        *) echo "用法: $0 [menu|test|monitor]" ; exit 1 ;;
    esac
}

# Trap signals to ensure clean exit
trap 'log "Script terminated"; reset >/dev/null 2>&1 || true; exit' SIGINT SIGTERM

# Run main
main "$@"

# Reset terminal to avoid affecting other scripts
reset >/dev/null 2>&1 || true
