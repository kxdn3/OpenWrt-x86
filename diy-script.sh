#!/bin/bash
# diy-script.sh - ImmortalWrt 25.12 (apk) 自定义脚本
# 使用 Feed 源方式安装插件，自动处理依赖

echo "========================================"
echo "开始执行 DIY 脚本 (ImmortalWrt 25.12 apk)"
echo "========================================"

# ============================================================
# 1. 添加第三方 Feed 源
# ============================================================
echo "[1/5] 添加第三方 Feed 源"

# --- kenzok8 综合源 (包含 Lucky、PushBot 等大量插件) ---
echo "src-git kenzo https://github.com/kenzok8/openwrt-packages" >> feeds.conf.default
echo "src-git small https://github.com/kenzok8/small" >> feeds.conf.default

# --- PassWall 官方源 ---
echo "src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main" >> feeds.conf.default
echo "src-git passwall_luci https://github.com/xiaorouji/openwrt-passwall.git;main" >> feeds.conf.default

echo "  - Feed 源添加完成"

# ============================================================
# 2. 更新并安装 Feeds（此时插件已进入编译系统）
# ============================================================
echo "[2/5] 更新并安装 Feeds"
./scripts/feeds update -a
./scripts/feeds install -a

# ============================================================
# 3. 修改默认 LAN IP 为 10.0.0.1
# ============================================================
echo "[3/5] 修改默认 LAN IP 为 10.0.0.1"
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# ============================================================
# 4. 清空 root 密码、设置主题和 Shell
# ============================================================
echo "[4/5] 设置密码、主题和 Shell"

# 清空 root 密码
if [ -f package/base-files/files/etc/shadow ]; then
    sed -i 's/^root:[^:]*:/root::/' package/base-files/files/etc/shadow
fi

# 设置默认主题为 fluent
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-set-theme <<EOF
#!/bin/sh
uci set luci.main.mediaurlbase='/luci-static/fluent'
uci commit luci
exit 0
EOF
chmod +x files/etc/uci-defaults/99-set-theme
sed -i 's/luci-theme-bootstrap/luci-theme-fluent/g' feeds/luci/collections/luci/Makefile 2>/dev/null || true

# 设置默认 Shell 为 zsh
if [ -f package/base-files/files/etc/passwd ]; then
    sed -i 's|/bin/ash|/usr/bin/zsh|' package/base-files/files/etc/passwd
fi

# ============================================================
# 5. 配置分区大小并启用所需包
# ============================================================
echo "[5/5] 配置分区大小与启用插件"

# 设置分区大小
sed -i '/CONFIG_TARGET_KERNEL_PARTSIZE/d' .config
sed -i '/CONFIG_TARGET_ROOTFS_PARTSIZE/d' .config
echo "CONFIG_TARGET_KERNEL_PARTSIZE=16" >> .config
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=2048" >> .config

# 启用插件（Feed 方式下插件名已标准化）
cat >> .config <<EOF
CONFIG_PACKAGE_luci-app-passwall=y
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_luci-app-diskman=y
CONFIG_PACKAGE_luci-app-lucky=y
CONFIG_PACKAGE_luci-app-pushbot=y
CONFIG_PACKAGE_luci-theme-fluent=y
CONFIG_PACKAGE_zsh=y
CONFIG_PACKAGE_kmod-igc=y
EOF

# 重新整理配置，自动解决依赖
make defconfig > /dev/null 2>&1

echo "DIY 脚本执行完毕"
