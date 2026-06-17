; LEUNG Codex Installer - Inno Setup Script
; Compile with Inno Setup 6.x: iscc setup.iss

#define MyAppName "LEUNG CLI Installer"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "LEUNG315"
#define MyAppURL "https://api.leung315.site"

[Setup]
AppId={{B8E3F2A1-4C5D-4E6F-9A8B-1C2D3E4F5A6B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={tmp}\LeungCliInstaller
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputDir=..\output
OutputBaseFilename=LeungCliInstaller-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
PrivilegesRequired=lowest
SetupIconFile=
Uninstallable=no
CreateUninstallRegKey=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\install.ps1"; DestDir: "{tmp}\LeungCliInstaller"; Flags: ignoreversion deleteafterinstall
Source: "..\internal\*"; DestDir: "{tmp}\LeungCliInstaller\internal"; Flags: ignoreversion recursesubdirs deleteafterinstall
Source: "launcher.bat"; DestDir: "{tmp}\LeungCliInstaller"; Flags: ignoreversion deleteafterinstall

[Run]
Filename: "{cmd}"; Parameters: "/c ""{tmp}\LeungCliInstaller\launcher.bat"""; Flags: runasoriginaluser waituntilterminated; Description: "Run LEUNG CLI Installer"

[Messages]
chinesesimplified.WelcomeLabel1=欢迎使用 LEUNG CLI 安装向导
chinesesimplified.WelcomeLabel2=本向导将为您安装 Codex CLI / Claude Code / Gemini CLI 和 Codex Desktop，并配置 LEUNG API 中转站。%n%n点击"下一步"继续。
chinesesimplified.FinishedLabel=安装向导已完成。所有 CLI 已配置为使用 LEUNG API 中转站。
english.WelcomeLabel1=Welcome to LEUNG CLI Installer
english.WelcomeLabel2=This wizard will install Codex CLI, Claude Code, Gemini CLI, and Codex Desktop, then configure the LEUNG API relay.%n%nClick Next to continue.
english.FinishedLabel=Setup complete. All CLIs are now configured to use the LEUNG API relay.

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
