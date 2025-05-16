#!/bin/bash

CONFIG_FILE="/etc/vps_notify.conf"
SCRIPT_PATH="/usr/local/bin/vps_notify.sh"
SERVICE_PATH="/etc/systemd/system/vps_notify.service"
CRON_JOB="*/5 * * * * root /usr/local/bin/vps_notify.sh monitor >/dev/null 2>&1"
IP_FILE="/var/lib/vps_notify_ip.txt"
LOG_FILE="/var/log/vps_notify.log"

TG_API="https://api.telegram.org/bot"
DINGTALK_API="https://oapi.dingtalk.com/robot/send?access_token="

# 彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志记录
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
    # 简单日志轮转
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 1048576 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.1"
        touch "$LOG_FILE"
    fi
}

# 获取公网 IP
get_ip() {
    ipv4=$(curl -s4m 3 ip.sb || curl -s4m 3 ifconfig.me || curl -s4m 3 ipinfo.io/ip || echo "获取失败")
    ipv6=$(curl -s6m 3 ip.sb || curl -s6m 3 ifconfig.me || curl -s6m 3 ipify.org || echo "获取失败")
    echo -e "IPv4: $ipv4\nIPv6: $ipv6"
}

# 获取仅IPv4地址
get_ipv4() {
    curl -s4m 3 ip.sb || curl -s4m 3 ifconfig.me || curl -s4m 3 ipinfo.io/ip || echo "获取失败"
}

# 检查IP变动
check_ip_change() {
    mkdir -p $(dirname "$IP_FILE")
    
    current_ip=$(get_ipv4)
    if [ "$current_ip" = "获取失败" ]; then
        log_message "ERROR: Failed to get IPv4 address"
        return 1
    fi
    
    if [ -f "$IP_FILE" ]; then
        old_ip=$(cat "$IP_FILE")
        if [ "$current_ip" != "$old_ip" ]; then
            echo "$current_ip" > "$IP_FILE"
            hostname=$(hostname)
            time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
            message="🔄 *IP 變更通知*

📝 備註: ${REMARK:-未设置}
🖥️ 主機名: $hostname
🌐 舊 IP: $old_ip
🌐 新 IP: $current_ip
🕒 時間: $time"
            send_notification "$message"
            log_message "IP changed from $old_ip to $current_ip"
            return 0
        fi
    else
        echo "$current_ip" > "$IP_FILE"
    fi
    return 1
}

# 验证 Telegram 配置
validate_tg() {
    local token="$1"
    local chat_id="$2"
    if [ -z "$token" ] || [ -z "$chat_id" ]; then
        return 1
    fi
    response=$(curl -s -X GET "${TG_API}${token}/getMe")
    if echo "$response" | grep -q '"ok":true'; then
        return 0
    else
        log_message "ERROR: Invalid Telegram token: $response"
        return 1
    fi
}

# 验证 DingTalk 配置
validate_dingtalk() {
    local webhook="$1"
    if [ -z "$webhook" ]; then
        return 1
    fi
    response=$(curl -s -X POST "${DINGTALK_API}${webhook}" \
        -H "Content-Type: application/json" \
        -d '{"msgtype": "text", "text": {"content": "Test"}}')
    if echo "$response" | grep -q '"errcode":0'; then
        return 0
    else
        log_message "ERROR: Invalid DingTalk webhook: $response"
        return 1
    fi
}

# 发送 Telegram 通知
send_tg() {
    local message="$1"
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_IDS" ]; then
        echo -e "${RED}错误: Telegram配置不完整${NC}"
        log_message "ERROR: Telegram configuration incomplete"
        return 1
    fi
    
    IFS=',' read -ra IDS <<< "$TG_CHAT_IDS"
    for id in "${IDS[@]}"; do
        response=$(curl -s -X POST "${TG_API}${TG_BOT_TOKEN}/sendMessage" \
            -H "Content-Type: application/json" \
            -d "{\"chat_id\": \"$id\", \"text\": \"$message\", \"parse_mode\": \"Markdown\"}")
        if ! echo "$response" | grep -q '"ok":true'; then
            echo -e "${RED}发送Telegram通知到 $id 失败${NC}"
            log_message "ERROR: Failed to send Telegram to $id: $response"
        else
            echo -e "${GREEN}成功发送Telegram通知到 $id${NC}"
            log_message "Sent Telegram notification to $id"
        fi
    done
}

# 发送 DingTalk 通知
send_dingtalk() {
    local message="$1"
    if [ -z "$DINGTALK_WEBHOOK" ]; then
        echo -e "${RED}错误: DingTalk配置不完整${NC}"
        log_message "ERROR: DingTalk configuration incomplete"
        return 1
    fi
    
    text=$(echo "$message" | sed 's/\*//g' | sed 's/^\s*//g')
    response=$(curl -s -X POST "${DINGTALK_API}${DINGTALK_WEBHOOK}" \
        -H "Content-Type: application/json" \
        -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$text\"}}")
    
    if ! echo "$response" | grep -q '"errcode":0'; then
        echo -e "${RED}发送DingTalk通知失败${NC}"
        log_message "ERROR: Failed to send DingTalk: $response"
    else
        echo -e "${GREEN}成功发送DingTalk通知${NC}"
        log_message "Sent DingTalk notification"
    fi
}

# 统一发送通知
send_notification() {
    local message="$1"
    [ "$ENABLE_TG_NOTIFY" = "Y" ] && send_tg "$message"
    [ "$ENABLE_DINGTALK_NOTIFY" = "Y" ] && send_dingtalk "$message"
}

# VPS 上线通知
notify_boot() {
    ip_info=$(get_ip)
    hostname=$(hostname)
    time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    message="✅ *VPS 已上線*

📝 備註: ${REMARK:-未设置}
🖥️ 主機名: $hostname
🌐 公網IP:
$ip_info
🕒 時間: $time"
    send_notification "$message"
    log_message "Sent boot notification"
}

# SSH 登录通知
notify_ssh() {
    user="$PAM_USER"
    ip="$PAM_RHOST"
    hostname=$(hostname)
    time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    message="🔐 *SSH 登錄通知*

📝 備註: ${REMARK:-未设置}
👤 用戶: $user
🖥️ 主機: $hostname
🌐 來源 IP: $ip
🕒 時間: $time"
    send_notification "$message"
    log_message "Sent SSH login notification for user $user from $ip"
}

# 资源监控
monitor_usage() {
    if [ "$ENABLE_IP_CHANGE_NOTIFY" = "Y" ]; then
        check_ip_change
    fi
    
    memory=$(free | awk '/Mem:/ {printf("%.0f", $3/$2*100)}')
    load=$(awk '{print int($1)}' /proc/loadavg)
    disk=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

    now=$(date +%s)
    last_warn=0
    [ -f /tmp/vps_notify_last ] && last_warn=$(cat /tmp/vps_notify_last)

    if (( now - last_warn < 21600 )); then
        return
    fi

    alert=""
    [[ $ENABLE_MEM_MONITOR == "Y" && $memory -ge $MEM_THRESHOLD ]] && alert+="🧠 *內存使用率過高*：${memory}%\n"
    [[ $ENABLE_CPU_MONITOR == "Y" && $load -ge $CPU_THRESHOLD ]] && alert+="🔥 *CPU 負載過高*：${load}\n"
    [[ $ENABLE_DISK_MONITOR == "Y" && $disk -ge $DISK_THRESHOLD ]] && alert+="💾 *磁盘使用率過高*：${disk}%\n"

    if [[ -n "$alert" || "$FORCE_SEND" == "Y" ]]; then
        echo "$now" > /tmp/vps_notify_last
        message="⚠️ *VPS 資源警報*

📝 備註: ${REMARK:-未设置}
$alert"
        send_notification "$message"
        log_message "Sent resource alert: $alert"
    fi
}

# 检查服务状态
check_status() {
    print_menu_header
    echo -e "${CYAN}[状态检查]${NC} 检查通知系统状态:\n"
    
    # 检查 systemd 服务
    if systemctl is-active vps_NOTIFY.service >/dev/null 2>&1; then
        echo -e "${GREEN}✓ systemd 服务 (vps_notify.service): 运行中${NC}"
    else
        echo -e "${RED}✗ systemd 服务 (vps_notify.service): 未运行${NC}"
    fi
    
    # 检查 cron 任务
    if grep -q "vps_notify.sh monitor" /etc/crontab; then
        echo -e "${GREEN}✓ cron 任务: 已配置 (每5分钟运行)${NC}"
    else
        echo -e "${RED}✗ cron 任务: 未配置${NC}"
    fi
    
    # 检查日志文件
    if [ -f "$LOG_FILE" ]; then
        echo -e "${GREEN}✓ 日志文件: 存在 ($LOG_FILE)${NC}"
        echo -e "${BLUE}最近日志:${NC}"
        tail -n 5 "$LOG_FILE"
    else
        echo -e "${RED}✗ 日志文件: 不存在${NC}"
    fi
    
    echo ""
    read -rp "按Enter键返回..."
}

# 绘制菜单标题
print_menu_header() {
    clear
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}║       ${YELLOW}VPS 通知系統 (高級版)       ${CYAN}║${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
}

# 检查依赖
check_dependencies() {
    for cmd in curl grep awk systemctl df; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}缺少依赖: $cmd${NC}"
            echo -e "${YELLOW}正在尝试安装必要依赖...${NC}"
            apt update -y >/dev/null 2>&1 && apt install -y curl grep gawk systemd coreutils >/dev/null 2>&1 || \
            yum install -y curl grep gawk systemd coreutils >/dev/null 2>&1
            
            if ! command -v $cmd &> /dev/null; then
                echo -e "${RED}安装依赖失败，请手动安装${NC}"
                log_message "ERROR: Failed to install dependency $cmd"
                exit 1
            fi
        fi
    done
}

# 显示当前配置
show_config() {
    echo -e "${CYAN}当前配置:${NC}"
    
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        
        if [ -n "$TG_BOT_TOKEN" ]; then
            token_prefix=$(echo $TG_BOT_TOKEN | cut -d':' -f1)
            token_masked="$token_prefix:****"
            echo -e "${BLUE}Telegram Bot Token:${NC} $token_masked"
        else
            echo -e "${BLUE}Telegram Bot Token:${NC} ${RED}未设置${NC}"
        fi
        echo -e "${BLUE}Telegram 通知:${NC} ${ENABLE_TG_NOTIFY:-N}"
        echo -e "${BLUE}Telegram Chat IDs:${NC} ${TG_CHAT_IDS:-未设置}"
        
        if [ -n "$DINGTALK_WEBHOOK" ]; then
            webhook_masked=$(echo $DINGTALK_WEBHOOK | cut -c1-10)****
            echo -e "${BLUE}DingTalk Webhook:${NC} $webhook_masked"
        else
            echo -e "${BLUE}DingTalk Webhook:${NC} ${RED}未设置${NC}"
        fi
        echo -e "${BLUE}DingTalk 通知:${NC} ${ENABLE_DINGTALK_NOTIFY:-N}"
        
        echo -e "${BLUE}备注:${NC} ${REMARK:-未设置}"
        echo -e "${BLUE}SSH登录通知:${NC} ${SSH_NOTIFY:-N}"
        echo -e "${BLUE}内存监控:${NC} ${ENABLE_MEM_MONITOR:-N} (阈值: ${MEM_THRESHOLD:-90}%)"
        echo -e "${BLUE}CPU监控:${NC} ${ENABLE_CPU_MONITOR:-N} (阈值: ${CPU_THRESHOLD:-4})"
        echo -e "${BLUE}磁盘监控:${NC} ${ENABLE_DISK_MONITOR:-N} (阈值: ${DISK_THRESHOLD:-90}%)"
        echo -e "${BLUE}IP变动通知:${NC} ${ENABLE_IP_CHANGE_NOTIFY:-N}"
    else
        echo -e "${RED}未找到配置文件，请先安装脚本${NC}"
    fi
    echo ""
}

# 安装脚本
install_script() {
    print_menu_header
    echo -e "${CYAN}[安装] ${GREEN}开始安装 VPS 通知系统...${NC}"
    echo ""
    
    check_dependencies
    
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    log_message "Starting installation"
    
    echo -e "${CYAN}[1/9]${NC} 选择通知方式:"
    echo -e "${CYAN}1.${NC} Telegram 通知"
    echo -e "${CYAN}2.${NC} DingTalk 通知"
    echo -e "${CYAN}3.${NC} 两者都启用"
    read -rp "请选择 [1-3]: " notify_choice
    case $notify_choice in
        1)
            ENABLE_TG_NOTIFY="Y"
            ENABLE_DINGTALK_NOTIFY="N"
            ;;
        2)
            ENABLE_TG_NOTIFY="N"
            ENABLE_DINGTALK_NOTIFY="Y"
            ;;
        3)
            ENABLE_TG_NOTIFY="Y"
            ENABLE_DINGTALK_NOTIFY="Y"
            ;;
        *)
            echo -e "${RED}无效选择，默认启用Telegram${NC}"
            log_message "Invalid notification choice, defaulting to Telegram"
            ENABLE_TG_NOTIFY="Y"
            ENABLE_DINGTALK_NOTIFY="N"
            ;;
    esac
    
    if [ "$ENABLE_TG_NOTIFY" = "Y" ]; then
        echo -e "\n${CYAN}[2/9]${NC} 输入 Telegram Bot Token:"
        read -rp "Token (格式如123456789:ABCDEF...): " TG_BOT_TOKEN
        echo -e "\n${CYAN}[3/9]${NC} 输入 Telegram Chat ID (支持多个，逗号分隔):"
        read -rp "Chat ID(s): " TG_CHAT_IDS
        if ! validate_tg "$TG_BOT_TOKEN" "$TG_CHAT_IDS"; then
            echo -e "${RED}Telegram 配置验证失败，请检查 Token 和 Chat ID${NC}"
            log_message "Telegram configuration validation failed"
            read -rp "按Enter键继续或 Ctrl+C 退出..."
        fi
    else
        TG_BOT_TOKEN=""
        TG_CHAT_IDS=""
    fi
    
    if [ "$ENABLE_DINGTALK_NOTIFY" = "Y" ]; then
        echo -e "\n${CYAN}[4/9]${NC} 输入 DingTalk Webhook:"
        read -rp "Webhook: " DINGTALK_WEBHOOK
        if ! validate_dingtalk "$DINGTALK_WEBHOOK"; then
            echo -e "${RED}DingTalk 配置验证失败，请检查 Webhook${NC}"
            log_message "DingTalk configuration validation failed"
            read -rp "按Enter键继续或 Ctrl+C 退出..."
        fi
    else
        DINGTALK_WEBHOOK=""
    fi
    
    echo -e "\n${CYAN}[5/9]${NC} 是否自定义主机备注? [Y/n]"
    read -rp "默认启用 (Y): " CUSTOM_REMARK
    CUSTOM_REMARK=${CUSTOM_REMARK:-Y}
    if [ "$CUSTOM_REMARK" = "Y" ]; then
        echo -e "${CYAN}[6/9]${NC} 输入主机备注 (如: 香港1号VPS):"
        read -rp "备注: " REMARK
    else
        REMARK=""
    fi
    
    echo -e "\n${CYAN}[7/9]${NC} 启用 SSH 登录通知? [Y/n]"
    read -rp "默认启用 (Y): " SSH_NOTIFY
    SSH_NOTIFY=${SSH_NOTIFY:-Y}
    
    echo -e
