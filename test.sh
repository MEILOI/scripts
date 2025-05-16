#!/bin/bash

CONFIG_FILE="/etc/vps_notify.conf"

# 检查配置文件是否存在
echo "=== 检查配置文件 ==="
if [ -f "$CONFIG_FILE" ]; then
  echo "✅ 配置文件存在"
  echo "配置文件内容:"
  cat "$CONFIG_FILE"
else
  echo "❌ 配置文件不存在，请先安装脚本"
  exit 1
fi

# 加载配置
source "$CONFIG_FILE"

# 检查配置项
echo -e "\n=== 检查配置项 ==="
if [ -z "$TG_BOT_TOKEN" ]; then
  echo "❌ Telegram Bot Token未设置"
  exit 1
else
  echo "✅ Telegram Bot Token已设置"
fi

if [ -z "$TG_CHAT_IDS" ]; then
  echo "❌ Telegram Chat ID未设置"
  exit 1
else
  echo "✅ Telegram Chat ID已设置: $TG_CHAT_IDS"
fi

# 测试网络连接
echo -e "\n=== 测试网络连接 ==="
echo "测试连接Telegram API服务器:"
if curl -s -m 10 "https://api.telegram.org/bot$TG_BOT_TOKEN/getMe" | grep -q "ok"; then
  echo "✅ 成功连接到Telegram API服务器"
else
  echo "❌ 无法连接到Telegram API服务器"
  echo "可能原因: Bot Token无效、网络连接问题或防火墙限制"
  
  # 检查是否能访问telegram.org
  if curl -s -m 5 "https://telegram.org" > /dev/null; then
    echo "✅ 可以访问telegram.org"
  else
    echo "❌ 无法访问telegram.org，请检查网络连接或防火墙设置"
  fi
fi

# 测试发送消息
echo -e "\n=== 测试发送消息 ==="
TG_API="https://api.telegram.org/bot"
TEST_MESSAGE="🧪 这是一条测试消息，时间: $(date '+%Y-%m-%d %H:%M:%S')"

echo "尝试发送测试消息..."
IFS=',' read -ra IDS <<< "$TG_CHAT_IDS"
for id in "${IDS[@]}"; do
    echo "发送到Chat ID: $id"
    RESPONSE=$(curl -s -X POST "${TG_API}${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="$id" \
        -d text="$TEST_MESSAGE" \
        -d parse_mode="Markdown")
    echo "响应: $RESPONSE"
    
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo "✅ 消息发送成功"
    else
        echo "❌ 消息发送失败"
        if echo "$RESPONSE" | grep -q "chat not found"; then
            echo "错误原因: Chat ID无效"
        elif echo "$RESPONSE" | grep -q "bot was blocked by the user"; then
            echo "错误原因: 用户已屏蔽机器人"
        fi
    fi
done

# 检查系统服务状态
echo -e "\n=== 检查系统服务状态 ==="
echo "检查vps_notify服务状态:"
systemctl status vps_notify.service
echo ""

echo "检查定时任务:"
if grep -q "vps_notify.sh monitor" /etc/crontab; then
  echo "✅ 定时任务已配置"
  grep "vps_notify.sh monitor" /etc/crontab
else
  echo "❌ 定时任务未配置"
fi

# 检查SSH通知配置
echo -e "\n=== 检查SSH通知配置 ==="
if [ "$SSH_NOTIFY" == "Y" ]; then
  echo "SSH通知已启用"
  
  if [ -f "/etc/security/pam_exec_notify.sh" ]; then
    echo "✅ PAM执行脚本存在"
    cat "/etc/security/pam_exec_notify.sh"
  else
    echo "❌ PAM执行脚本不存在"
  fi
  
  if grep -q "pam_exec.so" /etc/pam.d/sshd; then
    echo "✅ PAM配置已设置"
    grep "pam_exec.so" /etc/pam.d/sshd
  else
    echo "❌ PAM配置未设置"
  fi
else
  echo "SSH通知未启用"
fi

echo -e "\n=== 诊断完成 ==="
echo "如果以上测试都通过，但仍无法收到通知，请检查:"
echo "1. 确保您已在Telegram中与Bot进行了对话"
echo "2. 确保Bot有发送消息的权限"
echo "3. 检查/var/log/syslog中是否有相关错误日志"
