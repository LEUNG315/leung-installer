# Distribution Strategy

## 当前状态

仓库目前存在两个实际分发面：

1. `install.sh` / 仓库源码运行
2. `bootstrap.sh` 远程 bootstrap

其中：
- `install.sh` 适合本地开发、测试、仓库内运行
- `bootstrap.sh` 更接近正式对外入口

此前仓库中曾存在 `dist/index.json` 空索引文件，但当前并无生成、发布、消费链路，因此不应继续保留为“假能力”。

## 当前建议

在正式发行前：
- 将 `bootstrap.sh` 视为候选稳定入口
- 将仓库源码入口视为开发/测试入口
- 不保留未启用的索引式分发残留

## 对外说明建议

README / 用户手册 / release notes 应统一说明：
- 稳定入口是什么
- 测试入口是什么
- 是否依赖 GitHub 下载链路
- 默认 URL 是什么，以及何时需要覆盖

## 与 bootstrap pin 的关系

当前 CI 已维护 bootstrap pin 同步。正式发行时应额外记录：
- 对应 tag / commit
- bootstrap pin 指向
- archive checksum
- 是否允许 live main

## 清理结论

`dist/index.json` 已被判定为未启用残留：
- 当前无生产价值
- 当前无测试覆盖价值
- 当前无对外分发价值

因此在仓库内应删除该文件，避免误导后续维护者。
