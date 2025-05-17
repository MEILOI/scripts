#!/bin/bash

# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> /var/log/vps_notify.log
}

# 配置文件
CONFIG_FILE="/etc/tgvsdd.conf"

# 加载配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        log "Error: Config file $CONFIG_FILE not found"
        exit 1
    fi
}

# 获取公网 IP
get_ip() {
    local ipv4=$(curl -s4m 3 ip.sb || curl -s4m 3 ifconfig.me || curl -s4m 3 ipinfo.io/ip || echo "获取失败")
    local ipv6=$(curl -s6m 3 ip.sb || curl -s6m 3 ifconfig.me || curl -s6m 3 ipify.org || echo "获取失败")
    echo "$ipv4" > /tmp/ipv4.txt
    echo "$ipv6" > /tmp/ipv6.txt
}

# 发送 Telegram 通知
send_telegram() {
    local message="$1"
    if [[ "$ENABLE_TG_NOTIFY" -eq 1 && -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_IDS" ]]; then
        local final_message="$message"
        if [[ "$TG_EMOJI" -eq 1 ]]; then
            final_message=$(echo "$final_message" | sed 's/\[成功\]/✅/g; s/\[登录\]/🔐/g; s/\[警告\]/⚠️/g; s/\[网络\]/🌐/g')
        fi
        # 增强换行：单 \n 改为 \n\n
        final_message=$(echo "$final_message" | sed 's/\\n/\\n\\n/g')
        # 转义 Markdown 特殊字符
        final_message=$(echo "$final_message" | sed 's/[_*[\]()~`>#+=|{}.!]/\\&/g')
        for chat_id in ${TG_CHAT_IDS//,/ }; do
            local response=$(curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
                -H "Content-Type: application/json" \
                -d "{\"chat_id\": \"${chat_id}\", \"text\": \"${final_message}\", \"parse_mode\": \"Markdown\"}")
            log "Telegram raw message: $final_message"
            log "Telegram response: $response"
        done
    fi
}

# 发送开机通知
send_boot_notification() {
    local ipv4=$(cat /tmp/ipv4.txt)
    local ipv6=$(cat /tmp/ipv6.txt)
    local hostname=$(hostname)
    local time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    local message="*VPS 已上线* [成功]\n备注: ${REMARK:-未设置}\n主机名: $hostname\n公网IP:\nIPv4: $ipv4\nIPv6: $ipv6\n时间: $time"
    send_telegram "$message"
}

# 发送 SSH 登录通知
send_ssh_notification() {
    local user="$PAM_USER"
    local ip="$PAM_RHOST"
    local hostname=$(hostname)
    local time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    local message="*SSH 登录通知* [登录]\n备注: ${REMARK:-未设置}\n用户: $user\n主机: $hostname\n来源 IP: $ip\n时间: $time"
    send_telegram "$message"
}

# 检查 IP 变动
check_ip_change() {
    local current_ip=$(curl -s4m 3 ip.sb || curl -s4m 3 ifconfig.me || curl -s4m 3 ipinfo.io/ip || echo "获取失败")
    if [ "$current_ip" = "获取失败" ]; then
        log "Error: Failed to get current IP"
        return 1
    fi
    local ip_file="/var/lib/tgvsdd_ip.txt"
    mkdir -p $(dirname "$ip_file")
    if [ -f "$ip_file" ]; then
        local old_ip=$(cat "$ip_file")
        if [ "$current_ip" != "$old_ip" ]; then
            echo "$current_ip" > "$ip_file"
            local hostname=$(hostname)
            local time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
            local message="*IP 变更通知* [网络]\n备注: ${REMARK:-未设置}\n主机名: $hostname\n旧 IP: $old_ip\n新 IP: $current_ip\n时间: $time"
            send_telegram "$message"
            return 0
        fi
    else
        echo "$current_ip" > "$ip_file"
    fi
    return 1
}

# 主函数
main() {
    load_config
    case "$1" in
        boot)
            get_ip
            send_boot_notification
            ;;
        ssh)
            send_ssh_notification
            ;;
        monitor)
            check_ip_change
            ;;
        *)
            echo "Usage: $0 {boot|ssh|monitor}"
            exit 1
            ;;
    esac
}

main "$@"
