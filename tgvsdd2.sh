#!/bin/bash

# VPS Notify Script (tgvsdd2.sh) v2.8
# Purpose: Monitor VPS status (IP, SSH, resources) and send notifications via Telegram/DingTalk
# License: MIT
# Version: 2.8 (2025-05-17)
# Changelog:
# - v2.8: Added retry mechanism to DingTalk validation/sending, enhanced logging, removed invalid tags
# - v2.7: Enhanced comments, clarified validate_dingtalk logic (no access_token encryption)
# - v2.2: Added DingTalk signed request support
# - v2.1: Added script update functionality
# - v2.0: Initial optimized version with menu and multi-channel notifications

# Configuration file
CONFIG_FILE="/etc/vps_notify.conf"
LOG_FILE="/var/log/vps_notify.log"
LOG_MAX_SIZE=$((1024*1024)) # 1MB

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Ensure log file exists
mkdir -p /var/log
touch "$LOG_FILE"

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
    # Rotate log if exceeds max size
    if [[ -f "$LOG_FILE" && $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE") -gt $LOG_MAX_SIZE ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
        log "Log rotated due to size limit"
    fi
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        # Default values
        ENABLE_TG_NOTIFY=0
        TG_BOT_TOKEN=""
        TG_CHAT_IDS=""
        ENABLE_DINGTALK_NOTIFY=0
        DINGTALK_WEBHOOK=""
        DINGTALK_SECRET=""
        ENABLE_IP_CHANGE_NOTIFY=1
        ENABLE_MEM_MONITOR=1
        MEM_THRESHOLD=80
        ENABLE_CPU_MONITOR=1
        CPU_THRESHOLD=80
        ENABLE_DISK_MONITOR=1
        DISK_THRESHOLD=80
        REMARK=""
        log "Configuration file not found, using defaults"
    fi
}

# Save configuration
save_config() {
    cat > "$CONFIG_FILE" << EOL
ENABLE_TG_NOTIFY=$ENABLE_TG_NOTIFY
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_CHAT_IDS="$TG_CHAT_IDS"
ENABLE_DINGTALK_NOTIFY=$ENABLE_DINGTALK_NOTIFY
DINGTALK_WEBHOOK="$DINGTALK_WEBHOOK"
DINGTALK_SECRET="$DINGTALK_SECRET"
ENABLE_IP_CHANGE_NOTIFY=$ENABLE_IP_CHANGE_NOTIFY
ENABLE_MEM_MONITOR=$ENABLE_MEM_MONITOR
MEM_THRESHOLD=$MEM_THRESHOLD
ENABLE_CPU_MONITOR=$ENABLE_CPU_MONITOR
CPU_THRESHOLD=$CPU_THRESHOLD
ENABLE_DISK_MONITOR=$ENABLE_DISK_MONITOR
DISK_THRESHOLD=$DISK_THRESHOLD
REMARK="$REMARK"
EOL
    log "Configuration saved to $CONFIG_FILE"
}

# Validate Telegram configuration
validate_telegram() {
    if [[ "$ENABLE_TG_NOTIFY" -eq 1 && -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_IDS" ]]; then
        local response=$(curl -s -m 5 "https://api.telegram.org/bot${TG_BOT_TOKEN}/getMe")
        if echo "$response" | grep -q '"ok":true'; then
            echo "Telegram Bot 验证成功"
            return 0
        else
            echo "Telegram Bot 验证失败：无效的 Token"
            log "ERROR: Telegram validation failed: $response"
            return 1
        fi
    else
        echo "Telegram 配置不完整或未启用"
        return 1
    fi
}

# Validate DingTalk configuration
validate_dingtalk() {
    local webhook="$1"
    local secret="$2"
    local max_attempts=3
    local attempt=1
    local response errcode errmsg masked_webhook

    # Mask access_token for logging
    masked_webhook=$(echo "$webhook" | sed 's/\(access_token=\).*/\1[hidden]/')

    while [[ $attempt -le $max_attempts ]]; do
        local timestamp=$(date +%s%3N)
        local sign=""
        local url="$webhook"

        # Add timestamp and sign for signed requests
        if [[ -n "$secret" ]]; then
            local string_to_sign="${timestamp}\n${secret}"
            sign=$(echo -n "$string_to_sign" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | tr -d '\n')
            url="${webhook}×tamp=${timestamp}&sign=${sign}"
        fi

        # Send test message (includes keyword "VPS")
        response=$(curl -s -m 5 -X POST "$url" \
            -H "Content-Type: application/json" \
            -d '{"msgtype": "text", "text": {"content": "VPS 测试消息"}}')

        errcode=$(echo "$response" | grep -o '"errcode":[0-9]*' | cut -d: -f2)
        errmsg=$(echo "$response" | grep -o '"errmsg":"[^"]*"' | cut -d: -f2- | tr -d '"')

        if [[ "$errcode" == "0" ]]; then
            echo "DingTalk Webhook 验证成功"
            log "DingTalk validation succeeded on attempt $attempt for $masked_webhook"
            return 0
        else
            log "ERROR: DingTalk validation failed on attempt $attempt for $masked_webhook: errcode=$errcode, errmsg=$errmsg"
            if [[ $attempt -lt $max_attempts ]]; then
                sleep 2
                ((attempt++))
            else
                echo -e "${RED}DingTalk Webhook 验证失败 (错误码: $errcode)：$errmsg${NC}"
                return 1
            fi
        fi
    done
}

# Send Telegram notification
send_telegram() {
    local message="$1"
    if [[ "$ENABLE_TG_NOTIFY" -eq 1 && -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_IDS" ]]; then
        for chat_id in ${TG_CHAT_IDS//,/ }; do
            local response=$(curl -s -m 5 -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
                -d "chat_id=${chat_id}&text=${message}")
            if ! echo "$response" | grep -q '"ok":true'; then
                log "ERROR: Failed to send Telegram message to $chat_id: $response"
            fi
        done
        log "Telegram notification sent: $message"
    fi
}

# Send DingTalk notification
send_dingtalk() {
    local message="$1"
    if [[ "$ENABLE_DINGTALK_NOTIFY" -eq 1 && -n "$DINGTALK_WEBHOOK" ]]; then
        local max_attempts=3
        local attempt=1
        local response errcode masked_webhook

        # Mask access_token for logging
        masked_webhook=$(echo "$DINGTALK_WEBHOOK" | sed 's/\(access_token=\).*/\1[hidden]/')

        while [[ $attempt -le $max_attempts ]]; do
            local timestamp=$(date +%s%3N)
            local sign=""
            local url="$DINGTALK_WEBHOOK"

            if [[ -n "$DINGTALK_SECRET" ]]; then
                local string_to_sign="${timestamp}\n${DINGTALK_SECRET}"
                sign=$(echo -n "$string_to_sign" | openssl dgst -sha256 -hmac "$DINGTALK_SECRET" -binary | base64 | tr -d '\n')
                url="${DINGTALK_WEBHOOK}×tamp=${timestamp}&sign=${sign}"
            fi

            response=$(curl -s -m 5 -X POST "$url" \
                -H "Content-Type: application/json" \
                -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"VPS $message\"}}")

            errcode=$(echo "$response" | grep -o '"errcode":[0-9]*' | cut -d: -f2)
            if [[ "$errcode" == "0" ]]; then
                log "DingTalk notification sent on attempt $attempt for $masked_webhook: $message"
                return 0
            else
                log "ERROR: Failed to send DingTalk message on attempt $attempt for $masked_webhook: $response"
                if [[ $attempt -lt $max_attempts ]]; then
                    sleep 2
                    ((attempt++))
                else
                    return 1
                fi
            fi
        done
    fi
}

# Get public IP addresses
get_ip() {
    local ipv4=""
    local ipv6=""
    # Try multiple services for IPv4
    for service in "ip.sb" "ifconfig.me" "ipinfo.io/ip" "api.ipify.org"; do
        ipv4=$(curl -s -m 3 "https://$service")
        if [[ -n "$ipv4" && "$ipv4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        fi
    done
    # Try multiple services for IPv6
    for service in "ip.sb" "ifconfig.me" "ipinfo.io/ip"; do
        ipv6=$(curl -s -m 3 -6 "https://$service")
        if [[ -n "$ipv6" && "$ipv6" =~ ^[0-9a-fA-F:]+$ ]]; then
            break
        fi
    done
    echo "IPv4: ${ipv4:-获取失败}"
    echo "IPv6: ${ipv6:-获取失败}"
}

# Monitor resources
monitor_resources() {
    local message=""
    local current_time=$(date '+%s')
    local last_alert_file="/tmp/vps_notify_last_alert"

    # Check last alert time
    local last_alert=0
    if [[ -f "$last_alert_file" ]]; then
        last_alert=$(cat "$last_alert_file")
    fi

    # Only send alert if 6 hours have passed
    if [[ $((current_time - last_alert)) -lt $((6*3600)) ]]; then
        return
    fi

    # Memory usage
    if [[ "$ENABLE_MEM_MONITOR" -eq 1 ]]; then
        local mem_info=$(free | grep Mem)
        local total=$(echo "$mem_info" | awk '{print $2}')
        local used=$(echo "$mem_info" | awk '{print $3}')
        local usage=$((100 * used / total))
        if [[ $usage -ge $MEM_THRESHOLD ]]; then
            message+="内存使用率: ${usage}% (超过阈值 ${MEM_THRESHOLD}%)\n"
        fi
    fi

    # CPU usage
    if [[ "$ENABLE_CPU_MONITOR" -eq 1 ]]; then
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
        local usage=$(printf "%.0f" "$cpu_usage")
        if [[ $usage -ge $CPU_THRESHOLD ]]; then
            message+="CPU 使用率: ${usage}% (超过阈值 ${CPU_THRESHOLD}%)\n"
        fi
    fi

    # Disk usage
    if [[ "$ENABLE_DISK_MONITOR" -eq 1 ]]; then
        local disk_usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
        if [[ $disk_usage -ge $DISK_THRESHOLD ]]; then
            message+="磁盘使用率: ${disk_usage}% (超过阈值 ${DISK_THRESHOLD}%)\n"
        fi
    fi

    if [[ -n "$message" ]]; then
        message="⚠️ 资源警报\n$message时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
        send_telegram "$message"
        send_dingtalk "$message"
        echo "$current_time" > "$last_alert_file"
    fi
}

# Monitor IP changes
monitor_ip() {
    if [[ "$ENABLE_IP_CHANGE_NOTIFY" -eq 1 ]]; then
        local ip_file="/tmp/vps_notify_ip"
        local current_ip=$(get_ip)
        local old_ip=""
        if [[ -f "$ip_file" ]]; then
            old_ip=$(cat "$ip_file")
        fi
        if [[ "$current_ip" != "$old_ip" ]]; then
            local message="🌐 IP 变动\n旧 IP:\n$old_ip\n新 IP:\n$current_ip\n时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
            send_telegram "$message"
            send_dingtalk "$message"
            echo "$current_ip" > "$ip_file"
            log "IP changed: $current_ip"
        fi
    fi
}

# Send boot notification
send_boot_notification() {
    local hostname=$(hostname)
    local ip_info=$(get_ip)
    local message="✅ VPS 已上线\n备注: $REMARK\n主机名: $hostname\n公网IP:\n$ip_info\n时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
    send_telegram "$message"
    send_dingtalk "$message"
    log "Boot notification sent"
}

# Send SSH login notification
send_ssh_notification() {
    local user="$1"
    local ip="$2"
    local message="🔐 SSH 登录\n用户: $user\n来源 IP: $ip\n时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
    send_telegram "$message"
    send_dingtalk "$message"
    log "SSH login notification sent: $user from $ip"
}

# Install dependencies
install_dependencies() {
    local packages="curl grep gawk systemd coreutils openssl"
    if ! command -v apt >/dev/null 2>&1; then
        echo "仅支持基于 Debian/Ubuntu 的系统"
        log "ERROR: Unsupported system, apt not found"
        exit 1
    fi
    apt update
    apt install -y $packages
    log "Dependencies installed: $packages"
}

# Install script
install() {
    install_dependencies
    load_config
    echo "开始安装 VPS Notify..."
    # Configure systemd service
    cat > /etc/systemd/system/vps_notify.service << EOL
[Unit]
Description=VPS Notify Boot Service
After=network-online.target
[Service]
Type=oneshot
ExecStart=/bin/bash $PWD/tgvsdd2.sh boot
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOL
    systemctl enable vps_notify.service
    # Configure cron job
    echo "*/5 * * * * root /bin/bash $PWD/tgvsdd2.sh monitor" > /etc/cron.d/vps_notify
    # Configure SSH login notification
    echo "session optional pam_exec.so /bin/bash $PWD/tgvsdd2.sh ssh" >> /etc/pam.d/sshd
    save_config
    log "Installation completed"
    echo -e "${GREEN}安装完成！${NC}"
}

# Uninstall script
uninstall() {
    echo "开始卸载 VPS Notify..."
    systemctl disable vps_notify.service
    rm -f /etc/systemd/system/vps_notify.service
    rm -f /etc/cron.d/vps_notify
    sed -i '/pam_exec.so.*tgvsdd2.sh/d' /etc/pam.d/sshd
    rm -f "$CONFIG_FILE"
    rm -f /tmp/vps_notify_*
    log "Uninstallation completed"
    echo -e "${GREEN}卸载完成！${NC}"
}

# Update script
update_script() {
    local remote_url="https://raw.githubusercontent.com/meiloi/scripts/main/tgvsdd2.sh"
    local temp_file="/tmp/tgvsdd2.sh"
    if curl -s -o "$temp_file" "$remote_url"; then
        if [[ -s "$temp_file" ]]; then
            chmod +x "$temp_file"
            mv "$temp_file" "$PWD/tgvsdd2.sh"
            log "Script updated from $remote_url"
            echo -e "${GREEN}脚本更新成功！${NC}"
        else
            log "ERROR: Downloaded script is empty"
            echo -e "${RED}更新失败：下载的脚本为空${NC}"
        fi
    else
        log "ERROR: Failed to download script from $remote_url"
        echo -e "${RED}更新失败：无法下载脚本${NC}"
    fi
}

# Configure settings
configure_settings() {
    load_config
    while true; do
        echo -e "\n配置设置"
        echo "1. 启用/禁用 Telegram 通知"
        echo "2. 修改 Telegram Bot Token"
        echo "3. 修改 Telegram Chat IDs"
        echo "4. 启用/禁用 DingTalk 通知"
        echo "5. 修改 DingTalk Webhook"
        echo "6. 修改 DingTalk Secret"
        echo "7. 启用/禁用 IP 变动通知"
        echo "8. 配置资源监控"
        echo "9. 修改备注"
        echo "0. 返回主菜单"
        read -p "请选择: " choice
        case $choice in
            1)
                read -p "启用 Telegram 通知？(1=是, 0=否): " ENABLE_TG_NOTIFY
                ;;
            2)
                read -p "请输入 Telegram Bot Token: " TG_BOT_TOKEN
                validate_telegram && echo -e "${GREEN}Token 有效${NC}" || echo -e "${RED}Token 无效${NC}"
                ;;
            3)
                read -p "请输入 Telegram Chat IDs (逗号分隔): " TG_CHAT_IDS
                ;;
            4)
                read -p "启用 DingTalk 通知？(1=是, 0=否): " ENABLE_DINGTALK_NOTIFY
                ;;
            5)
                read -p "请输入 DingTalk Webhook: " DINGTALK_WEBHOOK
                validate_dingtalk "$DINGTALK_WEBHOOK" "$DINGTALK_SECRET"
                ;;
            6)
                read -p "请输入 DingTalk Secret (留空禁用加签): " DINGTALK_SECRET
                validate_dingtalk "$DINGTALK_WEBHOOK" "$DINGTALK_SECRET"
                ;;
            7)
                read -p "启用 IP 变动通知？(1=是, 0=否): " ENABLE_IP_CHANGE_NOTIFY
                ;;
            8)
                read -p "启用内存监控？(1=是, 0=否): " ENABLE_MEM_MONITOR
                read -p "内存使用率阈值 (%): " MEM_THRESHOLD
                read -p "启用 CPU 监控？(1=是, 0=否): " ENABLE_CPU_MONITOR
                read -p "CPU 使用率阈值 (%): " CPU_THRESHOLD
                read -p "启用磁盘监控？(1=是, 0=否): " ENABLE_DISK_MONITOR
                read -p "磁盘使用率阈值 (%): " DISK_THRESHOLD
                ;;
            9)
                read -p "请输入备注: " REMARK
                ;;
            0)
                save_config
                return
                ;;
            *)
                echo -e "${RED}无效选项${NC}"
                ;;
        esac
        save_config
    done
}

# Test notifications
test_notifications() {
    load_config
    while true; do
        echo -e "\n测试通知"
        echo "1. 测试开机通知"
        echo "2. 测试 SSH 登录通知"
        echo "3. 测试资源警报"
        echo "4. 测试 IP 变动通知"
        echo "0. 返回主菜单"
        read -p "请选择: " choice
        case $choice in
            1)
                send_boot_notification
                echo -e "${GREEN}开机通知已发送${NC}"
                ;;
            2)
                send_ssh_notification "testuser" "192.168.1.1"
                echo -e "${GREEN}SSH 登录通知已发送${NC}"
                ;;
            3)
                local message="⚠️ 测试资源警报\n内存使用率: 85%\nCPU 使用率: 90%\n磁盘使用率: 95%\n时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
                send_telegram "$message"
                send_dingtalk "$message"
                echo -e "${GREEN}资源警报已发送${NC}"
                ;;
            4)
                local message="🌐 测试 IP 变动\n旧 IP:\nIPv4: 192.168.1.1\n新 IP:\n$(get_ip)\n时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
                send_telegram "$message"
                send_dingtalk "$message"
                echo -e "${GREEN}IP 变动通知已发送${NC}"
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选项${NC}"
                ;;
        esac
    done
}

# Check system status
check_status() {
    echo -e "\n系统状态"
    if systemctl is-active --quiet vps_notify.service; then
        echo -e "${GREEN}VPS Notify 服务: 运行中${NC}"
    else
        echo -e "${RED}VPS Notify 服务: 未运行${NC}"
    fi
    if [[ -f /etc/cron.d/vps_notify ]]; then
        echo -e "${GREEN}Cron 任务: 已配置${NC}"
    else
        echo -e "${RED}Cron 任务: 未配置${NC}"
    fi
    if grep -q "pam_exec.so.*tgvsdd2.sh" /etc/pam.d/sshd; then
        echo -e "${GREEN}SSH 通知: 已启用${NC}"
    else
        echo -e "${RED}SSH 通知: 未启用${NC}"
    fi
    echo -e "\n最近日志:"
    tail -n 5 "$LOG_FILE"
}

# Main menu
main_menu() {
    while true; do
        echo -e "\nVPS Notify 管理菜单 (v2.8)"
        echo "1. 安装/重新安装"
        echo "2. 配置设置"
        echo "3. 测试通知"
        echo "4. 检查系统状态"
        echo "5. 卸载"
        echo "6. 更新脚本"
        echo "0. 退出"
        read -p "请选择: " choice
        case $choice in
            1)
                install
                ;;
            2)
                configure_settings
                ;;
            3)
                test_notifications
                ;;
            4)
                check_status
                ;;
            5)
                uninstall
                ;;
            6)
                update_script
                ;;
            0)
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项${NC}"
                ;;
        esac
    done
}

# Command line mode
case "$1" in
    install)
        install
        ;;
    uninstall)
        uninstall
        ;;
    boot)
        load_config
        send_boot_notification
        ;;
    ssh)
        load_config
        send_ssh_notification "$PAM_USER" "$PAM_RHOST"
        ;;
    monitor)
        load_config
        monitor_resources
        monitor_ip
        ;;
    menu|*)
        main_menu
        ;;
esac
