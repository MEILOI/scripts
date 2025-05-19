#!/bin/bash
# VPS Notification Script for Alpine Linux (tgvsdd3-alpine.sh)
# Version: 3.0.2

# [其他不變的常量、函數和邏輯省略，例如 load_config、validate_dingtalk、log 等]

# Send notification (updated for plain text with embedded newlines)
send_notification() {
    local message="$1"
    local timestamp sign
    # Telegram
    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_IDS" ]; then
        IFS=',' read -ra CHAT_IDS <<< "$TELEGRAM_CHAT_IDS"
        for chat_id in "${CHAT_IDS[@]}"; do
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
    # DingTalk (unchanged)
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

# Boot notification (updated message format)
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

# SSH notification (updated message format)
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
        message="🔐 SSH 登錄通知\n\n📝 備註: ${REMARK:-未設置}\n👤 用戶: $user\n🖥️ 主機: $hostname\n🌐 來源 IP: $ip\n🕒 時間: $time\n\n---"
        send_notification "$message"
        log "SSH login notification sent: $user from $ip"
    fi
}

# Resource monitor (updated message format)
monitor_resources() {
    load_config
    local memory_usage cpu_usage hostname time message
    memory_usage=$(free | grep Mem | gawk '{print int($3/$2 * 100)}')
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | gawk '{print int($2)}')
    [ "$memory_usage" -gt "${MEMORY_THRESHOLD:-90}" ] || [ "$cpu_usage" -gt "${CPU_THRESHOLD:-90}" ] || return
    hostname=$(hostname)
    time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    message="⚠️ 資源警報\n\n📝 備註: ${REMARK:-未設置}\n🖥️ 主機: $hostname\n📈 內存使用率: ${memory_usage}%\n📊 CPU 使用率: ${cpu_usage}%\n🕒 時間: $time\n\n---"
    send_notification "$message"
    log "Resource alert sent: Memory $memory_usage%, CPU $cpu_usage%"
}

# IP monitor (updated message format)
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

# [其他不變的函數和主邏輯省略，例如 install、uninstall、menu 等]
