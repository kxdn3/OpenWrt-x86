#!/bin/bash
#
# OpenWrt x86_64 Mini AIO 固件 DIY
#
# 基准:
#   源码: coolsnowwolf/lede master
#   LuCI: openwrt-25.12
#   Kernel: 6.12
#
# 功能:
#   PassWall
#   Docker
#   Samba4
#   DiskMan
#   DockerMan
#   Lucky
#   Argon
#
# 适用:
#   x86_64 小主机 / N100 / N5105 / J4125
#

set -e

echo "=========================================="
echo " OpenWrt x86_64 Mini DIY Start"
echo "=========================================="

OPENWRT_PATH="$PWD"


# ============================================================
# 基础检测
# ============================================================

echo ">>> 检查源码版本"

if [ -f package/base-files/files/etc/openwrt_release ]; then
    cat package/base-files/files/etc/openwrt_release
fi

echo

echo ">>> 检查 Kernel"

grep KERNEL_PATCHVER target/linux/x86/Makefile || true


# ============================================================
# 工具函数
# ============================================================

clone_package()
{
    local url="$1"
    local dir="$2"

    if [ -d "$dir" ]; then
        echo "已存在: $dir"
        return
    fi

    echo "Clone: $url"

    git clone --depth=1 "$url" "$dir"
}


merge_package()
{
    if [ $# -lt 3 ]; then
        echo "merge_package 参数错误"
        exit 1
    fi

    local branch="$1"
    local repo="$2"
    local target="$3"

    shift 3

    local tmpdir

    tmpdir=$(mktemp -d)

    git clone \
        -b "$branch" \
        --depth=1 \
        --filter=blob:none \
        --sparse \
        "$repo" \
        "$tmpdir"


    cd "$tmpdir"

    git sparse-checkout init --cone
    git sparse-checkout set "$@"

    for item in "$@"; do
        cp -rf "$item" "$OPENWRT_PATH/$target/"
    done


    cd "$OPENWRT_PATH"

    rm -rf "$tmpdir"
}



# ============================================================
# LuCI 分支固定
# ============================================================

echo ">>> 设置 LuCI 25.12"

sed -i '/^#\?src-git luci/d' feeds.conf.default

echo "src-git luci https://github.com/coolsnowwolf/luci.git;openwrt-25.12" \
>> feeds.conf.default



# ============================================================
# 系统默认设置
# ============================================================

echo ">>> 修改系统默认"

CFG_FILE="package/base-files/files/bin/config_generate"


if [ -f "$CFG_FILE" ]; then

    sed -i \
    's/192.168.1.1/10.0.0.1/g' \
    "$CFG_FILE"


    sed -i \
    "s/timezone='.*'/timezone='CST-8'/g" \
    "$CFG_FILE"


    sed -i \
    "/timezone='CST-8'/a\\
        uci set system.@system[-1].zonename='Asia/Shanghai'
    " \
    "$CFG_FILE"

fi



# 默认shell

sed -i \
's|/bin/ash|/usr/bin/zsh|g' \
package/base-files/files/etc/passwd



# ttyd 自动 root

if [ -f feeds/packages/utils/ttyd/files/ttyd.config ]; then

sed -i \
's|/bin/login|/bin/login -f root|g' \
feeds/packages/utils/ttyd/files/ttyd.config

fi



# ============================================================
# 镜像设置
# ============================================================

echo ">>> 设置 x86 镜像"

sed -i \
's/GRUB_BOOT_PARTSIZE:=256/GRUB_BOOT_PARTSIZE:=1024/g' \
target/linux/x86/image/Makefile


sed -i \
's/GRUB_EFI_BOOT_PARTSIZE:=256/GRUB_EFI_BOOT_PARTSIZE:=1024/g' \
target/linux/x86/image/Makefile



# ============================================================
# sysctl 网络优化
# ============================================================

SYSCTL_FILE="package/base-files/files/etc/sysctl.conf"


if ! grep -q nf_conntrack_max "$SYSCTL_FILE"; then

cat >> "$SYSCTL_FILE" <<EOF

# Docker / 高连接数优化
net.netfilter.nf_conntrack_max=65535

EOF

fi



# ============================================================
# 删除官方冲突插件
# ============================================================

echo ">>> 删除冲突 feeds"

rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/luci/applications/luci-app-netdata
rm -rf feeds/luci/applications/luci-app-dockerman
rm -rf feeds/luci/applications/luci-app-diskman



# ============================================================
# 第三方插件
# ============================================================

echo ">>> 添加第三方插件"


clone_package \
https://github.com/gdy666/luci-app-lucky.git \
package/lucky


clone_package \
https://github.com/zzsj0928/luci-app-pushbot \
package/luci-app-pushbot



# Dockerman

if [ ! -d package/luci-app-dockerman ]; then

git clone --depth=1 \
https://github.com/lisaac/luci-app-dockerman.git \
package/tmp-dockerman


cp -rf \
package/tmp-dockerman/applications/luci-app-dockerman \
package/


rm -rf package/tmp-dockerman

fi



clone_package \
https://github.com/lisaac/luci-lib-docker.git \
package/luci-lib-docker



clone_package \
https://github.com/lisaac/luci-app-diskman \
package/luci-app-diskman



# PassWall

clone_package \
https://github.com/Openwrt-Passwall/openwrt-passwall-packages \
package/openwrt-passwall-packages


clone_package \
https://github.com/Openwrt-Passwall/openwrt-passwall \
package/luci-app-passwall



# Argon

clone_package \
https://github.com/jerrykuku/luci-theme-argon \
package/luci-theme-argon


clone_package \
https://github.com/jerrykuku/luci-app-argon-config \
package/luci-app-argon-config


sed -i \
's/luci-theme-bootstrap/luci-theme-argon/g' \
feeds/luci/collections/luci/Makefile
sed -i \
's/luci-theme-bootstrap/luci-theme-argon/g' \
feeds/luci/collections/luci/Makefile


# ============================================================
# 软件包替换
# ============================================================

echo ">>> 替换核心软件包"


# nghttp3 / ngtcp2

merge_package \
master \
https://github.com/openwrt/packages \
feeds/packages/libs \
libs/nghttp3 \
libs/ngtcp2



# coremark

rm -rf feeds/packages/utils/coremark

merge_package \
main \
https://github.com/sbwml/openwrt_pkgs \
feeds/packages/utils \
coremark



# unzip

rm -rf feeds/packages/utils/unzip

clone_package \
https://github.com/sbwml/feeds_packages_utils_unzip \
feeds/packages/utils/unzip



# samba4

rm -rf feeds/packages/net/samba4


clone_package \
https://github.com/sbwml/feeds_packages_net_samba4 \
feeds/packages/net/samba4



if [ -f feeds/packages/net/samba4/files/smb.conf.template ]; then

sed -i \
'/workgroup/a\\
## enable multi-channel' \
feeds/packages/net/samba4/files/smb.conf.template


sed -i \
'/enable multi-channel/a\\
server multi channel support = yes' \
feeds/packages/net/samba4/files/smb.conf.template


sed -i \
's/#aio read size = 0/aio read size = 1/g' \
feeds/packages/net/samba4/files/smb.conf.template


sed -i \
's/#aio write size = 0/aio write size = 1/g' \
feeds/packages/net/samba4/files/smb.conf.template

fi



# ============================================================
# Autocore 信息优化
# ============================================================

echo ">>> 优化首页信息"


sed -i \
's/${g}.*/${a}${b}${c}${d}${e}${f}${hydrid}/g' \
package/lean/autocore/files/x86/autocore 2>/dev/null || true


find package/lean/autocore/files \
-name "index.htm" \
-exec sed -i \
's/os.date()/os.date("%Y-%m-%d %H:%M:%S") .. " " .. translate(os.date("%A"))/g' {} \; 2>/dev/null || true



# ============================================================
# 固件版本
# ============================================================

echo ">>> 设置固件版本"


DATE_VERSION=$(date +"%y.%m.%d")


VERSION_FILE="package/lean/default-settings/files/zzz-default-settings"


if [ -f "$VERSION_FILE" ]; then

OLD_VERSION=$(grep DISTRIB_REVISION "$VERSION_FILE" | awk -F "'" '{print $2}')


if [ -n "$OLD_VERSION" ]; then

sed -i \
"s/${OLD_VERSION}/R${DATE_VERSION} by kxdn/g" \
"$VERSION_FILE"

fi

fi



# ============================================================
# feeds 安装前处理
# ============================================================

echo ">>> 修正第三方 Makefile"


find package -name Makefile \
-exec sed -i \
's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' {} \;


find package -name Makefile \
-exec sed -i \
's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' {} \;



# ============================================================
# feeds 已由 workflow 更新
# ============================================================

echo ">>> feeds 已完成更新"



# ============================================================
# 安装 feeds
# ============================================================

./scripts/feeds install -a


make defconfig



# ============================================================
# Docker 内核支持
# ============================================================

echo ">>> 添加 Docker 内核模块"


DOCKER_MODULES="
kmod-bridge
kmod-veth
kmod-nf-nat
kmod-nf-conntrack
kmod-nf-conntrack6
kmod-ipt-nat
kmod-ipt-extra
"


for mod in $DOCKER_MODULES
do

sed -i "/CONFIG_PACKAGE_${mod}/d" .config

echo "CONFIG_PACKAGE_${mod}=y" >> .config

done



# ============================================================
# x86 硬件驱动
# ============================================================

echo ">>> 固定 x86 驱动"


X86_MODULES="
kmod-igc
kmod-e1000e
kmod-ixgbe
kmod-i40e
kmod-ahci
kmod-nvme
kmod-virtio
"


for mod in $X86_MODULES
do

sed -i "/CONFIG_PACKAGE_${mod}/d" .config

echo "CONFIG_PACKAGE_${mod}=y" >> .config

done



# ============================================================
# IPv6
# ============================================================

echo ">>> IPv6 支持"


IPV6_PACKAGES="
odhcp6c
odhcpd-ipv6only
"


for pkg in $IPV6_PACKAGES
do

sed -i "/CONFIG_PACKAGE_${pkg}/d" .config

echo "CONFIG_PACKAGE_${pkg}=y" >> .config

done



# ============================================================
# Samba 工具
# ============================================================

sed -i '/CONFIG_PACKAGE_samba4-utils/d' .config

echo "CONFIG_PACKAGE_samba4-utils=y" >> .config



# ============================================================
# 删除无用镜像
# ============================================================

echo ">>> 删除 targz 镜像"


sed -i '/CONFIG_TARGET_ROOTFS_TARGZ/d' .config

echo "# CONFIG_TARGET_ROOTFS_TARGZ is not set" >> .config



# ============================================================
# 最终配置
# ============================================================

make defconfig


echo
echo "=========================================="
echo " DIY 完成"
echo
echo "平台:"
grep CONFIG_TARGET_BOARD .config
echo
echo "Kernel:"
grep KERNEL_PATCHVER target/linux/x86/Makefile
echo
echo "Rootfs:"
grep CONFIG_TARGET_ROOTFS_PARTSIZE .config
echo
echo "Docker:"
grep CONFIG_PACKAGE_dockerd .config
echo
echo "PassWall:"
grep CONFIG_PACKAGE_luci-app-passwall .config
echo
echo "=========================================="
