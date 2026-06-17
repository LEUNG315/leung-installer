# Architecture Overview

## 入口层

- `install.sh`：顶层入口，转发到 Linux 实现
- `internal/linux/install.sh`：主程序入口
- `bootstrap.sh`：远程 bootstrap 与 GitHub pin 下载入口

## 模块层

Linux 安装器按职责拆分为多个 shell 模块：

- `common.sh`
  - 聚合通用上下文、日志、下载、事务、测试态、回滚能力
- `detect.sh`
  - 发行版 / 包管理器 / 集群环境检测
- `deps.sh`
  - 系统依赖安装
- `node.sh`
  - Node / nvm 安装与 PATH 配置
- `config.sh`
  - 安装器状态与 CLI 原生配置写入
- `connectivity.sh`
  - URL 连通性探测
- `installers.sh`
  - CLI 安装与 Codex fallback 逻辑
- `verify.sh`
  - 配置、二进制、连通性验证
- `ui.sh` / `ui_*`
  - TTY 交互界面
- `flows*.sh`
  - 安装流程、配置流程、菜单流程、非交互流程编排

## 数据层

### 安装器状态
- `~/.leung/auth.json`
- `~/.leung/config.toml`
- `~/.leung/logs/`
- `~/.leung/backups/`
- `~/.leung/state/`

### CLI 原生配置
- Claude: `~/.claude/settings.json`
- Codex: `~/.codex/config.toml` + `~/.codex/auth.json`
- Gemini: `~/.gemini/settings.json` + `~/.gemini/.env`

## 事务与回滚

安装器通过以下机制降低失败残留：
- 备份已有文件
- 记录事务副作用
- 在失败时尝试回滚文件与副作用

这是一套 **best-effort rollback** 机制，而不是严格 ACID 事务系统。

## 验证层

当前验证层分为三层：

1. `run_regression.sh`
   - 仓库级静态/流程回归
2. `run_release_readiness.sh`
   - regression + quality + smoke 统一入口
3. `run_cli_usable_validation.sh`
   - 安装后 CLI 最小可用命令验证

## 当前边界

当前架构已经适合：
- Linux 单机 CLI 安装器
- 单次处理一个 CLI
- 可维护的 shell 模块化实现

当前还未闭环：
- 真实发行版矩阵验证
- 正式 license/分发承诺
- 真实 endpoint 驱动的全链路发布闸门
