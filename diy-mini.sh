#!/bin/bash
#
# OpenWrt x86_64 Mini 自定义编译脚本
# 源码: coolsnowwolf/lede master
# LuCI: coolsnowwolf/luci openwrt-25.12
# 内核: 6.12
#

set -e

# ========== 基础配置 ==========
OPENWRT_PATH="$PWD"
CFG_FILE="package/base-files/files/bin/config_generate"

# ========== LuCI 源切换 ==========
echo ">>> 切换 LuCI 分支"
sed -i '/^#\?src-git luci/d' feeds.conf.default
echo "src-git luci https://github.com/coolsnowwolf/luci.git;openwrt-25.12" >> feeds.conf.default

# ========== 系统默认设置 ==========
echo ">>> 修改默认网络和时区"
if [ -f "$CFG_FILE" ]; then
    sed -i 's/192.168.1.1/10.0.0.1/g' "$CFG_FILE"
    sed -i "s/timezone='.*'/timezone='CST-8'/g" "$CFG_FILE"
    grep -q "Asia/Shanghai" "$CFG_FILE" || sed -i "/timezone='CST-8'/a\\
        uci set system.@system[-1].zonename='Asia/Shanghai'" "$CFG_FILE"
fi

# ========== 默认 Shell ==========
sed -i 's#/bin/ash#/usr/bin/zsh#g' package/base-files/files/etc/passwd

# ========== ttyd 设置 ==========
if [ -f feeds/packages/utils/ttyd/files/ttyd.config ]; then
    sed -i 's#/bin/login#/bin/login -f root#g' feeds/packages/utils/ttyd/files/ttyd.config
fi

# ========== 镜像分区设置 ==========
echo ">>> 调整 x86 镜像分区"
sed -i 's/GRUB_BOOT_PARTSIZE:=256/GRUB_BOOT_PARTSIZE:=1024/g' target/linux/x86/image/Makefile
sed -i 's/GRUB_EFI_BOOT_PARTSIZE:=256/GRUB_EFI_BOOT_PARTSIZE:=1024/g' target/linux/x86/image/Makefile

# ========== 网络连接优化 ==========
SYSCTL_FILE="package/base-files/files/etc/sysctl.conf"
if [ -f "$SYSCTL_FILE" ] && ! grep -q "nf_conntrack_max" "$SYSCTL_FILE"; then
    echo "net.netfilter.nf_conntrack_max=65535" >> "$SYSCTL_FILE"
fi

# ========== 第三方包函数 ==========
clone_pkg() {
    local url="$1"
    local dir="$2"
    [ -d "$dir" ] && rm -rf "$dir"
    git clone --depth=1 "$url" "$dir"
}

merge_package() {
    branch="$1"
    repo="$2"
    target="$3"
    shift 3
    tmpdir=$(mktemp -d)
    git clone -b "$branch" --depth=1 --filter=blob:none --sparse "$repo" "$tmpdir"
    cd "$tmpdir"
    git sparse-checkout init --cone
    git sparse-checkout set "$@"
    for folder in "$@"; do
        cp -rf "$folder" "$OPENWRT_PATH/$target/"
    done
    cd "$OPENWRT_PATH"
    rm -rf "$tmpdir"
}

# ========== 删除替换包 ==========
echo ">>> 删除需要替换的软件包"
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-dockerman
rm -rf feeds/luci/applications/luci-app-diskman
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/luci/applications/luci-app-netdata
rm -rf feeds/luci/applications/luci-app-pushbot

# ========== 添加第三方插件 ==========
echo ">>> 添加第三方插件"

clone_pkg https://github.com/gdy666/luci-app-lucky.git package/lucky

clone_pkg https://github.com/zzsj0928/luci-app-pushbot package/luci-app-pushbot

git clone --depth=1 https://github.com/lisaac/luci-app-dockerman.git package/tmp-dockerman
cp -rf package/tmp-dockerman/applications/luci-app-dockerman package/
rm -rf package/tmp-dockerman

clone_pkg https://github.com/lisaac/luci-lib-docker.git package/luci-lib-docker

clone_pkg https://github.com/lisaac/luci-app-diskman package/luci-app-diskman


# ========== PassWall ==========
echo ">>> 添加 PassWall"

clone_pkg https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall-packages

clone_pkg https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall


# ========== Argon 主题 ==========
echo ">>> 添加 Argon 主题"

clone_pkg https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon

clone_pkg https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config

sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile


# ========== 核心库替换 ==========
echo ">>> 替换核心软件包"

merge_package master https://github.com/openwrt/packages feeds/packages/libs libs/nghttp3 libs/ngtcp2


# ========== coremark ==========
rm -rf feeds/packages/utils/coremark

merge_package main https://github.com/sbwml/openwrt_pkgs feeds/packages/utils coremark


# ========== unzip ==========
rm -rf feeds/packages/utils/unzip

clone_pkg https://github.com/sbwml/feeds_packages_utils_unzip feeds/packages/utils/unzip


# ========== Samba4 ==========
echo ">>> 替换 Samba4"

rm -rf feeds/packages/net/samba4

clone_pkg https://github.com/sbwml/feeds_packages_net_samba4 feeds/packages/net/samba4


if [ -f feeds/packages/net/samba4/files/smb.conf.template ]; then

    sed -i '/workgroup/a\\
## enable multi-channel' feeds/packages/net/samba4/files/smb.conf.template

    sed -i '/enable multi-channel/a\\
server multi channel support = yes' feeds/packages/net/samba4/files/smb.conf.template

    sed -i 's/#aio read size = 0/aio read size = 1/g' feeds/packages/net/samba4/files/smb.conf.template

    sed -i 's/#aio write size = 0/aio write size = 1/g' feeds/packages/net/samba4/files/smb.conf.template

fi


# ========== 第三方 Makefile 修正 ==========
echo ">>> 修正第三方包路径"

find package -name Makefile -exec sed -i \
's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' {} \;

find package -name Makefile -exec sed -i \
's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' {} \;

find package -name Makefile -exec sed -i \
's|PKG_SOURCE_URL:=@GHREPO|PKG_SOURCE_URL:=https://github.com|g' {} \;

find package -name Makefile -exec sed -i \
's|PKG_SOURCE_URL:=@GHCODELOAD|PKG_SOURCE_URL:=https://codeload.github.com|g' {} \;


# ========== feeds 更新 ==========
echo ">>> 更新 feeds"

./scripts/feeds update -a
./scripts/feeds install -a

# ========== LuCI 显示优化 ==========
echo ">>> 优化系统显示"

if [ -f package/lean/autocore/files/x86/autocore ]; then
    sed -i 's/${g}.*/${a}${b}${c}${d}${e}${f}${hydrid}/g' package/lean/autocore/files/x86/autocore
fi

if ls package/lean/autocore/files/*/index.htm >/dev/null 2>&1; then
    sed -i 's/os.date()/os.date("%Y-%m-%d %H:%M:%S") .. " " .. translate(os.date("%A"))/g' package/lean/autocore/files/*/index.htm
fi


# ========== 固件版本信息 ==========
echo ">>> 设置固件版本"

DATE_VERSION=$(date +"%y.%m.%d")

VERSION_FILE="package/lean/default-settings/files/zzz-default-settings"

if [ -f "$VERSION_FILE" ]; then

    ORIG_VERSION=$(grep DISTRIB_REVISION= "$VERSION_FILE" | awk -F "'" '{print $2}')

    if [ -n "$ORIG_VERSION" ]; then
        sed -i "s/${ORIG_VERSION}/R${DATE_VERSION} by kxdn/g" "$VERSION_FILE"
    fi

fi


# ========== hostapd 修复 ==========
echo ">>> 检查 hostapd 修复"

if [ -n "$GITHUB_WORKSPACE" ] && [ -f "$GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch" ]; then

    mkdir -p package/network/services/hostapd/patches

    cp -f \
    "$GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch" \
    package/network/services/hostapd/patches/011-fix-mbo-modules-build.patch

fi


# ========== Docker 数据保护 ==========
echo ">>> 设置 Docker 数据目录"

mkdir -p files/etc/docker

cat > files/etc/docker/daemon.json <<EOF
{
    "data-root": "/opt/docker"
}
EOF


# ========== Docker 网络优化 ==========
cat >> files/etc/sysctl.conf <<EOF

# Docker optimize
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1

EOF


# ========== 删除无用驱动 ==========
echo ">>> 清理无用驱动"


REMOVE_DRIVERS="
kmod-cfg80211
kmod-mac80211
kmod-bluetooth
kmod-btusb
kmod-ath3k
kmod-bcmbt
bluez
kmod-r816
kmod-r8125
kmod-tg3
kmod-bnx2
kmod-sky2
kmod-pcnet32
kmod-via-rhine
kmod-via-velocity
kmod-forcedeth
kmod-natsemi
kmod-sis900
kmod-drm-amdgpu
kmod-nouveau
kmod-mhi
kmod-qmi
kmod-usb-net-qmi
kmod-firewire
kmod-sound
kmod-video
kmod-media
kmod-mmc
kmod-sdhci
"


for drv in $REMOVE_DRIVERS
do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done


# ========== 保留关键x86驱动 ==========
echo ">>> 保留关键驱动"


KEEP_DRIVERS="
kmod-igc
kmod-e1000e
kmod-ixgbe
kmod-i40e
kmod-ahci
kmod-nvme
kmod-virtio
"


for drv in $KEEP_DRIVERS
do
    grep -q "CONFIG_PACKAGE_${drv}=y" .config || \
    echo "CONFIG_PACKAGE_${drv}=y" >> .config
done


# ========== 防止关键配置丢失 ==========
echo ">>> 检查关键配置"

grep -q "CONFIG_PACKAGE_kmod-igc=y" .config || \
echo "CONFIG_PACKAGE_kmod-igc=y" >> .config


grep -q "CONFIG_PACKAGE_zsh=y" .config || \
echo "CONFIG_PACKAGE_zsh=y" >> .config


grep -q "CONFIG_PACKAGE_luci-theme-argon=y" .config || \
echo "CONFIG_PACKAGE_luci-theme-argon=y" >> .config


# ========== 最终处理 ==========
echo ">>> 重新生成配置"

make defconfig


echo "=========================================="
echo " diy-mini.sh 执行完成"
echo " LuCI: openwrt-25.12"
echo " Kernel: 6.12"
echo " IP: 10.0.0.1"
echo " Rootfs: 2048MB"
echo " Docker: /opt/docker"
echo "=========================================="
