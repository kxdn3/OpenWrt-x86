#!/bin/bash
#
# OpenWrt x86_64 Mini 自定义编译脚本
# 源码基准: coolsnowwolf/lede (master)
# LuCI 分支: coolsnowwolf/luci (openwrt-25.12)
# 内核版本: 6.12 (lede master 默认)
#
set -e
# ========== 基础配置 ==========
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
# 更改 boot 分区大小为 1MB（保持与原仓库 kxdn3/OpenWrt-x86 一致：lede 默认 256KB → 1MB）
# 使用精确匹配，避免原脚本 sed 's/256/1024/g' 全局替换误改其他 256 值
sed -i 's/GRUB_BOOT_PARTSIZE:=256/GRUB_BOOT_PARTSIZE:=1024/g' target/linux/x86/image/Makefile
sed -i 's/GRUB_EFI_BOOT_PARTSIZE:=256/GRUB_EFI_BOOT_PARTSIZE:=1024/g' target/linux/x86/image/Makefile
# 内核版本（lede master 已默认为 6.12，此处仅作显式声明兜底）
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
# ========== 移除需要替换的 feeds 包 ==========
# 科学上网相关核心（将由 passwall-packages 提供）
rm -rf feeds/packages/net/chinadns-ng
rm -rf feeds/packages/net/sing-box
rm -rf feeds/packages/net/xray-core
rm -rf feeds/packages/net/mosdns
rm -rf feeds/packages/net/msd_lite
rm -rf feeds/packages/net/smartdns
# LuCI 应用（将由第三方仓库提供更新版本）
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/luci/applications/luci-app-netdata
rm -rf feeds/luci/applications/luci-app-pushbot
rm -rf feeds/luci/applications/luci-app-dockerman
rm -rf feeds/luci/applications/luci-app-diskman
# ========== 添加第三方插件 ==========
# Lucky (动态域名 + 端口转发 + 反向代理等多功能工具)
git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/lucky
# PushBot (微信/Telegram 推送)
git clone --depth=1 https://github.com/kxdn3/luci-app-pushbot package/luci-app-pushbot
# DockerMan (Docker 管理)
git clone --depth=1 https://github.com/WYC-2020/luci-app-dockerman package/applications/luci-app-dockerman
# DiskMan (磁盘管理)
git clone --depth=1 https://github.com/lisaac/luci-app-diskman package/applications/luci-app-diskman
# ========== 科学上网: PassWall ==========
# PassWall 依赖包（xray-core, sing-box, chinadns-ng 等核心）
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall-packages
# PassWall LuCI 界面
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall
# ========== 主题 ==========
# Argon 主题（适配新版 LuCI，持续维护）
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
# Argon 主题配置插件（背景图/明暗模式等自定义）
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
# 设置默认主题为 argon
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' ./feeds/luci/collections/luci/Makefile
# ========== 核心库与工具替换/升级 ==========
# nghttp3 / ngtcp2 (HTTP/3 支持库，从 openwrt/packages master 获取)
merge_package master https://github.com/openwrt/packages feeds/packages/libs libs/nghttp3 libs/ngtcp2
# coremark (跑分工具，使用 sbwml 维护的更新版本)
rm -rf feeds/packages/utils/coremark
merge_package main https://github.com/sbwml/openwrt_pkgs feeds/packages/utils coremark
# unzip (修复大文件解压问题)
rm -rf feeds/packages/utils/unzip
git clone --depth=1 https://github.com/sbwml/feeds_packages_utils_unzip feeds/packages/utils/unzip
# samba4 (启用多通道支持，提升 SMB 性能)
rm -rf feeds/packages/net/samba4
git clone --depth=1 https://github.com/sbwml/feeds_packages_net_samba4 feeds/packages/net/samba4
# 启用 Samba 多通道
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
# sed -i 's/os.date("%c")/os.date("%Y-%m-%d %H:%M:%S")/g' feeds/luci/modules/luci-mod-system/luasrc/controller/admin/system.lua
# 去除主页 LuCI 版本号显示
sed -i 's/distversion)%>/distversion)%><!--/g' package/lean/autocore/files/*/index.htm
sed -i 's/luciversion)%>)/luciversion)%>)-->/g' package/lean/autocore/files/*/index.htm
# ========== 版本与安全设置 ==========
# 修改版本号为编译日期
date_version=$(date +"%y.%m.%d")
orig_version=$(grep DISTRIB_REVISION= package/lean/default-settings/files/zzz-default-settings | awk -F "'" '{print $2}')
if [ -n "$orig_version" ]; then
    sed -i "s/${orig_version}/R${date_version} by kxdn/g" package/lean/default-settings/files/zzz-default-settings
fi
# 取消默认 root 密码（首次登录需设置密码）
sed -i '/\/etc\/shadow/{/root/d;}' package/lean/default-settings/files/zzz-default-settings
# ========== 修复 hostapd 编译错误 ==========
if [ -f "$GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch" ]; then
    cp -f "$GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch" package/network/services/hostapd/patches/011-fix-mbo-modules-build.patch
fi
# ========== 修正第三方包 Makefile 路径问题 ==========
# 修正 luci.mk 引用路径
find package/*/ -maxdepth 2 -path "*/Makefile" -exec sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' {} \;
# 修正 golang-package.mk 引用路径
find package/*/ -maxdepth 2 -path "*/Makefile" -exec sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' {} \;
# 修正 GitHub 源码 URL 占位符
find package/*/ -maxdepth 2 -path "*/Makefile" -exec sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' {} \;
find package/*/ -maxdepth 2 -path "*/Makefile" -exec sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' {} \;
# ========== 更新并安装 feeds（必须在添加第三方包后重新执行） ==========
./scripts/feeds update -a
./scripts/feeds install -a

# 全部 feeds 处理完成之后，再执行这条sed，并且增加文件存在判断
LUCI_SYSTEM_LUA="feeds/luci/modules/luci-mod-system/luasrc/controller/admin/system.lua"
echo "检查文件路径: $LUCI_SYSTEM_LUA"
if [ -f "$LUCI_SYSTEM_LUA" ]; then
    echo "找到文件，执行sed修改时间格式"
    sed -i 's/os.date("%c")/os.date("%Y-%m-%d %H:%M:%S")/g' "$LUCI_SYSTEM_LUA"
else
    echo "警告：未找到luci‑mod‑system system.lua，跳过时间修改，不中断编译"
fi

echo "=========================================="
echo "  diy-mini.sh 执行完成"
echo "  LuCI 分支: openwrt-25.12"
echo "  内核版本: 6.12"
echo "  默认 IP: 10.0.0.1"
echo "  默认主题: argon"
echo "=========================================="
