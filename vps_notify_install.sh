#!/bin/bash

#=====================
# VPS 一键通知脚本（支持 Telegram 通知、SSH 登录提示、资源监控）
# 支持 HTML 消息格式，多用户推送
#=====================

install_script() {
  echo "正在安装依赖组件..."
  apt update -y && apt install -y curl jq lsof net-tools > /dev/null 2>&1

  echo "请输入 Telegram Bot Token："
  read -rp "BOT_TOKEN: " BOT_TOKEN
  echo "请输入接收通知的 Telegram 用户或频道 ID（多个用逗号分隔）："
  read -rp "CHAT_IDS: " CHAT_IDS

  echo "是否启用 SSH 登录通知？(y/n): "
  read -rp "SSH_NOTIFY: " SSH_NOTIFY

  echo "是否启用内存占用监控（超过90%通知）？(y/n): "
  read -rp "MEMORY_MONITOR: " MEMORY_MONITOR

  echo "是否启用 CPU 负载监控（Load > 2 通知）？(y/n): "
  read -rp "CPU_MONITOR: " CPU_MONITOR

  cat <<EOF > /usr/local/bin/vps_notify.sh
#!/bin/bash
BOT_TOKEN="${BOT_TOKEN}"
CHAT_IDS="${CHAT_IDS}"
HOSTNAME=\$(hostname)
DATETIME=\$(date '+%Y年 %m月 %d日 %A %T %Z')
IPV4=\$(curl -4s --max-time 3 ip.sb || echo "獲取失敗")
IPV6=\$(curl -6s --max-time 3 ip.sb || echo "獲取失敗")

MSG="✅ <b>VPS 已上線</b>\n\n<b>🖥️ 主機名:</b> 
