# CLI Config Paths

| CLI | 主配置文件 | 附加配置文件 |
| --- | --- | --- |
| Claude Code | `~/.claude/settings.json` | 无 |
| Codex CLI | `~/.codex/config.toml` | `~/.codex/auth.json` |
| Gemini CLI | `~/.gemini/settings.json` | `~/.gemini/.env` |

## Claude Code
- API Key 与 URL 写入 `env` 字段

## Codex CLI
- URL / model 写入 `~/.codex/config.toml`
- API Key 写入 `~/.codex/auth.json`

## Gemini CLI
- model 写入 `~/.gemini/settings.json`
- API Key / URL 写入 `~/.gemini/.env`
