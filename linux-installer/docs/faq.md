# FAQ

## 1. 这个安装器是否已经完全可正式发行？
还没有。当前仓库已经具备发行准备文档、回归脚本、CI 骨架，但仍存在外部依赖型阻塞项，例如：
- LICENSE 选择
- 真实发布闸门
- 真实兼容矩阵
- 默认 URL 产品策略定稿

详见 `RELEASE_TODOS.md`。

## 2. 为什么默认 URL 不是官方公共 API？
当前默认 URL 指向仓库维护者提供的既定地址。是否将其视为正式默认入口、代理入口或私有网关，仍需在正式发行前明确。

## 3. 如果默认 URL 不可用怎么办？
可在交互流程或非交互模式中覆盖 URL，例如：
```bash
bash install.sh --noninteractive --cli codex --api-key sk-xxx --url https://your-proxy.example/v1
```

## 4. 安装器会把 API Key 写到哪里？
见 `docs/security.md`。

## 5. 如何验证安装结果？
最小验证顺序：
```bash
bash scripts/run_release_readiness.sh
bash scripts/run_cli_usable_validation.sh --cli codex
```

## 6. 如何做真实联网验证？
配置真实环境变量后，运行：
```bash
bash scripts/run_live_smoke_matrix.sh
```

## 7. 如果安装失败怎么办？
先查看：
- `~/.leung/logs/`
- `docs/operations.md`

再检查：
- URL 是否可达
- npm / Node 是否正常
- 是否存在失效代理配置
