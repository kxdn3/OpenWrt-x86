#!/bin/bash
#
# OpenWrt x86_64 Mini 自定义编译脚本
#
# Source:
#   coolsnowwolf/lede master
#
# LuCI:
#   openwrt-25.12
#
# Kernel:
#   6.12
#
# Partition:
#   GRUB boot      1024K (1MB)
#   Kernel         16MB
#   Rootfs         2048MB
#
# Default:
#   IP: 10.0.0.1
#
set -e

OPENWRT_PATH="$PWD"

CFG_FILE="package/base-files/files/bin/config_generate"


echo "=========================================="
echo " OpenWrt x86_64 Mini DIY"
echo " LuCI: openwrt-25.12"
echo " Kernel: 6.12"
echo "=========================================="


# ============================================================
# ========== LuCI 源切换 ==========
# ============================================================

echo ">>> 设置 LuCI 分支"

sed -i '/^#\?src-git luci/d' feeds.conf.default

echo "src-git luci https://github.com/coolsnowwolf/luci.git;openwrt-25.12" \
>> feeds.conf.default


# ============================================================
# ========== 基础系统设置 ==========
# ============================================================

echo ">>> 修改默认网络"


if [ -f "$CFG_FILE" ]; then

    sed -i 's/192.168.1.1/10.0.0.1/g' "$CFG_FILE"

    sed -i "s/timezone='.*'/timezone='CST-8'/g" "$CFG_FILE"

    grep -q "Asia/Shanghai" "$CFG_FILE" || \
    sed -i "/timezone='CST-8'/a\\\t\tset system.@system[-1].zonename='Asia/Shanghai'" "$CFG_FILE"

fi


# 默认shell zsh

echo ">>> 设置默认Shell"

sed -i 's#/bin/ash#/usr/bin/zsh#g' \
package/base-files/files/etc/passwd


# ttyd自动root登录

if [ -f feeds/packages/utils/ttyd/files/ttyd.config ]; then

sed -i 's#/bin/login#/bin/login -f root#g' \
feeds/packages/utils/ttyd/files/ttyd.config

fi


# ============================================================
# ========== x86 分区设置 ==========
# ============================================================

echo ">>> 设置x86分区"


# GRUB boot 1024K = 1MB

sed -i \
's/GRUB_BOOT_PARTSIZE:=256/GRUB_BOOT_PARTSIZE:=1024/g' \
target/linux/x86/image/Makefile


sed -i \
's/GRUB_EFI_BOOT_PARTSIZE:=256/GRUB_EFI_BOOT_PARTSIZE:=1024/g' \
target/linux/x86/image/Makefile


# kernel 6.12

sed -i \
's/KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.12/g' \
target/linux/x86/Makefile


# ============================================================
# ========== 系统参数优化 ==========
# ============================================================


echo ">>> 设置conntrack"


SYSCTL_FILE="package/base-files/files/etc/sysctl.conf"


if [ -f "$SYSCTL_FILE" ]; then

grep -q "nf_conntrack_max" "$SYSCTL_FILE" || cat >> "$SYSCTL_FILE" <<EOF

# OpenWrt Mini optimize
net.netfilter.nf_conntrack_max=65535

EOF

fi


# ============================================================
# ========== 删除原插件 ==========
# ============================================================


echo ">>> 删除需要替换插件"


REMOVE_FEEDS="
feeds/luci/themes/luci-theme-argon
feeds/luci/applications/luci-app-mosdns
feeds/luci/applications/luci-app-netdata
feeds/luci/applications/luci-app-pushbot
feeds/luci/applications/luci-app-dockerman
feeds/luci/applications/luci-app-diskman
"


for item in $REMOVE_FEEDS
do
    [ -e "$item" ] && rm -rf "$item"
done


# ============================================================
# ========== 工具函数 ==========
# ============================================================


clone_pkg()
{
    repo=$1
    dir=$2

    echo ">>> Clone $repo"

    rm -rf "$dir"

    git clone \
    --depth=1 \
    "$repo" \
    "$dir"
}


# ============================================================
# ========== 第三方插件 ==========
# ============================================================


echo ">>> 添加第三方插件"


clone_pkg \
https://github.com/gdy666/luci-app-lucky.git \
package/lucky


clone_pkg \
https://github.com/zzsj0928/luci-app-pushbot \
package/luci-app-pushbot


# Dockerman

git clone \
--depth=1 \
https://github.com/lisaac/luci-app-dockerman.git \
package/tmp-dockerman


cp -r \
package/tmp-dockerman/applications/luci-app-dockerman \
package/


rm -rf package/tmp-dockerman


clone_pkg \
https://github.com/lisaac/luci-lib-docker.git \
package/luci-lib-docker


clone_pkg \
https://github.com/lisaac/luci-app-diskman \
package/luci-app-diskman
# ============================================================
# ========== PassWall ==========
# ============================================================


echo ">>> 添加 PassWall"


clone_pkg \
https://github.com/Openwrt-Passwall/openwrt-passwall-packages \
package/openwrt-passwall-packages


clone_pkg \
https://github.com/Openwrt-Passwall/openwrt-passwall \
package/luci-app-passwall



# ============================================================
# ========== Argon主题 ==========
# ============================================================


echo ">>> 添加 Argon主题"


clone_pkg \
https://github.com/jerrykuku/luci-theme-argon \
package/luci-theme-argon


clone_pkg \
https://github.com/jerrykuku/luci-app-argon-config \
package/luci-app-argon-config



# 修改默认主题

if [ -f feeds/luci/collections/luci/Makefile ]; then

sed -i \
's/luci-theme-bootstrap/luci-theme-argon/g' \
feeds/luci/collections/luci/Makefile

fi



# ============================================================
# ========== Samba4替换 ==========
# ============================================================


echo ">>> 替换Samba4"


rm -rf feeds/packages/net/samba4


clone_pkg \
https://github.com/sbwml/feeds_packages_net_samba4 \
feeds/packages/net/samba4



SAMBA_CONF="feeds/packages/net/samba4/files/smb.conf.template"


if [ -f "$SAMBA_CONF" ]; then


grep -q "server multi channel support" "$SAMBA_CONF" || cat >> "$SAMBA_CONF" <<EOF

# enable multi-channel
server multi channel support = yes

aio read size = 1
aio write size = 1

EOF


fi



# ============================================================
# ========== 核心库更新 ==========
# ============================================================


echo ">>> 更新核心库"


merge_package()
{

branch=$1
repo=$2
target=$3

shift 3


tmp=$(mktemp -d)


git clone \
--depth=1 \
-b "$branch" \
--filter=blob:none \
--sparse \
"$repo" \
"$tmp"


cd "$tmp"


git sparse-checkout init --cone


git sparse-checkout set "$@"


for dir in "$@"
do

mv "$dir" "$OLDPWD/$target/"

done


cd - >/dev/null


rm -rf "$tmp"

}



merge_package \
master \
https://github.com/openwrt/packages \
feeds/packages/libs \
libs/nghttp3 \
libs/ngtcp2



# coremark替换

rm -rf feeds/packages/utils/coremark


merge_package \
main \
https://github.com/sbwml/openwrt_pkgs \
feeds/packages/utils \
coremark



# unzip替换

rm -rf feeds/packages/utils/unzip


clone_pkg \
https://github.com/sbwml/feeds_packages_utils_unzip \
feeds/packages/utils/unzip



# ============================================================
# ========== PassWall依赖清理 ==========
# ============================================================


echo ">>> 删除冲突科学插件"


REMOVE_SC="
feeds/packages/net/chinadns-ng
feeds/packages/net/sing-box
feeds/packages/net/xray-core
feeds/packages/net/mosdns
feeds/packages/net/smartdns
feeds/helloworld/luci-app-ssr-plus
"


for pkg in $REMOVE_SC
do

[ -e "$pkg" ] && rm -rf "$pkg"

done



# ============================================================
# ========== feeds更新安装 ==========
# ============================================================


echo ">>> 更新Feeds"


./scripts/feeds update -a


./scripts/feeds install -a



make defconfig
# ============================================================
# ========== 系统显示优化 ==========
# ============================================================


echo ">>> 优化首页显示"


AUTOCORE="package/lean/autocore/files/x86/autocore"


if [ -f "$AUTOCORE" ]; then

sed -i \
's/${g}.*/${a}${b}${c}${d}${e}${f}${hydrid}/g' \
"$AUTOCORE"

fi



for file in package/lean/autocore/files/*/index.htm
do

[ -f "$file" ] || continue


sed -i \
's/os.date()/os.date("%Y-%m-%d %H:%M:%S") .. " " .. translate(os.date("%A"))/g' \
"$file"


done



# ============================================================
# ========== 固件版本 ==========
# ============================================================


echo ">>> 设置版本号"


VERSION_FILE="package/lean/default-settings/files/zzz-default-settings"


if [ -f "$VERSION_FILE" ]; then


DATE_VERSION=$(date +"%y.%m.%d")


OLD_VERSION=$(grep DISTRIB_REVISION "$VERSION_FILE" \
| awk -F "'" '{print $2}')


if [ -n "$OLD_VERSION" ]; then


sed -i \
"s/${OLD_VERSION}/R${DATE_VERSION} by kxdn/g" \
"$VERSION_FILE"


fi


fi



# ============================================================
# ========== hostapd修复 ==========
# ============================================================


echo ">>> 检查hostapd补丁"


PATCH="$GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch"


if [ -f "$PATCH" ]; then


mkdir -p package/network/services/hostapd/patches


cp "$PATCH" \
package/network/services/hostapd/patches/011-fix-mbo-modules-build.patch


fi



# ============================================================
# ========== 第三方Makefile修复 ==========
# ============================================================


echo ">>> 修复第三方包路径"


find package -maxdepth 3 -name Makefile \
-exec sed -i \
's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' {} \;


find package -maxdepth 3 -name Makefile \
-exec sed -i \
's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' {} \;



# ============================================================
# ========== 驱动精简 ==========
# ============================================================


echo ">>> 清理无用驱动"


REMOVE_DRIVERS="
kmod-cfg80211
kmod-mac80211
wpad
hostapd
iw

kmod-bluetooth
kmod-btusb
kmod-ath3k
kmod-bcmbt
bluez

kmod-r816
kmod-8139too
kmod-8139cp
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
kmod-mmc
kmod-sdhci

kmod-sound
alsa-lib

kmod-video
kmod-media

kmod-i2c-
kmod-gpio-
kmod-spi-
"


for drv in $REMOVE_DRIVERS
do

sed -i "/CONFIG_PACKAGE_${drv}/d" .config

done



# ============================================================
# ========== 保留x86关键驱动 ==========
# ============================================================


echo ">>> 锁定关键驱动"


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



# ============================================================
# ========== 保留核心功能 ==========
# ============================================================


echo ">>> 检查核心组件"


CORE_PACKAGES="
luci-theme-argon
luci-app-passwall
luci-app-dockerman
luci-app-diskman
luci-app-lucky
luci-app-pushbot
ttyd
zsh
"


for pkg in $CORE_PACKAGES
do


grep -q "CONFIG_PACKAGE_${pkg}=y" .config || \
echo "CONFIG_PACKAGE_${pkg}=y" >> .config


done



# ============================================================
# ========== 最终检查 ==========
# ============================================================


echo
echo "=========================================="
echo " diy-mini.sh 执行完成"
echo
echo " Platform : x86_64"
echo " LuCI     : openwrt-25.12"
echo " Kernel   : 6.12"
echo " GRUB     : 1024K (1MB)"
echo " Kernel P : 16MB"
echo " Rootfs   : 2048MB"
echo " IP       : 10.0.0.1"
echo
echo " Plugins:"
echo " PassWall"
echo " DockerMan"
echo " DiskMan"
echo " Lucky"
echo " PushBot"
echo " Samba4"
echo " Argon"
echo " TTYD"
echo
echo "=========================================="
