# Security Notes

## API Key 写入位置

安装器会把 API Key 写入以下位置：

- 安装器状态：`~/.leung/auth.json`
- Claude Code：`~/.claude/settings.json`
- Codex CLI：`~/.codex/auth.json`
- Gemini CLI：`~/.gemini/.env`

同时，URL / model 等非密钥配置会写入：

- 安装器状态：`~/.leung/config.toml`
- Codex CLI：`~/.codex/config.toml`
- Gemini CLI：`~/.gemini/settings.json`
- Claude Code：`~/.claude/settings.json`

## 文件权限预期

仓库当前实现会在写配置前确保目标目录存在，但**尚未建立单独的权限审计流程**。

发布前建议人工确认：
- API Key 所在文件仅当前用户可读写
- 日志目录不暴露敏感配置副本
- 备份目录权限不宽于原文件

## 日志与敏感信息

当前实现目标是：
- 正常用户提示不直接回显完整 API Key
- 日志以流程步骤和错误为主

但在正式发行前，仍应人工审查以下内容：
- `internal/linux/lib/*.sh`
- `internal/linux/bin/config_helper.py`
- `~/.leung/logs/` 中的实际输出

确认：
- 不会把完整 API Key 打进日志
- 不会在失败栈中泄露 Bearer Token
- 不会在调试输出中泄露用户 URL 上附带的敏感查询参数

## 安全清理建议

如需清理本地配置，至少应删除：

- `~/.leung/`
- `~/.claude/settings.json`
- `~/.codex/config.toml`
- `~/.codex/auth.json`
- `~/.gemini/settings.json`
- `~/.gemini/.env`

正式发行前建议补齐：
- 一键安全清理说明
- 回滚后残留文件说明
- 敏感文件权限检查命令示例

## 当前未完成项

以下安全相关事项仍未完全关闭：

- 未形成正式的权限/日志审计报告
- 未形成对外安全承诺文档
- 未形成 secrets 泄露自动扫描闸门
- 未形成真实发行前的安全检查 checklist
