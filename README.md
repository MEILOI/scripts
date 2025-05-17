VPS Notify (tgvsdd2.sh)

tgvsdd2.sh 是一个功能强大的 VPS 监控和通知脚本，支持 Telegram 和 DingTalk 通知，帮助用户实时监控 VPS 的 IP 变动、SSH 登录、系统资源使用情况以及开机状态。相比早期版本（tgvsdd1.sh），本脚本增加了多渠道通知、交互式彩色菜单、自动化安装、更新功能、钉钉加签支持和更健壮的错误处理，适合 Linux VPS（Debian/Ubuntu/CentOS 等）。
功能特性

多渠道通知：
支持 Telegram 和 DingTalk 通知，可单独或同时启用。
通知内容包括开机、SSH 登录、IP 变动和资源警报。


公网 IP 监控：
实时获取 IPv4 和 IPv6 地址，使用多个后备服务（ip.sb、ifconfig.me、ipinfo.io、api.ipify.org）。
检测 IP 变动并发送通知。


资源监控：
监控 CPU、内存和磁盘使用率，支持自定义阈值。
限制警报频率（6小时内不重复），避免通知轰炸。


交互式彩色菜单：
用户友好的彩色界面（黄色标题，绿色选项），支持安装、配置、测试通知、检查状态、卸载和更新脚本。
自动检测终端颜色支持，提示设置 TERM=xterm-256color。


自动化安装：
自动配置 systemd 服务（开机通知）和 cron 任务（每5分钟监控）。
集成 SSH 登录通知（通过 PAM）。
自动安装依赖（curl、grep、awk、openssl 等）。


日志管理：
记录所有操作和错误到 /var/log/vps_notify.log。
自动归档日志，限制大小为 1MB。
屏蔽敏感信息（如 DingTalk access_token）。


灵活配置：
通过 /etc/vps_notify.conf 管理配置，支持动态修改。
支持自定义主机备注（REMARK）。
支持钉钉加签（DINGTALK_SECRET）。


脚本更新：
支持从 GitHub 自动下载最新版本，保留现有配置和服务。



依赖

系统：Debian、Ubuntu、CentOS 或其他支持 bash 的 Linux 系统。
命令：curl、grep、awk、systemctl、df、openssl（脚本会自动尝试安装）。
网络：需要访问 raw.githubusercontent.com 和通知服务 API（Telegram/DingTalk）。

安装

下载并运行脚本：
curl -o tgvsdd2.sh -fsSL https://raw.githubusercontent.com/meiloi/scripts/main/tgvsdd2.sh && chmod +x tgvsdd2.sh && ./tgvsdd2.sh

这将下载脚本、设置可执行权限并启动交互式彩色菜单。

选择安装：

在菜单中选择 1. 安装/重新安装。
按照提示配置通知渠道（Telegram/DingTalk）、主机备注和监控选项。
如果使用钉钉加签，输入 DINGTALK_SECRET。
脚本会自动完成 systemd 服务、cron 任务和 SSH 通知的设置。


验证安装：

检查服务状态：systemctl status vps_notify.service


查看日志：cat /var/log/vps_notify.log





使用说明
交互式彩色菜单
运行 ./tgvsdd2.sh 进入主菜单，支持以下选项：

1. 安装/重新安装：配置并安装脚本。
2. 配置设置：修改通知渠道、阈值、备注或钉钉加签。
3. 测试通知：发送测试通知（开机、SSH、资源、IP 变动）。
4. 检查系统状态：查看服务、cron 和日志状态。
5. 卸载：删除脚本和所有相关文件。
6. 更新脚本：从 GitHub 下载最新版本，保留配置和服务。
0. 退出：退出脚本。

菜单使用黄色标题和绿色选项编号，确保直观易读。如果菜单无颜色，运行：
export TERM=xterm-256color
./tgvsdd2.sh

命令行模式
支持以下命令：
./tgvsdd2.sh [command]


install：安装脚本。
uninstall：卸载脚本。
boot：发送开机通知。
ssh：发送 SSH 登录通知（由 PAM 调用）。
monitor：运行资源监控（由 cron 调用）。
menu：显示交互式菜单（默认）。

配置管理
配置文件位于 /etc/vps_notify.conf，包含：

通知设置（ENABLE_TG_NOTIFY、TG_BOT_TOKEN、TG_CHAT_IDS、ENABLE_DINGTALK_NOTIFY、DINGTALK_WEBHOOK、DINGTALK_SECRET）。
监控选项（ENABLE_MEM_MONITOR、MEM_THRESHOLD、ENABLE_CPU_MONITOR、CPU_THRESHOLD、ENABLE_DISK_MONITOR、DISK_THRESHOLD、ENABLE_IP_CHANGE_NOTIFY）。
主机备注（REMARK）。

通过菜单的“配置设置”选项或手动编辑文件修改配置。
获取 Telegram/DingTalk 配置

Telegram：
在 Telegram 中搜索 @BotFather，发送 /start。
发送 /newbot 创建机器人，获取 TG_BOT_TOKEN（格式如 123456789:ABCDEF...）。
发送 /mybots，选择机器人，启用 Inline Mode（可选）。
获取 TG_CHAT_IDS：
私聊：将机器人加入聊天，发送消息后通过 API（如 curl https://api.telegram.org/bot<TOKEN>/getUpdates）获取 Chat ID。
群组：将机器人加入群组，获取群组 Chat ID（以 - 开头）。




DingTalk：
打开钉钉群组，进入“群设置” > “智能群助手” > “自定义机器人”。
检查现有机器人：
删除所有失效或不相关的机器人（避免 Webhook 混淆）。


创建新机器人：
点击“添加机器人” > 选择“自定义机器人”。
输入机器人名称（例如“VPS Notify”）。
选择安全设置（至少选一种）：
自定义关键词（推荐）：输入关键词如“VPS”或“通知”，消息需包含关键词。
加签：复制 secret（以 SEC 开头），在脚本配置中输入。
IP 地址：添加 VPS 公网 IP（运行 curl -s4m 3 ip.sb 获取）。


点击“完成”，复制 Webhook URL（格式如 https://oapi.dingtalk.com/robot/send?access_token=xxx）。
注意：只复制完整 Webhook URL，不要仅复制 access_token 或嵌套 URL。


验证 Webhook：
不带加签：curl -s -X POST "https://oapi.dingtalk.com/robot/send?access_token=<你的token>" \
    -H "Content-Type: application/json" \
    -d '{"msgtype": "text", "text": {"content": "VPS 测试消息"}}'


带加签：timestamp=$(date +%s%3N)
secret="<你的secret>"
string_to_sign="${timestamp}\n${secret}"
sign=$(echo -n "$string_to_sign" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | tr -d '\n')
curl -s -X POST "https://oapi.dingtalk.com/robot/send?access_token=<你的token>×tamp=${timestamp}&sign=${sign}" \
    -H "Content-Type: application/json" \
    -d '{"msgtype": "text", "text": {"content": "VPS 测试消息"}}'


正确返回：{"errcode":0,"errmsg":"ok"}
群组应收到消息：“VPS 测试消息”。





故障排除

彩色菜单不显示：
检查终端类型：echo $TERM


应为 xterm-256color 或类似。若不支持，设置：export TERM=xterm-256color


永久设置：echo "export TERM=xterm-256color" >> ~/.bashrc
source ~/.bashrc




检查终端颜色支持：tput colors


应返回 256 或 8。


确认 SSH 客户端（例如 PuTTY、OpenSSH）启用颜色：
PuTTY：设置 > 连接 > 数据 > 终端类型为 xterm-256color。


测试颜色：echo -e "\033[0;32m绿色测试\033[0m"




语法错误：
运行 bash -n tgvsdd2.sh 检查语法：bash -n tgvsdd2.sh


如果报错，确保脚本不包含非法标记：grep -n "<xaiArtifact" tgvsdd2.sh


下载正确版本：curl -o tgvsdd2.sh -fsSL https://raw.githubusercontent.com/meiloi/scripts/main/tgvsdd2.sh




通知失败：
检查 /var/log/vps_notify.log：cat /var/log/vps_notify.log | grep ERROR


Telegram：
验证 Token 和 Chat ID。
确保 VPS 可访问 api.telegram.org：curl -I https://api.telegram.org




DingTalk：
验证 Webhook：timestamp=$(date +%s%3N)
secret="<你的secret>"
string_to_sign="${timestamp}\n${secret}"
sign=$(echo -n "$string_to_sign" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | tr -d '\n')
curl -s -X POST "https://oapi.dingtalk.com/robot/send?access_token=<你的token>×tamp=${timestamp}&sign=${sign}" \
    -H "Content-Type: application/json" \
    -d '{"msgtype": "text", "text": {"content": "VPS 测试消息"}}'


检查 DINGTALK_SECRET：cat /etc/vps_notify.conf | grep DINGTALK_SECRET


常见错误：
300005：token is not exist - Webhook 失效或 IP 限制：
删除并重新创建机器人。
确认群组存在且你有权限。
检查 VPS IP：curl -s4m 3 ip.sb


从个人设备测试 Webhook。
联系钉钉客服，提供 IP、Webhook（部分隐藏）、错误和测试时间。








依赖缺失：
手动安装：apt update && apt install -y curl grep gawk systemd coreutils openssl




时间同步（加签相关）：
确保系统时间同步：timedatectl
ntpdate pool.ntp.org





示例日志
/var/log/vps_notify.log
[2025-05-17 11:47:00] Color support enabled (TERM=xterm-256color)
[2025-05-17 11:47:00] Installation completed
[2025-05-17 11:48:00] DingTalk notification sent on attempt 1 for https://oapi.dingtalk.com/robot/send?access_token=[hidden]: ...

贡献
欢迎提交 Pull Request 或 Issue！步骤：

Fork 仓库。
创建分支（git checkout -b feature/xxx）。
提交更改（git commit -m "Add xxx feature"）。
推送分支（git push origin feature/xxx）。
创建 Pull Request。注意：确保脚本仅包含纯 Bash 代码，无非法标记。

变更日志

v2.9 (2025-05-17)：
增强彩色菜单（黄色标题，绿色选项编号）。
添加终端颜色支持检测，提示设置 TERM=xterm-256color。
优化日志，记录颜色支持状态。


v2.8：
添加 DingTalk 验证/发送重试机制（3 次）。
增强日志，屏蔽 access_token。


v2.7：
补充 validate_dingtalk 逻辑说明。


v2.2：
新增钉钉加签支持。


v2.1：
新增脚本更新功能。


v2.0：
初始优化版本，添加菜单和多渠道通知。



许可
本项目采用 MIT 许可证。仅限学习和个人使用。
致谢
感谢所有测试和反馈的用户！
