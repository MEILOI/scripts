#!/bin/bash
# VPS Notification Script for Alpine Linux (tgvsdd3-alpine.sh)
# Version: 3.0.4

# Constants
SCRIPT_VERSION="3.0.4"
CONFIG_FILE="/etc/vps_notify.conf"
LOG_FILE="/var/log/vps_notify.log"
REMARK="未設置"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    # Rotate log if size exceeds 1MB
    if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE")" -gt 1048576 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
    fi
}

# Load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# Validate Telegram configuration
validate_telegram() {
    local token="$1" chat_ids="$2"
    if [ -z "$token" ] || [ -z "$chat_ids" ]; then
        echo -e "${RED}錯誤：Telegram Token 或 Chat ID 為空${NC}"
        log "ERROR: Telegram Token or Chat ID empty"
        return 1
    fi
    response=$(curl -s -m 10 "https://api.telegram.org/bot$token/getMe")
    if ! echo "$response" | grep -q '"ok":true'; then
        echo -e "${RED}錯誤：無效的 Telegram Token${NC}"
        log "ERROR: Invalid Telegram Token: $response"
        return 1
    fi
    log "Telegram validation successful"
    return 0
}

# Validate DingTalk configuration
validate_dingtalk() {
    local token="$1"
    if [ -z "$token",last_response); then
        echo -e "${RED}錯誤：釘釘 Token 為空${NC}"
        log "ERROR: DingTalk Token empty"
        return 1
    fi
    response=$(curl -s -m 10 -X POST "${token}" \
        -H 'Content-Type: application/json' \
        -d '{"msgtype":"text","text":{"content":"Validation test"}}')
    if echo "$response" | grep -q '"errcode":0'; then
        log "DingTalk validation successful"
        return 0
    else
        echo -e "${RED}錯誤：無效的釘釘 Token${NC}"
        log "ERROR: Invalid DingTalk Token: $response"
        return 1
    fi
}

# Send notification
send_notification() {
    local message="$1"
    local timestamp sign
    # Telegram
    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_IDS" ]; then
        IFS=',' read -ra CHAT_IDS <<< "$TELEGRAM_CHAT_IDS"
        for chat_id in "${CHAT_IDS[@]}"; do
            log "Sending Telegram notification to $chat_id with message: $message"
            response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
                -d chat_id="$chat_id" \
                -d text=$"$message" \
                -m 10)
            if echo "$response" | grep -q '"ok":true'; then
                log "Telegram notification sent to $chat_id"
            else
                log "ERROR: Telegram notification failed to $chat_id: $response"
            fi
        done
    fi
    # DingTalk
    if [ -n "$DINGTALK_TOKEN" ]; then
        timestamp=$(date +%s%3N)
        if [ -n "$DINGTALK_SECRET" ]; then
            sign=$(printf "%s\n%s" "$timestamp" "$DINGTALK_SECRET" | openssl dgst -sha256 -hmac "$DINGTALK_SECRET" -binary | base64)
            sign=$(echo -n "$sign" | sed 's/+/%2B/g;s/=/%3D/g;s/&/%26/g')
        fi
        for attempt in {1..3}; do
            response=$(curl -s -m 10 "${DINGTALK_TOKEN}&timestamp=$timestamp&sign=$sign" \
                -H 'Content-Type: application/json' \
                -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$message\"}}")
            if echo "$response" | grep -q '"errcode":0'; then
                log "DingTalk notification sent"
                break
            else
                log "ERROR: DingTalk notification attempt $attempt failed: $response"
                sleep 1
            fi
        done
    fi
}

# Resource monitor
monitor_resources() {
    load_config
    local memory_usage cpu_usage hostname time message
    memory_usage=$(free | grep Mem | gawk '{print int($3/$2 * 100)}')
    cpu_usage=$(vmstat 1 2 | tail -1 | gawk '{print int(100 - $15)}')
    [ "$memory_usage" -gt "${MEMORY_THRESHOLD:-90}" ] || [ "$cpu_usage" -gt "${CPU_THRESHOLD:-90}" ] || return
    hostname=$(hostname)
    time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    message="⚠️ 資源警報\n\n📝 備註: ${REMARK:-未設置}\n🖥️ 主機: $hostname\n📈 內存使用率: ${memory_usage}%\n📊 CPU 使用率: ${cpu_usage}%\n🕒 時間: $time\n\n---"
    send_notification "$message"
    log "Resource alert sent: Memory $memory_usage%, CPU $cpu_usage%"
}

# Install function
install() {
    echo -e "${YELLOW}正在安裝 VPS 通知腳本...${NC}"
    apk update >/dev/null 2>&1
    apk add bash curl gawk coreutils openssl vmstat >/dev/null 2>&1
    for cmd in bash curl gawk date openssl vmstat; do
        if ! command -v "$cmd" >/dev/null; then
            echo -e "${RED}錯誤：無法安裝 $cmd，請手動安裝${NC}"
            log "ERROR: Failed to install dependency: $cmd"
            exit 1
        fi
    done
    log "Dependencies installed successfully"

    cp "$0" /usr/local/bin/vps_notify.sh
    chmod +x /usr/local/bin/vps_notify.sh
    log "Script copied to /usr/local/bin/vps_notify.sh"

    echo -e "${YELLOW}設置 Telegram 通知${NC}"
    read -p "輸入 Telegram Bot Token（留空跳過）: " TELEGRAM_TOKEN
    if [ -n "$TELEGRAM_TOKEN" ]; then
        read -p "輸入 Telegram Chat ID（多個用逗號分隔）: " TELEGRAM_CHAT_IDS
        if validate_telegram "$TELEGRAM_TOKEN" "$TELEGRAM_CHAT_IDS"; then
            modify_config "TELEGRAM_TOKEN" "$TELEGRAM_TOKEN"
            modify_config "TELEGRAM_CHAT_IDS" "$TELEGRAM_CHAT_IDS"
            echo -e "${GREEN}Telegram 配置保存成功${NC}"
        else
            echo -e "${RED}Telegram 配置無效，跳過${NC}"
        fi
    fi

    echo -e "${YELLOW}設置釘釘通知${NC}"
    echo -e "${YELLOW}請輸入完整的釘釘 Webhook URL（格式：https://oapi.dingtalk.com/robot/send?access_token=xxx）${NC}"
    read -p "輸入釘釘 Webhook URL（留空跳過）: " DINGTALK_TOKEN
    if [ -n "$DINGTALK_TOKEN" ]; then
        read -p "輸入釘釘 Secret（留空跳過）: " DINGTALK_SECRET
        if validate_dingtalk "$DINGTALK_TOKEN"; then
            modify_config "DINGTALK_TOKEN" "$DINGTALK_TOKEN"
            [ -n "$DINGTALK_SECRET" ] && modify_config "DINGTALK_SECRET" "$DINGTALK_SECRET"
            echo -e "${GREEN}釘釘配置保存成功${NC}"
        else
            echo -e "${RED}釘釘配置無效，跳過${NC}"
        fi
    fi

    echo -e "${YELLOW}設置資源監控閾值${NC}"
    read -p "輸入內存使用率閾值（%）[默認 90]: " MEMORY_THRESHOLD
    read -p "輸入 CPU 使用率閾值（%）[默認 90]: " CPU_THRESHOLD
    [ -n "$MEMORY_THRESHOLD" ] && modify_config "MEMORY_THRESHOLD" "$MEMORY_THRESHOLD"
    [ -n "$CPU_THRESHOLD" ] && modify_config "CPU_THRESHOLD" "$CPU_THRESHOLD"

    if command -v rc-update >/dev/null; then
        echo -e "${YELLOW}設置 openrc 服務${NC}"
        cat > /etc/init.d/vps_notify << 'EOF'
#!/sbin/openrc-run
name="vps_notify"
description="VPS Notification Service"
command="/usr/local/bin/vps_notify.sh"
command_args="monitor"
command_background="yes"
pidfile="/var/run/vps_notify.pid"
EOF
        chmod +x /etc/init.d/vps_notify
        rc-update add vps_notify default
        rc-service vps_notify start
        log "Openrc service installed and started"
    fi

    echo -e "${GREEN}安裝完成！使用 ./tgvsdd3-alpine.sh 管理腳本${NC}"
    log "Installation completed"
}

# [其他函數和主邏輯與 v3.0.3 相同，省略]
