#!/bin/bash
# VPS Notification Script for Alpine Linux (tgvsdd3-alpine.sh)
# Version: 3.0.7

# Constants
SCRIPT_VERSION="3.0.7"
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
    local token="$1" keyword="${2:-Validation}"
    if [ -z "$token" ]; then
        echo -e "${RED}錯誤：釘釘 Token 為空${NC}"
        log "ERROR: DingTalk Token empty"
        return 1
    fi
    response=$(curl -s -m 10 -X POST "${token}" \
        -H 'Content-Type: application/json' \
        -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"${keyword} test\"}}")
    if echo "$response" | grep -q '"errcode":0'; then
        log "DingTalk validation successful"
        return 0
    else
        echo -e "${RED}錯誤：無效的釘釘 Token，請檢查 Webhook URL 或關鍵詞${NC}"
        log "ERROR: Invalid DingTalk Token: $response"
        return 1
    fi
}

# Modify configuration
modify_config() {
    local key="$1" value="$2" file="$CONFIG_FILE"
    mkdir -p "$(dirname "$file")"
    if [ -f "$file" ]; then
        if grep -q "^$key=" "$file"; then
            sed -i "s|^$key=.*|$key=$value|" "$file"
        else
            echo "$key=$value" >> "$file"
        fi
    else
        echo "$key=$value" > "$file"
    fi
    log "Config updated: $key=$value"
}

# Send notification
send_notification() {
    local message="$1"
    local timestamp sign text
    # Telegram
    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_IDS" ]; then
        IFS=',' read -ra CHAT_IDS <<< "$TELEGRAM_CHAT_IDS"
        for chat_id in "${CHAT_IDS[@]}"; do
            text=$(printf '%b' "$message")
            log "Sending Telegram notification to $chat_id with text: $text"
            response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
                -d chat_id="$chat_id" \
                -d text="$text" \
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
                -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"${DINGTALK_KEYWORD:-Notification} $message\"}}")
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

# Boot notification
notify_boot() {
    load_config
    local hostname ip time message
    hostname=$(hostname)
    ip=$(curl -s ifconfig.me)
    time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    message="🖥️ 開機通知\n\n📝 備註: ${REMARK:-未設置}\n🖥️ 主機: $hostname\n🌐 IP: $ip\n🕒 時間: $time\n\n---"
    send_notification "$message"
    log "Boot notification sent"
}

# SSH notification
notify_ssh() {
    load_config
    local log_file
    for f in /var/log/auth.log /var/log/secure /var/log/messages; do
        [ -f "$f" ] && log_file="$f" && break
    done
    if [ -z "$log_file" ]; then
        log "ERROR: No SSH log file found"
        return 1
    fi
    if tail -n 1 "$log_file" | grep -q "Accepted"; then
        local user ip hostname time message
        user=$(tail -n 1 "$log_file" | grep "Accepted" | gawk '{print $9}')
        ip=$(tail -n 1 "$log_file" | grep "Accepted" | gawk '{print $11}')
        hostname=$(hostname)
        time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
        message="🔐 SSH 登錄通知\n\n📝 備註: ${REMARK:-未設置}\n👤 用戶: $user\n🖥️ 主機: $hostname\n🌐 來源 IP: $ip\n🕒 時間: $time\n\n---"
        send_notification "$message"
        log "SSH login notification sent: $user from $ip"
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

# IP monitor
monitor_ip() {
    load_config
    local current_ip previous_ip hostname time message ip_file="/var/log/vps_notify_ip.log"
    current_ip=$(curl -s ifconfig.me)
    [ -f "$ip_file" ] && previous_ip=$(cat "$ip_file")
    [ "$current_ip" = "$previous_ip" ] && return
    echo "$current_ip" > "$ip_file"
    hostname=$(hostname)
    time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    message="🌐 IP 變動通知\n\n📝 備註: ${REMARK:-未設置}\n🖥️ 主機: $hostname\n🔙 原 IP: ${previous_ip:-未知}\n➡️ 新 IP: $current_ip\n🕒 時間: $time\n\n---"
    send_notification "$message"
    log "IP change notification sent: $previous_ip to $current_ip"
}

# Install function
install() {
    echo -e "${YELLOW}正在安裝 VPS 通知腳本...${NC}"
    apk update >/dev/null 2>&1
    apk add bash curl gawk coreutils openssl procps >/dev/null 2>&1
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
        echo -e "${YELLOW}請在釘釘機器人設置中查看關鍵詞（例如‘警報’），若無關鍵詞則留空${NC}"
        read -p "輸入釘釘關鍵詞（留空跳過）: " DINGTALK_KEYWORD
        read -p "輸入釘釘 Secret（留空跳過）: " DINGTALK_SECRET
        if validate_dingtalk "$DINGTALK_TOKEN" "$DINGTALK_KEYWORD"; then
            modify_config "DINGTALK_TOKEN" "$DINGTALK_TOKEN"
            [ -n "$DINGTALK_KEYWORD" ] && modify_config "DINGTALK_KEYWORD" "$DINGTALK_KEYWORD"
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

# Uninstall function
uninstall() {
    echo -e "${YELLOW}正在卸載 VPS 通知腳本...${NC}"
    if command -v rc-service >/dev/null; then
        rc-service vps_notify stop 2>/dev/null
        rc-update del vps_notify default 2>/dev/null
        rm -f /etc/init.d/vps_notify
        log "Openrc service removed"
    fi
    rm -f /usr/local/bin/vps_notify.sh
    rm -f "$CONFIG_FILE"
    rm -f /var/log/vps_notify_ip.log
    echo -e "${GREEN}卸載完成！日誌文件未刪除：$LOG_FILE${NC}"
    log "Uninstallation completed"
}

# Menu
menu() {
    while true; do
        echo -e "${YELLOW}VPS 通知腳本 (v$SCRIPT_VERSION)${NC}"
        echo "1) 安裝"
        echo "2) 卸載"
        echo "3) 配置 Telegram"
        echo "4) 配置釘釘"
        echo "5) 測試通知"
        echo "6) 查看日誌"
        echo "7) 退出"
        read -p "請選擇操作 [1-7] 或關鍵詞（install, uninstall, telegram, dingtalk, test, log, exit）: " choice
        case "$choice" in
            1|"install") install ;;
            2|"uninstall") uninstall ;;
            3|"telegram")
                echo -e "${YELLOW}設置 Telegram 通知${NC}"
                read -p "輸入 Telegram Bot Token（必填）: " TELEGRAM_TOKEN
                read -p "輸入 Telegram Chat ID（多個用逗號分隔）: " TELEGRAM_CHAT_IDS
                if validate_telegram "$TELEGRAM_TOKEN" "$TELEGRAM_CHAT_IDS"; then
                    modify_config "TELEGRAM_TOKEN" "$TELEGRAM_TOKEN"
                    modify_config "TELEGRAM_CHAT_IDS" "$TELEGRAM_CHAT_IDS"
                    echo -e "${GREEN}Telegram 配置保存成功${NC}"
                else
                    echo -e "${RED}Telegram 配置無效${NC}"
                fi
                ;;
            4|"dingtalk")
                echo -e "${YELLOW}設置釘釘通知${NC}"
                echo -e "${YELLOW}請輸入完整的釘釘 Webhook URL（格式：https://oapi.dingtalk.com/robot/send?access_token=xxx）${NC}"
                read -p "輸入釘釘 Webhook URL（必填）: " DINGTALK_TOKEN
                echo -e "${YELLOW}請在釘釘機器人設置中查看關鍵詞（例如‘警報’），若無關鍵詞則留空${NC}"
                read -p "輸入釘釘關鍵詞（留空跳過）: " DINGTALK_KEYWORD
                read -p "輸入釘釘 Secret（留空跳過）: " DINGTALK_SECRET
                if validate_dingtalk "$DINGTALK_TOKEN" "$DINGTALK_KEYWORD"; then
                    modify_config "DINGTALK_TOKEN" "$DINGTALK_TOKEN"
                    [ -n "$DINGTALK_KEYWORD" ] && modify_config "DINGTALK_KEYWORD" "$DINGTALK_KEYWORD"
                    [ -n "$DINGTALK_SECRET" ] && modify_config "DINGTALK_SECRET" "$DINGTALK_SECRET"
                    echo -e "${GREEN}釘釘配置保存成功${NC}"
                else
                    echo -e "${RED}釘釘配置無效${NC}"
                fi
                ;;
            5|"test")
                echo -e "${YELLOW}測試通知${NC}"
                notify_boot
                notify_ssh
                monitor_resources
                monitor_ip
                echo -e "${GREEN}測試通知已發送，請檢查 Telegram 或不需要deps釘釘${NC}"
                ;;
            6|"log")
                echo -e "${YELLOW}查看日誌${NC}"
                if [ -f "$LOG_FILE" ]; then
                    cat "$LOG_FILE"
                else
                    echo -e "${RED}日誌文件不存在：$LOG_FILE${NC}"
                fi
                ;;
            7|"exit") exit 0 ;;
            *) echo -e "${RED}無效選項，請選擇 [1-7] 或關鍵詞${NC}" ;;
        esac
    done
}

# Main logic
case "$1" in
    install) install ;;
    uninstall) uninstall ;;
    boot) notify_boot ;;
    ssh) notify_ssh ;;
    monitor) monitor_resources ;;
    ip) monitor_ip ;;
    menu|*) menu ;;
esac
