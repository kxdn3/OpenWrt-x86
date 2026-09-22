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
#   luci-theme-fluent (default, 编译期写死)
#   luci-theme-bootstrap (kept as fallback)
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
DEFAULT_SETTINGS="package/lean/default-settings/files/zzz-default-settings"


echo "=========================================="
echo " OpenWrt x86_64 Mini DIY"
echo " LuCI: openwrt-25.12"
echo " Kernel: 6.18"
echo " Theme: fluent (default), bootstrap (fallback)"
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

# BIOS Boot Partition: 256KB -> 1024KB (1MB)
# 注意:控制它的是 Build/combined 段里硬编码的 256,不是 GRUB_BOOT_PARTSIZE。
sed -i '/define Build\/combined/,/endef/s/^\s*256\s*$/ 1024/' \
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

# Lucky（sirpdboy 仓库）
clone_pkg \
https://github.com/sirpdboy/luci-app-lucky.git \
package/luci-app-lucky

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
# ========== Fluent 主题(默认主题) ==========
# ============================================================

echo ">>> 添加 Fluent 主题"

clone_pkg \
https://github.com/LazuliKao/luci-theme-fluent \
package/luci-theme-fluent


# ============================================================
# ========== 编译期写死 luci 默认主题 ==========
# ============================================================
#
# 说明:
#   只靠 uci-defaults 不可靠,可能被 lean 的 zzz-default-settings 覆盖。
#   最稳做法是在编译期直接写入 /etc/config/luci,
#   这样固件刷完开机就是 fluent,不会变。
#   bootstrap 源码保留,用户可在后台手动切回。
#
echo ">>> 编译期写死 luci 默认主题为 fluent"

LUCI_CONFIG="package/base-files/files/etc/config/luci"

mkdir -p "$(dirname "$LUCI_CONFIG")"

cat > "$LUCI_CONFIG" <<'EOF'
config core 'main'
    option lang 'zh_cn'
    option mediaurlbase '/luci-static/fluent'
    option resourcebase '/luci-static/resources'

config extern 'flash_keep'
    option uci '/etc/config/'
    option dropbear '/etc/dropbear/'
    option openvpn '/etc/openvpn/'
    option passwd '/etc/passwd'
    option opkg '/etc/opkg.conf'
    option firewall '/etc/firewall.user'
    option uploads '/lib/uci/upload/'

config internal 'languages'
    option en 'English'
    option zh_cn '简体中文'

config internal 'sauth'
    option sessionpath '/tmp/luci-sessions'
    option sessiontime '3600'

config internal 'ccache'
    option enable '1'

config internal 'apply'
    option rollback '90'
    option holdoff '4'
    option timeout '5'
    option display '1'

config internal 'diag'
    option dns 'openwrt.org'
    option ping 'openwrt.org'
    option route 'openwrt.org'
EOF


# ============================================================
# ========== 主题强制:base-files uci-defaults 兜底 ==========
# ============================================================
#
# 关键改动:
#   1) 不再改 feeds/luci/collections/luci/Makefile(会被 feeds update 冲掉)
#   2) 不再把 uci-defaults 写到 package/lean/default-settings(会被重装覆盖)
#   3) 统一写到 package/base-files/files/etc/uci-defaults/
#      因为 base-files 是最底层包,最后打包,不会被覆盖
#   4) 文件名用 zzz- 前缀,保证排在 lean 的 zzz-default-settings 之后执行
#
# 注意:
#   编译期已写死 /etc/config/luci,这里只是兜底,防止用户误改后无法恢复。
#
echo ">>> 兜底:确保默认主题为 Fluent"

BASE_UCI_DIR="package/base-files/files/etc/uci-defaults"
mkdir -p "$BASE_UCI_DIR"


# --- 1) 兜底设置 mediaurlbase ---
cat > "$BASE_UCI_DIR/zzz-set-fluent-theme" <<'EOF'
#!/bin/sh
#
# 兜底:如果 mediaurlbase 不是 fluent,强制改回
#
FLUENT_URL=""

if [ -d /www/luci-static/fluent ]; then
    FLUENT_URL="/luci-static/fluent"
else
    for d in /www/luci-static/fluent*; do
        [ -d "$d" ] || continue
        FLUENT_URL="/luci-static/$(basename "$d")"
        break
    done
fi

if [ -n "$FLUENT_URL" ]; then
    CUR=$(uci -q get luci.main.mediaurlbase)
    if [ "$CUR" != "$FLUENT_URL" ]; then
        uci -q set luci.main.mediaurlbase="$FLUENT_URL"
        uci -q commit luci
    fi
fi

exit 0
EOF

chmod 0755 "$BASE_UCI_DIR/zzz-set-fluent-theme"


# --- 2) 兜底:静态资源目录名不一致时补软链 ---
cat > "$BASE_UCI_DIR/zzz-fix-fluent-static" <<'EOF'
#!/bin/sh
FLUENT_DIR="/www/luci-static/fluent"

if [ ! -d "$FLUENT_DIR" ]; then
    for src in /www/luci-static/fluent*; do
        [ -d "$src" ] && [ "$src" != "$FLUENT_DIR" ] && \
            ln -sf "$(basename "$src")" "$FLUENT_DIR" && break
    done
fi

exit 0
EOF

chmod 0755 "$BASE_UCI_DIR/zzz-fix-fluent-static"


# --- 3) bash 软链:保证 /bin/bash 存在 ---
cat > "$BASE_UCI_DIR/zzz-bash-link" <<'EOF'
#!/bin/sh
[ -x /usr/bin/bash ] && [ ! -e /bin/bash ] && ln -sf /usr/bin/bash /bin/bash
exit 0
EOF

chmod 0755 "$BASE_UCI_DIR/zzz-bash-link"


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


# ============================================================
# ========== feeds install 后再清一次 default-settings ==========
# ============================================================
# feeds install 可能把 lean 的 default-settings 重新铺开,
# 里面如果带 mediaurlbase,会覆盖我们的 base-files uci-defaults。
echo ">>> 二次清理 zzz-default-settings 里的 mediaurlbase"

if [ -f "$DEFAULT_SETTINGS" ]; then
    sed -i '/luci\.main\.mediaurlbase/d' "$DEFAULT_SETTINGS"
fi


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
    's|os\.date()|os.date("%Y-%m-%d %H:%M:%S") .. " " .. translate(os.date("%A"))|g' \
    "$file"
done


# ============================================================
# ========== 固件版本 ==========
# ============================================================

echo ">>> 设置版本号"

VERSION_FILE="package/lean/default-settings/files/zzz-default-settings"

if [ -f "$VERSION_FILE" ]; then
    DATE_VERSION=$(date +"%y.%m.%d")

    OLD_VERSION=$(grep -m1 DISTRIB_REVISION "$VERSION_FILE" \
                  | awk -F "'" '{print $2}' \
                  | head -n1 \
                  | tr -d '\r')

    if [ -n "$OLD_VERSION" ]; then
        echo "    旧版本: [$OLD_VERSION]"
        echo "    新版本: [R${DATE_VERSION} by kxdn]"

        if command -v perl >/dev/null 2>&1; then
            OLD_VERSION="$OLD_VERSION" \
            NEW_VERSION="R${DATE_VERSION} by kxdn" \
            perl -i -pe 's/\Q$ENV{OLD_VERSION}\E/$ENV{NEW_VERSION}/g' \
                "$VERSION_FILE"
        else
            OLD_VERSION_ESC=$(printf '%s' "$OLD_VERSION" \
                              | sed -e 's/[][\\.^$*\/]/\\&/g')
            sed -i "s|${OLD_VERSION_ESC}|R${DATE_VERSION} by kxdn|g" \
                "$VERSION_FILE"
        fi
    else
        echo "    未在 $VERSION_FILE 中找到 DISTRIB_REVISION,跳过"
    fi
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
# ========== .config 强制主题 ==========
# ============================================================
#
# 说明:
#   - 排除 argon
#   - 选中 fluent
#   - bootstrap 保留(作为 fallback,用户可手动切回)
#
echo ">>> .config 选择 fluent 主题"

# 先确保 .config 存在
[ -f .config ] || cp .config.tmp .config 2>/dev/null || touch .config

# 排除 argon
for pkg in luci-theme-argon luci-app-argon-config; do
    sed -i "/CONFIG_PACKAGE_${pkg}=/d" .config
    echo "# CONFIG_PACKAGE_${pkg} is not set" >> .config
done

# 强制 fluent
sed -i "/CONFIG_PACKAGE_luci-theme-fluent=/d" .config
echo "CONFIG_PACKAGE_luci-theme-fluent=y" >> .config


# ============================================================
# ========== 清掉 default-settings 里的 mediaurlbase ==========
# ============================================================
# 关键:make defconfig 前再清一次,确保 lean 自带设置不会覆盖 fluent。
#
echo ">>> make defconfig 前最后一次清理 mediaurlbase"

if [ -f "$DEFAULT_SETTINGS" ]; then
    sed -i '/luci\.main\.mediaurlbase/d' "$DEFAULT_SETTINGS"
fi


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
"

for pkg in $CORE_PACKAGES; do
    grep -q "CONFIG_PACKAGE_${pkg}=y" .config || \
    echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done

# bash
grep -q "CONFIG_PACKAGE_bash=y" .config || \
echo "CONFIG_PACKAGE_bash=y" >> .config


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
# ========== 最终 defconfig 固化 ==========
# ============================================================

echo ">>> 最终 defconfig 固化配置"
make defconfig


# ============================================================
# ========== defconfig 后再次确认主题 ==========
# ============================================================
# 只需确保 fluent 被选中,argon 被排除。
# bootstrap 保留,允许用户手动切回。
echo ">>> defconfig 后二次确认主题"

sed -i "/CONFIG_PACKAGE_luci-theme-argon=/d" .config
echo "# CONFIG_PACKAGE_luci-theme-argon is not set" >> .config

sed -i "/CONFIG_PACKAGE_luci-app-argon-config=/d" .config
echo "# CONFIG_PACKAGE_luci-app-argon-config is not set" >> .config

grep -q "CONFIG_PACKAGE_luci-theme-fluent=y" .config || \
    echo "CONFIG_PACKAGE_luci-theme-fluent=y" >> .config

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
echo " Theme    : fluent (default, 编译期写死)"
echo "           bootstrap (fallback, 可手动切)"
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
echo " Fluent Theme (default)"
echo " TTYD"
echo " Zsh  (default login shell)"
echo " Bash (installed, /bin/bash linked)"
echo
echo "=========================================="
