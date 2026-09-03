#!/bin/bash
set -e  # 出错即停止

# 定义目标目录
ROOT_FS_DIR="files/root"
mkdir -p "$ROOT_FS_DIR"

# 1. 安装 Oh My Zsh（使用镜像加速）
pushd "$ROOT_FS_DIR" >/dev/null

# 使用 Gitee 镜像（国内加速）
# OMZ_REPO="https://gitee.com/mirrors/oh-my-zsh.git"
# 或使用 GitHub 原版（如果你的网络好）
OMZ_REPO="https://github.com/ohmyzsh/ohmyzsh.git"

if [ ! -d ".oh-my-zsh" ]; then
    git clone --depth=1 "$OMZ_REPO" ./.oh-my-zsh
else
    echo "Oh My Zsh already exists, skipping..."
fi

# 2. 安装插件（同样使用镜像）
PLUGIN_DIR="./.oh-my-zsh/custom/plugins"

# 定义插件列表（镜像地址映射）
declare -A PLUGINS=(
    ["zsh-autosuggestions"]="https://gitee.com/zsh-users/zsh-autosuggestions.git"
    ["zsh-syntax-highlighting"]="https://gitee.com/zsh-users/zsh-syntax-highlighting.git"
    ["zsh-completions"]="https://gitee.com/zsh-users/zsh-completions.git"
)

for plugin in "${!PLUGINS[@]}"; do
    target_dir="$PLUGIN_DIR/$plugin"
    if [ ! -d "$target_dir" ]; then
        git clone --depth=1 "${PLUGINS[$plugin]}" "$target_dir"
    else
        echo "Plugin $plugin already exists, skipping..."
    fi
done

# 3. 复制 .zshrc 配置
ZSH_RC_SOURCE="${GITHUB_WORKSPACE:-.}/scripts/.zshrc"
if [ -f "$ZSH_RC_SOURCE" ]; then
    cp "$ZSH_RC_SOURCE" ./.zshrc
else
    echo "WARNING: .zshrc not found at $ZSH_RC_SOURCE, creating default..."
    # 生成默认 .zshrc
    cat > ./.zshrc << 'EOF'
# 启用 Oh My Zsh
export ZSH="/root/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)
source $ZSH/oh-my-zsh.sh
EOF
fi

popd >/dev/null

echo "Zsh setup completed successfully!"
