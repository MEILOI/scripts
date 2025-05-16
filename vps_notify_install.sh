#!/bin/bash

CONFIG_FILE="/etc/vps_notify.conf"
SCRIPT_PATH="/usr/local/bin/vps_notify.sh"
SERVICE_PATH="/etc/systemd/system/vps_notify.service"
CRON_JOB="*/5 * * * * root /usr/local/bin/vps_notify.sh monitor >/dev/null 2>&1"
IP_FILE="/var/lib/vps_notify_ip.txt"

TG_API="https://api.telegram.org/bot"

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
    # 确保IP存储目录存在
    mkdir -p $(dirname "$IP_FILE")
    
    current_ip=$(get_ipv4)
    if [ "$current_ip" = "获取失败" ]; then
        return 1 # 跳过检测
    fi
    
    # 检查是否有保存的旧IP
    if [ -f "$IP_FILE" ]; then
        old_ip=$(cat "$IP_FILE")
        
        # 如果IP变动了
        if [ "$current_ip" != "$old_ip" ]; then
            # 更新IP记录
            echo "$current_ip" > "$IP_FILE"
            
            # 发送IP变动通知
            hostname=$(hostname)
            time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
            message="🔄 *IP 變更通知*

🖥️ 主機名: $hostname
🌐 舊 IP: $old_ip
🌐 新 IP: $current_ip
🕒 時間: $time"
            send_tg "$message"
            return 0
        fi
    else
        # 第一次运行，保存当前IP
        echo "$current_ip" > "$IP_FILE"
    fi
    
    return 1
}

# 发送 Telegram 通知 - 使用JSON格式确保换行符正确处理
send_tg() {
    local message="$1"
    # 检查配置是否存在
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_IDS" ]; then
        echo -e "${RED}错误: Telegram配置不完整，请先设置Bot Token和Chat ID${NC}"
        return 1
    fi
    
    IFS=',' read -ra IDS <<< "$TG_CHAT_IDS"
    for id in "${IDS[@]}"; do
        response=$(curl -s -X POST "${TG_API}${TG_BOT_TOKEN}/sendMessage" \
            -H "Content-Type: application/json" \
            -d "{\"chat_id\": \"$id\", \"text\": \"$message\", \"parse_mode\": \"Markdown\"}")
        
        if ! echo "$response" | grep -q '"ok":true'; then
            echo -e "${RED}发送通知到 $id 失败: $response${NC}"
        else
            echo -e "${GREEN}成功发送通知到 $id${NC}"
        fi
    done
}

# VPS 上线通知
notify_boot() {
    ip_info=$(get_ip)
    hostname=$(hostname)
    time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    message="✅ *VPS 已上線*

🖥️ 主機名: $hostname
🌐 公網IP:
$ip_info
🕒 時間: $time"
    send_tg "$message"
}

# SSH 登录通知
notify_ssh() {
    user="$PAM_USER"
    ip="$PAM_RHOST"
    hostname=$(hostname)
    time=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')
    message="🔐 *SSH 登錄通知*

👤 用戶: $user
🖥️ 主機: $hostname
🌐 來源 IP: $ip
🕒 時間: $time"
    send_tg "$message"
}

# 资源监控
monitor_usage() {
    # 首先检查IP变动
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

    if [[ -n "$alert" ]]; then
        echo "$now" > /tmp/vps_notify_last
        message="⚠️ *VPS 資源警報*

$alert"
        send_tg "$message"
    fi
}

# 绘制菜单标题
print_menu_header() {
    clear
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}║       ${YELLOW}VPS Telegram 通知系統       ${CYAN}║${NC}"
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
                echo -e "${RED}安装依赖失败，请手动安装 curl grep awk systemd${NC}"
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
        
        # 掩盖Token的一部分
        if [ -n "$TG_BOT_TOKEN" ]; then
            token_prefix=$(echo $TG_BOT_TOKEN | cut -d':' -f1)
            token_masked="$token_prefix:****"
            echo -e "${BLUE}Telegram Bot Token:${NC} $token_masked"
        else
            echo -e "${BLUE}Telegram Bot Token:${NC} ${RED}未设置${NC}"
        fi
        
        if [ -n "$TG_CHAT_IDS" ]; then
            echo -e "${BLUE}Telegram Chat IDs:${NC} $TG_CHAT_IDS"
        else
            echo -e "${BLUE}Telegram Chat IDs:${NC} ${RED}未设置${NC}"
        fi
        
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
    echo -e "${CYAN}[安装] ${GREEN}开始安装 VPS Telegram 通知系统...${NC}"
    echo ""
    
    check_dependencies
    
    echo -e "${CYAN}[1/6]${NC} 输入 Telegram Bot Token:"
    read -rp "Token (格式如123456789:ABCDEF...): " TG_BOT_TOKEN
    
    echo -e "\n${CYAN}[2/6]${NC} 输入接收通知的 Telegram Chat ID (支持多个，逗号分隔):"
    read -rp "Chat ID(s): " TG_CHAT_IDS
    
    echo -e "\n${CYAN}[3/6]${NC} 启用 SSH 登录通知? [Y/n]"
    read -rp "默认启用 (Y): " SSH_NOTIFY
    SSH_NOTIFY=${SSH_NOTIFY:-Y}
    
    echo -e "\n${CYAN}[4/6]${NC} 设置内存监控"
    read -rp "启用内存使用率监控? [Y/n] 默认启用 (Y): " ENABLE_MEM_MONITOR
    ENABLE_MEM_MONITOR=${ENABLE_MEM_MONITOR:-Y}
    
    if [ "$ENABLE_MEM_MONITOR" = "Y" ]; then
        read -rp "设置内存使用率警报阈值 (%) 默认90%: " MEM_THRESHOLD
        MEM_THRESHOLD=${MEM_THRESHOLD:-90}
    fi
    
    echo -e "\n${CYAN}[5/6]${NC} 设置CPU监控"
    read -rp "启用CPU负载监控? [Y/n] 默认启用 (Y): " ENABLE_CPU_MONITOR
    ENABLE_CPU_MONITOR=${ENABLE_CPU_MONITOR:-Y}
    
    if [ "$ENABLE_CPU_MONITOR" = "Y" ]; then
        read -rp "设置CPU负载警报阈值 默认4: " CPU_THRESHOLD
        CPU_THRESHOLD=${CPU_THRESHOLD:-4}
    fi
    
    echo -e "\n${CYAN}[6/6]${NC} 设置IP变动监控"
    read -rp "启用IP变动通知? [Y/n] 默认启用 (Y): " ENABLE_IP_CHANGE_NOTIFY
    ENABLE_IP_CHANGE_NOTIFY=${ENABLE_IP_CHANGE_NOTIFY:-Y}
    
    # 创建配置文件
    cat <<EOF > "$CONFIG_FILE"
# Telegram配置
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_CHAT_IDS="$TG_CHAT_IDS"

# 通知选项
SSH_NOTIFY="$SSH_NOTIFY"

# 资源监控选项
ENABLE_MEM_MONITOR="$ENABLE_MEM_MONITOR"
MEM_THRESHOLD="$MEM_THRESHOLD"
ENABLE_CPU_MONITOR="$ENABLE_CPU_MONITOR"
CPU_THRESHOLD="$CPU_THRESHOLD"

# IP变动通知
ENABLE_IP_CHANGE_NOTIFY="$ENABLE_IP_CHANGE_NOTIFY"
EOF
    
    # 保存当前IP作为基准
    if [ "$ENABLE_IP_CHANGE_NOTIFY" = "Y" ]; then
        mkdir -p $(dirname "$IP_FILE")
        get_ipv4 > "$IP_FILE"
    fi
    
    # 复制脚本到系统路径
    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    # 创建systemd服务
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
    
    # 添加cron任务
    if ! grep -q "vps_notify.sh monitor" /etc/crontab; then
        echo "$CRON_JOB" >> /etc/crontab
    fi
    
    # 配置SSH登录通知
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
    
    # 修复主机名解析问题
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
    echo -e "${CYAN}[卸载] ${YELLOW}正在卸载 VPS Telegram 通知系统...${NC}\n"
    
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
                echo -e "\n${GREEN}通知已发送，请检查你的Telegram${NC}"
                read -rp "按Enter键继续..."
                ;;
            2)
                echo -e "\n${YELLOW}正在发送SSH登录通知...${NC}"
                PAM_USER="测试用户" PAM_RHOST="192.168.1.100" notify_ssh
                echo -e "\n${GREEN}通知已发送，请检查你的Telegram${NC}"
                read -rp "按Enter键继续..."
                ;;
            3)
                echo -e "\n${YELLOW}正在发送资源监控通知(忽略阈值)...${NC}"
                # 强制发送资源通知
                FORCE_SEND="Y" monitor_usage
                echo -e "\n${GREEN}通知已发送，请检查你的Telegram${NC}"
                read -rp "按Enter键继续..."
                ;;
            4)
                echo -e "\n${YELLOW}正在发送IP变动通知...${NC}"
                # 保存当前IP以备恢复
                current_ip=""
                if [ -f "$IP_FILE" ]; then
                    current_ip=$(cat "$IP_FILE")
                    # 临时修改为其他IP以触发通知
                    echo "8.8.8.8" > "$IP_FILE"
                fi
                
                # 触发检测
                check_ip_change
                
                # 恢复真实IP
                if [ -n "$current_ip" ]; then
                    echo "$current_ip" > "$IP_FILE"
                fi
                
                echo -e "\n${GREEN}通知已发送，请检查你的Telegram${NC}"
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
        echo -e "${CYAN}1.${NC} 修改 Telegram Bot Token"
        echo -e "${CYAN}2.${NC} 修改 Telegram Chat ID"
        echo -e "${CYAN}3.${NC} ${SSH_NOTIFY == "Y" ? "禁用" : "启用"} SSH登录通知"
        echo -e "${CYAN}4.${NC} ${ENABLE_MEM_MONITOR == "Y" ? "禁用" : "启用"} 内存监控 (当前阈值: ${MEM_THRESHOLD:-90}%)"
        echo -e "${CYAN}5.${NC} ${ENABLE_CPU_MONITOR == "Y" ? "禁用" : "启用"} CPU监控 (当前阈值: ${CPU_THRESHOLD:-4})"
        echo -e "${CYAN}6.${NC} ${ENABLE_IP_CHANGE_NOTIFY == "Y" ? "禁用" : "启用"} IP变动通知"
        echo -e "${CYAN}0.${NC} 返回主菜单"
        echo ""
        read -rp "请选择 [0-6]: " choice
        
        case $choice in
            1)
                echo -e "\n${YELLOW}请输入新的 Telegram Bot Token:${NC}"
                read -rp "Token: " new_token
                if [ -n "$new_token" ]; then
                    sed -i "s/TG_BOT_TOKEN=.*$/TG_BOT_TOKEN=\"$new_token\"/" "$CONFIG_FILE"
                    echo -e "${GREEN}Token已更新${NC}"
                fi
                ;;
            2)
                echo -e "\n${YELLOW}请输入新的 Telegram Chat ID(s) (多个ID用逗号分隔):${NC}"
                read -rp "Chat ID(s): " new_ids
                if [ -n "$new_ids" ]; then
                    sed -i "s/TG_CHAT_IDS=.*$/TG_CHAT_IDS=\"$new_ids\"/" "$CONFIG_FILE"
                    echo -e "${GREEN}Chat ID已更新${NC}"
                fi
                ;;
            3)
                new_value=$([[ "$SSH_NOTIFY" == "Y" ]] && echo "N" || echo "Y")
                sed -i "s/SSH_NOTIFY=.*$/SSH_NOTIFY=\"$new_value\"/" "$CONFIG_FILE"
                
                if [ "$new_value" == "Y" ]; then
                    # 配置SSH通知
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
                    # 移除SSH通知配置
                    sed -i '/pam_exec.so.*pam_exec_notify.sh/d' /etc/pam.d/sshd
                    rm -f /etc/security/pam_exec_notify.sh
                    echo -e "${GREEN}SSH登录通知已禁用${NC}"
                fi
                ;;
            4)
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
            5)
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
            6)
                if [[ "$ENABLE_IP_CHANGE_NOTIFY" == "Y" ]]; then
                    sed -i "s/ENABLE_IP_CHANGE_NOTIFY=.*$/ENABLE_IP_CHANGE_NOTIFY=\"N\"/" "$CONFIG_FILE"
                    echo -e "${GREEN}IP变动通知已禁用${NC}"
                else
                    sed -i "s/ENABLE_IP_CHANGE_NOTIFY=.*$/ENABLE_IP_CHANGE_NOTIFY=\"Y\"/" "$CONFIG_FILE" 2>/dev/null || \
                    echo "ENABLE_IP_CHANGE_NOTIFY=\"Y\"" >> "$CONFIG_FILE"
                    # 保存当前IP作为基准
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
        # 重新加载配置
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
                echo -e "\n${GREEN}感谢使用 VPS Telegram 通知系统!${NC}"
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
    # 如果没有参数或参数是menu，显示菜单
    if [[ "$1" == "menu" || -z "$1" ]]; then
        if [ -x "$SCRIPT_PATH" ] && [ "$0" != "$SCRIPT_PATH" ]; then
            # 如果安装了系统级脚本且当前运行的不是系统脚本，则使用系统脚本
            exec "$SCRIPT_PATH" menu
        else
            # 否则显示菜单
            show_menu
        fi
    else
        # 处理其他命令行参数
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

# 执行主函数
main "$1"
