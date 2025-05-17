VPS Notify (tgvsdd2.sh)

tgvsdd2.sh 是一个功能强大的 VPS 监控和通知脚本，支持 Telegram 和 DingTalk 通知，帮助用户实时监控 VPS 的 IP 变动、SSH 登录、系统资源使用情况以及开机状态。相比早期版本（tgvsdd1.sh），本脚本增加了多渠道通知、交互式菜单、自动化安装和更健壮的错误处理，适合 Linux VPS（Debian/Ubuntu/CentOS 等）。
功能特性

多渠道通知：
支持 Telegram 和 DingTalk 通知，可单独或同时启用。
通知内容包括开机、SSH 登录、IP 变动和资源警报。


公网 IP 监控：
实时获取 IPv4 和 IPv6 地址，使用多个后备服务（ip.sb、ifconfig.me、ipinfo.io、ipify.org）。
检测 IP 变动并发送通知。


资源监控：
监控 CPU、内存和磁盘使用率，支持自定义阈值。
限制警报频率（6小时内不重复），避免通知轰炸。


交互式菜单：
用户友好的彩色界面，支持安装、配置、测试通知、检查状态和卸载。


自动化安装：
自动配置 systemd 服务（开机通知）和 cron 任务（每5分钟监控）。
集成 SSH 登录通知（通过 PAM）。
自动安装依赖（curl、grep、awk 等）。


日志管理：
记录所有操作和错误到 /var/log/vps_notify.log。
自动归档日志，限制大小为 1MB。


灵活配置：
通过 /etc/vps_notify.conf 管理配置，支持动态修改。
支持自定义主机备注（REMARK）。



依赖

系统：Debian、Ubuntu、CentOS 或其他支持 bash 的 Linux 系统。
命令：curl、grep、awk、systemctl、df（脚本会自动尝试安装）。
网络：需要访问 raw.githubusercontent.com 和通知服务 API（Telegram/DingTalk）。

安装

下载并运行脚本：
curl -o tgvsdd2.sh -fsSL https://raw.githubusercontent.com/meiloi/scripts/main/tgvsdd2.sh && chmod +x tgvsdd2.sh && ./tgvsdd2.sh

这将下载脚本、设置可执行权限并启动交互式菜单。

选择安装：

在菜单中选择 1. 安装/重新安装。
按照提示配置通知渠道（Telegram/DingTalk）、主机备注和监控选项。
脚本会自动完成 systemd 服务、cron 任务和 SSH 通知的设置。


验证安装：

检查服务状态：systemctl status vps_notify.service


查看日志：cat /var/log/vps_notify.log





使用说明
交互式菜单
运行 ./tgvsdd2.sh 进入主菜单，支持以下选项：

1. 安装/重新安装：配置并安装脚本。
2. 配置设置：修改通知渠道、阈值或备注。
3. 测试通知：发送测试通知（开机、SSH、资源、IP 变动）。
4. 检查系统状态：查看服务、cron 和日志状态。
5. 卸载：删除脚本和所有相关文件。
0. 退出：退出脚本。

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

通知设置（ENABLE_TG_NOTIFY、TG_BOT_TOKEN、TG_CHAT_IDS、ENABLE_DINGTALK_NOTIFY、DINGTALK_WEBHOOK）。
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
在钉钉群组中添加自定义机器人，获取 DINGTALK_WEBHOOK。
复制 Webhook URL（如 https://oapi.dingtalk.com/robot/send?access_token=xxx）。



故障排除

语法错误：
运行 bash -n tgvsdd2.sh 检查语法。
确保脚本从 GitHub 下载完整，未被截断。


通知失败：
检查 /var/log/vps_notify.log 中的错误信息。
验证 Telegram/DingTalk 配置（Token、Chat ID、Webhook）。
确保 VPS 可以访问 api.telegram.org 和 oapi.dingtalk.com。


依赖缺失：
手动安装：apt update && apt install -y curl grep gawk systemd coreutils




IP 获取失败：
检查网络连接：curl -s4m 3 ip.sb


确保 VPS 支持 IPv4/IPv6（视需求）。


其他问题：
提交 issue 到 GitHub 仓库（meiloi/scripts）。
提供日志输出和错误信息。



示例日志
/var/log/vps_notify.log
[2025-05-17 08:00:00] Installation completed
[2025-05-17 08:05:00] Sent boot notification
[2025-05-17 08:10:00] IP changed from 192.168.1.1 to 192.168.1.2

贡献
欢迎提交 Pull Request 或 Issue 来改进脚本！请遵循以下步骤：

Fork 仓库。
创建新分支（git checkout -b feature/xxx）。
提交更改（git commit -m "Add xxx feature"）。
推送分支（git push origin feature/xxx）。
创建 Pull Request。

许可
本项目采用 MIT 许可证。使用时请遵守相关法律法规，脚本仅限学习和个人使用。
致谢

感谢所有测试和反馈的用户。
灵感来源于社区的 VPS 监控脚本项目。

