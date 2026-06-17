# CLI Usable Validation

## 目的

“基础验证”只能证明：
- 配置文件存在
- 配置值基本一致
- CLI 二进制可执行
- URL 至少可达

它**不能充分证明**：安装后的 CLI 已经达到“用户可用”。

因此仓库额外提供：

```bash
bash scripts/run_cli_usable_validation.sh --cli <claude|codex|gemini>
```

## 当前默认探针

当前默认使用的最小命令是：

- Claude Code: `claude --version`
- Codex CLI: `codex --version`
- Gemini CLI: `gemini --version`

说明：
- 这只是最小“可执行”探针
- 它比单纯检查二进制存在更强
- 但仍弱于真实模型调用成功验证

## 自定义探针

如果后续确认了更合适的最小成功命令，可以这样运行：

```bash
bash scripts/run_cli_usable_validation.sh --cli codex --cmd 'codex --help'
```

或：

```bash
LEUNG_USABLE_CLI=codex \
LEUNG_USABLE_CMD='codex --help' \
bash scripts/run_cli_usable_validation.sh
```

## 与 release gate 的关系

正式发布前建议至少完成两层验证：

1. `bash scripts/run_release_readiness.sh`
2. `bash scripts/run_cli_usable_validation.sh --cli <target>`

若存在真实 endpoint / secrets，还应继续执行 live smoke / live matrix。

## 当前未完成项

以下内容仍需后续真实环境确认：
- 每个 CLI 的最佳“最小成功命令”是否应从 `--version` 升级为更接近真实推理调用的探针
- 对接真实 endpoint 后是否应增加返回内容断言
- 是否需要针对不同 CLI 维护不同的可用性检查模板
