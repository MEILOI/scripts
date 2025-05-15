#!/bin/bash

NOTIFY_DIR="/usr/local/vps_notify"
SCRIPT_NAME="vps_notify.sh"
SERVICE_NAME="vps-notify.service"
LOGIN_SCRIPT="/etc/profile.d/vps_ssh_notify.sh"

read_config() {
  if [[ -f "$NOTIFY_DIR/config" ]]; then
    source "$NOTIFY_DIR/config"
  fi
}

write_config() {
  mkdir -p "$NOTIFY_DIR"
  cat <<EOF > "$NOTIFY_DIR/config"
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
EOF
}

install_notify_script() {
  echo -e "\n==== 安裝通知腳本 ===="
  read -p "請輸入 Telegram Bot Token: " BOT_TOKEN
  read -p "請輸入 Telegram Chat ID: " CHAT_ID
  write_config

  cat <<'EOF' > "$NOTIFY_DIR/$SCRIPT_NAME"
#!/bin/bash
source "$NOTIFY_DIR/config"

HOSTNAME=$(hostname)
PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org)
TIME=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')

MESSAGE="✅ VPS 已上線

🖥️ 主機名: <code>$HOSTNAME</code>
🌐 公網IP: <code>$PUBLIC_IP</code>
🕒 時間: <code>$TIME</code>"

curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$MESSAGE" \
    -d parse_mode="HTML"
EOF

  chmod +x "$NOTIFY_DIR/$SCRIPT_NAME"

  cat <<EOF > "/etc/systemd/system/$SERVICE_NAME"
[Unit]
Description=VPS Notify on Boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$NOTIFY_DIR/$SCRIPT_NAME

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable $SERVICE_NAME
  echo -e "\n✅ 安裝完成，已設置開機啟動通知。"
}

setup_ssh_login_notify() {
  cat <<'EOF' > "$LOGIN_SCRIPT"
#!/bin/bash
source "$NOTIFY_DIR/config"

if [[ -n "$SSH_CONNECTION" ]]; then
  IP=$(echo $SSH_CONNECTION | awk '{print $1}')
  [[ "$IP" == 172.* ]] && exit 0
  USER=$(whoami)
  HOST=$(hostname)
  TIME=$(date '+%Y年 %m月 %d日 %A %H:%M:%S %Z')

  MESSAGE="🔐 SSH 登錄通知\n\n👤 用戶: <code>$USER</code>\n🖥️ 主機: <code>$HOST</code>\n🌐 來源 IP: <code>$IP</code>\n🕒 時間: <code>$TIME</code>"

  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
      -d chat_id="$CHAT_ID" \
      -d text="$MESSAGE" \
      -d parse_mode="HTML"
fi
EOF
  chmod +x "$LOGIN_SCRIPT"
}

modify_config() {
  read_config
  echo -e "\n==== 修改通知配置 ===="
  read -p "當前 Bot Token [$BOT_TOKEN]，請輸入新的（回車跳過）: " NEW_TOKEN
  read -p "當前 Chat ID [$CHAT_ID]，請輸入新的（回車跳過）: " NEW_CHAT
  BOT_TOKEN="${NEW_TOKEN:-$BOT_TOKEN}"
  CHAT_ID="${NEW_CHAT:-$CHAT_ID}"
  write_config
  echo "✅ 配置已更新。"
}

uninstall_all() {
  echo -e "\n⚠️ 確定要卸載通知腳本？(y/n): "
  read confirm
  if [[ "$confirm" != "y" ]]; then
    echo "取消卸載。"
    return
  fi
  systemctl disable $SERVICE_NAME &>/dev/null
  rm -f "/etc/systemd/system/$SERVICE_NAME"
  rm -f "$LOGIN_SCRIPT"
  rm -rf "$NOTIFY_DIR"
  systemctl daemon-reload
  echo "✅ 已卸載所有通知腳本。"
}

main_menu() {
  while true; do
    echo -e "\nVPS 通知腳本管理器"
    echo "============================"
    echo "1) 安裝通知腳本"
    echo "2) 修改 TG 配置"
    echo "3) 卸載通知腳本"
    echo "0) 退出"
    echo "============================"
    read -p "請輸入選項 [0-3]: " opt

    case $opt in
      1) install_notify_script && setup_ssh_login_notify ;;
      2) modify_config ;;
      3) uninstall_all ;;
      0) exit 0 ;;
      *) echo "❌ 無效選項，請重新輸入。" ;;
    esac
  done
}

main_menu
