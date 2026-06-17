# Versioning Policy

## 当前状态

仓库当前尚未形成严格版本号制度，但已经具备：
- bootstrap pin 同步
- release notes 文件
- repo 内 release readiness 流程

## 建议的版本规则

正式发行前建议采用以下最小规则：

- 破坏性变更：主版本递增
- 向后兼容功能：次版本递增
- bugfix / 文档 / CI 调整：补丁版本递增

## 每次发行至少记录

- 版本号或 tag
- bootstrap pin commit
- bootstrap archive SHA256
- 本次 release readiness 结果
- 已知限制

## Release Notes 最小结构

建议每次发行记录：
- Added
- Changed
- Fixed
- Risks / Known Limits

## 当前未完成项

- 仓库中尚无自动版本注入机制
- `RELEASE_NOTES.md` 仍需演化为版本化记录
- 尚未建立 release asset checksum 产出流程
