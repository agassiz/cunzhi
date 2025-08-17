#!/bin/bash

# 寸止开发版本安装脚本 - macOS
# 使用符号链接，方便开发和测试

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔨 寸止开发版本安装脚本${NC}"
echo "=================================="

# 获取当前项目路径
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"

echo "项目路径: $PROJECT_DIR"

# 检查是否在正确的项目目录
if [ ! -f "$PROJECT_DIR/Cargo.toml" ]; then
    echo -e "${RED}❌ 错误: 当前目录不是 Rust 项目${NC}"
    exit 1
fi

# 检查并安装前端依赖
echo -e "${YELLOW}📦 检查前端依赖...${NC}"
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}📦 安装前端依赖...${NC}"
    pnpm install
fi

# 构建前端
echo -e "${YELLOW}🎨 构建前端资源...${NC}"
pnpm build

# 构建发布版本
echo -e "${YELLOW}� 构建 Rust 后端...${NC}"
cd "$PROJECT_DIR"

# 构建 MCP 服务器（寸止）
cargo build --release --bin 寸止

# 构建 Tauri 应用（等一下）- 需要包含前端资源
echo -e "${YELLOW}🖥️  构建 Tauri 应用...${NC}"
if command -v cargo-tauri >/dev/null 2>&1; then
    cargo tauri build --no-bundle
    # 复制 Tauri 构建的二进制文件
    if [ -f "src-tauri/target/release/等一下" ]; then
        cp "src-tauri/target/release/等一下" "target/release/等一下"
    fi
else
    echo -e "${YELLOW}⚠️  未找到 tauri-cli，尝试安装...${NC}"
    cargo install tauri-cli
    cargo tauri build --no-bundle
    if [ -f "src-tauri/target/release/等一下" ]; then
        cp "src-tauri/target/release/等一下" "target/release/等一下"
    fi
fi

# 检查构建结果
if [ ! -f "target/release/寸止" ]; then
    echo -e "${RED}❌ 构建失败: 找不到 寸止 二进制文件${NC}"
    exit 1
fi

if [ ! -f "target/release/等一下" ]; then
    echo -e "${RED}❌ 构建失败: 找不到 等一下 二进制文件${NC}"
    echo -e "${YELLOW}💡 提示: 等一下 是 Tauri 应用，需要前端资源${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 构建成功${NC}"

# 检查是否需要 sudo
NEED_SUDO=false
if [ ! -w "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}⚠️  需要管理员权限安装到 $INSTALL_DIR${NC}"
    NEED_SUDO=true
fi

# 安装函数
install_with_symlink() {
    local binary_name="$1"
    local source_path="$PROJECT_DIR/target/release/$binary_name"
    local target_path="$INSTALL_DIR/$binary_name"
    
    echo -e "${YELLOW}📋 安装 $binary_name...${NC}"
    
    # 删除现有文件或链接
    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        if [ "$NEED_SUDO" = true ]; then
            sudo rm -f "$target_path"
        else
            rm -f "$target_path"
        fi
        echo "   删除现有文件: $target_path"
    fi
    
    # 创建符号链接
    if [ "$NEED_SUDO" = true ]; then
        sudo ln -sf "$source_path" "$target_path"
    else
        ln -sf "$source_path" "$target_path"
    fi
    
    echo -e "   ${GREEN}✅ 符号链接: $target_path -> $source_path${NC}"
}

# 安装二进制文件
install_with_symlink "寸止"
install_with_symlink "等一下"

echo ""
echo -e "${GREEN}🎉 安装完成！${NC}"

# 验证安装
echo -e "${BLUE}🔍 验证安装...${NC}"
for cmd in "寸止" "等一下"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ $cmd 安装成功${NC}"
        echo "   位置: $(which $cmd)"
    else
        echo -e "${RED}❌ $cmd 安装失败${NC}"
    fi
done

echo ""
echo -e "${BLUE}🧪 测试新功能:${NC}"
echo "# 测试默认模式"
echo "寸止 --version"
echo ""
echo "# 测试 Augment 模式 (新功能)"
echo "MCP_AI_CLIENT=augment 寸止 --version"
echo ""
echo "# 启动设置界面"
echo "等一下"

echo ""
echo -e "${YELLOW}💡 MCP 客户端配置 (支持新的图片功能):${NC}"
cat << 'EOF'
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
EOF

echo ""
echo -e "${BLUE}🔄 开发工作流:${NC}"
echo "1. 修改代码后运行: cargo build --release"
echo "2. 符号链接会自动指向新版本，无需重新安装"
echo "3. 直接测试: 寸止 或 MCP_AI_CLIENT=augment 寸止"

echo ""
echo -e "${GREEN}🚀 开发环境配置完成！${NC}"
