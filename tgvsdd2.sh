#!/bin/bash

# VPS Notify Script (tgvsdd2.sh) v3.0.7
# Purpose: Monitor VPS status (IP, SSH, resources, network) and send notifications via Telegram/DingTalk
# License: MIT
# Version: 3.0.7 (2025-05-17)
# Changelog:
# - v3.0.7: Fixed syntax error (line 203, binary operator), removed parse_mode=HTML and <br>, restored emoji (✅, 🔐, ⚠️, 🌐), added TG_EMOJI and TG_PARSE_MODE configs
# - v3.0.6: Fixed Telegram notification not showing (sanitize HTML, remove emoji, add retry with plain text), enhanced error checking
# - v3.0.5: Fixed Telegram newline (use parse_mode=HTML with <br>), enhanced API response logging
# - v3.0.4: Fixed Telegram newline (use parse_mode=MarkdownV2, escape special chars), added API response logging
# - v3.0.3: Fixed Telegram notification newline (added parse_mode=Markdown), optimized remark prompt
# - v3.0.2: Fixed log undefined error, fixed syntax error in get_ip and monitor_resources, improved compatibility
# - v3.0.1: Fixed Telegram config bug (validate_telegram required TG_CHAT_IDS), optimized guided_config
# - v3.0: Fixed Telegram newline bug, restored v2.2 guided install, added network monitoring and alert interval
# - v2.9.1: Restored v2.2 interactive UI with framed menu and config overview
# - v2.9: Enhanced colored menu, added TERM compatibility check
# - v2.8: Added retry mechanism to DingTalk validation/sending, enhanced logging
# - v2.7: Clarified validate_dingtalk logic
# - v2.2: Added DingTalk signed request support
# - v2.1: Added script update functionality
# - v2.0: Initial optimized version with menu and multi-channel notifications

# Configuration file
CONFIG_FILE="/etc/vps_notify.conf"
LOG_FILE="/var/log/vps_notify.log"
LOG_MAX_SIZE=$((1024*1024)) # 1MB
LOG_RETENTION_DAYS=7
DEBUG_TG=0 # Debug mode for Telegram (1=enabled, 0=disabled)
TG_EMOJI=1 # Enable emoji in Telegram messages (1=enabled, 0=disabled)
TG_PARSE_MODE="plain" # Telegram parse mode (plain, html)

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
    # Rotate log if exceeds max size
    if [[ -f "$LOG_FILE" && $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE") -gt $LOG_MAX_SIZE ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
        echo "[$timestamp] Log rotated due to size limit" >> "$LOG_FILE"
    fi
    # Clean up old logs
    find /var/log -name "vps_notify.log.old" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
}

# Ensure log file exists
mkdir -p /var/log
touch "$LOG_FILE"
log "Script started"

# Check Bash version
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "错误：需要 Bash 4.0 或更高版本"
    log "ERROR: Bash version ${BASH_VERSION} is too old, requires 4.0+"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check terminal color support
if [[ "$TERM" != *"color"* ]]; then
    echo -e "${YELLOW}警告：终端可能不支持颜色显示，已自动设置为 xterm-256color${NC}"
    export TERM=xterm-256color
    COLOR_SUPPORT=0
    log "Warning: TERM=$TERM does not support colors, set to xterm-256color"
else
    COLOR_SUPPORT=1
    log "Color support enabled (TERM=$TERM)"
fi

# Check time synchronization
check_time_sync() {
    if ! command -v ntpdate >/dev/null 2>&1; then
        apt install -y ntpdate >/dev/null 2>&1
    fi
    local ntp_status=$(ntpdate -q pool.ntp.org 2>&1)
    if [[ $? -ne 0 ]]; then
        echo -e "${YELLOW}警告：系统时间未同步，可能影响钉钉加签。请运行 'ntpdate pool.ntp.org'${NC}"
        log "Warning: Time sync failed: $ntp_status"
    else
        log "Time sync verified"
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
        ENABLE_NETWORK_MONITOR=1
        ALERT_INTERVAL=6
        REMARK=""
        DEBUG_TG=0
        TG_EMOJI=1
        TG_PARSE_MODE="plain"
        log "Configuration file not found, using defaults"
    fi
    # Ensure variables are defined
    : "${ENABLE_TG_NOTIFY:=0}"
    : "${TG_BOT_TOKEN:=}"
    : "${TG_CHAT_IDS:=}"
    : "${DEBUG_TG:=0}"
    : "${TG_EMOJI:=1}"
    : "${TG_PARSE_MODE:=plain}"
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
ENABLE_NETWORK_MONITOR=$ENABLE_NETWORK_MONITOR
ALERT_INTERVAL=$ALERT_INTERVAL
REMARK="$REMARK"
DEBUG_TG=$DEBUG_TG
TG_EMOJI=$TG_EMOJI
TG_PARSE_MODE="$TG_PARSE_MODE"
EOL
    log "Configuration saved to $CONFIG_FILE"
}

# Validate Telegram configuration
validate_telegram() {
    if [[ "$ENABLE_TG_NOTIFY" -eq 1 && -n "$TG_BOT_TOKEN" ]]; then
        local response=$(curl -s -m 5 "https://api.telegram.org/bot${TG_BOT_TOKEN}/getMe")
        if echo "$response" | grep -q '"ok":true'; then
            echo -e "${GREEN}Telegram Bot 验证成功${NC}"
            log "Telegram validation succeeded"
            return 0
        else
            echo -e "${RED}Telegram Bot 验证失败：无效的 Token${NC}"
            log "ERROR: Telegram validation failed: $response"
            return 1
        fi
    else
        echo -e "${YELLOW}Telegram 配置不完整或未启用${NC}"
        log "Telegram config incomplete or disabled"
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
            url="${webhook}&timestamp=${timestamp}&sign=${sign}"
        fi

        # Send test message (includes keyword "VPS")
        response=$(curl -s -m 5 -X POST "$url" \
            -H "Content-Type: application/json" \
            -d '{"msgtype": "text", "text": {"content": "VPS 测试消息"}}')

        errcode=$(echo "$response" | grep -o '"errcode":[0-9]*' | cut -d: -f2)
        errmsg=$(echo "$response" | grep -o '"errmsg":"[^"]*"' | cut -d: -f2- | tr -d '"')

        if [[ "$errcode" == "0" ]]; then
            echo -e "${GREEN}DingTalk Webhook 验证成功${NC}"
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

# Validate input
validate_input() {
    local type="$1"
    local value="$2"
    case $type in
        yes_no)
            if [[ "$value" != "1" && "$value" != "0" ]]; then
                echo -e "${RED}错误：请输入 1（是）或 0（否）${NC}"
                return 1
            fi
            ;;
        number)
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}错误：请输入有效数字${NC}"
                return 1
            fi
            ;;
        chat_ids)
            for id in ${value//,/ }; do
                if ! [[ "$id" =~ ^-?[0-9]+$ ]]; then
                    echo -e "${RED}错误：Chat IDs 必须为数字（群组以 - 开头）${NC}"
                    return 1
                fi
            done
            ;;
        parse_mode)
            if [[ "$value" != "plain" && "$value" != "html" ]]; then
                echo -e "${RED}错误：Parse mode 必须为 plain 或 html${NC}"
                return 1
            fi
            ;;
    esac
    return 0
}

# Send Telegram notification
send_telegram() {
    local message="$1"
    if [[ "$ENABLE_TG_NOTIFY" -eq 1 && -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_IDS" ]]; then
        # Apply emoji if enabled
        local final_message="$message"
        if [[ "$TG_EMOJI" -eq 1 ]]; then
            final_message=$(echo "$message" | sed 's/\[成功\]/✅/g; s/\[登录\]/🔐/g; s/\[警告\]/⚠️/g; s/\[网络\]/🌐/g')
        fi
        if [[ "$DEBUG_TG" -eq 1 ]]; then
            log "DEBUG: Original message: $message"
            log "DEBUG: Final message: $final_message"
        fi
        for chat_id in ${TG_CHAT_IDS//,/ }; do
            local url="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"
            local curl_cmd=(curl -s -m 5 -X POST "$url" --data-urlencode "chat_id=${chat_id}" --data-urlencode "text=$final_message")
            if [[ "$TG_PARSE_MODE" == "html" ]]; then
                curl_cmd+=(--data-urlencode "parse_mode=HTML")
            fi
            local response=$("${curl_cmd[@]}")
            local is_ok=$(echo "$response" | grep -o '"ok":true')
            local message_id=$(echo "$response" | grep -o '"message_id":[0-9]*' | cut -d: -f2)
            local error_desc=$(echo "$response" | grep -o '"description":"[^"]*"' | cut -d: -f2- | tr -d '"')
            if [[ -n "$is_ok" && -n "$message_id" ]]; then
                log "Telegram notification sent to $chat_id (message_id: $message_id): $final_message"
            else
                log "ERROR: Failed to send Telegram message to $chat_id: $response (Description: $error_desc)"
            fi
        done
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
                url="${webhook}&timestamp=${timestamp}&sign=${sign}"
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

    # Only send alert if ALERT_INTERVAL hours have passed
    if [[ $((current_time - last_alert)) -lt $((ALERT_INTERVAL*3600)) ]]; then
        return
    fi

    # Memory usage
    if [[ "$ENABLE_MEM_MONITOR" -eq 1 ]]; then
        local mem_info=$(free | grep Mem)
        local total=$(echo "$mem_info" | awk '{print $2}')
        local used=$(echo "$mem_info" | awk '{print $3}')
        local usage=$((100 * used / total))
        if [[ $usage -ge $MEM_THRESHOLD ]]; then
            message+="[警告] 内存使用率: ${usage}% 超过阈值 ${MEM_THRESHOLD}%\n"
        fi
    fi

    # CPU usage
    if [[ "$ENABLE_CPU_MONITOR" -eq 1 ]]; then
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
        local usage=$(printf "%.0f" "$cpu_usage")
        if [[ $usage -ge $CPU_THRESHOLD ]]; then
            message+="[警告] CPU 使用率: ${usage}% 超过阈值 ${CPU_THRESHOLD}%\n"
        fi
    fi

    # Disk usage
    if [[ "$ENABLE_DISK_MONITOR" -eq 1 ]]; then
        local disk_usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
        if [[ $disk_usage -ge $DISK_THRESHOLD ]]; then
            message+="[警告] 磁盘使用率: ${disk_usage}% 超过阈值 ${DISK_THRESHOLD}%\n"
        fi
    fi

    if [[ -n "$message" ]]; then
        message="[警告] 资源警报\n$message时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
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
            local message="[网络] IP 变动\n旧 IP:\n$old_ip\n新 IP:\n$current_ip\n时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
            send_telegram "$message"
            send_dingtalk "$message"
            echo "$current_ip" > "$ip_file"
            log "IP changed: $current_ip"
        fi
    fi
}

# Monitor network connectivity
monitor_network() {
    if [[ "$ENABLE_NETWORK_MONITOR" -eq 1 ]]; then
        local ping_result=$(ping -c 3 -W 2 8.8.8.8 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            local message="[网络] 网络连接失败\n目标: 8.8.8.8\n时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
            send_telegram "$message"
            send_dingtalk "$message"
            log "Network connectivity failed: $ping_result"
        fi
    fi
}

# Send boot notification
send_boot_notification() {
    local hostname=$(hostname)
    local ip_info=$(get_ip)
    local message="[成功] VPS 已上线\n备注: $REMARK\n主机名: $hostname\n公网IP:\n$ip_info\n时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
    send_telegram "$message"
    send_dingtalk "$message"
    log "Boot notification sent"
}

# Send SSH login notification
send_ssh_notification() {
    local user="$1"
    local ip="$2"
    local message="[登录] SSH 登录\n用户: $user\n来源 IP: $ip\n时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
    send_telegram "$message"
    send_dingtalk "$message"
    log "SSH login notification sent: $user from $ip"
}

# Install dependencies
install_dependencies() {
    local packages="curl grep gawk systemd coreutils openssl ntpdate"
    if ! command -v apt >/dev/null 2>&1; then
        echo -e "${RED}仅支持基于 Debian/Ubuntu 的系统${NC}"
        log "ERROR: Unsupported system, apt not found"
        exit 1
    fi
    apt update
    apt install -y $packages
    log "Dependencies installed: $packages"
}

# Guided configuration
guided_config() {
    echo -e "${BLUE}开始配置 VPS Notify...${NC}"
    # Telegram
    while true; do
        read -p "启用 Telegram 通知？(1=是, 0=否): " ENABLE_TG_NOTIFY
        validate_input yes_no "$ENABLE_TG_NOTIFY" && break
    done
    if [[ "$ENABLE_TG_NOTIFY" -eq 1 ]]; then
        local max_attempts=5
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            read -p "请输入 Telegram Bot Token: " TG_BOT_TOKEN
            if [[ -n "$TG_BOT_TOKEN" ]]; then
                if validate_telegram; then
                    break
                else
                    ((attempt++))
                    if [[ $attempt -le $max_attempts ]]; then
                        echo -e "${YELLOW}请重试（剩余 $((max_attempts - attempt + 1)) 次）${NC}"
                    else
                        echo -e "${RED}达到最大尝试次数，跳过 Telegram 配置${NC}"
                        ENABLE_TG_NOTIFY=0
                        TG_BOT_TOKEN=""
                        break
                    fi
                fi
            else
                echo -e "${RED}错误：Token 不能为空${NC}"
            fi
        done
        if [[ "$ENABLE_TG_NOTIFY" -eq 1 ]]; then
            while true; do
                read -p "请输入 Telegram Chat IDs (逗号分隔): " TG_CHAT_IDS
                if validate_input chat_ids "$TG_CHAT_IDS"; then
                    # Test Chat IDs by sending a message
                    local test_message="VPS 测试消息"
                    local valid_ids=""
                    for chat_id in ${TG_CHAT_IDS//,/ }; do
                        local response=$(curl -s -m 5 -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
                            --data-urlencode "chat_id=${chat_id}" \
                            --data-urlencode "text=${test_message}")
                        if echo "$response" | grep -q '"ok":true'; then
                            valid_ids+="$chat_id,"
                        else
                            log "ERROR: Invalid Chat ID $chat_id: $response"
                            echo -e "${YELLOW}警告：Chat ID $chat_id 无效，已跳过${NC}"
                        fi
                    done
                    if [[ -n "$valid_ids" ]]; then
                        TG_CHAT_IDS="${valid_ids%,}"
                        break
                    else
                        echo -e "${RED}错误：所有 Chat IDs 均无效，请重新输入${NC}"
                    fi
                fi
            done
            while true; do
                read -p "启用 Telegram 调试模式？(1=是, 0=否): " DEBUG_TG
                validate_input yes_no "$DEBUG_TG" && break
            done
            while true; do
                read -p "启用 Telegram emoji？(1=是, 0=否): " TG_EMOJI
                validate_input yes_no "$TG_EMOJI" && break
            done
            while true; do
                read -p "Telegram 消息格式 (plain=纯文本, html=HTML): " TG_PARSE_MODE
                validate_input parse_mode "$TG_PARSE_MODE" && break
            done
        else
            TG_BOT_TOKEN=""
            TG_CHAT_IDS=""
            DEBUG_TG=0
            TG_EMOJI=1
            TG_PARSE_MODE="plain"
        fi
    else
        TG_BOT_TOKEN=""
        TG_CHAT_IDS=""
        DEBUG_TG=0
        TG_EMOJI=1
        TG_PARSE_MODE="plain"
    fi

    # DingTalk
    while true; do
        read -p "启用 DingTalk 通知？(1=是, 0=否): " ENABLE_DINGTALK_NOTIFY
        validate_input yes_no "$ENABLE_DINGTALK_NOTIFY" && break
    done
    if [[ "$ENABLE_DINGTALK_NOTIFY" -eq 1 ]]; then
        while true; do
            read -p "请输入 DingTalk Webhook: " DINGTALK_WEBHOOK
            if [[ -n "$DINGTALK_WEBHOOK" ]]; then
                read -p "请输入 DingTalk Secret (留空禁用加签): " DINGTALK_SECRET
                if validate_dingtalk "$DINGTALK_WEBHOOK" "$DINGTALK_SECRET"; then
                    break
                else
                    echo -e "${YELLOW}请重试${NC}"
                fi
            else
                echo -e "${RED}错误：Webhook 不能为空${NC}"
            fi
        done
    else
        DINGTALK_WEBHOOK=""
        DINGTALK_SECRET=""
    fi

    # Monitoring
    while true; do
        read -p "启用 IP 变动通知？(1=是, 0=否): " ENABLE_IP_CHANGE_NOTIFY
        validate_input yes_no "$ENABLE_IP_CHANGE_NOTIFY" && break
    done
    while true; do
        read -p "启用内存监控？(1=是, 0=否): " ENABLE_MEM_MONITOR
        validate_input yes_no "$ENABLE_MEM_MONITOR" && break
    done
    if [[ "$ENABLE_MEM_MONITOR" -eq 1 ]]; then
        while true; do
            read -p "内存使用率阈值 (%): " MEM_THRESHOLD
            validate_input number "$MEM_THRESHOLD" && [[ $MEM_THRESHOLD -le 100 ]] && break
        done
    fi
    while true; do
        read -p "启用 CPU 监控？(1=是, 0=否): " ENABLE_CPU_MONITOR
        validate_input yes_no "$ENABLE_CPU_MONITOR" && break
    done
    if [[ "$ENABLE_CPU_MONITOR" -eq 1 ]]; then
        while true; do
            read -p "CPU 使用率阈值 (%): " CPU_THRESHOLD
            validate_input number "$CPU_THRESHOLD" && [[ $CPU_THRESHOLD -le 100 ]] && break
        done
    fi
    while true; do
        read -p "启用磁盘监控？(1=是, 0=否): " ENABLE_DISK_MONITOR
        validate_input yes_no "$ENABLE_DISK_MONITOR" && break
    done
    if [[ "$ENABLE_DISK_MONITOR" -eq 1 ]]; then
        while true; do
            read -p "磁盘使用率阈值 (%): " DISK_THRESHOLD
            validate_input number "$DISK_THRESHOLD" && [[ $DISK_THRESHOLD -le 100 ]] && break
        done
    fi
    while true; do
        read -p "启用网络连接监控？(1=是, 0=否): " ENABLE_NETWORK_MONITOR
        validate_input yes_no "$ENABLE_NETWORK_MONITOR" && break
    done
    while true; do
        read -p "资源警报间隔 (小时): " ALERT_INTERVAL
        validate_input number "$ALERT_INTERVAL" && break
    done
    read -p "请输入备注（如香港1号机）: " REMARK
    save_config
}

# Install script
install() {
    # Backup existing config
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
        log "Configuration backed up to ${CONFIG_FILE}.bak"
    fi
    install_dependencies
    check_time_sync
    guided_config
    echo -e "${BLUE}安装系统服务...${NC}"
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
    log "Installation completed"
    echo - Gabriel@12345 "${GREEN}安装完成！${NC}"
}

# Uninstall script
uninstall() {
    echo -e "${BLUE}开始卸载 VPS Notify...${NC}"
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
    guided_config
}

# Test notifications
test_notifications() {
    load_config
    while true; do
        echo -e "\n${YELLOW}=== 测试通知 ===${NC}"
        echo -e "${GREEN}1.${NC} 测试开机通知"
        echo -e "${GREEN}2.${NC} 测试 SSH 登录通知"
        echo -e "${GREEN}3.${NC} 测试资源警报"
        echo -e "${GREEN}4.${NC} 测试 IP 变动通知"
        echo -e "${GREEN}5.${NC} 测试网络连接通知"
        echo -e "${GREEN}0.${NC} 返回主菜单"
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
                local message="[警告] 测试资源警报\n内存使用率: 85%\nCPU 使用率: 90%\n磁盘使用率: 95%\n时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
                send_telegram "$message"
                send_dingtalk "$message"
                echo -e "${GREEN}资源警报已发送${NC}"
                ;;
            4)
                local message="[网络] 测试 IP 变动\n旧 IP:\nIPv4: 192.168.1.1\n新 IP:\n$(get_ip)\n时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
                send_telegram "$message"
                send_dingtalk "$message"
                echo -e "${GREEN}IP 变动通知已发送${NC}"
                ;;
            5)
                local message="[网络] 测试网络连接失败\n目标: 8.8.8.8\n时间: $(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')"
                send_telegram "$message"
                send_dingtalk "$message"
                echo -e "${GREEN}网络连接通知已发送${NC}"
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
    echo -e "\n${YELLOW}=== 系统状态 ===${NC}"
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
    echo -e "\n${BLUE}最近日志:${NC}"
    tail -n 5 "$LOG_FILE"
}

# Main menu
main_menu() {
    load_config
    while true; do
        # Check installation status
        local install_status="未安装"
        if [[ -f /etc/systemd/system/vps_notify.service && -f /etc/cron.d/vps_notify ]]; then
            install_status="已安装"
        fi

        # Mask sensitive info
        local tg_token_display="未设置"
        if [[ -n "$TG_BOT_TOKEN" ]]; then
            tg_token_display="${TG_BOT_TOKEN:0:10}****"
        fi
        local dt_webhook_display="未设置"
        if [[ -n "$DINGTALK_WEBHOOK" ]]; then
            dt_webhook_display=$(echo "$DINGTALK_WEBHOOK" | sed 's/\(access_token=\).*/\1[hidden]/')
        fi
        local dt_secret_display="未设置"
        if [[ -n "$DINGTALK_SECRET" ]]; then
            dt_secret_display="${DINGTALK_SECRET:0:6}****"
        fi

        # Display menu
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo -e "${GREEN}║       VPS 通知系統 (高級版)       ║${NC}"
        echo -e "${GREEN}║       Version: 3.0.7              ║${NC}"
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo -e "${GREEN}● 通知系统${install_status}${NC}\n"
        echo -e "当前配置:"
        echo -e "Telegram Bot Token: $tg_token_display"
        echo -e "Telegram 通知: ${ENABLE_TG_NOTIFY:-0} (1=Y, 0=N)"
        echo -e "Telegram Chat IDs: ${TG_CHAT_IDS:-未设置}"
        echo -e "Telegram 调试模式: ${DEBUG_TG:-0} (1=Y, 0=N)"
        echo -e "Telegram Emoji: ${TG_EMOJI:-1} (1=Y, 0=N)"
        echo -e "Telegram 消息格式: ${TG_PARSE_MODE:-plain}"
        echo -e "DingTalk Webhook: $dt_webhook_display"
        echo -e "DingTalk 通知: ${ENABLE_DINGTALK_NOTIFY:-0} (1=Y, 0=N)"
        echo -e "DingTalk Secret: $dt_secret_display"
        echo -e "备注: ${REMARK:-未设置}"
        echo -e "内存监控: ${ENABLE_MEM_MONITOR:-1} (阈值: ${MEM_THRESHOLD:-80}%)"
        echo -e "CPU监控: ${ENABLE_CPU_MONITOR:-1} (阈值: ${CPU_THRESHOLD:-80}%)"
        echo -e "磁盘监控: ${ENABLE_DISK_MONITOR:-1} (阈值: ${DISK_THRESHOLD:-80}%)"
        echo -e "网络监控: ${ENABLE_NETWORK_MONITOR:-1} (1=Y, 0=N)"
        echo -e "警报间隔: ${ALERT_INTERVAL:-6} 小时"
        echo -e "IP变动通知: ${ENABLE_IP_CHANGE_NOTIFY:-1} (1=Y, 0=N)"
        echo -e "\n${YELLOW}请选择操作:${NC}"
        echo -e "${GREEN}1.${NC} 安装/重新安装"
        echo -e "${GREEN}2.${NC} 配置设置"
        echo -e "${GREEN}3.${NC} 测试通知"
        echo -e "${GREEN}4.${NC} 检查系统状态"
        echo -e "${GREEN}5.${NC} 卸载"
        echo -e "${GREEN}6.${NC} 更新脚本"
        echo -e "${GREEN}0.${NC} 退出"
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
        load_config
        install
        ;;
    uninstall)
        load_config
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
        monitor_network
        ;;
    menu|*)
        main_menu
        ;;
esac
