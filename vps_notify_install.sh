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

MSG="✅ <b>VPS 已上線</b>\n\n<b>🖥️ 主機名:</b> \${HOSTNAME}\n<b>🌐 公網IP:</b>\nIPv4: \${IPV4}\nIPv6: \${IPV6}\n<b>🕒 時間:</b> \${DATETIME}"

for ID in \$(echo \${CHAT_IDS} | tr ',' ' '); do
  curl -s -X POST "https://api.telegram.org/bot\${BOT_TOKEN}/sendMessage" \
    -d chat_id="\${ID}" \
    -d parse_mode="HTML" \
    -d text="\${MSG}"
  sleep 1
done
EOF

  chmod +x /usr/local/bin/vps_notify.sh
  echo '@reboot /usr/local/bin/vps_notify.sh' | crontab -l 2>/dev/null | grep -q 'vps_notify.sh' || (crontab -l 2>/dev/null; echo '@reboot /usr/local/bin/vps_notify.sh') | crontab -

  if [[ "\$SSH_NOTIFY" == "y" ]]; then
    cat <<EOF > /etc/profile.d/ssh_notify.sh
#!/bin/bash
BOT_TOKEN="${BOT_TOKEN}"
CHAT_IDS="${CHAT_IDS}"
USER=\$(whoami)
HOST=\$(hostname)
SRC_IP=\$(who | awk '{print \$5}' | tr -d '()')
TIME=\$(date '+%Y年 %m月 %d日 %A %T %Z')

MSG="🔐 <b>SSH 登錄通知</b>\n\n<b>👤 用戶:</b> \${USER}\n<b>🖥️ 主機:</b> \${HOST}\n<b>🌐 來源 IP:</b> \${SRC_IP}\n<b>🕒 時間:</b> \${TIME}"

for ID in \$(echo \${CHAT_IDS} | tr ',' ' '); do
  curl -s -X POST "https://api.telegram.org/bot\${BOT_TOKEN}/sendMessage" \
    -d chat_id="\${ID}" \
    -d parse_mode="HTML" \
    -d text="\${MSG}"
  sleep 1
done
EOF
    chmod +x /etc/profile.d/ssh_notify.sh
  fi

  if [[ "\$MEMORY_MONITOR" == "y" ]]; then
    echo "*/5 * * * * free | awk '/Mem/{if(\$3/\$2>0.9) print \"Memory Alert: \" \$3/\$2}' | grep -q 'Memory Alert' && /usr/local/bin/vps_notify.sh" | crontab -
  fi

  if [[ "\$CPU_MONITOR" == "y" ]]; then
    echo "*/5 * * * * uptime | awk -F'load average:' '{print \$2}' | awk -F',' '{if(\$1>2.0) print \"CPU Load Alert: \" \$1}' | grep -q 'CPU Load Alert' && /usr/local/bin/vps_notify.sh" | crontab -
  fi

  echo "✅ 安装完成！支持開機通知、SSH提示、資源監控！"
}

uninstall_script() {
  rm -f /usr/local/bin/vps_notify.sh /etc/profile.d/ssh_notify.sh
  crontab -l | grep -v 'vps_notify.sh' | crontab -
  echo "✅ 已卸載通知腳本與相關任務"
}

case "$1" in
  install)
    install_script
    ;;
  uninstall)
    uninstall_script
    ;;
  *)
    echo "使用方法: bash $0 install | uninstall"
    ;;
esac
