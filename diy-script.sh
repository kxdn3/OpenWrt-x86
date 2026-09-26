#!/bin/bash
# ============================================================
# diy-script.sh - ImmortalWrt 25.12 (apk) 自定义脚本
# x86 物理机专用版
# 功能：
#   1. 内核切换到 6.18（含 RTC CMOS 补丁）
#   2. BIOS Boot Partition 256 -> 1024
#   3. LAN IP 10.0.0.1 / 主题 / root 空密码 / zsh
#   4. Lucky（sirpdboy 版，拆分界面包 + 核心包）
#   5. PassWall / Diskman / PushBot / Fluent
#   6. 分区大小 + 包启用 + 内核配置同步
# ============================================================

set -e
echo "========================================"
echo "开始执行 DIY 脚本 (ImmortalWrt 25.12 / x86 物理机)"
echo "========================================"

TARGET_PLATFORM="x86"
OLD_KVER="6.12"
NEW_KVER="6.18"

# ---------- 通用函数 ----------
clone() {
    local url="$1" dir="$2"
    [ -d "$dir" ] && { echo "  - 已存在，跳过: $dir"; return 0; }
    echo "  - clone: $dir"
    git clone --depth=1 "$url" "$dir" || { echo "!! clone 失败: $url" >&2; exit 1; }
}

remove_paths() {
    for p in "$@"; do
        [ -e "$p" ] && { echo "  - 删除 $p"; rm -rf "$p"; }
    done
}

# ============================================================
# 0. 内核切换至 6.18（含补丁目录迁移）
# ============================================================
echo "[0/8] 内核版本检查与切换"

CURRENT_KVER=$(grep -oP 'KERNEL_PATCHVER:=\K[0-9.]+' \
    "target/linux/${TARGET_PLATFORM}/Makefile" 2>/dev/null || echo "unknown")
echo "  当前 KERNEL_PATCHVER: ${CURRENT_KVER}"

if [ "${CURRENT_KVER}" = "${NEW_KVER}" ]; then
    echo "  → 已是 ${NEW_KVER}，跳过迁移"
elif [ "${CURRENT_KVER}" = "${OLD_KVER}" ]; then
    echo "  → 执行 ${OLD_KVER} → ${NEW_KVER} 迁移"
    chmod +x scripts/kernel_bump.sh
    ./scripts/kernel_bump.sh -p "${TARGET_PLATFORM}" \
        -s "v${OLD_KVER}" -t "v${NEW_KVER}"
    sed -i "s/^KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=${NEW_KVER}/" \
        "target/linux/${TARGET_PLATFORM}/Makefile"
    echo "  ✓ KERNEL_PATCHVER 已改为 ${NEW_KVER}"
else
    echo "  !! 未知内核版本 ${CURRENT_KVER}，请手动确认" >&2
    exit 1
fi

# 校验补丁目录存在
if [ ! -d "target/linux/${TARGET_PLATFORM}/patches-${NEW_KVER}" ]; then
    echo "!! patches-${NEW_KVER} 不存在，内核迁移失败" >&2
    exit 1
fi
echo "  ✓ patches-${NEW_KVER} 已就绪"

# ============================================================
# 0.5 RTC CMOS 补丁（6.18 物理机专属，修复 IRQ 报错）
# ============================================================
echo "[0.5/8] 检查 RTC CMOS 补丁"

RTC_PATCH_DIR="target/linux/${TARGET_PLATFORM}/patches-${NEW_KVER}"
RTC_PATCH_NAME="831-rtc-cmos-use-platform_get_irq_optional-in-probe.patch"

if ls "${RTC_PATCH_DIR}" 2>/dev/null | grep -q "831-rtc-cmos-use-platform_get_irq_optional"; then
    echo "  → RTC 补丁已存在，跳过"
else
    echo "  → 创建 RTC CMOS 补丁"
    cat > "${RTC_PATCH_DIR}/${RTC_PATCH_NAME}" <<'PATCH_EOF'
From: Rafael J. Wysocki <rafael.j.wysocki@intel.com>
Subject: [PATCH] rtc: cmos: Use platform_get_irq_optional() in
 cmos_platform_probe()

The rtc-cmos driver can live without an IRQ and returning an error code
from platform_get_irq() is not a problem for it in general, so make it
call platform_get_irq_optional() in cmos_platform_probe() instead of
platform_get_irq() to avoid a confusing error message printed by the
latter if an IRQ cannot be found for index 0, which is possible on x86
platforms.

--- a/drivers/rtc/rtc-cmos.c
+++ b/drivers/rtc/rtc-cmos.c
@@ -1423,9 +1423,18 @@ static int __init cmos_platform_probe(struct platform_device *pdev)
 	resource = platform_get_resource(pdev, IORESOURCE_IO, 0);
 	else
 		resource = platform_get_resource(pdev, IORESOURCE_MEM, 0);
-	irq = platform_get_irq(pdev, 0);
-	if (irq < 0)
+	irq = platform_get_irq_optional(pdev, 0);
+	if (irq < 0) {
 		irq = -1;
+#ifdef CONFIG_X86
+		/*
+		 * On some x86 systems, the IRQ is not
+		 * defined, but it should always be safe
+		 * to hardcode it on systems with a
+		 * legacy PIC.
+		 */
+		if (nr_legacy_irqs())
+			irq = RTC_IRQ;
+#endif
+	}
 
 	if (resource == NULL) {
 		dev_err(&pdev->dev, "no I/O or memory resource\n");
PATCH_EOF
    echo "  ✓ RTC 补丁已创建"
fi

# ============================================================
# 0.7 BIOS Boot Partition 256 -> 1024 (1MB)
# ============================================================
echo "[0.7/8] 调整 BIOS Boot Partition 大小"

echo "  原始 Build/combined 段内含 256 的行："
sed -n '/define Build\/combined/,/endef/p' target/linux/x86/image/Makefile \
    | grep -n 256 || echo "    (未找到)"

# 精确替换：保留原缩进（tab 或空格）
sed -i '/define Build\/combined/,/endef/{
    s/^\([[:space:]]*\)256\([[:space:]]*\)$/\11024\2/
}' target/linux/x86/image/Makefile

# 校验
if sed -n '/define Build\/combined/,/endef/p' target/linux/x86/image/Makefile \
        | grep -qE '^[[:space:]]*1024[[:space:]]*$'; then
    echo "  ✓ BIOS Boot Partition 已改为 1024"
else
    echo "  !! 替换失败，请检查原始行格式" >&2
    sed -n '/define Build\/combined/,/endef/p' target/linux/x86/image/Makefile
    exit 1
fi

# ============================================================
# 1. LAN IP 10.0.0.1（uci-defaults 方式）
# ============================================================
echo "[1/8] 修改默认 LAN IP 为 10.0.0.1"
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/98-set-lan-ip <<'EOF'
#!/bin/sh
uci set network.lan.ipaddr='10.0.0.1'
uci commit network
exit 0
EOF
chmod +x files/etc/uci-defaults/98-set-lan-ip

# ============================================================
# 2. root 空密码 / 主题 / zsh
# ============================================================
echo "[2/8] 设置密码、主题和 Shell"

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

# zsh 用启动时切换，避免构建早期 sshd 找不到 shell
cat > files/etc/uci-defaults/97-set-shell <<'EOF'
#!/bin/sh
if [ -x /usr/bin/zsh ]; then
    sed -i 's|/bin/ash|/usr/bin/zsh|' /etc/passwd
fi
exit 0
EOF
chmod +x files/etc/uci-defaults/97-set-shell

# ============================================================
# 3. 清理 feeds 里自带的旧 lucky，避免包名冲突
# ============================================================
echo "[3/8] 清理 feeds 旧 lucky"

remove_paths \
    feeds/luci/applications/luci-app-lucky \
    feeds/packages/net/lucky \
    package/feeds/luci/luci-app-lucky \
    package/feeds/packages/lucky

# ============================================================
# 4. 克隆插件源码（含 sirpdboy Lucky 拆分）
# ============================================================
echo "[4/8] 克隆插件源码"

# --- Fluent 主题 ---
clone https://github.com/LazuliKao/luci-theme-fluent.git \
    package/luci-theme-fluent

# --- PassWall ---
clone https://github.com/xiaorouji/openwrt-passwall.git \
    package/openwrt-passwall
clone https://github.com/xiaorouji/openwrt-passwall-packages.git \
    package/openwrt-passwall-packages

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

    # 校验两个 Makefile
    [ -f package/lucky/Makefile ] && echo "    ✓ package/lucky/Makefile" \
        || { echo "!! package/lucky/Makefile 缺失" >&2; exit 1; }
    [ -f package/luci-app-lucky/Makefile ] && echo "    ✓ package/luci-app-lucky/Makefile" \
        || { echo "!! package/luci-app-lucky/Makefile 缺失" >&2; exit 1; }
else
    echo "  - Lucky 目录已存在，跳过克隆"
fi

# ============================================================
# 5. 分区大小
# ============================================================
echo "[5/8] 配置分区大小"
sed -i '/CONFIG_TARGET_KERNEL_PARTSIZE/d' .config
sed -i '/CONFIG_TARGET_ROOTFS_PARTSIZE/d' .config
echo "CONFIG_TARGET_KERNEL_PARTSIZE=16" >> .config
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=2048" >> .config

# ============================================================
# 6. 启用所需包
# ============================================================
echo "[6/8] 启用插件"
make defconfig > /dev/null 2>&1

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

make defconfig > /dev/null 2>&1

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
# 7. 内核配置同步
# ============================================================
echo "[7/8] 同步内核配置到 ${NEW_KVER}"
make kernel_oldconfig CONFIG_TARGET=subtarget > /dev/null 2>&1 || \
    echo "  !! kernel_oldconfig 有未决项，请手动 make kernel_menuconfig 检查"

# ============================================================
# 8. 完成
# ============================================================
echo "[8/8] 校验 BIOS Boot Partition"
sed -n '/define Build\/combined/,/endef/p' target/linux/x86/image/Makefile \
    | grep -n "1024" || echo "  (未匹配到 1024，请手动确认)"

echo "========================================"
echo "DIY 脚本执行完毕"
echo "========================================"
