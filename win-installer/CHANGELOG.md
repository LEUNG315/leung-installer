# CHANGELOG

## v1.1.0 (2026-06-14)

### 问题修复

#### 1. GUI 中文字体无法正常显示

**问题描述**：  
WinForms GUI 界面中的中文字符显示为方块或乱码。

**原因**：  
窗体字体硬编码为 `Segoe UI`，该字体在部分 Windows 系统上缺少中文字形回退（font fallback），导致 CJK 字符无法渲染。

**修复方案**：  
优先使用 `Microsoft YaHei UI`（微软雅黑），这是 Windows 自带的中文字体。当系统不存在该字体时自动回退到 `Segoe UI`。

**涉及文件**：`internal/windows/gui.ps1`

---

#### 2. PowerShell 报错"在此系统上禁止运行脚本"

**问题描述**：  
用户通过 `irm https://static.leung315.site/install-win.ps1 | iex` 远程安装时，下载到本地的 `.ps1` 子脚本被 Windows 的 ExecutionPolicy 拦截，报错：
> 无法加载文件 xxx.ps1，因为在此系统上禁止运行脚本。

**原因**：  
Windows PowerShell 默认的 ExecutionPolicy 为 `Restricted`，禁止运行所有 `.ps1` 脚本文件。虽然 `irm | iex` 本身以内存方式执行不受限制，但安装过程中 dot-source (`. lib\xxx.ps1`) 加载子脚本时会触发策略检查。此外，从互联网下载的文件会被标记 Zone.Identifier（NTFS 备用数据流），即使策略为 `RemoteSigned` 也会阻止未签名的外部脚本。

**修复方案**：  
新增 `remote-install.ps1` 远程引导脚本，解决三层问题：

| 层级 | 问题 | 解决方式 |
|------|------|----------|
| irm \| iex 入口 | 不受 ExecutionPolicy 限制 | 无需处理（内存执行） |
| 下载的 .ps1 被标记为"来自互联网" | Zone.Identifier ADS 触发阻止 | `Unblock-File` 移除标记 |
| 子进程运行 .ps1 脚本 | ExecutionPolicy 拦截 | 以 `powershell -ExecutionPolicy Bypass` 启动 |
| 后续用户使用 npm CLI | npm 安装的 .ps1 shim 无法运行 | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |

**涉及文件**：`remote-install.ps1`（新增）、`internal/windows/lib/common.ps1`（已有 `Set-PsExecutionPolicyIfNeeded`）

---

### 新增文件

- `remote-install.ps1` — 远程安装引导脚本，用户通过 `irm url | iex` 使用
- `CHANGELOG.md` — 本文件

### 版本号变更

- `inno/setup.iss`: `1.0.0` → `1.1.0`

---

## v1.0.0 (2026-06-13)

初始版本。支持 Codex CLI / Claude Code / Gemini CLI 的安装与 LEUNG API 中转配置。
