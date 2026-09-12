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
#   6.18
#
# Theme:
#   luci-theme-fluent (only, forced)
#
# Shell:
#   default = zsh
#   included = zsh + bash
#
# Docker:
#   dockerd + containerd + docker + compose (explicit)
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
echo " Kernel: 6.18"
echo " Theme: fluent (only)"
echo " Shell: default=zsh, include=zsh+bash"
echo " Docker: engine + dockerman"
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


# 默认 shell = zsh
echo ">>> 设置默认Shell为 zsh"

if [ -f package/base-files/files/etc/passwd ]; then
    sed -i 's#/bin/ash#/usr/bin/zsh#g' \
    package/base-files/files/etc/passwd
fi


# ttyd 自动 root 登录
if [ -f feeds/packages/utils/ttyd/files/ttyd.config ]; then
    sed -i 's#/bin/login#/bin/login -f root#g' \
    feeds/packages/utils/ttyd/files/ttyd.config
fi


# ============================================================
# ========== x86 分区设置 ==========
# ============================================================

echo ">>> 设置x86分区"

sed -i \
's/GRUB_BOOT_PARTSIZE:=256/GRUB_BOOT_PARTSIZE:=1024/g' \
target/linux/x86/image/Makefile

sed -i \
's/GRUB_EFI_BOOT_PARTSIZE:=256/GRUB_EFI_BOOT_PARTSIZE:=1024/g' \
target/linux/x86/image/Makefile

# Kernel 6.18
sed -i \
's/KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.18/g' \
target/linux/x86/Makefile

# 若上游将 6.18 归为 testing,则同时设置 testing 版本号
if grep -q '^KERNEL_TESTING_PATCHVER' target/linux/x86/Makefile; then
    sed -i \
    's/KERNEL_TESTING_PATCHVER:=.*/KERNEL_TESTING_PATCHVER:=6.18/g' \
    target/linux/x86/Makefile
fi


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

remove_paths() {
    for p in "$@"; do
        if [ -e "$p" ]; then
            rm -rf "$p"
            echo "    - removed $p"
        fi
    done
}

remove_paths \
    feeds/luci/themes/luci-theme-argon \
    feeds/luci/applications/luci-app-argon-config \
    feeds/luci/themes/luci-theme-fluent \
    feeds/luci/applications/luci-app-mosdns \
    feeds/luci/applications/luci-app-netdata \
    feeds/luci/applications/luci-app-pushbot \
    feeds/luci/applications/luci-app-dockerman \
    feeds/luci/applications/luci-app-diskman


# ============================================================
# ========== 工具函数 ==========
# ============================================================

clone_pkg()
{
    local repo="$1"
    local dir="$2"
    local attempt

    echo ">>> Clone $repo"

    for attempt in 1 2 3; do
        rm -rf "$dir"
        if git clone --depth=1 "$repo" "$dir"; then
            return 0
        fi
        echo ">>> Clone $repo 失败,重试 $attempt/3"
        sleep 5
    done

    echo ">>> Clone $repo 彻底失败" >&2
    return 1
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
clone_pkg \
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
# ========== Fluent 主题(唯一主题) ==========
# ============================================================

echo ">>> 添加 Fluent 主题"

clone_pkg \
https://github.com/LazuliKao/luci-theme-fluent \
package/luci-theme-fluent


# --- 1) 让 luci 元包选择 fluent 而非 bootstrap ---
if [ -f feeds/luci/collections/luci/Makefile ]; then
    sed -i \
    's/luci-theme-bootstrap/luci-theme-fluent/g' \
    feeds/luci/collections/luci/Makefile
fi


# --- 2) 清理 zzz-default-settings 里可能存在的旧默认值 ---
DEFAULT_SETTINGS="package/lean/default-settings/files/zzz-default-settings"

if [ -f "$DEFAULT_SETTINGS" ]; then
    sed -i '/luci\.main\.mediaurlbase/d' "$DEFAULT_SETTINGS"
fi


# --- 3) 用 uci-defaults 强制设置 mediaurlbase 为 fluent ---
FLUENT_UCI_DIR="package/lean/default-settings/files/etc/uci-defaults"
mkdir -p "$FLUENT_UCI_DIR"

cat > "$FLUENT_UCI_DIR/99-set-fluent-theme" <<'EOF'
#!/bin/sh
# 强制将 LuCI 默认主题设为 Fluent
uci -q batch <<-EOC
    set luci.main.mediaurlbase='/luci-static/fluent'
    commit luci
EOC
exit 0
EOF

chmod 0755 "$FLUENT_UCI_DIR/99-set-fluent-theme"


# --- 4) 兜底:静态资源目录名不一致时补软链 ---
cat > "$FLUENT_UCI_DIR/98-fix-fluent-static" <<'EOF'
#!/bin/sh
FLUENT_DIR="/www/luci-static/fluent"
if [ ! -d "$FLUENT_DIR" ]; then
    for src in /www/luci-static/fluent*; do
        [ -d "$src" ] && [ "$src" != "$FLUENT_DIR" ] && \
            ln -sf "$src" "$FLUENT_DIR" && break
    done
fi
exit 0
EOF

chmod 0755 "$FLUENT_UCI_DIR/98-fix-fluent-static"


# --- 5) bash 软链:保证 /bin/bash 存在 ---
cat > "$FLUENT_UCI_DIR/97-bash-link" <<'EOF'
#!/bin/sh
[ -x /usr/bin/bash ] && [ ! -e /bin/bash ] && ln -sf /usr/bin/bash /bin/bash
exit 0
EOF

chmod 0755 "$FLUENT_UCI_DIR/97-bash-link"


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
    local branch="$1"
    local repo="$2"
    local target="$3"
    shift 3

    local origin="$PWD"
    local tmp
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

    local dir
    for dir in "$@"; do
        mv "$dir" "$origin/$target/"
    done

    cd "$origin"
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

remove_paths \
    feeds/packages/net/chinadns-ng \
    feeds/packages/net/sing-box \
    feeds/packages/net/xray-core \
    feeds/packages/net/mosdns \
    feeds/packages/net/smartdns \
    feeds/helloworld/luci-app-ssr-plus


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

for file in package/lean/autocore/files/*/index.htm; do
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
    OLD_VERSION=$(grep DISTRIB_REVISION "$VERSION_FILE" | awk -F "'" '{print $2}')

    if [ -n "$OLD_VERSION" ]; then
        if command -v perl >/dev/null 2>&1; then
            perl -i -pe \
            "s/\Q${OLD_VERSION}\E/R${DATE_VERSION} by kxdn/g" \
            "$VERSION_FILE"
        else
            OLD_VERSION_ESC=$(printf '%s' "$OLD_VERSION" | sed 's/[][\.*^$/]/\\&/g')
            sed -i \
            "s/${OLD_VERSION_ESC}/R${DATE_VERSION} by kxdn/g" \
            "$VERSION_FILE"
        fi
    fi
fi


# ============================================================
# ========== hostapd修复 ==========
# ============================================================

echo ">>> 检查hostapd补丁"

PATCH="${GITHUB_WORKSPACE:-$PWD}/scripts/011-fix-mbo-modules-build.patch"

if [ -f "$PATCH" ]; then
    mkdir -p package/network/services/hostapd/patches
    cp "$PATCH" \
    package/network/services/hostapd/patches/011-fix-mbo-modules-build.patch
else
    echo ">>> 补丁不存在,跳过: $PATCH"
fi


# ============================================================
# ========== 第三方Makefile修复 ==========
# ============================================================

echo ">>> 修复第三方包路径"

find package -maxdepth 3 -name Makefile \
    -exec sed -i \
    's|\.\./\.\./luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' {} \;

find package -maxdepth 3 -name Makefile \
    -exec sed -i \
    's|\.\./\.\./lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' {} \;


# ============================================================
# ========== 驱动精简 ==========
# ============================================================

echo ">>> 清理无用驱动"

sed -i -E \
'/^CONFIG_PACKAGE_kmod-(video|media|sound|i2c|gpio|spi|firewire|mmc|sdhci|drm-amdgpu|nouveau|mhi|qmi|usb-net-qmi|bluetooth|btusb|ath3k|bcmbt)/d' \
.config

REMOVE_DRIVERS="
kmod-cfg80211
kmod-mac80211
wpad
hostapd
iw

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

bluez
alsa-lib
"

for drv in $REMOVE_DRIVERS; do
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

for drv in $KEEP_DRIVERS; do
    grep -q "CONFIG_PACKAGE_${drv}=y" .config || \
    echo "CONFIG_PACKAGE_${drv}=y" >> .config
done


# ============================================================
# ========== 保留核心功能 ==========
# ============================================================

echo ">>> 检查核心组件"

CORE_PACKAGES="
luci-theme-fluent
luci-compat
luci-lib-jsonc
luci-app-passwall
luci-app-dockerman
luci-lib-docker
luci-app-diskman
luci-app-lucky
luci-app-pushbot
iputils-arping
curl
wget-ssl
jq
ttyd
zsh
bash
"

for pkg in $CORE_PACKAGES; do
    grep -q "CONFIG_PACKAGE_${pkg}=y" .config || \
    echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done

# bash 兼容不同 feeds 下的命名
for pkg in bash bash-full; do
    grep -q "CONFIG_PACKAGE_${pkg}=y" .config || \
    echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done


# ============================================================
# ========== Docker 引擎(显式保险) ==========
# ============================================================

echo ">>> 显式勾选 Docker 引擎"

for pkg in dockerd containerd docker docker-compose; do
    grep -q "CONFIG_PACKAGE_${pkg}=y" .config || \
    echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done

# Docker 网络所需内核模块
for pkg in \
    kmod-br-netfilter \
    kmod-veth \
    kmod-ipt-nat \
    kmod-nf-ipvs \
    kmod-ipt-physdev \
    kmod-nf-nathelper-extra
do
    grep -q "CONFIG_PACKAGE_${pkg}=y" .config || \
    echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done


# ============================================================
# ========== 显式排除旧主题 ==========
# ============================================================

for pkg in luci-theme-bootstrap luci-theme-argon luci-app-argon-config; do
    sed -i "/CONFIG_PACKAGE_${pkg}=/d" .config
    echo "# CONFIG_PACKAGE_${pkg} is not set" >> .config
done


# ============================================================
# ========== 最终 defconfig 固化 ==========
# ============================================================

echo ">>> 最终 defconfig 固化配置"
make defconfig


# ============================================================
# ========== 存在性校验 ==========
# ============================================================

echo ">>> 校验关键包是否会被编入固件"

for pkg in \
    zsh bash luci-theme-fluent \
    dockerd containerd docker \
    luci-app-pushbot iputils-arping curl wget-ssl jq
do
    if grep -q "CONFIG_PACKAGE_${pkg}=y" .config; then
        echo "    ✓ ${pkg} 已勾选"
    else
        echo "    ! 警告: ${pkg} 未勾选" >&2
    fi
done

if grep -q "CONFIG_PACKAGE_luci-theme-argon=y" .config; then
    echo "    ! 警告: argon 主题意外被勾选" >&2
else
    echo "    ✓ argon 主题已排除"
fi


# ============================================================
# ========== 最终检查 ==========
# ============================================================

echo
echo "=========================================="
echo " diy-mini.sh 执行完成"
echo
echo " Platform : x86_64"
echo " LuCI     : openwrt-25.12"
echo " Kernel   : 6.18"
echo " Theme    : fluent (only)"
echo " Shell    : zsh (default) + bash"
echo " Docker   : engine + dockerman"
echo " GRUB     : 1024K (1MB)"
echo " Kernel P : 16MB"
echo " Rootfs   : 2048MB"
echo " IP       : 10.0.0.1"
echo
echo " Plugins:"
echo " PassWall"
echo " DockerMan  (+ dockerd/containerd/docker)"
echo " DiskMan"
echo " Lucky"
echo " PushBot    (+ arping/curl/wget-ssl/jq)"
echo " Samba4"
echo " Fluent Theme"
echo " TTYD"
echo " Zsh  (default login shell)"
echo " Bash (installed, /bin/bash linked)"
echo
echo "=========================================="
