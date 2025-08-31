# 寸止开发版本安装脚本 - Windows PowerShell
# 使用符号链接，方便开发和测试

param(
    [switch]$Force,
    [string]$InstallDir = "$env:USERPROFILE\.local\bin"
)

# 设置错误处理
$ErrorActionPreference = "Stop"

# 颜色函数
function Write-ColorText {
    param([string]$Text, [string]$Color = "White")
    $colors = @{
        "Red" = "Red"
        "Green" = "Green" 
        "Yellow" = "Yellow"
        "Blue" = "Blue"
        "White" = "White"
    }
    Write-Host $Text -ForegroundColor $colors[$Color]
}

Write-ColorText "🔨 寸止开发版本安装脚本" "Blue"
Write-Host "=================================="

# 获取当前项目路径
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "项目路径: $ProjectDir"

# 检查是否在正确的项目目录
if (-not (Test-Path "$ProjectDir\Cargo.toml")) {
    Write-ColorText "❌ 错误: 当前目录不是 Rust 项目" "Red"
    exit 1
}

# 检查并安装前端依赖
Write-ColorText "📦 检查前端依赖..." "Yellow"
if (-not (Test-Path "node_modules")) {
    Write-ColorText "📦 安装前端依赖..." "Yellow"
    pnpm install
    if ($LASTEXITCODE -ne 0) {
        Write-ColorText "❌ 前端依赖安装失败" "Red"
        exit 1
    }
}

# 构建前端
Write-ColorText "🎨 构建前端资源..." "Yellow"
pnpm build
if ($LASTEXITCODE -ne 0) {
    Write-ColorText "❌ 前端构建失败" "Red"
    exit 1
}

# 构建发布版本
Write-ColorText "🔧 构建 Rust 后端..." "Yellow"
Set-Location $ProjectDir

# 构建 MCP 服务器（寸止）
cargo build --release --bin 寸止
if ($LASTEXITCODE -ne 0) {
    Write-ColorText "❌ 寸止构建失败" "Red"
    exit 1
}

# 构建 Tauri 应用（等一下）
Write-ColorText "🖥️  构建 Tauri 应用..." "Yellow"
$tauriExists = Get-Command cargo-tauri -ErrorAction SilentlyContinue
if ($tauriExists) {
    cargo tauri build --no-bundle
    if ($LASTEXITCODE -ne 0) {
        Write-ColorText "❌ Tauri 应用构建失败" "Red"
        exit 1
    }
    # 复制 Tauri 构建的二进制文件
    if (Test-Path "src-tauri\target\release\等一下.exe") {
        Copy-Item "src-tauri\target\release\等一下.exe" "target\release\等一下.exe" -Force
    }
} else {
    Write-ColorText "⚠️  未找到 tauri-cli，尝试安装..." "Yellow"
    cargo install tauri-cli
    if ($LASTEXITCODE -ne 0) {
        Write-ColorText "❌ tauri-cli 安装失败" "Red"
        exit 1
    }
    cargo tauri build --no-bundle
    if ($LASTEXITCODE -ne 0) {
        Write-ColorText "❌ Tauri 应用构建失败" "Red"
        exit 1
    }
    if (Test-Path "src-tauri\target\release\等一下.exe") {
        Copy-Item "src-tauri\target\release\等一下.exe" "target\release\等一下.exe" -Force
    }
}

# 检查构建结果
if (-not (Test-Path "target\release\寸止.exe")) {
    Write-ColorText "❌ 构建失败: 找不到 寸止.exe 二进制文件" "Red"
    exit 1
}

if (-not (Test-Path "target\release\等一下.exe")) {
    Write-ColorText "❌ 构建失败: 找不到 等一下.exe 二进制文件" "Red"
    Write-ColorText "💡 提示: 等一下 是 Tauri 应用，需要前端资源" "Yellow"
    exit 1
}

Write-ColorText "✅ 构建成功" "Green"

# 创建安装目录
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "创建安装目录: $InstallDir"
}

# 安装函数
function Install-WithSymlink {
    param([string]$BinaryName)
    
    $SourcePath = "$ProjectDir\target\release\$BinaryName.exe"
    $TargetPath = "$InstallDir\$BinaryName.exe"
    
    Write-ColorText "📋 安装 $BinaryName..." "Yellow"
    
    # 删除现有文件或链接
    if (Test-Path $TargetPath) {
        Remove-Item $TargetPath -Force
        Write-Host "   删除现有文件: $TargetPath"
    }
    
    # 创建符号链接（需要管理员权限）或硬链接
    try {
        # 尝试创建符号链接
        New-Item -ItemType SymbolicLink -Path $TargetPath -Target $SourcePath -Force | Out-Null
        Write-ColorText "   ✅ 符号链接: $TargetPath -> $SourcePath" "Green"
    } catch {
        # 如果符号链接失败，创建硬链接
        try {
            New-Item -ItemType HardLink -Path $TargetPath -Target $SourcePath -Force | Out-Null
            Write-ColorText "   ✅ 硬链接: $TargetPath -> $SourcePath" "Green"
        } catch {
            # 如果都失败，直接复制文件
            Copy-Item $SourcePath $TargetPath -Force
            Write-ColorText "   ✅ 复制: $TargetPath" "Green"
            Write-ColorText "   ⚠️  使用文件复制，修改代码后需重新运行安装脚本" "Yellow"
        }
    }
}

# 安装二进制文件
Install-WithSymlink "寸止"
Install-WithSymlink "等一下"

Write-Host ""
Write-ColorText "🎉 安装完成！" "Green"

# 检查 PATH 环境变量
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$InstallDir*") {
    Write-ColorText "⚠️  需要将 $InstallDir 添加到 PATH 环境变量" "Yellow"
    Write-Host "运行以下命令添加到用户 PATH:"
    Write-Host "`$env:PATH += ';$InstallDir'" -ForegroundColor Cyan
    Write-Host "或者运行以下命令永久添加:"
    Write-Host "[Environment]::SetEnvironmentVariable('PATH', `$env:PATH + ';$InstallDir', 'User')" -ForegroundColor Cyan
}

# 验证安装
Write-ColorText "🔍 验证安装..." "Blue"
$commands = @("寸止", "等一下")
foreach ($cmd in $commands) {
    $cmdPath = "$InstallDir\$cmd.exe"
    if (Test-Path $cmdPath) {
        Write-ColorText "✅ $cmd 安装成功" "Green"
        Write-Host "   位置: $cmdPath"
    } else {
        Write-ColorText "❌ $cmd 安装失败" "Red"
    }
}

Write-Host ""
Write-ColorText "🧪 测试新功能:" "Blue"
Write-Host "# 测试默认模式"
Write-Host "寸止 --version"
Write-Host ""
Write-Host "# 测试 Augment 模式 (新功能)"
Write-Host "`$env:MCP_AI_CLIENT='augment'; 寸止 --version"
Write-Host ""
Write-Host "# 启动设置界面"
Write-Host "等一下"

Write-Host ""
Write-ColorText "💡 MCP 客户端配置 (支持新的图片功能):" "Yellow"
@"
{
  "mcpServers": {
    "寸止": {
      "command": "寸止",
      "env": {
        "MCP_AI_CLIENT": "augment"
      }
    }
  }
}
"@

Write-Host ""
Write-ColorText "🔄 开发工作流:" "Blue"
Write-Host "1. 修改代码后运行: cargo build --release"
Write-Host "2. 符号链接会自动指向新版本，无需重新安装"
Write-Host "3. 直接测试: 寸止 或 `$env:MCP_AI_CLIENT='augment'; 寸止"

Write-Host ""
Write-ColorText "🚀 开发环境配置完成！" "Green"
