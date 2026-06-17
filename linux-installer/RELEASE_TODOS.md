# Release TODOs

本清单用于判断 linux-installer 是否达到“可对外正式发行”的标准。

## 阻塞项（未完成前不建议正式发行）

- [ ] 建立真实发布闸门
  - 在干净 Linux 环境执行真实安装，不使用 `--dry-run`
  - 覆盖 `claude` / `codex` / `gemini`
  - 作为发布前必跑流程，而非仅手动抽查

- [~] 把验证从“网络可达”升级到“CLI 可用”
  - 不只检查 `/models`
  - 已增加 `scripts/run_cli_usable_validation.sh` 作为最小可用命令验证入口
  - 仍需在真实环境中为三种 CLI 实跑并确认最佳探针

- [ ] 明确正式分发入口
  - 统一用户安装入口（bootstrap / release asset / repo script）
  - 保证 README、用户手册、CI、release 流程一致

- [ ] 选择并补齐 LICENSE
  - 当前仓库未声明明确许可证
  - 该项涉及法律/分发边界，需仓库所有者明确决定

- [ ] 明确默认 URL 产品策略
  - 解释 `api.leung315.site` / `api.leung315.site/v1` 的定位
  - 说明默认 URL 是否为官方网关、代理或私有服务
  - 说明默认 URL 不可用时的替代路径

- [ ] 做兼容性实测矩阵
  - 至少覆盖主流 Linux 发行版
  - 覆盖 `x86_64` / `aarch64`（若声称支持）
  - 覆盖当前声明支持的包管理器

## 高优先级（强烈建议发行前完成）

- [x] 建立 repo 内可追踪的发行清单
- [x] 建立统一的 release-readiness 本地脚本入口
- [x] 在 CI 中复用统一的 release-readiness 入口
- [x] 完善发布元数据
  - 版本号规则
  - changelog / release notes 规范
  - 发布校验和输出
  - bootstrap pin 与 release/tag 关系说明

- [x] 补齐发行文档
  - 安装方式
  - 升级方式
  - 回滚方式
  - 常见故障排查
  - 日志路径说明

- [x] 补安全说明
  - API Key 写入哪些文件
  - 文件权限预期
  - 敏感信息是否进入日志
  - 如何安全清理本地配置

- [x] 增强 CI 覆盖
  - 将真实 smoke 纳入受控发布流程
  - 增加多发行版验证
  - 增加失败日志归档

- [x] 校验发布索引/分发面是否真的启用
  - 发现 `dist/index.json` 为空且无生成/消费链路
  - 已按“未启用残留”处理并删除

## 中优先级（建议 1.0 前后尽快补齐）

- [x] 补用户支持边界
- [x] 优化错误提示
- [x] 增加 fallback / proxy / rollback 回归用例
- [x] 再扫一遍旧分发概念残留并统一术语

## 可后置

- [x] FAQ
- [ ] 终端录屏 / 截图
- [x] 更细的架构说明
