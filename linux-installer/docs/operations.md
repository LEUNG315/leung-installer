# Operations Guide

## 安装入口

当前仓库支持两类入口：

1. 仓库内运行：
   ```bash
   bash install.sh
   ```
2. 非交互运行：
   ```bash
   bash install.sh --noninteractive --cli codex --api-key sk-xxx
   ```

正式稳定分发入口仍需按 `docs/distribution-strategy.md` 定稿。

## 升级建议

当前仓库尚未实现单独的“升级命令”，建议升级流程为：

1. 获取最新安装器代码或最新 bootstrap
2. 重新执行安装流程
3. 让安装器重新写入目标 CLI 配置
4. 执行：
   ```bash
   bash scripts/run_release_readiness.sh
   ```
   或至少执行内置验证流程

## 回滚

当前仓库已实现事务与回滚相关逻辑，但仍建议把回滚视为“尽力恢复”，而不是对外保证的强一致事务系统。

可用方式：
- 交互菜单中的手动回滚入口
- test-mode 自动恢复测试态

发布前建议补充：
- 回滚覆盖范围的明确说明
- 哪些文件一定恢复，哪些只做 best effort

## 常见故障排查

### 1. URL 连不通
- 检查 DNS / TLS / 代理
- 使用安装器内置连通性检查
- 若默认 URL 不可用，改成自定义 URL

### 2. npm 安装失败
- 检查 Node/npm 是否可用
- 检查网络、镜像、代理设置
- 检查本地 npm proxy 是否残留无效 localhost 配置

### 3. CLI 已安装但不可执行
- 检查 PATH
- 检查全局 npm prefix
- 对 Codex 检查是否走了 release fallback 路径

### 4. 配置写入后 CLI 仍异常
- 检查原生配置文件内容
- 检查 model / URL / API Key 是否一致
- 检查是否存在旧配置残留覆盖

## 日志位置

重点关注：
- `~/.leung/logs/`
- `~/.leung/backups/`
- `~/.leung/summary/`（若存在对应汇总输出）

如需仓库级验证：
```bash
bash scripts/run_regression.sh
bash scripts/run_quality.sh
bash scripts/run_smoke.sh
```

统一入口：
```bash
bash scripts/run_release_readiness.sh
```

## 受控真实验证

如已配置真实环境变量，可运行：
```bash
bash scripts/run_live_smoke_matrix.sh
```

若只验证单个 CLI：
```bash
bash scripts/run_live_smoke_matrix.sh codex
```

## 相关阅读
- FAQ：`docs/faq.md`
- 架构说明：`docs/architecture.md`
