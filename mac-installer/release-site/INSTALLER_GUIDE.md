# LEUNG Installer 发布说明与使用指南

## 1. 内容简介
本发布包包含 LEUNG 三个平台安装器：

- Linux 安装器：`linux-installer.tar.gz`
- macOS 安装器：`mac-installer.tar.gz`
- Windows 安装器：`win-installer.zip`

以及网站端远程启动脚本：

- `install-linux.sh`
- `install-mac.sh`
- `install-win.ps1`

这些脚本的作用是：

1. 从你的网站或 CDN 下载对应平台的安装器压缩包
2. 在本地临时目录解压
3. 自动启动真实安装程序

---

## 2. 推荐网站部署结构
建议把以下文件放到同一个静态目录，例如：

```text
https://static.your-domain.com/installers/
  ├── linux-installer.tar.gz
  ├── mac-installer.tar.gz
  ├── win-installer.zip
  ├── install-linux.sh
  ├── install-mac.sh
  └── install-win.ps1
```

---

## 3. 发布前需要修改的内容
当前脚本内默认占位地址为：

```text
https://static.example.com/installers
```

正式发布前，请替换成你的真实静态文件地址。

需要修改的文件：

- `install-linux.sh`
- `install-mac.sh`
- `install-win.ps1`

将其中的：

```text
https://static.example.com/installers
```

替换为例如：

```text
https://static.leung315.site/installers
```

---

## 4. 用户使用方式

### Linux
用户执行：

```bash
curl -fsSL https://your-site/install-linux.sh | bash
```

### macOS
用户执行：

```bash
curl -fsSL https://your-site/install-mac.sh | bash
```

### Windows
用户执行：

```powershell
irm https://your-site/install-win.ps1 | iex
```

---

## 5. 文件作用说明

### `linux-installer.tar.gz`
Linux 完整安装器归档，包含安装逻辑、模板、脚本及资源。

### `mac-installer.tar.gz`
macOS 完整安装器归档，包含安装逻辑、模板、脚本及资源。

### `win-installer.zip`
Windows 完整安装器归档，包含 PowerShell 安装逻辑与资源。

### `install-linux.sh` / `install-mac.sh`
Shell 启动器：

- 下载压缩包
- 解压到临时目录
- 执行安装器入口 `install.sh`

### `install-win.ps1`
PowerShell 启动器：

- 下载 zip 包
- 解压到临时目录
- 自动 `Unblock-File`
- 用 `ExecutionPolicy Bypass` 启动 `install.ps1`

---

## 6. 推荐发布流程

1. 生成三平台安装器归档
2. 上传归档包到静态站点/CDN
3. 上传三个远程启动脚本
4. 修改脚本中的 `BASE_URL`
5. 分别在 Linux / macOS / Windows 上做一次真实下载安装测试

---

## 7. 推荐测试命令

### Linux
```bash
curl -fsSL https://your-site/install-linux.sh | bash
```

### macOS
```bash
curl -fsSL https://your-site/install-mac.sh | bash
```

### Windows
```powershell
irm https://your-site/install-win.ps1 | iex
```

---

## 8. 注意事项

1. Windows 远程脚本依赖 PowerShell 5.1+
2. Linux/macOS 远程脚本依赖 `curl` 或 `wget`
3. 安装器首次运行可能会联网下载依赖或 CLI 组件
4. 若面向中国大陆用户，建议静态文件放在大陆友好 CDN 或对象存储后面
5. 若希望最稳，建议发布时同时附带各平台 bundles

---

## 9. 当前发布物目录
当前已整理到外挂硬盘目录：

```text
/run/media/leung/Ventoy/leung-installers
```

