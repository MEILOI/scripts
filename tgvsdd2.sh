#!/bin/bash

# 确保使用 Bash
if [ -z "$BASH_VERSION" ]; then
    echo "Error: This script requires Bash. Run with 'bash $0' or './$0'."
    exit 1
fi

# 日志函数
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp $1" >> /var/log/vps_notify.log 2>/dev/null || \
    echo "$timestamp $1" >&2
}

# 配置文件
CONFIG_FILE="/etc/tgvsdd.conf"

# 加载配置
load_config() {
    log "Entering load_config"
    if [ ! -f "$CONFIG_FILE" ] || [ ! -r "$CONFIG_FILE" ]; then
        log "Error: Config file $CONFIG_FILE not found or not readable"
        echo "Error: Config file $CONFIG_FILE not found or not readable" >&2
        exit 1
    fi
    source "$CONFIG_FILE"
    log "Config loaded: ENABLE_TG_NOTIFY=$ENABLE_TG_NOTIFY"
}

# 获取公网 IP
get_ip() {
    log "Entering get_ip"
    local ipv4=$(curl -s4m 3 ip.sb || curl -s4m 3 ifconfig.me || curl -s4m 3 ipinfo.io/ip || echo "获取失败")
    local ipv6=$(curl -s6m 3 ip.sb || curl -s6m 3 ifconfig.me || curl -s6m 3 ipify.org || echo "获取失败")
    echo "$ipv4" > /tmp/ipv4.txt
    echo "$ipv6" > /tmp/ipv6.txt
    log "IPv4: $ipv4, IPv6: $ipv6"
}

# 发送 Telegram 通知
send_telegram() {
    local message="$1"
    log "Entering send_telegram"
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
    else
        log "Telegram notification skipped: ENABLE_TG_NOTIFY=$ENABLE_TG_NOTIFY, TG_BOT_TOKEN=$TG_BOT_TOKEN, TG_CHAT_IDS=$TG_CHAT_IDS"
    fi
}

# 发送开机通知
send_boot_notification() {
    log "Entering send_boot_notification"
    local ipv4=$(cat /tmp/ipv4.txt)
    local ipv6=$(cat /tmp/ipv6.txt)
    local hostname=$(hostname)
    local time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    local message="*VPS 已上线* [成功]\n备注: ${REMARK:-未设置}\n主机名: $hostname\n公网IP:\nIPv4: $ipv4\nIPv6: $ipv6\n时间: $time"
    send_telegram "$message"
}

# 发送 SSH 登录通知
send_ssh_notification() {
    log "Entering send_ssh_notification"
    local user="$PAM_USER"
    local ip="$PAM_RHOST"
    local hostname=$(hostname)
    local time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    local message="*SSH 登录通知* [登录]\n备注: ${REMARK:-未设置}\n用户: $user\n主机: $hostname\n来源 IP: $ip\n时间: $time"
    send_telegram "$message"
}

# 检查 IP 变动
check_ip_change() {
    log "Entering check_ip_change"
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

# 测试 Telegram 推送
test_telegram() {
    log "Entering test_telegram"
    local hostname=$(hostname)
    local time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    local message="*测试通知* [成功]\n备注: ${REMARK:-未设置}\n主机名: $hostname\n时间: $time"
    send_telegram "$message"
    echo "Test notification sent. Check Telegram and /var/log/vps_notify.log."
}

# 显示使用说明
show_usage() {
    echo "Usage: $0 {boot|ssh|monitor|test}"
    echo "  boot    : Send boot notification"
    echo "  ssh     : Send SSH login notification"
    echo "  monitor : Check for IP changes"
    echo "  test    : Send test notification"
    echo "  menu    : Show interactive menu"
}

# 交互菜单
show_menu() {
    while true; do
        clear
        echo "=== VPS Notification System (v3.0.20) ==="
        echo "1. Send boot notification"
        echo "2. Send SSH login notification"
        echo "3. Check IP change"
        echo "4. Send test notification"
        echo "0. Exit"
        read -rp "Select an option [0-4]: " choice
        case $choice in
            1) get_ip; send_boot_notification ;;
            2) PAM_USER="testuser" PAM_RHOST="192.168.1.100" send_ssh_notification ;;
            3) check_ip_change ;;
            4) test_telegram ;;
            0) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid option, try again." ;;
        esac
        read -rp "Press Enter to continue..."
    done
}

# 主函数
main() {
    log "Script started with args: $@"
    if [ $# -eq 0 ]; then
        show_menu
    else
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
            test)
                test_telegram
                ;;
            menu)
                show_menu
                ;;
            *)
                show_usage
                exit 1
                ;;
        esac
    fi
}

main "$@"
