#!/bin/bash
# diy-script.sh - ImmortalWrt 25.12 (apk) 自定义脚本
# 执行位置：openwrt 源码根目录（工作流中已 cd $OPENWRT_PATH）

echo "========================================"
echo "开始执行 DIY 脚本 (ImmortalWrt 25.12 apk)"
echo "========================================"

# ============================================================
# 1. 修改默认 LAN IP 为 10.0.0.1
# ============================================================
echo "[1/6] 修改默认 LAN IP 为 10.0.0.1"
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# ============================================================
# 2. 清空 root 密码
# ============================================================
echo "[2/6] 设置 root 密码为空"
if [ -f package/base-files/files/etc/shadow ]; then
    sed -i 's/^root:[^:]*:/root::/' package/base-files/files/etc/shadow
else
    echo "  - shadow 文件不存在，跳过"
fi

# ============================================================
# 3. 安装 luci-theme-fluent 并设为默认主题
# ============================================================
echo "[3/6] 安装 luci-theme-fluent 主题"
git clone --depth=1 https://github.com/LazuliKao/luci-theme-fluent.git package/luci-theme-fluent

# 通过 uci-defaults 设置默认主题
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-set-theme <<EOF
#!/bin/sh
uci set luci.main.mediaurlbase='/luci-static/fluent'
uci commit luci
exit 0
EOF
chmod +x files/etc/uci-defaults/99-set-theme

# 同时修改 feeds 中的默认主题引用（双保险）
sed -i 's/luci-theme-bootstrap/luci-theme-fluent/g' feeds/luci/collections/luci/Makefile 2>/dev/null || true

# ============================================================
# 4. 切换默认 Shell 为 zsh
# ============================================================
echo "[4/6] 设置默认 Shell 为 zsh"
if [ -f package/base-files/files/etc/passwd ]; then
    sed -i 's|/bin/ash|/usr/bin/zsh|' package/base-files/files/etc/passwd
else
    echo "  - passwd 文件不存在，跳过"
fi

# ============================================================
# 5. 克隆插件源码到 package 目录
# ============================================================
echo "[5/6] 克隆插件源码"

# --- PassWall 官方源码及依赖 ---
echo "  - PassWall"
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall.git package/openwrt-passwall
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages.git package/openwrt-passwall-packages

# --- luci-app-dockerman 及依赖 ---
echo "  - luci-app-dockerman"
git clone --depth=1 https://github.com/lisaac/luci-app-dockerman.git package/luci-app-dockerman
git clone --depth=1 https://github.com/lisaac/luci-lib-docker.git package/luci-lib-docker

# --- luci-app-diskman ---
echo "  - luci-app-diskman"
git clone --depth=1 https://github.com/lisaac/luci-app-diskman.git package/luci-app-diskman

# --- sirpdboy 的 luci-app-lucky ---
echo "  - luci-app-lucky"
git clone --depth=1 https://github.com/sirpdboy/luci-app-lucky.git package/luci-app-lucky

# --- luci-app-pushbot ---
echo "  - luci-app-pushbot"
git clone --depth=1 https://github.com/zzsj0928/luci-app-pushbot.git package/luci-app-pushbot

# ============================================================
# 6. 强制设置分区大小并启用所需包
# ============================================================
echo "[6/6] 配置分区大小与启用插件"

# 删除旧配置，写入新分区大小
sed -i '/CONFIG_TARGET_KERNEL_PARTSIZE/d' .config
sed -i '/CONFIG_TARGET_ROOTFS_PARTSIZE/d' .config
echo "CONFIG_TARGET_KERNEL_PARTSIZE=16" >> .config
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=2048" >> .config

# 追加插件启用项
cat >> .config <<EOF
CONFIG_PACKAGE_luci-app-passwall=y
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_luci-app-diskman=y
CONFIG_PACKAGE_luci-app-lucky=y
CONFIG_PACKAGE_luci-app-pushbot=y
CONFIG_PACKAGE_luci-theme-fluent=y
CONFIG_PACKAGE_zsh=y
EOF

# 重新整理配置，自动解决依赖
make defconfig > /dev/null 2>&1

echo "DIY 脚本执行完毕"
