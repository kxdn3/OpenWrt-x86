#!/bin/bash
#
# OpenWrt x86_64 Mini 自定义编译脚本
# 源码: coolsnowwolf/lede master
# LuCI: openwrt-25.12
# 内核: 6.12
#
set -e

OPENWRT_PATH="$PWD"

CFG_FILE="package/base-files/files/bin/config_generate"

echo ">>> 开始执行DIY脚本"

# ============================================================
# LuCI源切换
# ============================================================

echo ">>> 切换LuCI分支"

sed -i '/^#\?src-git luci/d' feeds.conf.default

echo "src-git luci https://github.com/coolsnowwolf/luci.git;openwrt-25.12" >> feeds.conf.default


# ============================================================
# 默认网络设置
# ============================================================

echo ">>> 修改默认IP"

sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate


# 默认时区

if [ -f "$CFG_FILE" ]; then

sed -i "s/timezone='.*'/timezone='CST-8'/g" "$CFG_FILE"

grep -q "Asia/Shanghai" "$CFG_FILE" || \
sed -i "/timezone='CST-8'/a\	\tsystem.@system[-1].zonename='Asia/Shanghai'" "$CFG_FILE"

fi


# ============================================================
# 默认Shell修改
# ============================================================

echo ">>> 设置zsh"

sed -i 's#/bin/ash#/usr/bin/zsh#g' package/base-files/files/etc/passwd


# ttyd自动登录root

if [ -f feeds/packages/utils/ttyd/files/ttyd.config ]; then

sed -i 's#/bin/login#/bin/login -f root#g' feeds/packages/utils/ttyd/files/ttyd.config

fi


# ============================================================
# x86镜像设置
# ============================================================

echo ">>> 修改x86镜像"


# GRUB引导分区
# 256K -> 1024K (1MB)

sed -i \
's/GRUB_BOOT_PARTSIZE:=256/GRUB_BOOT_PARTSIZE:=1024/g' \
target/linux/x86/image/Makefile


sed -i \
's/GRUB_EFI_BOOT_PARTSIZE:=256/GRUB_EFI_BOOT_PARTSIZE:=1024/g' \
target/linux/x86/image/Makefile


# 内核6.12

sed -i \
's/KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.12/g' \
target/linux/x86/Makefile


# ============================================================
# 内核参数优化
# ============================================================

echo ">>> 设置连接数"


SYSCTL="package/base-files/files/etc/sysctl.conf"

if ! grep -q nf_conntrack_max "$SYSCTL"; then

cat >> "$SYSCTL" <<EOF

# 最大连接数
net.netfilter.nf_conntrack_max=65535

EOF

fi


# ============================================================
# 下载第三方包函数
# ============================================================


clone_pkg()
{

repo=$1
dir=$2

rm -rf "$dir"

git clone --depth=1 "$repo" "$dir"

}


# 稀疏克隆函数

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

for p in "$@"
do

mv "$p" "$OLDPWD/$target/"

done

cd - >/dev/null

rm -rf "$tmp"

}


echo ">>> 基础设置完成"
# ============================================================
# 第三方插件
# ============================================================

echo ">>> 添加第三方插件"


# Lucky DDNS/端口转发

clone_pkg \
https://github.com/gdy666/luci-app-lucky \
package/lucky



# PushBot消息推送

clone_pkg \
https://github.com/zzsj0928/luci-app-pushbot \
package/luci-app-pushbot



# ============================================================
# DockerMan
# ============================================================

echo ">>> 添加DockerMan"


clone_pkg \
https://github.com/lisaac/luci-lib-docker \
package/luci-lib-docker


git clone --depth=1 \
https://github.com/lisaac/luci-app-dockerman.git \
package/tmp-dockerman


if [ -d package/tmp-dockerman/applications/luci-app-dockerman ]; then

mv package/tmp-dockerman/applications/luci-app-dockerman \
package/luci-app-dockerman

fi


rm -rf package/tmp-dockerman



# ============================================================
# DiskMan
# ============================================================

echo ">>> 添加DiskMan"


clone_pkg \
https://github.com/lisaac/luci-app-diskman \
package/luci-app-diskman



# ============================================================
# PassWall
# ============================================================

echo ">>> 添加PassWall"


# PassWall官方依赖仓库
# xray-core/chinadns-ng由PassWall依赖管理

clone_pkg \
https://github.com/Openwrt-Passwall/openwrt-passwall-packages \
package/openwrt-passwall-packages


clone_pkg \
https://github.com/Openwrt-Passwall/openwrt-passwall \
package/luci-app-passwall



# ============================================================
# Argon主题
# ============================================================

echo ">>> 添加Argon主题"


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
# Samba4替换
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
# 核心库替换
# ============================================================

echo ">>> 更新核心库"


merge_package \
master \
https://github.com/openwrt/packages \
feeds/packages/libs \
libs/nghttp3 \
libs/ngtcp2



# coremark优化

rm -rf feeds/packages/utils/coremark


merge_package \
main \
https://github.com/sbwml/openwrt_pkgs \
feeds/packages/utils \
coremark



# unzip优化

rm -rf feeds/packages/utils/unzip


clone_pkg \
https://github.com/sbwml/feeds_packages_utils_unzip \
feeds/packages/utils/unzip



# ============================================================
# 删除冲突插件
# ============================================================

echo ">>> 删除冲突插件"


# 注意：
# xray-core和chinadns-ng不删除
# 由PassWall依赖管理


REMOVE_PACKAGES="
feeds/packages/net/mosdns
feeds/packages/net/smartdns
feeds/packages/net/sing-box
feeds/helloworld/luci-app-ssr-plus
"


for pkg in $REMOVE_PACKAGES
do

if [ -e "$pkg" ]; then

rm -rf "$pkg"

echo "删除: $pkg"

fi

done



echo ">>> 第三方插件处理完成"
# ============================================================
# 修复第三方包Makefile路径
# ============================================================

echo ">>> 修复第三方包路径"


find package -maxdepth 3 -name Makefile \
-exec sed -i \
's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' {} \;


find package -maxdepth 3 -name Makefile \
-exec sed -i \
's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' {} \;



# ============================================================
# 更新feeds
# ============================================================

echo ">>> 更新Feeds"


./scripts/feeds update -a

./scripts/feeds install -a



# ============================================================
# 生成配置
# ============================================================

echo ">>> 生成配置"


make defconfig



# ============================================================
# x86硬件信息依赖
# ============================================================

echo ">>> 开启硬件信息支持"


sed -i \
's/^# CONFIG_BC is not set/CONFIG_BC=y/' \
.config


sed -i \
's/^# CONFIG_PCIUTILS is not set/CONFIG_PCIUTILS=y/' \
.config


sed -i \
's/^# CONFIG_LM_SENSORS is not set/CONFIG_LM_SENSORS=y/' \
.config



# ============================================================
# 保留关键驱动
# ============================================================

echo ">>> 保留核心驱动"


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
# 清理无线驱动
# ============================================================

echo ">>> 清理无线驱动"


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
kmod-pata-
kmod-ata-piix

kmod-sound
alsa-

kmod-video
kmod-media

kmod-i2c-
kmod-gpio-
kmod-spi-

kmod-mmc
kmod-sdhci

kmod-fs-isofs
kmod-fs-udf

kmod-input-touchscreen
kmod-input-tablet
"


for drv in $REMOVE_DRIVERS
do

sed -i "/CONFIG_PACKAGE_${drv}/d" .config

done



# ============================================================
# 清理调试工具
# ============================================================

echo ">>> 清理调试工具"


for pkg in tcpdump strace gdb
do

sed -i "/CONFIG_PACKAGE_${pkg}/d" .config

done



# ============================================================
# 重新生成依赖
# ============================================================

make defconfig



# ============================================================
# 固件版本
# ============================================================

echo ">>> 设置固件版本"


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
# 清理root密码自动登录
# ============================================================


if [ -f "$VERSION_FILE" ]; then

sed -i '/\/etc\/shadow/{/root/d;}' "$VERSION_FILE"

fi



# ============================================================
# 最终检查
# ============================================================


echo
echo "=========================================="
echo " DIY Mini Build Script 完成"
echo
echo "源码:"
echo "coolsnowwolf/lede master"
echo
echo "LuCI:"
echo "openwrt-25.12"
echo
echo "Kernel:"
echo "6.12"
echo
echo "默认IP:"
echo "10.0.0.1"
echo
echo "GRUB:"
echo "1024K (1MB)"
echo
echo "ROOTFS:"
echo "2048MB"
echo
echo "插件:"
echo "PassWall"
echo "DockerMan"
echo "DiskMan"
echo "Lucky"
echo "PushBot"
echo "Samba4"
echo "Argon"
echo "TTYD"
echo
echo "=========================================="

