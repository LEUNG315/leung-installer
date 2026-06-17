# linux-installer

一个面向 **Linux** 的轻量交互式安装器，用于安装并配置以下 CLI：

- Claude Code
- Codex CLI
- Gemini CLI

核心能力：
- 安装目标 CLI
- 写入 `auth.json`、`config.toml` 及各 CLI 原生配置文件
- 用户输入 API Key
- 默认使用对应官方 URL
- 支持手动改 URL
- 安装后执行基础验证

## 快速开始

### 本地运行
```bash
bash install.sh
```

### 非交互示例
```bash
bash install.sh --noninteractive --cli codex --api-key sk-xxx
bash install.sh --noninteractive --cli gemini --api-key sk-xxx --url https://your-proxy.example/v1
```

## 默认 URL

- Claude Code: `https://api.leung315.site`
- Codex CLI: `https://api.leung315.site/v1`
- Gemini CLI: `https://api.leung315.site/v1`

安装时会自动带入默认值；如果你走代理/中转，也可以在安装确认阶段或高级选项里改成自定义 URL。

## 会写入哪些文件

安装器状态文件：
- `~/.leung/auth.json`
- `~/.leung/config.toml`

CLI 原生配置文件：
- Claude: `~/.claude/settings.json`
- Codex: `~/.codex/config.toml` + `~/.codex/auth.json`
- Gemini: `~/.gemini/settings.json` + `~/.gemini/.env`

## 高级选项

提供以下维护入口：
- 手动覆盖 API Key
- 手动覆盖 URL
- 重新生成并写入配置
- 仅安装 CLI（不写配置）
- 测试安装（内置测试 Key）
- 查看配置状态 / 最近日志
- 清理安装器缓存


## 发行准备状态

当前仓库已具备基础安装、配置写入、回归/质量/smoke 脚本，但**尚未完成全部正式发行阻塞项**。

- 发行清单：`RELEASE_TODOS.md`
- 发行流程说明：`docs/release-process.md`
- 统一检查入口：`bash scripts/run_release_readiness.sh`

## 发行与支持文档

- 发行流程：`docs/release-process.md`
- 分发策略：`docs/distribution-strategy.md`
- 版本策略：`docs/versioning-policy.md`
- 安全说明：`docs/security.md`
- 支持矩阵：`docs/support-matrix.md`
- 运维说明：`docs/operations.md`
- FAQ：`docs/faq.md`
- 架构说明：`docs/architecture.md`

## 测试

```bash
bash scripts/run_smoke.sh
bash scripts/run_cli_usable_validation.sh --cli codex
```
