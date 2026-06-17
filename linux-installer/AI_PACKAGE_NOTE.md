# AI Package Note - linux-installer

## Purpose
这是一个 Linux 轻量安装器，面向终端用户安装并配置以下三种 AI CLI：
- Claude Code
- Codex CLI
- Gemini CLI

每次流程处理一个 CLI，完成：
1. 选择 CLI
2. 输入 API Key
3. 使用默认 URL 或手动改 URL
4. 安装 CLI
5. 写入安装器状态文件与 CLI 原生配置
6. 执行基础验证

## Public entrypoint
- `install.sh`
- 实际转发到 `internal/linux/install.sh`

## State files
安装器状态：
- `~/.leung/auth.json`
- `~/.leung/config.toml`

CLI 原生配置：
- Claude -> `~/.claude/settings.json`
- Codex -> `~/.codex/config.toml` + `~/.codex/auth.json`
- Gemini -> `~/.gemini/settings.json` + `~/.gemini/.env`

## Defaults
默认 URL：
- Claude: `https://api.leung315.site`
- Codex: `https://api.leung315.site/v1`
- Gemini: `https://api.leung315.site`

允许用户在安装流程或高级选项中覆盖 URL。

## Constraints
- Linux only
- 每次只处理一个 CLI
- 保持中文 TTY 交互
- 保持配置写入路径稳定
- 优先小改动，避免重写整个安装器骨架
