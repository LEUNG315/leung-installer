# Codex API Keys Example

这个文件是给月度 bundle / 发布工具做演示用的 markdown 示例。
发布工具会从正文里提取形如 `sk-...` 的 key。

## 使用说明

- 每行一个 key 最清晰
- 可以混合说明文字，提取器会自动扫描正文
- 重复 key 会被去重
- 不要把真实生产 key 提交到公开仓库

## Example Keys

sk-codex-demo-alpha-001
sk-codex-demo-beta-002
sk-codex-demo-alpha-001

## Mixed Text Example

下面这段说明里也包含一个可被提取的 key：sk-codex-demo-gamma-003

