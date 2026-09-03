#!/bin/bash
#
# OpenWrt x86_64 Mini 自定义编译脚本（修复版）
# 源码基准: coolsnowwolf/lede (master)
# LuCI 分支: coolsnowwolf/luci (openwrt-25.12)
# 内核版本: 6.12 (lede master 默认)
#
set -e

# ========== 基础配置 ==========
# 获取脚本所在目录（OpenWrt 源码根目录）
OPENWRT_PATH="$(cd "$(dirname "$0")" && pwd)"
cd "$OPENWRT_PATH"

# 目标配置文件路径（用于时区等 uci 默认值修改）
CFG_FILE="package/base-files/files/bin/config_generate"

# ========== LuCI 源切换 ==========
# 删除原有 luci 源，切换到 openwrt-25.12 分支
sed -i '/^#\?src-git luci/d' feeds.conf.default
echo "src-git luci https://github.com/coolsnowwolf/luci.git;openwrt-25.12" >> feeds.conf.default

# ========== 系统默认值修改 ==========
# 修改默认 IP 为 10.0.0.1
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# 修改默认时区为 Asia/Shanghai (CST-8)
if [ -f "$CFG_FILE" ]; then
    sed -i "s/timezone='.*'/timezone='CST-8'/g" "$CFG_FILE"
    sed -i "/timezone='CST-8'/a\\\t\t\set system.@system[-1].zonename='Asia/Shanghai'" "$CFG_FILE"
fi

# 更改默认 Shell 为 zsh
sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# TTYD 免登录（注意：有安全风险，仅建议内网使用）
sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# ========== 镜像与内核配置 ==========
# 更改 boot 分区大小为 1MB
sed -i 's/GRUB_BOOT_PARTSIZE:=256/GRUB_BOOT_PARTSIZE:=1024/g' target/linux/x86/image/Makefile
sed -i 's/GRUB_EFI_BOOT_PARTSIZE:=256/GRUB_EFI_BOOT_PARTSIZE:=1024/g' target/linux/x86/image/Makefile

# 内核版本（显式声明，lede master 默认为 6.12）
sed -i 's/KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.12/g' ./target/linux/x86/Makefile

# 最大连接数修改为 65535
if ! grep -q 'nf_conntrack_max' package/base-files/files/etc/sysctl.conf; then
    sed -i '/customized in this file/a net.netfilter.nf_conntrack_max=65535' package/base-files/files/etc/sysctl.conf
fi

# ========== 辅助函数定义 ==========
# 从第三方仓库稀疏克隆指定文件夹到目标路径
function merge_package() {
    if [[ $# -lt 3 ]]; then
        echo "Syntax error: [$#] [$*]" >&2
        return 1
    fi
    trap 'rm -rf "$tmpdir"' EXIT
    branch="$1" curl="$2" target_dir="$3" && shift 3
    rootdir="$PWD"
    localdir="$target_dir"
    [ -d "$localdir" ] || mkdir -p "$localdir"
    tmpdir="$(mktemp -d)" || exit 1
    git clone -b "$branch" --depth 1 --filter=blob:none --sparse "$curl" "$tmpdir"
    cd "$tmpdir"
    git sparse-checkout init --cone
    git sparse-checkout set "$@"
    for folder in "$@"; do
        mv -f "$folder" "$rootdir/$localdir"
    done
    cd "$rootdir"
}

# Git 稀疏克隆，只克隆指定目录到 package/
function git_sparse_clone() {
    branch="$1" repourl="$2" && shift 2
    git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
    repodir=$(echo "$repourl" | awk -F '/' '{print $(NF)}')
    cd "$repodir" && git sparse-checkout set "$@"
    mv -f "$@" ../package
    cd .. && rm -rf "$repodir"
}

# ========== 更新 feeds 并准备 ==========
# 先更新一次，以便后续删除 feeds 中的包
./scripts/feeds update -a

# ========== 移除需要替换的 feeds 包（在 update 后执行） ==========
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/luci/applications/luci-app-netdata
rm -rf feeds/luci/applications/luci-app-pushbot
rm -rf feeds/luci/applications/luci-app-dockerman
rm -rf feeds/luci/applications/luci-app-diskman

# 科学上网相关核心（将由 passwall-packages 提供）
rm -rf feeds/packages/net/chinadns-ng
rm -rf feeds/packages/net/sing-box
rm -rf feeds/packages/net/xray-core
rm -rf feeds/packages/net/mosdns
rm -rf feeds/packages/net/msd_lite
rm -rf feeds/packages/net/smartdns
rm -rf feeds/luci/luci-app-msd_lite
rm -rf feeds/luci/luci-app-smartdns

# ========== 添加第三方插件 ==========
# Lucky
git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/lucky

# PushBot
git clone --depth=1 https://github.com/kxdn3/luci-app-pushbot package/luci-app-pushbot

# DockerMan
git clone https://github.com/lisaac/luci-app-dockerman.git package/tmp-dockerman
cp -r package/tmp-dockerman/applications/luci-app-dockerman package/
rm -rf package/tmp-dockerman
git clone https://github.com/lisaac/luci-lib-docker.git package/luci-lib-docker

# DiskMan
git clone --depth=1 https://github.com/lisaac/luci-app-diskman package/applications/luci-app-diskman

# PassWall 依赖包
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall-packages

# PassWall LuCI 界面
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall

# Argon 主题及配置
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config

# ========== 核心库与工具替换/升级 ==========
# nghttp3 / ngtcp2
merge_package master https://github.com/openwrt/packages feeds/packages/libs libs/nghttp3 libs/ngtcp2

# coremark
rm -rf feeds/packages/utils/coremark
merge_package main https://github.com/sbwml/openwrt_pkgs feeds/packages/utils coremark

# unzip
rm -rf feeds/packages/utils/unzip
git clone --depth=1 https://github.com/sbwml/feeds_packages_utils_unzip feeds/packages/utils/unzip

# samba4
rm -rf feeds/packages/net/samba4
git clone --depth=1 https://github.com/sbwml/feeds_packages_net_samba4 feeds/packages/net/samba4
if [ -f feeds/packages/net/samba4/files/smb.conf.template ]; then
    sed -i '/workgroup/a \\n\t## enable multi-channel' feeds/packages/net/samba4/files/smb.conf.template
    sed -i '/enable multi-channel/a \\tserver multi channel support = yes' feeds/packages/net/samba4/files/smb.conf.template
    sed -i 's/#aio read size = 0/aio read size = 1/g' feeds/packages/net/samba4/files/smb.conf.template
    sed -i 's/#aio write size = 0/aio write size = 1/g' feeds/packages/net/samba4/files/smb.conf.template
fi

# ========== 显示与信息优化 ==========
# x86 型号只显示 CPU 型号
sed -i 's/${g}.*/${a}${b}${c}${d}${e}${f}${hydrid}/g' package/lean/autocore/files/x86/autocore

# 修改本地时间格式
sed -i 's#os.date()#os.date("%Y-%m-%d %H:%M:%S") .. " " .. translate(os.date("%A"))#g' package/lean/autocore/files/*/index.htm

# 去除主页 LuCI 版本号显示
sed -i 's/distversion)%>/distversion)%><!--/g' package/lean/autocore/files/*/index.htm
sed -i 's/luciversion)%>)/luciversion)%>)-->/g' package/lean/autocore/files/*/index.htm

# ========== 版本与安全设置 ==========
# 修改版本号为编译日期
date_version=$(date +"%y.%m.%d")
orig_version=$(grep DISTRIB_REVISION= package/lean/default-settings/files/zzz-default-settings | awk -F "'" '{print $2}')
if [ -n "$orig_version" ]; then
    # 使用 | 作为分隔符，避免版本号含 / 导致错误
    sed -i "s|${orig_version}|R${date_version} by kxdn|g" package/lean/default-settings/files/zzz-default-settings
fi

# 取消默认 root 密码：直接追加清空密码的命令（更可靠）
# 注意：该文件是 Shell 脚本，追加在末尾会生效
echo "sed -i '/^root:/d' /etc/shadow" >> package/lean/default-settings/files/zzz-default-settings

# ========== 修复 hostapd 编译错误 ==========
# 查找补丁文件（优先使用脚本同级的 scripts/ 目录）
PATCH_FILE="$(dirname "$0")/scripts/011-fix-mbo-modules-build.patch"
if [ -f "$PATCH_FILE" ]; then
    cp -f "$PATCH_FILE" package/network/services/hostapd/patches/011-fix-mbo-modules-build.patch
fi

# ========== 修正第三方包 Makefile 路径问题 ==========
find package/*/ -maxdepth 2 -path "*/Makefile" -exec sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' {} \;
find package/*/ -maxdepth 2 -path "*/Makefile" -exec sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' {} \;
find package/*/ -maxdepth 2 -path "*/Makefile" -exec sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' {} \;
find package/*/ -maxdepth 2 -path "*/Makefile" -exec sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' {} \;

# ========== 设置默认主题为 argon（在 install 后修改，避免被覆盖） ==========
# 注意：需要等 feeds install 之后再改，因此放在后面，但我们现在提前修改？实际上 install 会复制 feeds/luci/... 到 staging_dir，不会覆盖 feeds/ 目录，所以现在改也可以。
# 但为安全，我们放在 install 之后（见下文）

# ========== 再次更新并安装 feeds ==========
# 因为添加了第三方包，需要更新索引，但已有一次 update，现在只需 install
# 但为了保险，再次运行 update（但不再删除包，因为之前已删除）
./scripts/feeds update -a
./scripts/feeds install -a

# 修改默认主题（在 install 后执行，确保目标文件存在）
if [ -f feeds/luci/collections/luci/Makefile ]; then
    sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
fi

# ========== 配置编译选项 ==========
make defconfig

# autocore x86首页硬件信息依赖
sed -i 's/^# CONFIG_BC is not set/CONFIG_BC=y/' .config
sed -i 's/^# CONFIG_PCIUTILS is not set/CONFIG_PCIUTILS=y/' .config
sed -i 's/^# CONFIG_LM_SENSORS is not set/CONFIG_LM_SENSORS=y/' .config

# ========== 驱动精简（增强版） ==========
echo ">>> 锁定 kmod-igc 驱动..."
# 删除原有行，追加 =y
sed -i '/CONFIG_PACKAGE_kmod-igc/d' .config
echo "CONFIG_PACKAGE_kmod-igc=y" >> .config

echo ">>> 删除无线驱动..."
for pkg in kmod-cfg80211 kmod-mac80211 wpad hostapd iw; do
    sed -i "/CONFIG_PACKAGE_${pkg}/d" .config
done
echo "# CONFIG_PACKAGE_kmod-cfg80211 is not set" >> .config
echo "# CONFIG_PACKAGE_kmod-mac80211 is not set" >> .config

echo ">>> 删除蓝牙驱动..."
for pkg in kmod-bluetooth kmod-btusb kmod-ath3k kmod-bcmbt kmod-rtl_bt bluez; do
    sed -i "/CONFIG_PACKAGE_${pkg}/d" .config
done

echo ">>> 删除非 Intel 网卡驱动..."
for pkg in r816 8139 r8125 tg3 bnx2 sky2 pcnet32 via-forcedeth natsemi sis900 usb-net-; do
    sed -i "/CONFIG_PACKAGE_kmod-${pkg}/d" .config
done

echo ">>> 删除非 Intel 显示驱动..."
for pkg in drm-amdgpu nouveau; do
    sed -i "/CONFIG_PACKAGE_kmod-${pkg}/d" .config
done

echo ">>> 删除蜂窝模块..."
for pkg in mhi qmi usb-net-qmi; do
    sed -i "/CONFIG_PACKAGE_kmod-${pkg}/d" .config
done

echo ">>> 深度清理冗余组件（NFS保留）..."
for pkg in ata-piix pata- firewire- parport serial- i2c- gpio- spi- tokenring atm sound- alsa- video- media- mmc sdhci fs-isofs fs-udf input-touchscreen input-tablet thinkpad_acpi ideapad-laptop battery; do
    sed -i "/CONFIG_PACKAGE_kmod-${pkg}/d" .config
done
# 网络调试工具
for pkg in tcpdump strace gdb; do
    sed -i "/CONFIG_PACKAGE_${pkg}/d" .config
done

echo ">>> 验证关键驱动保留情况："
grep -E "CONFIG_PACKAGE_kmod-(igc|ahci|virtio)" .config || echo "注意：未找到 igc/ahci/virtio，请检查"

# 再次执行 defconfig 使配置生效
make defconfig

echo "=========================================="
echo "  diy-mini.sh 执行完成（修复版）"
echo "  LuCI 分支: openwrt-25.12"
echo "  内核版本: 6.12"
echo "  默认 IP: 10.0.0.1"
echo "  默认主题: argon"
echo "=========================================="
