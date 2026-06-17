# Release Process

## 当前状态

当前仓库已经具备：
- 非交互安装入口
- 基础回归、质量检查、smoke 脚本
- bootstrap pin 同步

当前仓库尚未具备：
- 自动化真实安装发布闸门
- 明确的 LICENSE
- 明确的正式分发策略与对外承诺

因此，当前状态应视为 **候选发行准备中**，而不是“已完全具备正式发行条件”。

正式发行阻塞项清单见 `RELEASE_TODOS.md`。

## 建议的正式发行入口

在阻塞项关闭前，建议对外只提供以下其中一种入口，并在 README / 手册 / CI 中保持一致：

1. `bootstrap.sh` 远程执行入口
2. GitHub Release 附件入口
3. 仓库源码入口（仅限开发/测试）

若三者同时存在，必须明确：
- 哪个是稳定入口
- 哪个是测试入口
- 哪个仅供开发者使用

## 本地发行前检查

在仓库根目录执行：

```bash
bash scripts/run_release_readiness.sh
```

该脚本当前会执行：
- regression
- quality
- smoke

建议额外执行：
- `bash scripts/run_cli_usable_validation.sh --cli <target>`

如需真实联网 smoke：

```bash
LEUNG_LIVE_SMOKE=1 \
LEUNG_LIVE_SMOKE_CLI=codex \
LEUNG_LIVE_SMOKE_URL=https://your-endpoint.example/v1 \
LEUNG_LIVE_SMOKE_API_KEY=sk-xxx \
bash scripts/run_release_readiness.sh
```

## 发布前人工确认

- README、USER_MANUAL、RELEASE_TODOS 一致
- 默认 URL 策略已经明确说明
- LICENSE 已确定
- 至少一个干净 Linux 环境完成真实安装验证
- 如声明支持多发行版/多架构，已完成对应实测

## 发布后最小追踪

建议在每次正式发布时记录：
- 发布版本或 tag
- 使用的 bootstrap pin
- 回归脚本结果
- smoke 结果
- 已知限制
