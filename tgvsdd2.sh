#!/bin/bash

# VPS Notify Script (tgvsdd2.sh)
# Version: 3.1.0 (2025-05-17)
# Purpose: Advanced VPS notification system with Telegram and DingTalk integration
# Features: One-key install, interactive menu, SSH login alerts, CPU monitoring, script update/uninstall
# Fixes: CPU 100% bug, Telegram newlines, compatibility

# Configuration
LOG_FILE="/var/log/vps_notify.log"
CONFIG_FILE="/etc/vps_notify.conf"
TG_BOT_TOKEN=""
TG_CHAT_ID=""
DINGTALK_WEBHOOK=""
SCRIPT_NAME="tgvsdd2.sh"
VERSION="3.1.0"
GITHUB_URL="https://raw.githubusercontent.com/meiloi/scripts/main/tgvsdd2.sh"
ENABLE_SSH_NOTIFY="no"
ENABLE_CPU_NOTIFY="no"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
}

# Escape Markdown characters
escape_markdown() {
    echo "$1" | sed 's/\\([_*\\[]\\[`#+=\\-|.{}()!]\\)/\\\\\\1/g' 2>/dev/null
}

# Send Telegram notification
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
}

# Send DingTalk notification
send_dingtalk() {
    local message="$1"
    if [ -z "$DINGTALK_WEBHOOK" ]; then
        log "Error: DingTalk not configured"
        return 1
    fi
    local final_message=$(echo "$message" | sed 's/\\n/\\n\\n/g')
    local json_payload=$(printf '{"msgtype":"markdown","markdown":{"title":"VPS 通知","text":"%s"}}' "$final_message")
    local response
    response=$(curl -s --max-time 10 -X POST "$DINGTALK_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$json_payload" 2>/dev/null)
    log "DingTalk sent: raw='$final_message', response='$response'"
}

# Send notification (both Telegram and DingTalk)
send_notification() {
    local message="$1"
    send_telegram "$message"
    send_dingtalk "$message"
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
    send_notification "$message"
    log "Boot notification sent for $remark"
}

# SSH login notification
ssh_notify() {
    local log_file="/var/log/auth.log"
    [ -f "/var/log/secure" ] && log_file="/var/log/secure"
    tail -n 0 -f "$log_file" 2>/dev/null | grep --line-buffered "Accepted" | while read -r line; do
        local user=$(echo "$line" | grep -oP "for \K\S+")
        local ip=$(echo "$line" | grep -oP "from \K\S+")
        local message="🔐 SSH 登录\n用户: $user\nIP: $ip\n主机名: $(hostname)\n時間: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
        send_notification "$message"
        log "SSH login detected: user=$user, ip=$ip"
    done &
    local pid=$!
    echo "$pid" > "/var/run/vps_notify_ssh.pid"
    log "SSH notify started, PID=$pid"
}

# CPU usage monitoring
cpu_notify() {
    local threshold=100  # CPU usage in percent
    local duration=300   # 5 minutes in seconds
    local check_interval=30
    local high_usage_start=0
    while true; do
        local cpu_usage=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1)
        [ -z "$cpu_usage" ] && cpu_usage=$(ps -eo pcpu | awk '{sum+=$1} END {print sum}' | cut -d. -f1)
        if [ "$cpu_usage" -ge "$threshold" ]; then
            if [ $high_usage_start -eq 0 ]; then
                high_usage_start=$(date +%s)
            elif [ $(( $(date +%s) - high_usage_start )) -ge $duration ]; then
                local message="⚠ CPU 使用率过高\n使用率: $cpu_usage%\n持续时间: 5分钟\n主机名: $(hostname)\n時間: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
                send_notification "$message"
                log "CPU high usage alert: $cpu_usage%"
                high_usage_start=0  # Reset after alert
            fi
        else
            high_usage_start=0
        fi
        sleep $check_interval
    done &
    local pid=$!
    echo "$pid" > "/var/run/vps_notify_cpu.pid"
    log "CPU notify started, PID=$pid"
}

# Network monitor
monitor_network() {
    local max_runs=360  # 1 hour at 10s intervals
    local count=0
    local last_status="online"
    log "Network monitor started"
    echo "网络监控已启动（1 小时后停止）"
    while [ $count -lt $max_runs ]; do
        local status=$(curl -s --max-time 5 http://ipinfo.io/ip 2>/dev/null || echo "offline")
        if [ "$status" != "$last_status" ]; then
            if [ "$status" = "offline" ]; then
                send_notification "⚠ VPS 离线\n主机名: $(hostname 2>/dev/null || echo '未知')"
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
}

# Main menu
main_menu() {
    clear
    echo "════════════════════════════════════════"
    echo "║       VPS 通知系统 (高级版)       ║"
    echo "║       Version: $VERSION           ║"
    echo "════════════════════════════════════════"
    echo "1. 安装推送服务"
    echo "   1. Telegram 推送"
    echo "   2. 钉钉推送"
    echo "2. 设置参数"
    echo "3. 测试通知"
    echo "4. 卸载脚本"
    echo "5. 更新脚本"
    echo "0. 退出"
    echo "请输入选项 [0-5] 或 1.1/1.2："
    read -r choice 2>/dev/null
    case "$choice" in
        1.1) install_service "telegram" ;;
        1.2) install_service "dingtalk" ;;
        1) install_service ;;
        2) configure ;;
        3) test_notification ;;
        4) uninstall ;;
        5) update_script ;;
        0) log "Script exited by user" ; exit 0 ;;
        *) echo "无效选项，请输入 0-5 或 1.1/1.2" ; sleep 1 ; main_menu ;;
    esac
}

# Test notification
test_notification() {
    if [ -z "$TG_BOT_TOKEN" ] && [ -z "$DINGTALK_WEBHOOK" ]; then
        echo "未配置 Telegram 或 钉钉，请先配置"
        sleep 1
        configure
    fi
    boot_notification "Test"
    echo "测试通知已发送，请检查 Telegram 或 钉钉"
    sleep 2
    main_menu
}

# Install dependencies
install_deps() {
    local missing=""
    for cmd in curl sed date hostname grep; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done
    if [ -n "$missing" ]; then
        log "Installing dependencies:$missing"
        if command -v apt >/dev/null 2>&1; then
            echo "检测到 Debian 系统，正在安装依赖..."
            apt update >/dev/null 2>&1
            apt install -y curl sed coreutils grep >/dev/null 2>&1
        elif command -v apk >/dev/null 2>&1; then
            echo "检测到 Alpine 系统，正在安装依赖..."
            apk update >/dev/null 2>&1
            apk add curl sed coreutils grep >/dev/null 2>&1
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
    local push_type="$1"
    clear
    echo "════════════════════════════════════════"
    echo "║       安装 VPS 通知服务       ║"
    echo "════════════════════════════════════════"
    echo "请选择功能（y/n）："
    echo "启用 SSH 登录通知？"
    read -r ssh_notify
    echo "启用 CPU 使用率监控（100% 持续 5 分钟通知）？"
    read -r cpu_notify
    [ "$ssh_notify" = "y" ] && ENABLE_SSH_NOTIFY="yes" || ENABLE_SSH_NOTIFY="no"
    [ "$cpu_notify" = "y" ] && ENABLE_CPU_NOTIFY="yes" || ENABLE_CPU_NOTIFY="no"

    # Configure push
    if [ "$push_type" = "telegram" ] || [ -z "$push_type" ]; then
        if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
            echo "未配置 Telegram，正在引导配置..."
            configure_telegram
        fi
    fi
    if [ "$push_type" = "dingtalk" ] || [ -z "$push_type" ]; then
        if [ -z "$DINGTALK_WEBHOOK" ]; then
            echo "未配置 钉钉，正在引导配置..."
            configure_dingtalk
        fi
    fi

    # Save configuration
    cat > "$CONFIG_FILE" << EOF
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_CHAT_ID="$TG_CHAT_ID"
DINGTALK_WEBHOOK="$DINGTALK_WEBHOOK"
ENABLE_SSH_NOTIFY="$ENABLE_SSH_NOTIFY"
ENABLE_CPU_NOTIFY="$ENABLE_CPU_NOTIFY"
EOF
    chmod 600 "$CONFIG_FILE"
    log "Configuration saved: SSH=$ENABLE_SSH_NOTIFY, CPU=$ENABLE_CPU_NOTIFY"

    # Install service
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

    # Start monitors
    [ "$ENABLE_SSH_NOTIFY" = "yes" ] && ssh_notify
    [ "$ENABLE_CPU_NOTIFY" = "yes" ] && cpu_notify

    echo "安装完成！"
    boot_notification "安装完成"
    sleep 2
    main_menu
}

# Configure Telegram
configure_telegram() {
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
        echo "当前 Telegram 配置："
        echo "TG_BOT_TOKEN: $TG_BOT_TOKEN"
        echo "TG_CHAT_ID: $TG_CHAT_ID"
        echo "是否修改？(y/n)"
        read -r modify
        [ "$modify" != "y" ] && return
    fi
    echo "请输入 TG_BOT_TOKEN："
    read -r token
    echo "请输入 TG_CHAT_ID："
    read -r chat_id
    if [ -z "$token" ] || [ -z "$chat_id" ]; then
        log "Error: Invalid Telegram configuration"
        echo "错误：Token 或 Chat ID 不能为空"
        sleep 1
        configure_telegram
        return
    fi
    TG_BOT_TOKEN="$token"
    TG_CHAT_ID="$chat_id"
    log "Telegram configured: TG_BOT_TOKEN=$token, TG_CHAT_ID=$chat_id"
}

# Configure DingTalk
configure_dingtalk() {
    clear
    echo "════════════════════════════════════════"
    echo "║       配置 钉钉 参数       ║"
    echo "════════════════════════════════════════"
    echo "请按照以下步骤获取参数："
    echo "1. 打开钉钉群，添加自定义机器人"
    echo "2. 获取 Webhook URL（格式：https://oapi.dingtalk.com/robot/send?access_token=...）"
    echo ""
    if [ -n "$DINGTALK_WEBHOOK" ]; then
        echo "当前 钉钉 配置："
        echo "DINGTALK_WEBHOOK: $DINGTALK_WEBHOOK"
        echo "是否修改？(y/n)"
        read -r modify
        [ "$modify" != "y" ] && return
    fi
    echo "请输入 DINGTALK_WEBHOOK："
    read -r webhook
    if [ -z "$webhook" ]; then
        log "Error: Invalid DingTalk configuration"
        echo "错误：Webhook 不能为空"
        sleep 1
        configure_dingtalk
        return
    fi
    DINGTALK_WEBHOOK="$webhook"
    log "DingTalk configured: DINGTALK_WEBHOOK=$webhook"
}

# Configure parameters
configure() {
    clear
    echo "════════════════════════════════════════"
    echo "║       设置参数       ║"
    echo "════════════════════════════════════════"
    echo "1. 配置 Telegram"
    echo "2. 配置 钉钉"
    echo "3. 配置通知功能"
    echo "0. 返回"
    echo "请输入选项 [0-3]："
    read -r choice
    case "$choice" in
        1) configure_telegram ;;
        2) configure_dingtalk ;;
        3) configure_features ;;
        0) main_menu ;;
        *) echo "无效选项" ; sleep 1 ; configure ;;
    esac

    # Save configuration
    cat > "$CONFIG_FILE" << EOF
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_CHAT_ID="$TG_CHAT_ID"
DINGTALK_WEBHOOK="$DINGTALK_WEBHOOK"
ENABLE_SSH_NOTIFY="$ENABLE_SSH_NOTIFY"
ENABLE_CPU_NOTIFY="$ENABLE_CPU_NOTIFY"
EOF
    chmod 600 "$CONFIG_FILE"
    log "Configuration saved"
    main_menu
}

# Configure features
configure_features() {
    clear
    echo "════════════════════════════════════════"
    echo "║       配置通知功能       ║"
    echo "════════════════════════════════════════"
    echo "当前设置："
    echo "SSH 登录通知: $ENABLE_SSH_NOTIFY"
    echo "CPU 使用率监控: $ENABLE_CPU_NOTIFY"
    echo ""
    echo "启用 SSH 登录通知？(y/n)"
    read -r ssh_notify
    echo "启用 CPU 使用率监控（100% 持续 5 分钟通知）？(y/n)"
    read -r cpu_notify
    [ "$ssh_notify" = "y" ] && ENABLE_SSH_NOTIFY="yes" || ENABLE_SSH_NOTIFY="no"
    [ "$cpu_notify" = "y" ] && ENABLE_CPU_NOTIFY="yes" || ENABLE_CPU_NOTIFY="no"
    log "Features configured: SSH=$ENABLE_SSH_NOTIFY, CPU=$ENABLE_CPU_NOTIFY"
    echo "配置已更新"
    sleep 2
}

# Uninstall script
uninstall() {
    clear
    echo "════════════════════════════════════════"
    echo "║       卸载 VPS 通知脚本       ║"
    echo "════════════════════════════════════════"
    echo "正在卸载..."

    # Stop services
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop vps-notify >/dev/null 2>&1
        systemctl disable vps-notify >/dev/null 2>&1
        rm -f /etc/systemd/system/vps-notify.service
    elif command -v rc-update >/dev/null 2>&1; then
        rc-service vps-notify stop >/dev/null 2>&1
        rc-update del vps-notify default >/dev/null 2>&1
        rm -f /etc/init.d/vps-notify
    fi

    # Stop monitors
    for pid_file in /var/run/vps_notify_*.pid; do
        if [ -f "$pid_file" ]; then
            kill $(cat "$pid_file") 2>/dev/null
            rm -f "$pid_file"
        fi
    done

    # Remove files
    rm -f "$CONFIG_FILE" "$LOG_FILE" "/root/$SCRIPT_NAME"
    log "Script uninstalled"
    echo "卸载完成！"
    exit 0
}

# Update script
update_script() {
    clear
    echo "════════════════════════════════════════"
    echo "║       更新 VPS 通知脚本       ║"
    echo "════════════════════════════════════════"
    echo "正在检查更新..."
    local temp_file=$(mktemp)
    if curl -s --max-time 10 -o "$temp_file" "$GITHUB_URL" 2>/dev/null; then
        local new_version=$(grep "Version:" "$temp_file" | head -n 1 | cut -d' ' -f3)
        if [ "$new_version" != "$VERSION" ]; then
            mv "$temp_file" "/root/$SCRIPT_NAME"
            chmod +x "/root/$SCRIPT_NAME"
            log "Script updated to version $new_version"
            echo "脚本已更新到版本 $new_version"
            echo "请重新运行脚本：./$SCRIPT_NAME"
            exit 0
        else
            rm -f "$temp_file"
            log "No update available"
            echo "当前已是最新版本 ($VERSION)"
        fi
    else
        rm -f "$temp_file"
        log "Error: Failed to check update"
        echo "错误：无法检查更新，请检查网络"
    fi
    sleep 2
    main_menu
}

# One-key installation
one_key_install() {
    log "One-key installation started"
    clear
    echo "════════════════════════════════════════"
    echo "║       VPS 通知系统一键安装       ║"
    echo "════════════════════════════════════════"

    # Install dependencies
    install_deps

    # Sync time
    sync_time

    # Configure push
    if [ -z "$TG_BOT_TOKEN" ] && [ -z "$DINGTALK_WEBHOOK" ]; then
        echo "未检测到推送配置，请选择推送方式："
        echo "1. Telegram"
        echo "2. 钉钉"
        echo "3. 两者都配置"
        read -r push_choice
        case "$push_choice" in
            1) configure_telegram ;;
            2) configure_dingtalk ;;
            3) configure_telegram ; configure_dingtalk ;;
            *) configure_telegram ;;
        esac
    fi

    # Configure features
    configure_features

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
        monitor) monitor_network ;;
        "") one_key_install ;;
        *) echo "用法: $0 [menu|test|monitor]" ; exit 1 ;;
    esac
}

# Trap signals
trap 'log "Script terminated"; reset >/dev/null 2>&1 || true; exit' SIGINT SIGTERM

# Run main
main "$@"

# Reset terminal
reset >/dev/null 2>&1 || true
