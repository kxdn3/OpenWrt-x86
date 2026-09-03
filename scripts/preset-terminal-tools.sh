#!/bin/bash
set -e

# 定义目标目录
ROOT_FS_DIR="files/root"
mkdir -p "$ROOT_FS_DIR"

pushd "$ROOT_FS_DIR" >/dev/null

# ========== 1. 检测缓存 ==========
if [ -d ".oh-my-zsh" ] && [ -f ".zshrc" ]; then
    echo "✅ Oh My Zsh cache found, skipping installation"
    popd >/dev/null
    exit 0
fi

# ========== 2. 克隆 Oh My Zsh ==========
echo "📥 Installing Oh My Zsh from GitHub..."

# GitHub Actions 环境访问 GitHub 速度快，无需镜像
git clone --depth=1 --single-branch \
    https://github.com/ohmyzsh/ohmyzsh.git ./.oh-my-zsh

# ========== 3. 安装插件（并行克隆加速） ==========
PLUGIN_DIR="./.oh-my-zsh/custom/plugins"

echo "📥 Installing plugins from GitHub..."

# 并行克隆 3 个插件（后台运行）
git clone --depth=1 --single-branch \
    https://github.com/zsh-users/zsh-autosuggestions.git \
    "$PLUGIN_DIR/zsh-autosuggestions" &

git clone --depth=1 --single-branch \
    https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$PLUGIN_DIR/zsh-syntax-highlighting" &

git clone --depth=1 --single-branch \
    https://github.com/zsh-users/zsh-completions.git \
    "$PLUGIN_DIR/zsh-completions" &

wait  # 等待所有后台任务完成
echo "✅ All plugins cloned"

# ========== 4. 创建 .zshrc ==========
echo "📝 Creating .zshrc..."

cat > ./.zshrc << 'EOF'
# Oh My Zsh 配置
export ZSH="/root/.oh-my-zsh"
ZSH_THEME="robbyrussell"

# 启用插件
plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-completions
)

# 自动补全配置
autoload -U compinit && compinit

# 加载 Oh My Zsh
source $ZSH/oh-my-zsh.sh

# 自定义别名
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# 历史记录配置
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_ALL_DUPS
setopt SHARE_HISTORY
EOF

popd >/dev/null

echo "✅ Zsh setup completed successfully!"
