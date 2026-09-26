#!/bin/bash
# ============================================================
# diy-script.sh - ImmortalWrt 25.12 (apk) 自定义脚本
# x86 物理机专用版
# ============================================================

set -e
echo "========================================"
echo "开始执行 DIY 脚本 (ImmortalWrt 25.12 / x86 物理机)"
echo "========================================"

TARGET_PLATFORM="x86"

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
# 0. 注入最新 PassWall 源
# ============================================================
echo "[0/8] 注入最新 PassWall 源到 feeds.conf.default"

if grep -q "Openwrt-Passwall/openwrt-passwall" feeds.conf.default 2>/dev/null; then
    echo "  → 已存在 PassWall 源，跳过"
else
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

echo "  → 更新 passwall_packages / passwall_luci"
./scripts/feeds update passwall_packages passwall_luci
echo "  → 安装 passwall 包"
./scripts/feeds install -a -p passwall_packages
./scripts/feeds install -a -p passwall_luci

# ============================================================
# 1. BIOS Boot Partition 256 -> 1024
# ============================================================
echo "[1/8] 调整 BIOS Boot Partition 大小"
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
    echo "  !! 替换失败" >&2
    sed -n '/define Build\/combined/,/endef/p' target/linux/x86/image/Makefile
    exit 1
fi

# ============================================================
# 2. LAN IP 10.0.0.1
# ============================================================
echo "[2/8] 修改默认 LAN IP 为 10.0.0.1"
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/98-set-lan-ip <<'UCI_EOF'
#!/bin/sh
uci set network.lan.ipaddr='10.0.0.1'
uci commit network
exit 0
UCI_EOF
chmod +x files/etc/uci-defaults/98-set-lan-ip

# ============================================================
# 3. root 空密码 / 主题 / zsh
# ============================================================
echo "[3/8] 设置密码、主题和 Shell"
if [ -f package/base-files/files/etc/shadow ]; then
    sed -i 's/^root:[^:]*:/root::/' package/base-files/files/etc/shadow
fi

cat > files/etc/uci-defaults/99-set-theme <<'UCI_EOF'
#!/bin/sh
uci set luci.main.mediaurlbase='/luci-static/fluent'
uci set luci.main.theme='fluent'
uci commit luci
exit 0
UCI_EOF
chmod +x files/etc/uci-defaults/99-set-theme

cat > files/etc/uci-defaults/97-set-shell <<'UCI_EOF'
#!/bin/sh
if [ -x /usr/bin/zsh ]; then
    sed -i 's|/bin/ash|/usr/bin/zsh|' /etc/passwd
fi
exit 0
UCI_EOF
chmod +x files/etc/uci-defaults/97-set-shell

# ============================================================
# 4. 清理 feeds 旧 lucky
# ============================================================
echo "[4/8] 清理 feeds 旧 lucky"
remove_paths \
    feeds/luci/applications/luci-app-lucky \
    feeds/packages/net/lucky \
    package/feeds/luci/luci-app-lucky \
    package/feeds/packages/lucky

# ============================================================
# 5. 克隆插件源码
# ============================================================
echo "[5/8] 克隆插件源码"

# --- Fluent 主题 ---
clone https://github.com/LazuliKao/luci-theme-fluent.git \
    package/luci-theme-fluent

# --- Diskman ---
clone https://github.com/lisaac/luci-app-diskman.git \
    package/luci-app-diskman

# --- PushBot ---
clone https://github.com/zzsj0928/luci-app-pushbot.git \
    package/luci-app-pushbot

# --- Lucky (sirpdboy)：自包含 clone ---
echo "  - Lucky (sirpdboy 版)"
if [ ! -d package/lucky ]; then
    LUCKY_URL="https://github.com/sirpdboy/luci-app-lucky.git"
    LUCKY_OK=0
    for m in \
        "$LUCKY_URL" \
        "https://ghfast.top/$LUCKY_URL" \
        "https://gh-proxy.com/$LUCKY_URL" ; do
        echo "  - clone: $m"
        if git clone --depth=1 "$m" package/lucky; then
            echo "    ✓ 来源: $m"
            LUCKY_OK=1
            break
        fi
        rm -rf package/lucky
        echo "    ! 失败，尝试下一个源"
    done

    if [ "$LUCKY_OK" != "1" ]; then
        echo "!! Lucky clone 全部失败" >&2
        exit 1
    fi
else
    echo "  - package/lucky 已存在，跳过克隆"
fi

# 打印 Lucky 内部实际的 Makefile 位置
echo "  ---- package/lucky 下的 Makefile 位置 ----"
find package/lucky -maxdepth 3 -name Makefile -not -path '*/.git/*' 2>/dev/null \
    || echo "    (未找到 Makefile)"

MK_COUNT=$(find package/lucky -maxdepth 3 -name Makefile -not -path '*/.git/*' 2>/dev/null | wc -l)
if [ "$MK_COUNT" -lt 2 ]; then
    echo "!! package/lucky 下 Makefile 数量不足（${MK_COUNT}），仓库结构可能已变化" >&2
    exit 1
fi
echo "  ✓ 找到 ${MK_COUNT} 个 Makefile"

# ============================================================
# 6. 分区大小
# ============================================================
echo "[6/8] 配置分区大小"
sed -i '/CONFIG_TARGET_KERNEL_PARTSIZE/d' .config
sed -i '/CONFIG_TARGET_ROOTFS_PARTSIZE/d' .config
echo "CONFIG_TARGET_KERNEL_PARTSIZE=16" >> .config
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=2048" >> .config

# ============================================================
# 7. 启用所需包（直接追加 .config，不依赖 scripts/config）
# ============================================================
echo "[7/8] 启用插件"

PKGS="luci-base luci-compat luci-mod-admin-full \
      luci-theme-fluent zsh kmod-igc \
      luci-app-passwall luci-app-dockerman luci-app-diskman \
      luci-app-lucky lucky luci-app-pushbot \
      docker dockerd docker-compose"

echo "  → make defconfig（第一次，生成基础符号）"
make defconfig > /dev/null 2>&1 || true

echo "  → 追加包开关到 .config"
for p in $PKGS ; do
    sed -i "/^CONFIG_PACKAGE_${p}=/d" .config
    sed -i "/^# CONFIG_PACKAGE_${p} is not set/d" .config
    echo "CONFIG_PACKAGE_${p}=y" >> .config
done

echo "  → make defconfig（第二次，解析依赖）"
make defconfig > /dev/null 2>&1 || true

echo "---- 关键包校验 ----"
for p in $PKGS ; do
    if grep -q "^CONFIG_PACKAGE_${p}=y" .config; then
        echo "  ✓ ${p}"
    else
        echo "  ✗ ${p}"
    fi
done

echo "---- 未启用包诊断 ----"
DIAG=0
for p in $PKGS ; do
    grep -q "^CONFIG_PACKAGE_${p}=y" .config && continue
    DIAG=$((DIAG+1))
    echo "== ${p} =="
    if [ -f tmp/.packageinfo ] && grep -q "^Package: ${p}$" tmp/.packageinfo 2>/dev/null; then
        echo "  包已识别，依赖未满足："
        grep -A8 "^Package: ${p}$" tmp/.packageinfo | grep -E "Depends:" | head -3
    else
        echo "  包未被构建系统识别"
        echo "  相关 Makefile 位置："
        find package -maxdepth 4 -name Makefile -path "*${p}*" -not -path '*/.git/*' 2>/dev/null \
            || echo "    (无)"
    fi
done
[ "$DIAG" = "0" ] && echo "  ✓ 全部包已启用"

# ============================================================
# 8. 完成
# ============================================================
echo "[8/8] 校验 BIOS Boot Partition"
sed -n '/define Build\/combined/,/endef/p' target/linux/x86/image/Makefile \
    | grep -n "1024" || echo "  (未匹配到 1024，请手动确认)"

echo "========================================"
echo "DIY 脚本执行完毕"
echo "========================================"
