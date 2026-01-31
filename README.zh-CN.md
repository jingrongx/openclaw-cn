# 🦞 OpenClaw CN — 个人 AI 助手 (中文增强版)

<p align="center">
    <picture>
        <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/openclaw/openclaw/main/docs/assets/openclaw-logo-text-dark.png">
        <img src="https://raw.githubusercontent.com/openclaw/openclaw/main/docs/assets/openclaw-logo-text.png" alt="OpenClaw" width="500">
    </picture>
</p>

**OpenClaw CN** 是 OpenClaw 的中文增强版本，为中国用户提供更好的使用体验，并集成了国内主流的通信渠道和大模型提供商。

## 🎯 特性增强

### 🇨🇳 全面中文化
- ✅ **Web UI 汉化**：完整的中文用户界面
- ✅ **中文文档**：安装指南、配置说明和使用教程
- ✅ **本地化体验**：针对中文用户优化的交互设计

### 🤖 新增大模型支持
- ✅ **DeepSeek**：完整支持 DeepSeek API
  - `deepseek-chat` (V3.2 非思考模式)
  - `deepseek-reasoner` (V3.2 思考模式)
  - 完全兼容 OpenAI API 格式
  - 极具竞争力的价格

### 💬 新增通信渠道

#### 已实现
- 🔵 **企业渠道**（基于官方 API）
  - 钉钉 (DingTalk)
  - 飞书 (Feishu/Lark)
  - 企业微信 (WeChat Work)

#### 计划中
- 🟡 **个人渠道**（基于 OneBot 协议）
  - 微信（通过 OneBot 适配器如 Gewechat）
  - QQ（通过 OneBot 适配器如 NapCatQQ）
  - 华为畅连（开发中）

> **注意**：个人微信和 QQ 需要运行独立的 OneBot 客户端。推荐方案：
> - **QQ**: [NapCatQQ](https://github.com/NapNeko/NapCatQQ), [Lagrange](https://github.com/LagrangeDev/Lagrange.Core)
> - **微信**: [Gewechat](https://github.com/Devo919/Gewechat)

## 核心功能 (继承自 OpenClaw)

- **多渠道消息支持**：连接 WhatsApp、Telegram、Slack、Discord、Google Chat、Signal、iMessage、WebChat 等
- **本地优先网关**：统一的控制平面，管理会话、渠道、工具和事件
- **语音唤醒与对话**：支持 macOS/iOS/Android 上的语音交互
- **实时画布**：代理驱动的可视化工作空间
- **浏览器控制**：通过 Chrome/Chromium 实现网页自动化
- **技能平台**：可扩展的技能系统，支持自定义工具

[完整功能列表](https://docs.openclaw.ai)

## 快速开始

### 环境要求
- **Node.js** ≥ 22
- **操作系统**: macOS, Linux, Windows (推荐 WSL2)

### 安装

推荐使用一键安装脚本（支持 macOS 和 Linux/WSL）：

```bash
SHARP_IGNORE_GLOBAL_LIBVIPS=0 curl -fsSL https://daokedao.space/install.sh | bash
```

### 卸载

```bash
# 卸载所有组件
openclaw uninstall --all

# 清理残留文件 (如果需要)
find / \( -path /mnt -prune \) -o \( -name openclaw -print \)
```

### 常用命令

```bash
# 查看版本，确认命令已在 PATH 中
openclaw --version

# 运行自检工具，这是最全面的验证方式
openclaw doctor

# 自动修复常见问题
openclaw doctor --fix

# 查看网关服务状态
systemctl --user status openclaw-gateway

# 查看最近的日志并实时滚动（按 Ctrl+C 退出）
journalctl --user -u openclaw-gateway -f

# 查看最后 50 行日志
journalctl --user -u openclaw-gateway -n 50

# 启动网关服务 (systemd)
systemctl --user start openclaw-gateway

# 停止网关服务 (systemd)
systemctl --user stop openclaw-gateway

# 重启网关服务 (systemd)
systemctl --user restart openclaw-gateway

# 查看网关状态 (systemd)
systemctl --user status openclaw-gateway

# 直接启动网关 (前台运行)
openclaw gateway

# 运行配置向导 (初始化或重新配置)
openclaw onboard
```

### 故障排除

如果遇到服务无法启动、配置错误或奇怪的 bug，建议进行完整重置：

**1. 运行配置向导进行重置**

```bash
openclaw onboard
```

在菜单中选择 **"配置处理方式" -> "重置 (Reset)" -> "完整重置 (配置 + 凭证 + 会话 + 工作区)"**。

![重置配置](docs/assets/troubleshoot-reset.png)

这将清除所有本地状态，让你从头开始。

**2. 重新安装服务**

如果问题依旧，可以在向导中选择 **"服务管理" -> "重新安装 (Reinstall)"**。

![重新安装服务](docs/assets/troubleshoot-reinstall.png)

这将重新注册 systemd 服务，解决潜在的权限或路径问题。

> **WSL 用户注意**：
> 如果在 WSL 中遇到 `systemctl` 相关错误（如 System has not been booted with systemd as init system），可能是您的 WSL 版本或配置未启用 systemd。
> 1. 确保使用 WSL 2。
> 2. 在 `/etc/wsl.conf` 中添加以下内容并重启 WSL (wsl --shutdown)：
> ```ini
> [boot]
> systemd=true
> ```

### DeepSeek 配置示例

在 `~/.openclaw/openclaw.json` 中添加：

```json
{
  "models": {
    "providers": {
      "deepseek": {
        "baseUrl": "https://api.deepseek.com/v1",
        "apiKey": "${DEEPSEEK_API_KEY}",
        "api": "openai-responses",
        "models": [
          {
            "id": "deepseek-chat",
            "name": "DeepSeek Chat",
            "contextWindow": 64000,
            "maxTokens": 8000
          },
          {
            "id": "deepseek-reasoner",
            "name": "DeepSeek Reasoner (思考模式)",
            "reasoning": true,
            "contextWindow": 64000,
            "maxTokens": 8000
          }
        ]
      }
    }
  },
  "agent": {
    "model": "deepseek/deepseek-chat"
  }
}
```

或使用环境变量：

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxx
```

### 启动网关

```bash
# 启动网关
openclaw gateway --port 18789 --verbose

# 发送消息
openclaw agent --message "你好，请介绍一下自己" --model deepseek/deepseek-chat
```

## 文档

- 📘 [DeepSeek 配置指南](docs/zh-CN/deepseek-guide.md)
- 📘 [钉钉配置指南](docs/zh-CN/dingtalk-guide.md) *(即将推出)*
- 📘 [飞书配置指南](docs/zh-CN/feishu-guide.md) *(即将推出)*
- 📘 [官方文档](https://docs.openclaw.ai) (英文)

## 价格优势

DeepSeekV3.2 定价（/百万 tokens）：

| 模型 | 输入 | 输出 | 缓存读 | 缓存写 |
|------|------|------|--------|--------|
| deepseek-chat | $0.14 | $0.28 | $0.014 | $0.14 |
| deepseek-reasoner | $0.55 | $2.19 | - | - |

**相比 Claude 和 GPT 系列，DeepSeek 价格仅为其几分之一，同时性能优异！**

## 安全性

- **默认安全**：DM 配对机制，未知发送者需要批准
- **沙箱模式**：支持 Docker 沙箱运行非主会话
- **权限控制**：基于白名单的渠道访问控制

详见 [安全指南](https://docs.openclaw.ai/gateway/security)

## 贡献

欢迎提交 Pull Request！查看 [CONTRIBUTING.md](CONTRIBUTING.md) 了解贡献指南。

## 开源协议

MIT License - 详见 [LICENSE](LICENSE)

## 致谢

- 感谢 [OpenClaw 官方团队](https://github.com/openclaw/openclaw)
- 感谢 Peter Steinberger 和社区贡献者
- 特别感谢 DeepSeek 提供优秀的开源大模型

## 链接

- [OpenClaw 官网](https://openclaw.ai)
- [官方文档](https://docs.openclaw.ai)
- [Discord 社区](https://discord.gg/clawd)
- [GitHub 仓库](https://github.com/openclaw/openclaw)

---

**⚠️ 注意**: 本项目是 OpenClaw 的社区增强版本，主要面向中文用户。如需使用原版 OpenClaw，请访问 [官方仓库](https://github.com/openclaw/openclaw)。
