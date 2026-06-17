# installers

这是一个统一管理多套安装器与相关分发工具的仓库。

当前仓库已经不是单一的 `linux-installer` 项目，而是一个集中放置多个 installer 子项目的总仓。

## 目录结构

```text
installers/
  README.md
  bundle-private/
  linux-installer/
  mac-installer/
  tempo-installer/
  win-installer/
  windows-usb-install/
```

## 各目录说明

### `linux-installer/`
Linux 平台安装器。

主要用途：
- 安装 Claude Code / Codex CLI / Gemini CLI
- 写入对应配置文件
- 支持交互式与非交互式安装
- 提供 smoke / regression / release readiness 脚本

入口参考：
- `linux-installer/README.md`
- `linux-installer/install.sh`

### `mac-installer/`
macOS 平台安装器。

主要用途：
- 为 macOS 提供安装与配置脚本
- 生成发布站点所需的安装包与远程启动脚本

入口参考：
- `mac-installer/install.sh`
- `mac-installer/release-site/INSTALLER_GUIDE.md`

### `win-installer/`
Windows 平台安装器。

主要用途：
- 安装 Node.js / Codex CLI / Claude Code / Gemini CLI
- 写入 Windows 侧配置
- 支持自检、日志与若干安装策略开关

入口参考：
- `win-installer/install.ps1`
- `win-installer/CHANGELOG.md`

### `tempo-installer/`
偏临时/专项用途的 Windows 安装器目录。

当前主要包含：
- `windows-installer/` 下的一套 Windows 安装脚本
- 与 VM 共享目录同步有关的脚本

入口参考：
- `tempo-installer/windows-installer/README.md`
- `tempo-installer/windows-installer/install.ps1`

### `windows-usb-install/`
Windows USB / Ventoy / WinPE 相关制作与安装辅助目录。

主要用途：
- Windows 安装 U 盘流程辅助
- WinPE / QEMU / Ventoy 相关脚本和材料
- 本地缓存、镜像构建、同步辅助

说明：
- 该目录下很多内容是体积较大的本地产物
- 当前总仓 `.gitignore` 已忽略大体积缓存和备份目录

入口参考：
- `windows-usb-install/run_windows_usb_qemu_install.sh`
- `windows-usb-install/sync-to-ventoy.sh`

### `bundle-private/`
安装器相关的私有出包与管理工具目录。

主要用途：
- 管理每月用户配置
- 管理 API Key 原始输入材料
- 生成加密后的 installer bundle

说明：
- `secrets/` 与本地私有数据不会进入版本控制
- 相关忽略规则已在仓库顶层 `.gitignore` 中配置

入口参考：
- `bundle-private/README.md`
- `bundle-private/scripts/publish_month.sh`

## 仓库约定

### 1. 这是总仓
本仓库用于集中管理多个 installer 子项目。

因此：
- 平台级安装器可以分别维护在各自子目录
- 公共说明、根级规范与整体结构在仓库根目录维护

### 2. 大文件与本地产物不直接入库
当前根 `.gitignore` 已忽略例如：
- `windows-usb-install/project-cache/`
- `windows-usb-install/ventoy-backup/`
- `mac-installer/release-packages/`
- `linux-installer/dist/`
- 常见大镜像文件（如 `*.iso`、`*.img`、`*.wim`）

新增大体积本地产物时，优先先补忽略规则。

### 3. 私有数据不入库
例如：
- `bundle-private/secrets/`
- `bundle-private/users.json`

这些内容默认为本地私有数据，不应直接提交。

## 建议使用方式

如果你只关心单个平台：
- Linux：进入 `linux-installer/`
- macOS：进入 `mac-installer/`
- Windows：进入 `win-installer/` 或对应专项目录

如果你关心整体发布链路：
- 先看各子目录 README
- 再结合 `bundle-private/` 和 `release-site/` 相关脚本理解分发流程

## 当前状态

远端仓库 `LEUNG315/leung-installer` 当前已经承载这一总仓结构，而不是旧的单一 installer 结构。
