#!/bin/bash

# VPS Notify Script (tgvsdd2.sh)
# Version: 2.8.1.1 (2025-05-18)
# Purpose: Simple VPS notification system with Telegram integration
# Fixes: Telegram newline bug

# Configuration
LOG_FILE="/var/log/vps_notify.log"
CONFIG_FILE="/etc/vps_notify.conf"
TG_BOT_TOKEN=""
TG_CHAT_ID=""
SCRIPT_NAME="tgvsdd2.sh"
VERSION="2.8.1.1"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
}

# Escape Markdown characters for Telegram
escape_markdown() {
    echo "$1" | sed 's/\\([_*\\[]\\[`#+=\\-|.{}()!]\\)/\\\\\\1/g' 2>/dev/null
}

# Send Telegram notification (fixed newline bug)
send_telegram() {
    local message="$1"
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        log "Error: Telegram not configured"
        return 1
    fi
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

# Sync system time
sync_time() {
    if command -v ntpdate >/dev/null 2>&1; then
        ntpdate pool.ntp.org >/dev/null 2>&1
        log "Time synced with ntpdate"
    elif command -v ntpd >/dev/null 2>&1; then
        ntpd -q -p pool.ntp.org >/dev/null 2>&1
        log "Time synced with ntpd"
    else
        log "Warning: No NTP client found"
    fi
}

# Boot notification
boot_notification() {
    local remark="$1"
    local hostname=$(hostname 2>/dev/null || echo "未知")
    read ipv4 ipv6 <<< $(get_public_ip)
    local message="✅ VPS 已上线\n备注: $remark\n主机名: $hostname\n公网IP:\nIPv4: $ipv4\nIPv6: $ipv6\n時間: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
    send_telegram "$message"
    log "Boot notification sent for $remark"
}

# Main menu
main_menu() {
    clear
    echo "════════════════════════════════════════"
    echo "║       VPS 通知系统       ║"
    echo "║       Version: $VERSION       ║"
    echo "════════════════════════════════════════"
    echo "1. 安装服务"
    echo "2. 配置 Telegram"
    echo "3. 测试通知"
    echo "4. 启动网络监控"
    echo "0. 退出"
    echo "请输入选项 [0-4]："
    read -r choice 2>/dev/null
    case "$choice" in
        1) install_service ;;
        2) configure ;;
        3) test_notification ;;
        4) monitor ;;
        0) log "Script exited by user" ; exit 0 ;;
        *) echo "无效选项，请输入 0-4" ; sleep 1 ; main_menu ;;
    esac
}

# Test notification
test_notification() {
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        echo "未配置 Telegram，请先配置"
        sleep 1
        configure
    fi
    boot_notification "Test"
    echo "测试通知已发送，请检查 Telegram"
    sleep 2
    main_menu
}

# Monitor network
monitor() {
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        echo "未配置 Telegram，请先配置"
        sleep 1
        configure
    fi
    local max_runs=360  # 1 hour at 10s intervals
    local count=0
    local last_status="online"
    log "Network monitor started"
    echo "网络监控已启动（1 小时后停止）"
    while [ $count -lt $max_runs ]; do
        local status=$(curl -s --max-time 5 http://ipinfo.io/ip 2>/dev/null || echo "offline")
        if [ "$status" != "$last_status" ]; then
            if [ "$status" = "offline" ]; then
                send_telegram "⚠ VPS 离线\n主机名: $(hostname 2>/dev/null || echo '未知')"
            else
                boot_notification "网络恢复"
            fi
            last_status="$status"
        fi
        count=$((count + 1))
        sleep 10
    done
    log "Network monitor stopped after $max_runs runs"
    echo "网络监控已停止"
    sleep 2
    main_menu
}

# Install dependencies
install_deps() {
    local missing=""
    for cmd in curl sed date hostname; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done
    if [ -n "$missing" ]; then
        log "Installing dependencies:$missing"
        if command -v apt >/dev/null 2>&1; then
            echo "检测到 Debian 系统，正在安装依赖..."
            apt update >/dev/null 2>&1
            apt install -y curl sed coreutils >/dev/null 2>&1
        elif command -v apk >/dev/null 2>&1; then
            echo "检测到 Alpine 系统，正在安装依赖..."
            apk update >/dev/null 2>&1
            apk add curl sed coreutils >/dev/null 2>&1
        else
            log "Error: Unsupported package manager"
            echo "错误：不支持的包管理器，请手动安装：$missing"
            exit 1
        fi
    fi
    log "Dependencies installed"
}

# Install service
install_service() {
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        echo "未配置 Telegram，请先配置"
        sleep 1
        configure
    fi
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
        log "Error: No supported service manager"
        echo "错误：未找到支持的服务管理器"
        sleep 2
        main_menu
        return
    fi
    echo "服务安装完成"
    boot_notification "安装完成"
    sleep 2
    main_menu
}

# Configure Telegram
configure() {
    clear
    echo "════════════════════════════════════════"
    echo "║       配置 Telegram 参数       ║"
    echo "════════════════════════════════════════"
    echo "请按照以下步骤获取参数："
    echo "1. 打开 Telegram，搜索 @BotFather"
    echo "2. 发送 /newbot 创建机器人，获取 TG_BOT_TOKEN"
    echo "3. 搜索 @userinfobot 获取 TG_CHAT_ID"
    echo ""
    if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
        echo "当前配置："
        echo "TG_BOT_TOKEN: $TG_BOT_TOKEN"
        echo "TG_CHAT_ID: $TG_CHAT_ID"
        echo "是否修改？(y/n)"
        read -r modify
        if [ "$modify" != "y" ]; then
            log "Configuration unchanged"
            main_menu
            return
        fi
    fi
    echo "请输入 TG_BOT_TOKEN："
    read -r token
    echo "请输入 TG_CHAT_ID："
    read -r chat_id
    if [ -z "$token" ] || [ -z "$chat_id" ]; then
        log "Error: Invalid Telegram configuration"
        echo "错误：Token 或 Chat ID 不能为空"
        sleep 1
        configure
        return
    fi
    echo "TG_BOT_TOKEN=\"$token\"" > "$CONFIG_FILE"
    echo "TG_CHAT_ID=\"$chat_id\"" >> "$CONFIG_FILE"
    TG_BOT_TOKEN="$token"
    TG_CHAT_ID="$chat_id"
    log "Configuration saved: TG_BOT_TOKEN=$token, TG_CHAT_ID=$chat_id"
    echo "配置已保存到 $CONFIG_FILE"
    sleep 2
    main_menu
}

# One-key installation
one_key_install() {
    log "One-key installation started"
    echo "正在执行一键安装..."

    # Install dependencies
    install_deps

    # Sync time
    sync_time

    # Configure Telegram
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        echo "未检测到 Telegram 配置，正在引导配置..."
        configure
    fi

    # Install service
    install_service

    echo "一键安装完成！测试通知已发送"
    sleep 2
    main_menu
}

# Main function
main() {
    # Initialize log
    mkdir -p /var/log 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null
    chmod 666 "$LOG_FILE" 2>/dev/null
    log "Script started: $SCRIPT_NAME v$VERSION"

    # Handle arguments
    case "$1" in
        menu) main_menu ;;
        test) test_notification ;;
        monitor) monitor ;;
        "") one_key_install ;;
        *) echo "用法: $0 [menu|test|monitor]" ; exit 1 ;;
    esac
}

# Trap signals to ensure clean exit
trap 'log "Script terminated"; reset >/dev/null 2>&1 || true; exit' SIGINT SIGTERM

# Run main
main "$@"

# Reset terminal to avoid affecting other scripts
reset >/dev/null 2>&1 || true
