# linux-installer 用户手册

## 1. 这个安装器做什么
它用于在 Linux 上安装并配置：
- Claude Code
- Codex CLI
- Gemini CLI

它会帮你：
1. 选择一个 CLI
2. 输入 API Key
3. 自动带入默认 URL，并允许你手动修改
4. 安装 CLI
5. 写入配置文件
6. 做基础验证

## 2. 启动方式
```bash
bash install.sh
```

## 3. 主菜单
1. 安装并配置 CLI
2. 查看 CLI 配置详情
3. 验证已安装 CLI
4. 高级选项
5. 退出

## 4. 默认 URL
- Claude Code: `https://api.leung315.site`
- Codex CLI: `https://api.leung315.site/v1`
- Gemini CLI: `https://api.leung315.site`

如果你使用代理/中转服务，可以在安装确认阶段选择“修改 URL”，或在高级选项里单独改。

## 5. 会写到哪里
安装器状态文件：
- `~/.leung/auth.json`
- `~/.leung/config.toml`

CLI 原生配置文件：
- Claude: `~/.claude/settings.json`
- Codex: `~/.codex/config.toml` + `~/.codex/auth.json`
- Gemini: `~/.gemini/settings.json` + `~/.gemini/.env`

## 6. 高级选项
你可以在高级选项里：
- 修改 API Key
- 修改 URL
- 重建配置文件
- 仅安装 CLI 本体
- 运行测试安装
- 查看配置状态
- 查看最近日志
- 清理缓存

## 7. 非交互模式
```bash
bash install.sh --noninteractive --cli codex --api-key sk-xxx
bash install.sh --noninteractive --cli claude --api-key sk-xxx --url https://your-proxy.example
```

## 8. 验证
安装完成后，安装器会检查：
- 配置文件是否存在
- 配置值是否一致
- CLI 是否可执行
- URL 连通性是否正常

## 9. 发行与支持说明
- 当前正式发行阻塞项见 `RELEASE_TODOS.md`
- 发行流程说明见 `docs/release-process.md`
- 安全说明见 `docs/security.md`
- 支持矩阵见 `docs/support-matrix.md`
- 分发策略见 `docs/distribution-strategy.md`
- 运维说明见 `docs/operations.md`
- FAQ 见 `docs/faq.md`
- 架构说明见 `docs/architecture.md`
