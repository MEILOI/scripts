#!/bin/bash
# VPS Notify Script for Alpine Linux (tgvsdd3-alpine.sh) v3.0.5
# Monitors IP changes, SSH logins, and system resources, sends notifications via Telegram and DingTalk
# Simplified for minimal dependencies and core functionality

# Constants
SCRIPT_VERSION="3.0.5"
SCRIPT_PATH="/usr/local/bin/vps_notify.sh"
CONFIG_FILE="/etc/vps_notify.conf"
LOG_FILE="/var/log/vps_notify.log"
SERVICE_PATH="/etc/init.d/vps_notify"
BACKUP_CONFIG="/etc/vps_notify.conf.bak"
CURRENT_IP_FILE="/var/run/vps_notify_current_ip"
REMARK="VPS監控"

# Logging function
log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    # Rotate log if size exceeds 1MB
    if [ -f "$LOG_FILE" ]; then
        local size
        size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 1048576 ] 2>/dev/null; then
            mv "$LOG_FILE" "${LOG_FILE}.old"
            touch "$LOG_FILE"
            chmod 644 "$LOG_FILE"
        fi
    fi
}

# Check dependencies
check_dependencies() {
    local deps="curl gawk coreutils openssl"
    echo "正在更新軟件源..."
    apk update >/dev/null 2>&1 || {
        echo "錯誤：無法更新軟件源，請檢查網絡或添加 community 倉庫"
        echo "嘗試運行：echo 'http://dl-cdn.alpinelinux.org/alpine/v$(cat /etc/alpine-release | cut -d. -f1,2)/community' >> /etc/apk/repositories"
        log "ERROR: Failed to update apk repositories"
        exit 1
    }
    echo "正在安裝依賴：$deps"
    apk add $deps >/dev/null 2>&1 || {
        echo "錯誤：無法安裝依賴，請手動安裝：apk add $deps"
        log "ERROR: Failed to install dependencies: $deps"
        exit 1
    }
    for cmd in $deps; do
        if ! command -v "${cmd%% *}" >/dev/null; then
            echo "錯誤：無法安裝 $cmd，請手動安裝"
            log "ERROR: Failed to install dependency: $cmd"
            exit 1
        fi
    done
    log "Dependencies installed: $deps"
}

# Send notification
send_notification() {
    local message="$1"
    local timestamp sign encoded_sign
    # Telegram
    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_IDS" ]; then
        IFS=',' read -ra CHAT_IDS <<< "$TELEGRAM_CHAT_IDS"
        for chat_id in "${CHAT_IDS[@]}"; do
            response=$(curl -s -w "%{http_code}" -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
                -d chat_id="$chat_id" \
                -d text="$message" \
                -m 10 2>&1)
            http_code=${response##*[!0-9]}
            response=${response%[0-9]*}
            if [ "$http_code" -eq 200 ] && echo "$response" | grep -q '"ok":true'; then
                log "Telegram notification sent to $chat_id"
            else
                log "ERROR: Telegram notification failed to $chat_id (HTTP $http_code): $response"
                echo "Telegram 通知失敗，請檢查日誌：$LOG_FILE"
            fi
        done
    else
        log "WARNING: Telegram notification skipped (missing TOKEN or CHAT_IDS)"
    fi
    # DingTalk
    if [ -n "$DINGTALK_TOKEN" ]; then
        timestamp=$(date +%s%3N)
        if [ -n "$DINGTALK_SECRET" ]; then
            sign=$(echo -n "$timestamp\n$DINGTALK_SECRET" | openssl dgst -sha256 -hmac "$DINGTALK_SECRET" -binary | base64)
            encoded_sign=$(printf %s "$sign" | xxd -p -c 256 | tr -d '\n' | xxd -r -p | base64 -w 0)
            encoded_sign=$(printf %s "$encoded_sign" | sed 's/+/%2B/g; s/=/%3D/g; s/&/%26/g')
        else
            encoded_sign=""
        fi
        url="$DINGTALK_TOKEN"
        [ -n "$encoded_sign" ] && url="${url}×tamp=$timestamp&sign=$encoded_sign"
        # Include DingTalk keyword if set
        local dingtalk_message="$message"
        [ -n "$DINGTALK_KEYWORD" ] && dingtalk_message="$DINGTALK_KEYWORD\n$message"
        for attempt in {1..3}; do
            response=$(curl -s -w "%{http_code}" -m 10 "$url" \
                -H 'Content-Type: application/json' \
                -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$dingtalk_message\"}}" 2>&1)
            http_code=${response##*[!0-9]}
            response=${response%[0-9]*}
            if [ "$http_code" -eq 200 ] && echo "$response" | grep -q '"errcode":0'; then
                log "DingTalk notification sent (attempt $attempt)"
                break
            else
                log "ERROR: DingTalk notification attempt $attempt failed (HTTP $http_code): $response"
                if [ $attempt -eq 3 ]; then
                    echo "釘釘通知失敗，請檢查日誌：$LOG_FILE"
                fi
                sleep 1
            fi
        done
    else
        log "WARNING: DingTalk notification skipped (missing TOKEN)"
    fi
}

# Validate Telegram configuration
validate_telegram() {
    local token="$1" chat_ids="$2"
    if [ -z "$token" ] || [ -z "$chat_ids" ]; then
        echo "錯誤：Telegram Token 或 Chat ID 為空"
        log "ERROR: Telegram Token or Chat ID empty"
        return 1
    fi
    response=$(curl -s -m 10 "https://api.telegram.org/bot$token/getMe" 2>&1)
    if ! echo "$response" | grep -q '"ok":true'; then
        echo "錯誤：無效的 Telegram Token"
        log "ERROR: Invalid Telegram Token: $response"
        return 1
    fi
    log "Telegram validation successful"
    return 0
}

# Validate DingTalk configuration
validate_dingtalk() {
    local token="$1" keyword="$2"
    if [ -z "$token" ]; then
        echo "錯誤：DingTalk Webhook 為空"
        log "ERROR: DingTalk Webhook empty"
        return 1
    fi
    local test_message="測試消息"
    [ -n "$keyword" ] && test_message="$keyword\n$test_message"
    for attempt in {1..3}; do
        response=$(curl -s -w "%{http_code}" -m 10 "$token" \
            -H 'Content-Type: application/json' \
            -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$test_message\"}}" 2>&1)
        http_code=${response##*[!0-9]}
        response=${response%[0-9]*}
        if [ "$http_code" -eq 200 ] && echo "$response" | grep -q '"errcode":0'; then
            log "DingTalk validation successful"
            return 0
        else
            log "ERROR: DingTalk validation attempt $attempt failed (HTTP $http_code): $response"
            sleep 1
        fi
    done
    echo "錯誤：無效的 DingTalk Webhook 或關鍵詞不匹配，請檢查 Webhook URL 和關鍵詞設置"
    log "ERROR: DingTalk validation failed after 3 attempts"
    return 1
}

# Modify configuration
modify_config() {
    local key="$1" value="$2" file="$CONFIG_FILE"
    if [ -f "$file" ]; then
        if grep -q "^$key=" "$file"; then
            sed -i "s|^$key=.*|$key=$value|" "$file"
        else
            echo "$key=$value" >> "$file"
        fi
    else
        echo "$key=$value" > "$file"
    fi
    chmod 600 "$file"
    log "Config updated: $key=$value"
}

# Load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# Install script
install_script() {
    check_dependencies
    echo "正在安裝 VPS Notify Script..."
    # Install script
    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    # Configure Telegram
    echo "設置 Telegram 通知"
    read -p "輸入 Telegram Bot Token（留空跳過）: " TELEGRAM_TOKEN
    read -p "輸入 Telegram Chat ID（多個用逗號分隔，留空跳過）: " TELEGRAM_CHAT_IDS
    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_IDS" ]; then
        if validate_telegram "$TELEGRAM_TOKEN" "$TELEGRAM_CHAT_IDS"; then
            modify_config "TELEGRAM_TOKEN" "$TELEGRAM_TOKEN"
            modify_config "TELEGRAM_CHAT_IDS" "$TELEGRAM_CHAT_IDS"
        else
            echo "Telegram 配置無效，未保存"
        fi
    fi
    # Configure DingTalk
    echo "設置 DingTalk 通知"
    read -p "輸入 DingTalk Webhook（留空跳過）: " DINGTALK_TOKEN
    read -p "輸入 DingTalk Secret（留空跳過）: " DINGTALK_SECRET
    read -p "輸入 DingTalk 關鍵詞（留空跳過）: " DINGTALK_KEYWORD
    if [ -n "$DINGTALK_TOKEN" ]; then
        if validate_dingtalk "$DINGTALK_TOKEN" "$DINGTALK_KEYWORD"; then
            modify_config "DINGTALK_TOKEN" "$DINGTALK_TOKEN"
            [ -n "$DINGTALK_SECRET" ] && modify_config "DINGTALK_SECRET" "$DINGTALK_SECRET"
            [ -n "$DINGTALK_KEYWORD" ] && modify_config "DINGTALK_KEYWORD" "$DINGTALK_KEYWORD"
        else
            echo "DingTalk 配置驗證失敗，仍保存配置"
            modify_config "DINGTALK_TOKEN" "$DINGTALK_TOKEN"
            [ -n "$DINGTALK_SECRET" ] && modify_config "DINGTALK_SECRET" "$DINGTALK_SECRET"
            [ -n "$DINGTALK_KEYWORD" ] && modify_config "DINGTALK_KEYWORD" "$DINGTALK_KEYWORD"
        fi
    fi
    # Install OpenRC service
    cat <<EOF >/etc/init.d/vps_notify
#!/sbin/openrc-run
name="vps_notify"
description="VPS Notify Boot Service"
command="/bin/sh $SCRIPT_PATH boot"
command_background=false
depend() {
    after network-online
    need network-online
}
EOF
    chmod +x /etc/init.d/vps_notify
    rc-update add vps_notify default
    log "OpenRC service installed"
    # Setup SSH notification
    echo "設置 SSH 登錄通知"
    read -p "是否啟用 SSH 登錄通知？（y/n，默認 y）: " enable_ssh
    if [ "$enable_ssh" != "n" ]; then
        log_file="/var/log/messages"
        [ -f /var/log/auth.log ] && log_file="/var/log/auth.log"
        echo "使用日誌文件：$log_file"
        modify_config "SSH_NOTIFY" "true"
    fi
    # Setup resource monitoring
    echo "設置資源監控"
    read -p "輸入內存使用率閾值（%，默認 90）: " memory_threshold
    read -p "輸入 CPU 使用率閾值（%，默認 90）: " cpu_threshold
    modify_config "MEMORY_THRESHOLD" "${memory_threshold:-90}"
    modify_config "CPU_THRESHOLD" "${cpu_threshold:-90}"
    # Setup cron job
    crontab -l > /tmp/cron 2>/dev/null
    if ! grep -q "$SCRIPT_PATH monitor" /tmp/cron; then
        echo "*/5 * * * * $SCRIPT_PATH monitor" >> /tmp/cron
        crontab /tmp/cron
    fi
    rm -f /tmp/cron
    log "Cron job installed for resource monitoring"
    echo "安裝完成！運行 'vps_notify.sh menu' 查看選項"
    log "Installation completed"
}

# Uninstall script
uninstall_script() {
    echo "正在卸載 VPS Notify Script..."
    [ -f "$SCRIPT_PATH" ] && rm -f "$SCRIPT_PATH"
    [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE"
    [ -f "$BACKUP_CONFIG" ] && rm -f "$BACKUP_CONFIG"
    [ -f "$CURRENT_IP_FILE" ] && rm -f "$CURRENT_IP_FILE"
    [ -f "$SERVICE_PATH" ] && {
        rc-update del vps_notify default
        rm -f "$SERVICE_PATH"
    }
    crontab -l | grep -v "$SCRIPT_PATH monitor" | crontab -
    rm -f "$LOG_FILE" "${LOG_FILE}.old"
    rmdir "$(dirname "$LOG_FILE")" 2>/dev/null
    echo "卸載完成"
    log "Uninstallation completed"
    exit 0
}

# Boot notification
notify_boot() {
    load_config
    local hostname ip time message
    hostname=$(hostname)
    ip=$(curl -s ipinfo.io/ip)
    time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    message="🖥️ 開機通知\n\n📝 備註: ${REMARK:-未設置}\n🖥️ 主機: $hostname\n🌐 IP: $ip\n🕒 時間: $time"
    send_notification "$message"
    log "Boot notification sent"
}

# SSH notification
notify_ssh() {
    load_config
    local log_file="/var/log/messages"
    [ -f /var/log/auth.log ] && log_file="/var/log/auth.log"
    if tail -n 1 "$log_file" | grep -q "Accepted"; then
        local user ip hostname time message
        user=$(tail -n 1 "$log_file" | grep "Accepted" | gawk '{print $9}')
        ip=$(tail -n 1 "$log_file" | grep "Accepted" | gawk '{print $11}')
        hostname=$(hostname)
        time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
        message="🔐 SSH 登錄通知\n\n📝 備註: ${REMARK:-未設置}\n👤 用戶: $user\n🖥️ 主機: $hostname\n🌐 來源 IP: $ip\n🕒 時間: $time"
        send_notification "$message"
        log "SSH login notification sent: $user from $ip"
    fi
}

# Monitor resources
monitor_resources() {
    load_config
    local memory_usage cpu_usage hostname time message
    memory_usage=$(free | gawk '/Mem:/ {printf("%.0f", $3/$2*100)}')
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | gawk '{print $2}' | cut -d. -f1)
    if [ "$memory_usage" -gt "${MEMORY_THRESHOLD:-90}" ] || [ "$cpu_usage" -gt "${CPU_THRESHOLD:-90}" ]; then
        hostname=$(hostname)
        time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
        message="⚠️ 資源警報\n\n📝 備註: ${REMARK:-未設置}\n🖥️ 主機: $hostname\n📈 內存使用率: ${memory_usage}%\n📊 CPU 使用率: ${cpu_usage}%\n🕒 時間: $time"
        send_notification "$message"
        log "Resource alert: Memory=$memory_usage%, CPU=$cpu_usage%"
    fi
}

# Monitor IP change
monitor_ip() {
    load_config
    local current_ip previous_ip hostname time message
    current_ip=$(curl -s ipinfo.io/ip)
    if [ -f "$CURRENT_IP_FILE" ]; then
        previous_ip=$(cat "$CURRENT_IP_FILE")
    else
        previous_ip=""
    fi
    if [ "$current_ip" != "$previous_ip" ] && [ -n "$current_ip" ]; then
        hostname=$(hostname)
        time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
        message="🌐 IP 變動通知\n\n📝 備註: ${REMARK:-未設置}\n🖥️ 主機: $hostname\n🔙 原 IP: ${previous_ip:-未知}\n➡️ 新 IP: $current_ip\n🕒 時間: $time"
        send_notification "$message"
        echo "$current_ip" > "$CURRENT_IP_FILE"
        log "IP change detected: $previous_ip -> $current_ip"
    fi
}

# Test notifications
test_notification() {
    echo "選擇測試通知類型"
    echo "1. 開機通知"
    echo "2. SSH 登錄通知"
    echo "3. 資源警報"
    echo "4. IP 變動通知"
    read -p "輸入選項（1-4）: " choice
    case $choice in
        1) notify_boot ;;
        2) notify_ssh ;;
        3) monitor_resources ;;
        4) monitor_ip ;;
        *) echo "無效選項" ;;
    esac
}

# Configuration menu
config_menu() {
    echo "配置選項"
    echo "1. 修改 Telegram 配置"
    echo "2. 修改 DingTalk 配置"
    echo "3. 修改資源監控閾值"
    read -p "輸入選項（1-3）: " choice
    case $choice in
        1)
            read -p "輸入 Telegram Bot Token: " TELEGRAM_TOKEN
            read -p "輸入 Telegram Chat ID（多個用逗號分隔）: " TELEGRAM_CHAT_IDS
            if validate_telegram "$TELEGRAM_TOKEN" "$TELEGRAM_CHAT_IDS"; then
                modify_config "TELEGRAM_TOKEN" "$TELEGRAM_TOKEN"
                modify_config "TELEGRAM_CHAT_IDS" "$TELEGRAM_CHAT_IDS"
                echo "Telegram 配置已更新"
            else
                echo "Telegram 配置無效，未保存"
            fi
            ;;
        2)
            read -p "輸入 DingTalk Webhook: " DINGTALK_TOKEN
            read -p "輸入 DingTalk Secret（留空跳過）: " DINGTALK_SECRET
            read -p "輸入 DingTalk 關鍵詞（留空跳過）: " DINGTALK_KEYWORD
            if validate_dingtalk "$DINGTALK_TOKEN" "$DINGTALK_KEYWORD"; then
                modify_config "DINGTALK_TOKEN" "$DINGTALK_TOKEN"
                [ -n "$DINGTALK_SECRET" ] && modify_config "DINGTALK_SECRET" "$DINGTALK_SECRET"
                [ -n "$DINGTALK_KEYWORD" ] && modify_config "DINGTALK_KEYWORD" "$DINGTALK_KEYWORD"
                echo "DingTalk 配置已更新"
            else
                echo "DingTalk 配置驗證失敗，仍保存配置"
                modify_config "DINGTALK_TOKEN" "$DINGTALK_TOKEN"
                [ -n "$DINGTALK_SECRET" ] && modify_config "DINGTALK_SECRET" "$DINGTALK_SECRET"
                [ -n "$DINGTALK_KEYWORD" ] && modify_config "DINGTALK_KEYWORD" "$DINGTALK_KEYWORD"
            fi
            ;;
        3)
            read -p "輸入內存使用率閾值（%，默認 90）: " memory_threshold
            read -p "輸入 CPU 使用率閾值（%，默認 90）: " cpu_threshold
            modify_config "MEMORY_THRESHOLD" "${memory_threshold:-90}"
            modify_config "CPU_THRESHOLD" "${cpu_threshold:-90}"
            echo "資源監控閾值已更新"
            ;;
        *) echo "無效選項" ;;
    esac
}

# Main menu
main_menu() {
    echo "=== VPS Notify Script (Alpine) v$SCRIPT_VERSION ==="
    echo "1. 安裝/重新安裝"
    echo "2. 配置設置"
    echo "3. 測試通知"
    echo "4. 卸載"
    echo "0. 退出"
    read -p "輸入選項（0-4）: " choice
    case $choice in
        1) install_script ;;
        2) config_menu ;;
        3) test_notification ;;
        4) uninstall_script ;;
        0) exit 0 ;;
        *) echo "無效選項" ;;
    esac
}

# Main logic
case "$1" in
    install) install_script ;;
    uninstall) uninstall_script ;;
    boot|notify_boot) notify_boot ;;
    ssh|notify_ssh) notify_ssh ;;
    monitor)
        monitor_resources
        monitor_ip
        ;;
    menu|*) main_menu ;;
esac
