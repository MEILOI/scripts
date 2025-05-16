#!/bin/bash

CONFIG_FILE="/etc/vps_notify.conf"
SCRIPT_PATH="/usr/local/bin/vps_notify.sh"
SERVICE_PATH="/etc/systemd/system/vps_notify.service"
CRON_JOB="*/5 * * * * root /usr/local/bin/vps_notify.sh monitor >/dev/null 2>&1"
IP_FILE="/var/lib/vps_notify_ip.txt"

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
            return 0
        fi
    else
        echo "$current_ip" > "$IP_FILE"
    fi
    return 1
}

# 发送 Telegram 通知
send_tg() {
    local message="$1"
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_IDS" ]; then
        echo -e "${RED}错误: Telegram配置不完整${NC}"
        return 1
    fi
    
    IFS=',' read -ra IDS <<< "$TG_CHAT_IDS"
    for id in "${IDS[@]}"; do
        response=$(curl -s -X POST "${TG_API}${TG_BOT_TOKEN}/sendMessage" \
            -H "Content-Type: application/json" \
            -d "{\"chat_id\": \"$id\", \"text\": \"$message\", \"parse_mode\": \"Markdown\"}")
        if ! echo "$response" | grep -q '"ok":true'; then
            echo -e "${RED}发送Telegram通知到 $id 失败${NC}"
        else
            echo -e "${GREEN}成功发送Telegram通知到 $id${NC}"
        fi
    done
}

# 发送 DingTalk 通知
send_dingtalk() {
    local message="$1"
    if [ -z "$DINGTALK_WEBHOOK" ]; then
        echo -e "${RED}错误: DingTalk配置不完整${NC}"
        return 1
    fi
    
    # 转换Markdown为纯文本以适应DingTalk
    text=$(echo "$message" | sed 's/\*//g' | sed 's/^\s*//g')
    response=$(curl -s -X POST "${DINGTALK_API}${DINGTALK_WEBHOOK}" \
        -H "Content-Type: application/json" \
        -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$text\"}}")
    
    if ! echo "$response" | grep -q '"errcode":0'; then
        echo -e "${RED}发送DingTalk通知失败: $response${NC}"
    else
        echo -e "${GREEN}成功发送DingTalk通知${NC}"
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
}

# 资源监控
monitor_usage() {
    if [ "$ENABLE_IP_CHANGE_NOTIFY" = "Y" ]; then
        check_ip_change
    fi
    
    memory=$(free | awk '/Mem:/ {printf("%.0f", $3/$2*100)}')
    load=$(awk '{print int($1)}' /proc/loadavg)

    now=$(date +%s)
    last_warn=0
    [ -f /tmp/vps_notify_last ] && last_warn=$(cat /tmp/vps_notify_last)

    if (( now - last_warn < 21600 )); then
        return
    fi

    alert=""
    [[ $ENABLE_MEM_MONITOR == "Y" && $memory -ge $MEM_THRESHOLD ]] && alert+="🧠 *內存使用率過高*：${memory}%\n"
    [[ $ENABLE_CPU_MONITOR == "Y" && $load -ge $CPU_THRESHOLD ]] && alert+="🔥 *CPU 負載過高*：${load}\n"

    if [[ -n "$alert" || "$FORCE_SEND" == "Y" ]]; then
        echo "$now" > /tmp/vps_notify_last
        message="⚠️ *VPS 資源警報*

📝 備註: ${REMARK:-未设置}
$alert"
        send_notification "$message"
    fi
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
    for cmd in curl grep awk systemctl; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}缺少依赖: $cmd${NC}"
            echo -e "${YELLOW}正在尝试安装必要依赖...${NC}"
            apt update -y >/dev/null 2>&1 && apt install -y curl grep gawk systemd >/dev/null 2>&1 || \
            yum install -y curl grep gawk systemd >/dev/null 2>&1
            
            if ! command -v $cmd &> /dev/null; then
                echo -e "${RED}安装依赖失败，请手动安装${NC}"
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
        
        # Telegram 配置
        if [ -n "$TG_BOT_TOKEN" ]; then
            token_prefix=$(echo $TG_BOT_TOKEN | cut -d':' -f1)
            token_masked="$token_prefix:****"
            echo -e "${BLUE}Telegram Bot Token:${NC} $token_masked"
        else
            echo -e "${BLUE}Telegram Bot Token:${NC} ${RED}未设置${NC}"
        fi
        echo -e "${BLUE}Telegram 通知:${NC} ${ENABLE_TG_NOTIFY:-N}"
        echo -e "${BLUE}Telegram Chat IDs:${NC} ${TG_CHAT_IDS:-未设置}"
        
        # DingTalk 配置
        if [ -n "$DINGTALK_WEBHOOK" ]; then
            webhook_masked=$(echo $DINGTALK_WEBHOOK | cut -c1-10)****
            echo -e "${BLUE}DingTalk Webhook:${NC} $webhook_masked"
        else
            echo -e "${BLUE}DingTalk Webhook:${NC} ${RED}未设置${NC}"
        fi
        echo -e "${BLUE}DingTalk 通知:${NC} ${ENABLE_DINGTALK_NOTIFY:-N}"
        
        # 其他配置
        echo -e "${BLUE}备注:${NC} ${REMARK:-未设置}"
        echo -e "${BLUE}SSH登录通知:${NC} ${SSH_NOTIFY:-N}"
        echo -e "${BLUE}内存监控:${NC} ${ENABLE_MEM_MONITOR:-N} (阈值: ${MEM_THRESHOLD:-90}%)"
        echo -e "${BLUE}CPU监控:${NC} ${ENABLE_CPU_MONITOR:-N} (阈值: ${CPU_THRESHOLD:-4})"
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
    
    # 通知方式选择
    echo -e "${CYAN}[1/8]${NC} 选择通知方式:"
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
            ENABLE_TG_NOTIFY="Y"
            ENABLE_DINGTALK_NOTIFY="N"
            ;;
    esac
    
    # Telegram 配置
    if [ "$ENABLE_TG_NOTIFY" = "Y" ]; then
        echo -e "\n${CYAN}[2/8]${NC} 输入 Telegram Bot Token:"
        read -rp "Token (格式如123456789:ABCDEF...): " TG_BOT_TOKEN
        echo -e "\n${CYAN}[3/8]${NC} 输入 Telegram Chat ID (支持多个，逗号分隔):"
        read -rp "Chat ID(s): " TG_CHAT_IDS
    else
        TG_BOT_TOKEN=""
        TG_CHAT_IDS=""
    fi
    
    # DingTalk 配置
    if [ "$ENABLE_DINGTALK_NOTIFY" = "Y" ]; then
        echo -e "\n${CYAN}[4/8]${NC} 输入 DingTalk Webhook:"
        read -rp "Webhook: " DINGTALK_WEBHOOK
    else
        DINGTALK_WEBHOOK=""
    fi
    
    # 备注配置
    echo -e "\n${CYAN}[5/8]${NC} 是否自定义主机备注? [Y/n]"
    read -rp "默认启用 (Y): " CUSTOM_REMARK
    CUSTOM_REMARK=${CUSTOM_REMARK:-Y}
    if [ "$CUSTOM_REMARK" = "Y" ]; then
        echo -e "${CYAN}[6/8]${NC} 输入主机备注 (如: 香港1号VPS):"
        read -rp "备注: " REMARK
    else
        REMARK=""
    fi
    
    # 其他配置
    echo -e "\n${CYAN}[7/8]${NC} 启用 SSH 登录通知? [Y/n]"
    read -rp "默认启用 (Y): " SSH_NOTIFY
    SSH_NOTIFY=${SSH_NOTIFY:-Y}
    
    echo -e "\n${CYAN}[8/8]${NC} 设置监控选项"
    read -rp "启用内存使用率监控? [Y/n] 默认启用 (Y): " ENABLE_MEM_MONITOR
    ENABLE_MEM_MONITOR=${ENABLE_MEM_MONITOR:-Y}
    if [ "$ENABLE_MEM_MONITOR" = "Y" ]; then
        read -rp "设置内存使用率警报阈值 (%) 默认90%: " MEM_THRESHOLD
        MEM_THRESHOLD=${MEM_THRESHOLD:-90}
    fi
    read -rp "启用CPU负载监控? [Y/n] 默认启用 (Y): " ENABLE_CPU_MONITOR
    ENABLE_CPU_MONITOR=${ENABLE_CPU_MONITOR:-Y}
    if [ "$ENABLE_CPU_MONITOR" = "Y" ]; then
        read -rp "设置CPU负载警报阈值 默认4: " CPU_THRESHOLD
        CPU_THRESHOLD=${CPU_THRESHOLD:-4}
    fi
    read -rp "启用IP变动通知? [Y/n] 默认启用 (Y): " ENABLE_IP_CHANGE_NOTIFY
    ENABLE_IP_CHANGE_NOTIFY=${ENABLE_IP_CHANGE_NOTIFY:-Y}
    
    # 创建配置文件
    cat <<EOF > "$CONFIG_FILE"
# 通知配置
ENABLE_TG_NOTIFY="$ENABLE_TG_NOTIFY"
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_CHAT_IDS="$TG_CHAT_IDS"
ENABLE_DINGTALK_NOTIFY="$ENABLE_DINGTALK_NOTIFY"
DINGTALK_WEBHOOK="$DINGTALK_WEBHOOK"
REMARK="$REMARK"

# 通知选项
SSH_NOTIFY="$SSH_NOTIFY"

# 资源监控选项
ENABLE_MEM_MONITOR="$ENABLE_MEM_MONITOR"
MEM_THRESHOLD="$MEM_THRESHOLD"
ENABLE_CPU_MONITOR="$ENABLE_CPU_MONITOR"
CPU_THRESHOLD="$CPU_THRESHOLD"
ENABLE_IP_CHANGE_NOTIFY="$ENABLE_IP_CHANGE_NOTIFY"
EOF
    
    if [ "$ENABLE_IP_CHANGE_NOTIFY" = "Y" ]; then
        mkdir -p $(dirname "$IP_FILE")
        get_ipv4 > "$IP_FILE"
    fi
    
    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=VPS Notify Boot Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_PATH boot

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable vps_notify.service
    
    if ! grep -q "vps_notify.sh monitor" /etc/crontab; then
        echo "$CRON_JOB" >> /etc/crontab
    fi
    
    if [[ $SSH_NOTIFY == "Y" ]]; then
        mkdir -p /etc/security
        pam_script="/etc/security/pam_exec_notify.sh"
        cat <<EOF > "$pam_script"
#!/bin/bash
PAM_USER="\$PAM_USER" PAM_RHOST="\$PAM_RHOST" $SCRIPT_PATH ssh
EOF
        chmod +x "$pam_script"
        if ! grep -q pam_exec.so /etc/pam.d/sshd; then
            echo "session optional pam_exec.so seteuid $pam_script" >> /etc/pam.d/sshd
        fi
    fi
    
    if ! grep -q "127.0.0.1 $(hostname)" /etc/hosts; then
        echo "127.0.0.1 $(hostname)" >> /etc/hosts
    fi
    
    echo -e "\n${GREEN}✅ 安装完成!${NC}"
    echo -e "${YELLOW}提示: 可以重启VPS测试开机通知，或从菜单中选择'测试通知'选项${NC}"
    sleep 2
}

# 卸载脚本
uninstall_script() {
    print_menu_header
    echo -e "${CYAN}[卸载] ${YELLOW}正在卸载 VPS 通知系统...${NC}\n"
    
    systemctl disable vps_notify.service 2>/dev/null
    rm -f "$SERVICE_PATH" "$SCRIPT_PATH" "$CONFIG_FILE" "$IP_FILE"
    sed -i '/vps_notify.sh monitor/d' /etc/crontab
    sed -i '/pam_exec.so.*pam_exec_notify.sh/d' /etc/pam.d/sshd
    rm -f /etc/security/pam_exec_notify.sh /tmp/vps_notify_last
    
    echo -e "\n${GREEN}✅ 卸载完成!${NC}"
    echo -e "${YELLOW}所有配置文件和脚本已删除${NC}"
    sleep 2
    exit 0
}

# 测试通知
test_notifications() {
    load_config
    
    while true; do
        print_menu_header
        echo -e "${CYAN}[测试通知]${NC} 请选择要测试的通知类型:\n"
        echo -e "${CYAN}1.${NC} 测试开机通知"
        echo -e "${CYAN}2.${NC} 测试SSH登录通知"
        echo -e "${CYAN}3.${NC} 测试资源监控通知"
        echo -e "${CYAN}4.${NC} 测试IP变动通知"
        echo -e "${CYAN}0.${NC} 返回主菜单"
        echo ""
        read -rp "请选择 [0-4]: " choice
        
        case $choice in
            1)
                echo -e "\n${YELLOW}正在发送开机通知...${NC}"
                notify_boot
                echo -e "\n${GREEN}通知已发送，请检查你的通知渠道${NC}"
                read -rp "按Enter键继续..."
                ;;
            2)
                echo -e "\n${YELLOW}正在发送SSH登录通知...${NC}"
                PAM_USER="测试用户" PAM_RHOST="192.168.1.100" notify_ssh
                echo -e "\n${GREEN}通知已发送，请检查你的通知渠道${NC}"
                read -rp "按Enter键继续..."
                ;;
            3)
                echo -e "\n${YELLOW}正在发送资源监控通知(忽略阈值)...${NC}"
                FORCE_SEND="Y" monitor_usage
                echo -e "\n${GREEN}通知已发送，请检查你的通知渠道${NC}"
                read -rp "按Enter键继续..."
                ;;
            4)
                echo -e "\n${YELLOW}正在发送IP变动通知...${NC}"
                current_ip=""
                if [ -f "$IP_FILE" ]; then
                    current_ip=$(cat "$IP_FILE")
                    echo "8.8.8.8" > "$IP_FILE"
                fi
                check_ip_change
                if [ -n "$current_ip" ]; then
                    echo "$current_ip" > "$IP_FILE"
                fi
                echo -e "\n${GREEN}通知已发送，请检查你的通知渠道${NC}"
                read -rp "按Enter键继续..."
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择，请重试${NC}"
                sleep 1
                ;;
        esac
    done
}

# 修改配置
modify_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误: 配置文件不存在，请先安装脚本${NC}"
        sleep 2
        return
    fi
    
    load_config
    
    while true; do
        print_menu_header
        echo -e "${CYAN}[配置设置]${NC} 当前配置:\n"
        show_config
        
        echo -e "请选择要修改的配置项:"
        echo -e "${CYAN}1.${NC} ${ENABLE_TG_NOTIFY == "Y" ? "禁用" : "启用"} Telegram 通知"
        echo -e "${CYAN}2.${NC} 修改 Telegram Bot Token"
        echo -e "${CYAN}3.${NC} 修改 Telegram Chat ID"
        echo -e "${CYAN}4.${NC} ${ENABLE_DINGTALK_NOTIFY == "Y" ? "禁用" : "启用"} DingTalk 通知"
        echo -e "${CYAN}5.${NC} 修改 DingTalk Webhook"
        echo -e "${CYAN}6.${NC} 修改主机备注"
        echo -e "${CYAN}7.${NC} ${SSH_NOTIFY == "Y" ? "禁用" : "启用"} SSH登录通知"
        echo -e "${CYAN}8.${NC} ${ENABLE_MEM_MONITOR == "Y" ? "禁用" : "启用"} 内存监控 (当前阈值: ${MEM_THRESHOLD:-90}%)"
        echo -e "${CYAN}9.${NC} ${ENABLE_CPU_MONITOR == "Y" ? "禁用" : "启用"} CPU监控 (当前阈值: ${CPU_THRESHOLD:-4})"
        echo -e "${CYAN}10.${NC} ${ENABLE_IP_CHANGE_NOTIFY == "Y" ? "禁用" : "启用"} IP变动通知"
        echo -e "${CYAN}0.${NC} 返回主菜单"
        echo ""
        read -rp "请选择 [0-10]: " choice
        
        case $choice in
            1)
                new_value=$([[ "$ENABLE_TG_NOTIFY" == "Y" ]] && echo "N" || echo "Y")
                sed -i "s/ENABLE_TG_NOTIFY=.*$/ENABLE_TG_NOTIFY=\"$new_value\"/" "$CONFIG_FILE"
                echo -e "${GREEN}Telegram通知已${new_value == "Y" ? "启用" : "禁用"}${NC}"
                ;;
            2)
                echo -e "\n${YELLOW}请输入新的 Telegram Bot Token:${NC}"
                read -rp "Token: " new_token
                if [ -n "$new_token" ]; then
                    sed -i "s/TG_BOT_TOKEN=.*$/TG_BOT_TOKEN=\"$new_token\"/" "$CONFIG_FILE"
                    echo -e "${GREEN}Telegram Token已更新${NC}"
                fi
                ;;
            3)
                echo -e "\n${YELLOW}请输入新的 Telegram Chat ID(s) (多个ID用逗号分隔):${NC}"
                read -rp "Chat ID(s): " new_ids
                if [ -n "$new_ids" ]; then
                    sed -i "s/TG_CHAT_IDS=.*$/TG_CHAT_IDS=\"$new_ids\"/" "$CONFIG_FILE"
                    echo -e "${GREEN}Telegram Chat ID已更新${NC}"
                fi
                ;;
            4)
                new_value=$([[ "$ENABLE_DINGTALK_NOTIFY" == "Y" ]] && echo "N" || echo "Y")
                sed -i "s/ENABLE_DINGTALK_NOTIFY=.*$/ENABLE_DINGTALK_NOTIFY=\"$new_value\"/" "$CONFIG_FILE"
                echo -e "${GREEN}DingTalk通知已${new_value == "Y" ? "启用" : "禁用"}${NC}"
                ;;
            5)
                echo -e "\n${YELLOW}请输入新的 DingTalk Webhook:${NC}"
                read -rp "Webhook: " new_webhook
                if [ -n "$new_webhook" ]; then
                    sed -i "s/DINGTALK_WEBHOOK=.*$/DINGTALK_WEBHOOK=\"$new_webhook\"/" "$CONFIG_FILE"
                    echo -e "${GREEN}DingTalk Webhook已更新${NC}"
                fi
                ;;
            6)
                echo -e "\n${YELLOW}请输入新的主机备注:${NC}"
                read -rp "备注: " new_remark
                sed -i "s/REMARK=.*$/REMARK=\"$new_remark\"/" "$CONFIG_FILE" 2>/dev/null || \
                echo "REMARK=\"$new_remark\"" >> "$CONFIG_FILE"
                echo -e "${GREEN}主机备注已更新${NC}"
                ;;
            7)
                new_value=$([[ "$SSH_NOTIFY" == "Y" ]] && echo "N" || echo "Y")
                sed -i "s/SSH_NOTIFY=.*$/SSH_NOTIFY=\"$new_value\"/" "$CONFIG_FILE"
                if [ "$new_value" == "Y" ]; then
                    mkdir -p /etc/security
                    pam_script="/etc/security/pam_exec_notify.sh"
                    cat <<EOF > "$pam_script"
#!/bin/bash
PAM_USER="\$PAM_USER" PAM_RHOST="\$PAM_RHOST" $SCRIPT_PATH ssh
EOF
                    chmod +x "$pam_script"
                    if ! grep -q pam_exec.so /etc/pam.d/sshd; then
                        echo "session optional pam_exec.so seteuid $pam_script" >> /etc/pam.d/sshd
                    fi
                    echo -e "${GREEN}SSH登录通知已启用${NC}"
                else
                    sed -i '/pam_exec.so.*pam_exec_notify.sh/d' /etc/pam.d/sshd
                    rm -f /etc/security/pam_exec_notify.sh
                    echo -e "${GREEN}SSH登录通知已禁用${NC}"
                fi
                ;;
            8)
                if [[ "$ENABLE_MEM_MONITOR" == "Y" ]]; then
                    sed -i "s/ENABLE_MEM_MONITOR=.*$/ENABLE_MEM_MONITOR=\"N\"/" "$CONFIG_FILE"
                    echo -e "${GREEN}内存监控已禁用${NC}"
                else
                    sed -i "s/ENABLE_MEM_MONITOR=.*$/ENABLE_MEM_MONITOR=\"Y\"/" "$CONFIG_FILE"
                    echo -e "\n${YELLOW}请设置内存使用率警报阈值 (%):${NC}"
                    read -rp "阈值 (默认90): " threshold
                    threshold=${threshold:-90}
                    sed -i "s/MEM_THRESHOLD=.*$/MEM_THRESHOLD=\"$threshold\"/" "$CONFIG_FILE" 2>/dev/null || \
                    echo "MEM_THRESHOLD=\"$threshold\"" >> "$CONFIG_FILE"
                    echo -e "${GREEN}内存监控已启用，阈值设为 ${threshold}%${NC}"
                fi
                ;;
            9)
                if [[ "$ENABLE_CPU_MONITOR" == "Y" ]]; then
                    sed -i "s/ENABLE_CPU_MONITOR=.*$/ENABLE_CPU_MONITOR=\"N\"/" "$CONFIG_FILE"
                    echo -e "${GREEN}CPU监控已禁用${NC}"
                else
                    sed -i "s/ENABLE_CPU_MONITOR=.*$/ENABLE_CPU_MONITOR=\"Y\"/" "$CONFIG_FILE"
                    echo -e "\n${YELLOW}请设置CPU负载警报阈值:${NC}"
                    read -rp "阈值 (默认4): " threshold
                    threshold=${threshold:-4}
                    sed -i "s/CPU_THRESHOLD=.*$/CPU_THRESHOLD=\"$threshold\"/" "$CONFIG_FILE" 2>/dev/null || \
                    echo "CPU_THRESHOLD=\"$threshold\"" >> "$CONFIG_FILE"
                    echo -e "${GREEN}CPU监控已启用，阈值设为 ${threshold}${NC}"
                fi
                ;;
            10)
                if [[ "$ENABLE_IP_CHANGE_NOTIFY" == "Y" ]]; then
                    sed -i "s/ENABLE_IP_CHANGE_NOTIFY=.*$/ENABLE_IP_CHANGE_NOTIFY=\"N\"/" "$CONFIG_FILE"
                    echo -e "${GREEN}IP变动通知已禁用${NC}"
                else
                    sed -i "s/ENABLE_IP_CHANGE_NOTIFY=.*$/ENABLE_IP_CHANGE_NOTIFY=\"Y\"/" "$CONFIG_FILE" 2>/dev/null || \
                    echo "ENABLE_IP_CHANGE_NOTIFY=\"Y\"" >> "$CONFIG_FILE"
                    mkdir -p $(dirname "$IP_FILE")
                    get_ipv4 > "$IP_FILE"
                    echo -e "${GREEN}IP变动通知已启用，当前IP已记录${NC}"
                fi
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择，请重试${NC}"
                sleep 1
                ;;
        esac
        sleep 1
        load_config
    done
}

# 加载配置
load_config() {
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
}

# 显示用法帮助
show_usage() {
    echo -e "用法: $0 [命令]"
    echo ""
    echo -e "命令:"
    echo -e "  install   安装脚本"
    echo -e "  uninstall 卸载脚本"
    echo -e "  boot      发送开机通知"
    echo -e "  ssh       发送SSH登录通知(由PAM调用)"
    echo -e "  monitor   监控系统资源(由cron调用)"
    echo -e "  menu      显示交互式菜单(默认)"
    echo ""
}

# 主菜单
show_menu() {
    while true; do
        print_menu_header
        
        if [ -f "$CONFIG_FILE" ]; then
            echo -e "${GREEN}● 通知系统已安装${NC}\n"
            show_config
        else
            echo -e "${RED}● 通知系统未安装${NC}\n"
        fi
        
        echo -e "请选择操作:"
        echo -e "${CYAN}1.${NC} 安装/重新安装"
        echo -e "${CYAN}2.${NC} 配置设置"
        echo -e "${CYAN}3.${NC} 测试通知"
        echo -e "${CYAN}4.${NC} 卸载"
        echo -e "${CYAN}0.${NC} 退出"
        echo ""
        read -rp "请选择 [0-4]: " choice
        
        case $choice in
            1)
                install_script
                ;;
            2)
                modify_config
                ;;
            3)
                test_notifications
                ;;
            4)
                echo -e "\n${YELLOW}警告: 此操作将删除所有配置和脚本!${NC}"
                read -rp "确认卸载? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    uninstall_script
                fi
                ;;
            0)
                echo -e "\n${GREEN}感谢使用 VPS 通知系统!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重试${NC}"
                sleep 1
                ;;
        esac
    done
}

main() {
    if [[ "$1" == "menu" || -z "$1" ]]; then
        if [ -x "$SCRIPT_PATH" ] && [ "$0" != "$SCRIPT_PATH" ]; then
            exec "$SCRIPT_PATH" menu
        else
            show_menu
        fi
    else
        case "$1" in
            boot)
                load_config
                notify_boot
                ;;
            ssh)
                load_config
                notify_ssh
                ;;
            monitor)
                load_config
                monitor_usage
                ;;
            install)
                install_script
                ;;
            uninstall)
                uninstall_script
                ;;
            help|--help|-h)
                show_usage
                ;;
            *)
                echo -e "${RED}错误: 未知命令 '$1'${NC}"
                show_usage
                exit 1
                ;;
        esac
    fi
}

main "$1"
