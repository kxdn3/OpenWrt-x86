#!/bin/bash
# ============================================================
# diy-script.sh - ImmortalWrt 25.12 (apk) 自定义脚本
# x86 物理机专用版
# 功能：
#   1. BIOS Boot Partition 256 -> 1024
#   2. LAN IP 10.0.0.1 / 主题 / root 空密码 / zsh
#   3. PassWall 最新源（方法1：feeds.conf.default 顶部插入）
#   4. Lucky（sirpdboy 版，拆分界面包 + 核心包）
#   5. Diskman / PushBot / Fluent
#   6. 分区大小 + 包启用 + 内核配置同步
# ============================================================

set -e
echo "========================================"
echo "开始执行 DIY 脚本 (ImmortalWrt 25.12 / x86 物理机)"
echo "========================================"

TARGET_PLATFORM="x86"

# 让 git 遇到错误立即失败，不要尝试交互式索要用户名/密码
export GIT_TERMINAL_PROMPT=0
export GIT_HTTP_LOW_SPEED_LIMIT=1000
export GIT_HTTP_LOW_SPEED_TIME=30

# ---------- 通用函数 ----------
clone() {
    local url="$1" dir="$2"

    if [ -d "$dir" ]; then
        echo "  - 已存在，跳过: $dir"
        return 0
    fi
    echo "  - clone: $dir"

    local candidates=(
        "$url"
        "https://ghfast.top/${url}"
        "https://gh-proxy.com/${url}"
    )

    local m attempt
    for m in "${candidates[@]}"; do
        for attempt in 1 2 3; do
            if git clone --depth=1 "$m" "$dir"; then
                echo "    ✓ 来源: $m"
                return 0
            fi
            rm -rf "$dir"
            echo "    ! 失败，重试 ($attempt/3): $m"
            sleep 3
        done
    done

    echo "!! clone 失败: $url" >&2
    exit 1
}

remove_paths() {
    local removed=0
    for p in "$@"; do
        if [ -e "$p" ]; then
            echo "  - 删除 $p"
            rm -rf "$p"
            removed=1
        fi
    done
    [ "$removed" = "0" ] && echo "  - 无匹配目录需要清理"
    return 0
}

# ============================================================
# 0. 注入最新 PassWall 源到 feeds.conf.default 顶部（方法1）
# ============================================================
echo "[0/9] 注入最新 PassWall 源到 feeds.conf.default"

if grep -q "Openwrt-Passwall/openwrt-passwall" feeds.conf.default 2>/dev/null; then
    echo "  → 已存在 PassWall 源，跳过"
else
    # 通过临时文件插入到顶部（顺序敏感：先 luci 后 packages，保证 feeds 解析顺序）
    tmpfile=$(mktemp)
    {
        echo "src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall.git;main"
        echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main"
        cat feeds.conf.default
    } > "$tmpfile"
    mv "$tmpfile" feeds.conf.default
    echo "  ✓ PassWall 源已插入 feeds.conf.default 顶部"
fi

echo "  ---- feeds.conf.default 前 5 行 ----"
head -n 5 feeds.conf.default

# 更新并安装新增的 PassWall feeds
echo "  → 更新 passwall_packages / passwall_luci"
./scripts/feeds update passwall_packages passwall_luci

echo "  → 安装 passwall 包"
./scripts/feeds install -a -p passwall_packages
./scripts/feeds install -a -p passwall_luci

# ============================================================
# 1. BIOS Boot Partition 256 -> 1024 (1MB)
# ============================================================
echo "[1/9] 调整 BIOS Boot Partition 大小"

echo "  原始 Build/combined 段内含 256 的行："
sed -n '/define Build\/combined/,/endef/p' target/linux/x86/image/Makefile \
    | grep -n 256 || echo "    (未找到)"

sed -i '/define Build\/combined/,/endef/{
    s/^\([[:space:]]*\)256\([[:space:]]*\)$/\11024\2/
}' target/linux/x86/image/Makefile

if sed -n '/define Build\/combined/,/endef/p' target/linux/x86/image/Makefile \
        | grep -qE '^[[:space:]]*1024[[:space:]]*$'; then
    echo "  ✓ BIOS Boot Partition 已改为 1024"
else
    echo "  !! 替换失败，请检查原始行格式" >&2
    sed -n '/define Build\/combined/,/endef/p' target/linux/x86/image/Makefile
    exit 1
fi

# ============================================================
# 2. LAN IP 10.0.0.1（uci-defaults 方式）
# ============================================================
echo "[2/9] 修改默认 LAN IP 为 10.0.0.1"
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/98-set-lan-ip <<'EOF'
#!/bin/sh
uci set network.lan.ipaddr='10.0.0.1'
uci commit network
exit 0
EOF
chmod +x files/etc/uci-defaults/98-set-lan-ip

# ============================================================
# 3. root 空密码 / 主题 / zsh
# ============================================================
echo "[3/9] 设置密码、主题和 Shell"

if [ -f package/base-files/files/etc/shadow ]; then
    sed -i 's/^root:[^:]*:/root::/' package/base-files/files/etc/shadow
fi

cat > files/etc/uci-defaults/99-set-theme <<'EOF'
#!/bin/sh
uci set luci.main.mediaurlbase='/luci-static/fluent'
uci set luci.main.theme='fluent'
uci commit luci
exit 0
EOF
chmod +x files/etc/uci-defaults/99-set-theme

cat > files/etc/uci-defaults/97-set-shell <<'EOF'
#!/bin/sh
if [ -x /usr/bin/zsh ]; then
    sed -i 's|/bin/ash|/usr/bin/zsh|' /etc/passwd
fi
exit 0
EOF
chmod +x files/etc/uci-defaults/97-set-shell

# ============================================================
# 4. 清理 feeds 里自带的旧 lucky，避免包名冲突
# ============================================================
echo "[4/9] 清理 feeds 旧 lucky"

remove_paths \
    feeds/luci/applications/luci-app-lucky \
    feeds/packages/net/lucky \
    package/feeds/luci/luci-app-lucky \
    package/feeds/packages/lucky

# ============================================================
# 5. 克隆插件源码（PassWall 已由 feeds 注入，不再手动 clone）
# ============================================================
echo "[5/9] 克隆插件源码"

# --- Fluent 主题 ---
clone https://github.com/LazuliKao/luci-theme-fluent.git \
    package/luci-theme-fluent

# --- Diskman ---
clone https://github.com/lisaac/luci-app-diskman.git \
    package/luci-app-diskman

# --- PushBot ---
clone https://github.com/zzsj0928/luci-app-pushbot.git \
    package/luci-app-pushbot

# --- Lucky (sirpdboy)：先克隆到临时目录，再拆分界面包 + 核心包 ---
echo "  - Lucky (sirpdboy 版)"
if [ ! -d package/lucky ] && [ ! -d package/luci-app-lucky ]; then
    clone https://github.com/sirpdboy/luci-app-lucky.git \
        package/tmp-sirpdboy-lucky

    if [ -d package/tmp-sirpdboy-lucky/lucky ]; then
        mv package/tmp-sirpdboy-lucky/lucky package/lucky
        echo "    - 核心包 → package/lucky"
    else
        echo "!! sirpdboy 仓库里没有 lucky/ 子目录" >&2
        exit 1
    fi

    mv package/tmp-sirpdboy-lucky package/luci-app-lucky
    echo "    - 界面包 → package/luci-app-lucky"

    if [ -f package/lucky/Makefile ]; then
        echo "    ✓ package/lucky/Makefile"
    else
        echo "!! package/lucky/Makefile 缺失" >&2
        exit 1
    fi
    if [ -f package/luci-app-lucky/Makefile ]; then
        echo "    ✓ package/luci-app-lucky/Makefile"
    else
        echo "!! package/luci-app-lucky/Makefile 缺失" >&2
        exit 1
    fi
else
    echo "  - Lucky 目录已存在，跳过克隆"
fi

# ============================================================
# 6. 分区大小
# ============================================================
echo "[6/9] 配置分区大小"
sed -i '/CONFIG_TARGET_KERNEL_PARTSIZE/d' .config
sed -i '/CONFIG_TARGET_ROOTFS_PARTSIZE/d' .config
echo "CONFIG_TARGET_KERNEL_PARTSIZE=16" >> .config
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=2048" >> .config

# ============================================================
# 7. 启用所需包
# ============================================================
echo "[7/9] 启用插件"
make defconfig > /dev/null 2>&1 || true

for p in \
    luci-theme-fluent \
    zsh \
    kmod-igc \
    luci-app-passwall \
    luci-app-dockerman \
    luci-app-diskman \
    luci-app-lucky \
    lucky \
    luci-app-pushbot \
    docker \
    dockerd \
    docker-compose ; do
    ./scripts/config --set y "CONFIG_PACKAGE_${p}" 2>/dev/null || \
        echo "  !! 未找到配置项: CONFIG_PACKAGE_${p}"
done

make defconfig > /dev/null 2>&1 || true

echo "---- 关键包校验 ----"
for p in luci-app-passwall luci-app-dockerman luci-app-lucky lucky \
         zsh luci-theme-fluent ; do
    if grep -q "^CONFIG_PACKAGE_${p}=y" .config; then
        echo "  ✓ ${p}"
    else
        echo "  ✗ ${p} 未启用（可能依赖不满足）"
    fi
done

# ============================================================
# 8. 内核配置同步
# ============================================================
echo "[8/9] 同步内核配置"
make kernel_oldconfig CONFIG_TARGET=subtarget > /dev/null 2>&1 || \
    echo "  !! kernel_oldconfig 有未决项，请手动 make kernel_menuconfig 检查"

# ============================================================
# 9. 完成
# ============================================================
echo "[9/9] 校验 BIOS Boot Partition"
sed -n '/define Build\/combined/,/endef/p' target/linux/x86/image/Makefile \
    | grep -n "1024" || echo "  (未匹配到 1024，请手动确认)"

echo "========================================"
echo "DIY 脚本执行完毕"
echo "========================================"
