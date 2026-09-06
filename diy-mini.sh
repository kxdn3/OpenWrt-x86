#!/bin/bash
#
# OpenWrt x86_64 Mini 自定义编译脚本
# 源码基准: coolsnowwolf/lede (master)
# LuCI 分支: coolsnowwolf/luci (openwrt-25.12)
# 内核版本: 6.12 (lede master 默认)
#
set -e

# ========== 基础配置 ==========
OPENWRT_PATH="$PWD"  # 定义工作路径

# ========== 目标配置文件路径 ==========
CFG_FILE="package/base-files/files/bin/config_generate"

# ========== LuCI 源切换 ==========
sed -i '/^#\?src-git luci/d' feeds.conf.default
echo "src-git luci https://github.com/coolsnowwolf/luci.git;openwrt-25.12" >> feeds.conf.default

# ========== 系统默认值修改 ==========
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

if [ -f "$CFG_FILE" ]; then
    sed -i "s/timezone='.*'/timezone='CST-8'/g" "$CFG_FILE"
    sed -i "/timezone='CST-8'/a\\\t\t\set system.@system[-1].zonename='Asia/Shanghai'" "$CFG_FILE"
fi

sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd
sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# ========== 镜像与内核配置 ==========
sed -i 's/GRUB_BOOT_PARTSIZE:=256/GRUB_BOOT_PARTSIZE:=1024/g' target/linux/x86/image/Makefile
sed -i 's/GRUB_EFI_BOOT_PARTSIZE:=256/GRUB_EFI_BOOT_PARTSIZE:=1024/g' target/linux/x86/image/Makefile
sed -i 's/KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.12/g' ./target/linux/x86/Makefile

if ! grep -q 'nf_conntrack_max' package/base-files/files/etc/sysctl.conf; then
    sed -i '/customized in this file/a net.netfilter.nf_conntrack_max=65535' package/base-files/files/etc/sysctl.conf
fi

# ========== 辅助函数定义 ==========
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

function git_sparse_clone() {
    branch="$1" repourl="$2" && shift 2
    git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
    repodir=$(echo "$repourl" | awk -F '/' '{print $(NF)}')
    cd "$repodir" && git sparse-checkout set "$@"
    mv -f "$@" ../package
    cd .. && rm -rf "$repodir"
}

# ========== 移除需要替换的 feeds 包 ==========
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/luci/applications/luci-app-netdata
rm -rf feeds/luci/applications/luci-app-pushbot
rm -rf feeds/luci/applications/luci-app-dockerman
rm -rf feeds/luci/applications/luci-app-diskman

# ========== 添加第三方插件 ==========
git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/lucky
git clone --depth=1 https://github.com/zzsj0928/luci-app-pushbot package/luci-app-pushbot

git clone https://github.com/lisaac/luci-app-dockerman.git package/tmp-dockerman
cp -r package/tmp-dockerman/applications/luci-app-dockerman package/
rm -rf package/tmp-dockerman
git clone https://github.com/lisaac/luci-lib-docker.git package/luci-lib-docker

git clone --depth=1 https://github.com/lisaac/luci-app-diskman package/applications/luci-app-diskman

# ========== 科学上网: PassWall ==========
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall-packages
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall

# ========== 主题 ==========
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' ./feeds/luci/collections/luci/Makefile

# ========== 核心库与工具替换/升级 ==========
merge_package master https://github.com/openwrt/packages feeds/packages/libs libs/nghttp3 libs/ngtcp2

rm -rf feeds/packages/utils/coremark
merge_package main https://github.com/sbwml/openwrt_pkgs feeds/packages/utils coremark

rm -rf feeds/packages/utils/unzip
git clone --depth=1 https://github.com/sbwml/feeds_packages_utils_unzip feeds/packages/utils/unzip

rm -rf feeds/packages/net/samba4
git clone --depth=1 https://github.com/sbwml/feeds_packages_net_samba4 feeds/packages/net/samba4

if [ -f feeds/packages/net/samba4/files/smb.conf.template ]; then
    sed -i '/workgroup/a \\n\t## enable multi-channel' feeds/packages/net/samba4/files/smb.conf.template
    sed -i '/enable multi-channel/a \\tserver multi channel support = yes' feeds/packages/net/samba4/files/smb.conf.template
    sed -i 's/#aio read size = 0/aio read size = 1/g' feeds/packages/net/samba4/files/smb.conf.template
    sed -i 's/#aio write size = 0/aio write size = 1/g' feeds/packages/net/samba4/files/smb.conf.template
fi

# ========== 显示与信息优化 ==========
sed -i 's/${g}.*/${a}${b}${c}${d}${e}${f}${hydrid}/g' package/lean/autocore/files/x86/autocore
sed -i 's#os.date()#os.date("%Y-%m-%d %H:%M:%S") .. " " .. translate(os.date("%A"))#g' package/lean/autocore/files/*/index.htm
sed -i 's/distversion)%>/distversion)%><!--/g' package/lean/autocore/files/*/index.htm
sed -i 's/luciversion)%>)/luciversion)%>)-->/g' package/lean/autocore/files/*/index.htm

# ========== 版本与安全设置 ==========
date_version=$(date +"%y.%m.%d")
orig_version=$(grep DISTRIB_REVISION= package/lean/default-settings/files/zzz-default-settings | awk -F "'" '{print $2}')
if [ -n "$orig_version" ]; then
    sed -i "s/${orig_version}/R${date_version} by kxdn/g" package/lean/default-settings/files/zzz-default-settings
fi
sed -i '/\/etc\/shadow/{/root/d;}' package/lean/default-settings/files/zzz-default-settings

# ========== 修复 hostapd 编译错误 ==========
if [ -f "$GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch" ]; then
    cp -f "$GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch" package/network/services/hostapd/patches/011-fix-mbo-modules-build.patch
fi

# ========== 修正第三方包 Makefile 路径问题 ==========
find package/*/ -maxdepth 2 -path "*/Makefile" -exec sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' {} \;
find package/*/ -maxdepth 2 -path "*/Makefile" -exec sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' {} \;
find package/*/ -maxdepth 2 -path "*/Makefile" -exec sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' {} \;
find package/*/ -maxdepth 2 -path "*/Makefile" -exec sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' {} \;

# ==========================================
# ========== 统一执行 feeds 更新 ==========
# ==========================================
echo ">>> 更新 feeds..."
./scripts/feeds update -a

# ==========================================
# ========== 删除冲突包（路径修正 + 验证） ==========
# ==========================================
echo ">>> 移除冲突包（统一处理）..."

REMOVE_PACKAGES=(
    "feeds/packages/net/chinadns-ng"
    "feeds/packages/net/sing-box"
    "feeds/packages/net/xray-core"
    "feeds/packages/net/mosdns"
    "feeds/packages/net/msd_lite"
    "feeds/packages/net/smartdns"
    "feeds/luci/applications/luci-app-msd_lite"   # ✅ 修正路径
    "feeds/luci/applications/luci-app-smartdns"   # ✅ 修正路径
    "feeds/helloworld/luci-app-ssr-plus"
)

for pkg in "${REMOVE_PACKAGES[@]}"; do
    if [ -e "$pkg" ]; then
        rm -rf "$pkg"
        echo "  ✅ 已移除: $pkg"
    else
        echo "  ⚠️ 未找到: $pkg（可能已被移除或不存在）"
    fi
done

# 二次扫描，防止有残留（如被安装到其他目录）
echo ">>> 二次扫描删除可能残留的 luci-app-msd_lite / luci-app-smartdns ..."
find feeds/luci -type d -name "luci-app-msd_lite" -exec rm -rf {} \; 2>/dev/null
find feeds/luci -type d -name "luci-app-smartdns" -exec rm -rf {} \; 2>/dev/null

# 验证是否真的删除
echo ">>> 验证关键包是否已移除："
for pkg in "luci-app-msd_lite" "luci-app-smartdns"; do
    if find feeds/luci -type d -name "$pkg" | grep -q .; then
        echo "  ❌ 警告：$pkg 仍然存在！"
    else
        echo "  ✅ $pkg 已成功删除"
    fi
done

# 清理 .config 中残留的配置项
echo ">>> 清理 .config 中相关配置..."
sed -i '/CONFIG_PACKAGE_luci-app-msd_lite/d' .config 2>/dev/null
sed -i '/CONFIG_PACKAGE_luci-app-smartdns/d' .config 2>/dev/null
sed -i '/CONFIG_PACKAGE_msd_lite/d' .config 2>/dev/null
sed -i '/CONFIG_PACKAGE_smartdns/d' .config 2>/dev/null

# ==========================================
# ========== 重新安装 feeds 并生成配置 ==========
# ==========================================
./scripts/feeds install -a
make defconfig

# 最终检查 .config 是否还有残留（仅输出，不修改）
echo ">>> 最终检查 .config 中是否残留相关配置..."
grep -E "CONFIG_PACKAGE_(luci-app-msd_lite|luci-app-smartdns|msd_lite|smartdns)" .config || echo "  ✅ 无相关配置残留"

# ==========================================
# ========== 优化后的驱动清理 ==========
# ==========================================

# autocore x86首页硬件信息依赖
sed -i 's/^# CONFIG_BC is not set/CONFIG_BC=y/' .config
sed -i 's/^# CONFIG_PCIUTILS is not set/CONFIG_PCIUTILS=y/' .config
sed -i 's/^# CONFIG_LM_SENSORS is not set/CONFIG_LM_SENSORS=y/' .config
make defconfig

# ========== 锁定关键驱动 ==========
echo ">>> 锁定 kmod-igc 驱动..."
sed -i 's/CONFIG_PACKAGE_kmod-igc=m/CONFIG_PACKAGE_kmod-igc=y/' .config
sed -i 's/# CONFIG_PACKAGE_kmod-igc is not set/CONFIG_PACKAGE_kmod-igc=y/' .config
grep -q "CONFIG_PACKAGE_kmod-igc=y" .config || echo "CONFIG_PACKAGE_kmod-igc=y" >> .config

# ========== 批量清理驱动 ==========

# 1. 无线驱动
echo ">>> 清理无线驱动..."
WIRELESS_DRIVERS="kmod-cfg80211 kmod-mac80211 wpad hostapd iw"
for drv in $WIRELESS_DRIVERS; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done

# 2. 蓝牙驱动
echo ">>> 清理蓝牙驱动..."
BLUETOOTH_DRIVERS="kmod-bluetooth kmod-btusb kmod-ath3k kmod-bcmbt kmod-rtl_bt bluez"
for drv in $BLUETOOTH_DRIVERS; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done

# 3. 非 Intel 网卡驱动
echo ">>> 清理非 Intel 网卡驱动..."
NON_INTEL_NICS="kmod-r816 kmod-8139too kmod-8139cp kmod-r8125 kmod-tg3 kmod-bnx2 kmod-sky2 kmod-pcnet32 kmod-via-rhine kmod-via-velocity kmod-forcedeth kmod-natsemi kmod-sis900"
for drv in $NON_INTEL_NICS; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done
sed -i '/CONFIG_PACKAGE_kmod-usb-net-/d' .config

# 4. 非 Intel 显示驱动
echo ">>> 清理非 Intel 显示驱动..."
DISPLAY_DRIVERS="kmod-drm-amdgpu kmod-nouveau"
for drv in $DISPLAY_DRIVERS; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done

# 5. 蜂窝模块
echo ">>> 清理蜂窝模块..."
CELLULAR_DRIVERS="kmod-mhi kmod-qmi kmod-usb-net-qmi"
for drv in $CELLULAR_DRIVERS; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done

# 6. 老旧存储接口
echo ">>> 清理老旧存储接口..."
OLD_STORAGE="kmod-ata-piix"
for drv in $OLD_STORAGE; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done
sed -i '/CONFIG_PACKAGE_kmod-pata-/d' .config
sed -i '/CONFIG_PACKAGE_kmod-firewire-/d' .config

# 7. 并口/串口
echo ">>> 清理并口/串口..."
PARALLEL_SERIAL="kmod-parport kmod-serial-8250 kmod-serial-core"
for drv in $PARALLEL_SERIAL; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done
sed -i '/CONFIG_PACKAGE_kmod-parport/d' .config

# 8. GPIO/I2C/SPI
echo ">>> 清理 GPIO/I2C/SPI..."
sed -i '/CONFIG_PACKAGE_kmod-i2c-/d' .config
sed -i '/CONFIG_PACKAGE_kmod-gpio-/d' .config
sed -i '/CONFIG_PACKAGE_kmod-spi-/d' .config

# 9. 网络调试工具
echo ">>> 清理网络调试工具..."
DEBUG_TOOLS="tcpdump strace gdb"
for drv in $DEBUG_TOOLS; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done

# 10. 老旧有线协议
echo ">>> 清理老旧有线协议..."
OLD_PROTOCOLS="kmod-tokenring kmod-atm"
for drv in $OLD_PROTOCOLS; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done

# 11. 音视频驱动
echo ">>> 清理音视频驱动..."
sed -i '/CONFIG_PACKAGE_kmod-sound-/d' .config
sed -i '/CONFIG_PACKAGE_alsa-/d' .config
sed -i '/CONFIG_PACKAGE_kmod-video-/d' .config
sed -i '/CONFIG_PACKAGE_kmod-media-/d' .config

# 12. MMC/SD 卡驱动
echo ">>> 清理 MMC/SD 卡驱动..."
MMC_SD="kmod-mmc kmod-sdhci"
for drv in $MMC_SD; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done

# 13. 光驱文件系统
echo ">>> 清理光驱文件系统..."
OPTICAL_FS="kmod-fs-isofs kmod-fs-udf"
for drv in $OPTICAL_FS; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done

# 14. 触摸屏/手写板
echo ">>> 清理触摸屏/手写板..."
TOUCH_INPUT="kmod-input-touchscreen kmod-input-tablet"
for drv in $TOUCH_INPUT; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done

# 15. 笔记本专用驱动
echo ">>> 清理笔记本专用驱动..."
LAPTOP_DRIVERS="kmod-thinkpad_acpi kmod-ideapad-laptop"
for drv in $LAPTOP_DRIVERS; do
    sed -i "/CONFIG_PACKAGE_${drv}/d" .config
done

# 16. 电池驱动
echo ">>> 清理电池驱动..."
sed -i '/CONFIG_PACKAGE_kmod-battery/d' .config

# ========== 验证关键驱动 ==========
echo ""
echo ">>> 验证关键驱动保留情况："
CRITICAL_DRIVERS="kmod-igc kmod-ahci kmod-virtio"
for drv in $CRITICAL_DRIVERS; do
    if grep -q "CONFIG_PACKAGE_${drv}=y" .config; then
        echo "  ✅ $drv 已启用"
    else
        echo "  ⚠️  $drv 未找到，请检查"
    fi
done

echo ""
echo ">>> 驱动精简完成！"
echo "=========================================="
echo "  diy-mini.sh 执行完成"
echo "  LuCI 分支: openwrt-25.12"
echo "  内核版本: 6.12"
echo "  默认 IP: 10.0.0.1"
echo "  默认主题: argon"
echo "=========================================="
