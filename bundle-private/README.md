# bundle-private

本地私有仓库：
- 存放明文 `*_apikey.md`
- 存放每月用户分配配置 `users.json`
- 在仓库内直接完成管理员加密出包
- 默认把加密后的 bundle 输出到 `../installer/dist/<YYYY-MM>/`

## 目录结构

```text
bundle-private/
  scripts/
    build_to_installer_dist.sh
    publish_month.sh
    menu.sh
    hash_password.sh
    test_bundle_to_installer_flow.sh
    test_all_bundle_flows.sh
  tools/
    admin_bundle/
      build_monthly_bundles.py
      open_cli_bundle.py
      bundle_crypto.py
      password_codec.py
  secrets/
    2026-05/
      codex_apikey.md
      gemini_apikey.md
      claude_apikey.md
      opencode_apikey.md
      users.json
```

## 简化后的输入约定

每个月只需要两类输入：
- `secrets/<month>/*_apikey.md`
- `secrets/<month>/users.json`

其中：
- `*_apikey.md` 里只要能匹配出 API Key 即可，允许带标题、列表、备注
- `users.json` 必须直接提供每个用户的明文 `password`
- `password_hash` 仍可保留，用于校验明文 `password` 是否写对
- 不再依赖 `passwords.env` / `password_env`

`users.json` 示例：

```json
{
  "cli_defaults": {
    "codex": {
      "base_url": "https://gateway.example.com/v1",
      "model": "gpt-5.4"
    }
  },
  "users": [
    {
      "name": "alice",
      "password": "pw-alice",
      "password_hash": "pbkdf2_sha256$...",
      "allowed_clis": ["codex"]
    }
  ]
}
```


## 一键发布

最推荐的月度命令：

```bash
bash scripts/publish_month.sh 2026-05
```

如果你不想记多个脚本，也可以直接打开统一菜单：

```bash
bash scripts/menu.sh
```

它会自动执行：
- 先批量 dry-run 测试当月所有 CLI
- 全部通过后，再正式出包到 `../installer/dist/<month>/`

只发布部分 CLI：

```bash
bash scripts/publish_month.sh 2026-05 --cli codex --cli gemini
```

如果你确认前面的测试已经做过，也可以跳过测试直接出包：

```bash
bash scripts/publish_month.sh 2026-05 --skip-tests
```

如果希望顺手把 `installer/dist/<month>/` 加入 git：

```bash
bash scripts/publish_month.sh 2026-05 --git-add
```

如果希望顺手提交：

```bash
bash scripts/publish_month.sh 2026-05 --git-commit
```

## 构建

默认构建某个月全部 bundle：

```bash
bash scripts/build_to_installer_dist.sh 2026-05
```

只构建某个 CLI：

```bash
bash scripts/build_to_installer_dist.sh 2026-05 --cli codex
```

如果要先输出到别处测试：

```bash
OUTPUT_ROOT=/tmp/bundle-out bash scripts/build_to_installer_dist.sh 2026-05
```

说明：
- 该脚本现在直接调用 `bundle-private/tools/admin_bundle/build_monthly_bundles.py`
- 默认会追加 `--verify`，构建后会用 `users.json` 里的密码逐个回读 bundle

## 端到端干跑验证

```bash
bash scripts/test_bundle_to_installer_flow.sh 2026-05 --cli codex
```

特点：
- 默认选择该 CLI 的第一个可用用户
- 默认直接读取 `users.json` 中该用户的 `password`
- 会先出包，再用对应密码解包一次
- 然后调用 `../installer/install.sh --bundle-mode` 做 dry-run
- 最后校验 installer 写入的 `~/.leung/auth.json` / `config.toml` 元数据是否和解包结果一致

保留临时产物便于排查：

```bash
bash scripts/test_bundle_to_installer_flow.sh 2026-05 --cli codex --keep-artifacts
```


批量测试当前月份所有 CLI：

```bash
bash scripts/test_all_bundle_flows.sh 2026-05
```

只测试部分 CLI：

```bash
bash scripts/test_all_bundle_flows.sh 2026-05 --cli codex --cli gemini
```

特点：
- 默认自动扫描 `secrets/<month>/*_apikey.md`
- 逐个调用 `test_bundle_to_installer_flow.sh`
- 最后输出 pass/fail 汇总
- 任一 CLI 失败时整体返回非 0


## 生成 password_hash

```bash
bash scripts/hash_password.sh '你的密码'
```


## 推荐操作顺序

最省心：

```bash
bash scripts/menu.sh
```

或直接一键：

```bash
bash scripts/publish_month.sh 2026-05 --git-commit
```

建议顺序：
1. 准备 `secrets/<month>/*_apikey.md` 和 `users.json`
2. 先跑 `test_all_bundle_flows.sh` 做批量 dry-run
3. 再跑 `publish_month.sh` 正式出包
4. 如需记录发布结果，可加 `--git-add` 或 `--git-commit`
