@echo off
setlocal enabledelayedexpansion

REM 寸止开发版本安装脚本 - Windows 批处理
REM 使用符号链接，方便开发和测试

echo 🔨 寸止开发版本安装脚本
echo ==================================

REM 获取当前项目路径
set "PROJECT_DIR=%~dp0"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
set "INSTALL_DIR=%USERPROFILE%\.local\bin"

echo 项目路径: %PROJECT_DIR%

REM 检查是否在正确的项目目录
if not exist "%PROJECT_DIR%\Cargo.toml" (
    echo ❌ 错误: 当前目录不是 Rust 项目
    exit /b 1
)

REM 检查并安装前端依赖
echo 📦 检查前端依赖...
if not exist "node_modules" (
    echo 📦 安装前端依赖...
    call pnpm install
    if errorlevel 1 (
        echo ❌ 前端依赖安装失败
        exit /b 1
    )
)

REM 构建前端
echo 🎨 构建前端资源...
call pnpm build
if errorlevel 1 (
    echo ❌ 前端构建失败
    exit /b 1
)

REM 构建发布版本
echo 🔧 构建 Rust 后端...
cd /d "%PROJECT_DIR%"

REM 构建 MCP 服务器（寸止）
call cargo build --release --bin 寸止
if errorlevel 1 (
    echo ❌ 寸止构建失败
    exit /b 1
)

REM 构建 Tauri 应用（等一下）
echo 🖥️  构建 Tauri 应用...
where cargo-tauri >nul 2>&1
if %errorlevel% equ 0 (
    call cargo tauri build --no-bundle
    if errorlevel 1 (
        echo ❌ Tauri 应用构建失败
        exit /b 1
    )
    REM 复制 Tauri 构建的二进制文件
    if exist "src-tauri\target\release\等一下.exe" (
        copy "src-tauri\target\release\等一下.exe" "target\release\等一下.exe" >nul
    )
) else (
    echo ⚠️  未找到 tauri-cli，尝试安装...
    call cargo install tauri-cli
    if errorlevel 1 (
        echo ❌ tauri-cli 安装失败
        exit /b 1
    )
    call cargo tauri build --no-bundle
    if errorlevel 1 (
        echo ❌ Tauri 应用构建失败
        exit /b 1
    )
    if exist "src-tauri\target\release\等一下.exe" (
        copy "src-tauri\target\release\等一下.exe" "target\release\等一下.exe" >nul
    )
)

REM 检查构建结果
if not exist "target\release\寸止.exe" (
    echo ❌ 构建失败: 找不到 寸止.exe 二进制文件
    exit /b 1
)

if not exist "target\release\等一下.exe" (
    echo ❌ 构建失败: 找不到 等一下.exe 二进制文件
    echo 💡 提示: 等一下 是 Tauri 应用，需要前端资源
    exit /b 1
)

echo ✅ 构建成功

REM 创建安装目录
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
    echo 创建安装目录: %INSTALL_DIR%
)

REM 安装函数
call :install_binary "寸止"
call :install_binary "等一下"

echo.
echo 🎉 安装完成！

REM 检查 PATH 环境变量
echo %PATH% | findstr /i "%INSTALL_DIR%" >nul
if errorlevel 1 (
    echo ⚠️  需要将 %INSTALL_DIR% 添加到 PATH 环境变量
    echo 请手动添加或运行以下 PowerShell 命令:
    echo [Environment]::SetEnvironmentVariable('PATH', $env:PATH + ';%INSTALL_DIR%', 'User'^)
)

REM 验证安装
echo.
echo 🔍 验证安装...
for %%c in (寸止 等一下) do (
    if exist "%INSTALL_DIR%\%%c.exe" (
        echo ✅ %%c 安装成功
        echo    位置: %INSTALL_DIR%\%%c.exe
    ) else (
        echo ❌ %%c 安装失败
    )
)

echo.
echo 🧪 测试新功能:
echo # 测试默认模式
echo 寸止 --version
echo.
echo # 测试 Augment 模式 (新功能^)
echo set MCP_AI_CLIENT=augment ^&^& 寸止 --version
echo.
echo # 启动设置界面
echo 等一下

echo.
echo 💡 MCP 客户端配置 (支持新的图片功能^):
echo {
echo   "mcpServers": {
echo     "寸止": {
echo       "command": "寸止",
echo       "env": {
echo         "MCP_AI_CLIENT": "augment"
echo       }
echo     }
echo   }
echo }

echo.
echo 🔄 开发工作流:
echo 1. 修改代码后运行: cargo build --release
echo 2. 符号链接会自动指向新版本，无需重新安装
echo 3. 直接测试: 寸止 或 set MCP_AI_CLIENT=augment ^&^& 寸止

echo.
echo 🚀 开发环境配置完成！
goto :eof

:install_binary
set "BINARY_NAME=%~1"
set "SOURCE_PATH=%PROJECT_DIR%\target\release\%BINARY_NAME%.exe"
set "TARGET_PATH=%INSTALL_DIR%\%BINARY_NAME%.exe"

echo 📋 安装 %BINARY_NAME%...

REM 删除现有文件或链接
if exist "%TARGET_PATH%" (
    del /f "%TARGET_PATH%"
    echo    删除现有文件: %TARGET_PATH%
)

REM 尝试创建符号链接，如果失败则复制文件
mklink "%TARGET_PATH%" "%SOURCE_PATH%" >nul 2>&1
if errorlevel 1 (
    REM 符号链接失败，直接复制文件
    copy "%SOURCE_PATH%" "%TARGET_PATH%" >nul
    echo    ✅ 复制: %TARGET_PATH%
    echo    ⚠️  使用文件复制，修改代码后需重新运行安装脚本
) else (
    echo    ✅ 符号链接: %TARGET_PATH% -^> %SOURCE_PATH%
)
goto :eof
