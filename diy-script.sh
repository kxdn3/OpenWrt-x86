#!/bin/bash
# diy-script.sh - ImmortalWrt 25.12 (apk) 自定义脚本
# 修正版：dockerman 改用官方 feed

echo "========================================"
echo "开始执行 DIY 脚本 (ImmortalWrt 25.12 apk)"
echo "========================================"

# ============================================================
# 1. 修改默认 LAN IP 为 10.0.0.1
# ============================================================
echo "[1/5] 修改默认 LAN IP 为 10.0.0.1"
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# ============================================================
# 2. 清空 root 密码、设置主题和 Shell
# ============================================================
echo "[2/5] 设置密码、主题和 Shell"

if [ -f package/base-files/files/etc/shadow ]; then
    sed -i 's/^root:[^:]*:/root::/' package/base-files/files/etc/shadow
fi

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-set-theme <<EOF
#!/bin/sh
uci set luci.main.mediaurlbase='/luci-static/fluent'
uci commit luci
exit 0
EOF
chmod +x files/etc/uci-defaults/99-set-theme

if [ -f package/base-files/files/etc/passwd ]; then
    sed -i 's|/bin/ash|/usr/bin/zsh|' package/base-files/files/etc/passwd
fi

# ============================================================
# 3. 克隆插件源码（dockerman 不再 clone，改用官方 feed）
# ============================================================
echo "[3/5] 克隆插件源码"

# --- Fluent 主题 ---
echo "  - luci-theme-fluent"
git clone --depth=1 https://github.com/LazuliKao/luci-theme-fluent.git package/luci-theme-fluent

# --- PassWall 官方源码 + 依赖包 ---
echo "  - PassWall"
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall.git package/openwrt-passwall
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages.git package/openwrt-passwall-packages

# --- Diskman (磁盘管理) ---
echo "  - luci-app-diskman"
git clone --depth=1 https://github.com/lisaac/luci-app-diskman.git package/luci-app-diskman

# --- Lucky (sirpdboy) ---
echo "  - luci-app-lucky"
git clone --depth=1 https://github.com/sirpdboy/luci-app-lucky.git package/luci-app-lucky

# --- PushBot (zzsj0928) ---
echo "  - luci-app-pushbot"
git clone --depth=1 https://github.com/zzsj0928/luci-app-pushbot.git package/luci-app-pushbot

# ============================================================
# 4. 配置分区大小
# ============================================================
echo "[4/5] 配置分区大小"
sed -i '/CONFIG_TARGET_KERNEL_PARTSIZE/d' .config
sed -i '/CONFIG_TARGET_ROOTFS_PARTSIZE/d' .config
echo "CONFIG_TARGET_KERNEL_PARTSIZE=16" >> .config
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=2048" >> .config

# ============================================================
# 5. 启用所需包（dockerman 走官方 feed）
# ============================================================
echo "[5/5] 启用插件"

cat >> .config <<EOF
CONFIG_PACKAGE_luci-theme-fluent=y
CONFIG_PACKAGE_zsh=y
CONFIG_PACKAGE_kmod-igc=y
CONFIG_PACKAGE_luci-app-passwall=y
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_luci-lib-docker=y
CONFIG_PACKAGE_luci-app-diskman=y
CONFIG_PACKAGE_luci-app-lucky=y
CONFIG_PACKAGE_luci-app-pushbot=y
CONFIG_PACKAGE_docker=y
CONFIG_PACKAGE_dockerd=y
CONFIG_PACKAGE_docker-compose=y
EOF

make defconfig > /dev/null 2>&1

echo "DIY 脚本执行完毕"
