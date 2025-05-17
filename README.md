VPS Notify (tgvsdd2.sh)

tgvsdd2.sh 是一个功能强大的 VPS 监控和通知脚本，支持 Telegram 和 DingTalk 通知，帮助用户实时监控 VPS 的 IP 变动、SSH 登录、系统资源使用情况以及开机状态。相比早期版本（tgvsdd1.sh），本脚本增加了多渠道通知、交互式菜单、自动化安装、更新功能、钉钉加签支持和更健壮的错误处理，适合 Linux VPS（Debian/Ubuntu/CentOS 等）。
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
用户友好的彩色界面，支持安装、配置、测试通知、检查状态、卸载和更新脚本。


自动化安装：
自动配置 systemd 服务（开机通知）和 cron 任务（每5分钟监控）。
集成 SSH 登录通知（通过 PAM）。
自动安装依赖（curl、grep、awk、openssl 等）。


日志管理：
记录所有操作和错误到 /var/log/vps_notify.log。
自动归档日志，限制大小为 1MB。


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

这将下载脚本、设置可执行权限并启动交互式菜单。

选择安装：

在菜单中选择 1. 安装/重新安装。
按照提示配置通知渠道（Telegram/DingTalk）、主机备注和监控选项。
如果使用钉钉加签，输入 DINGTALK_SECRET。
脚本会自动完成 systemd 服务、cron 任务和 SSH 通知的设置。


验证安装：

检查服务状态：systemctl status vps_notify.service


查看日志：cat /var/log/vps_notify.log





使用说明
交互式菜单
运行 ./tgvsdd2.sh 进入主菜单，支持以下选项：

1. 安装/重新安装：配置并安装脚本。
2. 配置设置：修改通知渠道、阈值、备注或钉钉加签。
3. 测试通知：发送测试通知（开机、SSH、资源、IP 变动）。
4. 检查系统状态：查看服务、cron 和日志状态。
5. 卸载：删除脚本和所有相关文件。
6. 更新脚本：从 GitHub 下载最新版本，保留配置和服务。
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


如果 Webhook 失效（例如错误 300005）：
删除机器人并重新创建。
确认群组存在且你有权限。
退出钉钉客户端并重新登录，刷新配置.
尝试在另一设备（例如手机）创建机器人。
在新群组中创建机器人测试。





故障排除

语法错误：
运行 bash -n tgvsdd2.sh 检查语法。
确保脚本从 GitHub 下载完整，未被截断。


通知失败：
检查 /var/log/vps_notify.log 中的错误信息：cat /var/log/vps_notify.log | grep ERROR


Telegram：
验证 Token 和 Chat ID 是否正确。
确保 VPS 可以访问 api.telegram.org：curl -I https://api.telegram.org




DingTalk：
验证 Webhook 是否有效：timestamp=$(date +%s%3N)
secret="<你的secret>"
string_to_sign="${timestamp}\n${secret}"
sign=$(echo -n "$string_to_sign" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | tr -d '\n')
curl -s -X POST "https://oapi.dingtalk.com/robot/send?access_token=<你的token>×tamp=${timestamp}&sign=${sign}" \
    -H "Content-Type: application/json" \
    -d '{"msgtype": "text", "text": {"content": "VPS 测试消息"}}'


如果使用加签，验证 DINGTALK_SECRET 是否正确：cat /etc/vps_notify.conf | grep DINGTALK_SECRET


脚本验证逻辑（validate_dingtalk）：
使用完整 Webhook URL，不修改 access_token。
如果启用加签，附加 timestamp 和 sign（HMAC-SHA256）。
不对 access_token 加密或编码，直接传递。


常见错误码：
300005：token is not exist - Webhook 失效、token 错误或 IP 限制：
确认群组存在且你有权限。
删除旧机器人，重新创建 Webhook。
检查 Webhook URL 是否完整（64 位 access_token）。
确保未输入嵌套 URL（如 access_token=完整的URL）。
退出钉钉客户端并重新登录，刷新配置。
尝试在其他群组或设备创建机器人。
检查 VPS IP 是否被限制：curl -s4m 3 ip.sb


从另一设备（例如个人电脑）测试 Webhook。
添加 VPS IP 到机器人白名单。
使用代理绕过限制：apt install -y tinyproxy




联系钉钉客服，确认 IP 限制或服务器同步：
提供 VPS IP、Webhook URL（部分隐藏）、错误信息和测试时间。




400：无效的 access_token - 检查 Webhook URL 是否正确。
403：关键词或 IP 不在白名单 - 确保消息包含关键词（如“VPS”）或添加 VPS IP：curl -s4m 3 ip.sb


310000：消息内容为空或格式错误 - 确保消息包含 content 字段。
42001：access_token 过期 - 重新生成 Webhook。
加签错误：签名不匹配 - 验证 DINGTALK_SECRET 和系统时间：timedatectl
ntpdate pool.ntp.org




确保 VPS 可以访问 oapi.dingtalk.com：curl -I https://oapi.dingtalk.com


多 VPS 测试：
在多台 VPS 上测试相同 Webhook，记录每台的 IP 和输出。
如果所有 VPS 失败，尝试在非 VPS 设备（例如个人电脑）测试。
如果仅 VPS 失败，可能是 IP 限制或云服务商范围限制。






依赖缺失：
手动安装：apt update && apt install -y curl grep gawk systemd coreutils openssl




IP 获取失败：
检查网络连接：curl -s4m 3 ip.sb


确保 VPS 支持 IPv4/IPv6（视需求）。


更新脚本失败：
检查 GitHub 连通性：curl -I https://raw.githubusercontent.com/meiloi/scripts/main/tgvsdd2.sh


查看日志：cat /var/log/vps_notify.log | grep update




时间同步（加签相关）：
确保系统时间与钉钉服务器同步（误差 < 1 小时）：timedatectl
ntpdate pool.ntp.org




群组权限：
确认你是钉钉群组管理员。
如果群组配置异常，创建新群组测试。


客户端同步问题：
退出钉钉客户端并重新登录。
在另一设备（例如手机）检查机器人配置.


其他问题：
提交 issue 到 GitHub 仓库（meiloi/scripts）。
提供日志输出、Webhook 测试结果和错误信息。



示例日志
/var/log/vps_notify.log
[2025-05-17 11:00:00] Installation completed
[2025-05-17 11:05:00] Sent boot notification
[2025-05-17 11:10:00] IP changed from 192.168.1.1 to 192.168.1.2
[2025-05-17 11:15:00] ERROR: Invalid DingTalk webhook: {"errcode":300005,"errmsg":"token is not exist"}

贡献
欢迎提交 Pull Request 或 Issue 来改进脚本！请遵循以下步骤：

Fork 仓库。
创建新分支（git checkout -b feature/xxx）。
提交更改（git commit -m "Add xxx feature"）。
推送分支（git push origin feature/xxx）。
创建 Pull Request。

变更日志

v2.7 (2025-05-17)：
更新 README，补充 validate_dingtalk 验证逻辑说明，明确不加密 access_token。
添加多 VPS 测试指南，优化 300005 错误排查。


v2.6：
补充钉钉 IP 限制的测试方法、代理配置指南和联系客服步骤。
优化 300005 错误排查，添加 IP 限制场景。


v2.5：
补充加签测试的完整示例、钉钉客户端同步问题排查和 300005 错误的更多场景。
强调加签请求必须包含 timestamp 和 sign。


v2.4：
补充正确的 Webhook 输入格式、常见输入错误示例（如嵌套 URL）和钉钉机器人管理注意事项。
优化 300005 错误排查，添加 URL 格式检查。


v2.3：
补充详细钉钉机器人创建步骤、加签调试和 300005 错误的多场景解决方法。
优化故障排除，添加群组权限和 Webhook 混淆的检查。


v2.2：
新增钉钉加签支持（DINGTALK_SECRET），兼容“加签”安全策略。
增强 validate_dingtalk 和 send_dingtalk，支持签名验证和详细错误日志。


v2.1：
新增“更新脚本”功能（菜单选项 6），支持从 GitHub 自动下载最新版本。
增强钉钉通知错误处理，添加重试机制和详细日志。


v2.0：
初始优化版本，修复 get_ip 语法错误，添加交互式菜单和多渠道通知。



许可
本项目采用 MIT 许可证。使用时请遵守相关法律法规，脚本仅限学习和个人使用。
致谢

感谢所有测试和反馈的用户。
灵感来源于社区的 VPS 监控脚本项目。

