#!/bin/sh
# 固件首次启动初始化脚本 (uci-defaults)
# 云编译时自动打包，首次启动执行一次后自动删除

set -e  # 出错即停止，避免部分配置失效继续运行

# 日志函数
log() {
    logger -t "firstboot-init" "$1"
}

log "Starting firstboot initialization..."

# 1. 设置默认主题为 Argon
if command -v uci >/dev/null 2>&1; then
    # 确保 luci.main 存在（若不存在则创建）
    uci -q set luci.main.mediaurlbase='/luci-static/argon'
    uci -q set luci.main.mediaurlbase  # 触发实际写入，无实际作用，仅用于确认
    log "Set LuCI theme to Argon"
else
    log "ERROR: uci command not found"
    exit 1
fi

# 2. 可选功能：禁用 IPv6 ULA 前缀（通过环境变量 FIRSTBOOT_DISABLE_ULA 控制）
if [ "$FIRSTBOOT_DISABLE_ULA" = "1" ]; then
    if uci -q get network.globals.ula >/dev/null; then
        # 注释掉 ula 配置项（使用 sed 或 uci delete，但 uci 不支持注释，改用 sed 更安全）
        sed -i 's/^[[:space:]]*option[[:space:]]\+ula/#&/' /etc/config/network
        log "Disabled IPv6 ULA prefix"
    else
        log "ULA prefix not found, skipping"
    fi
fi

# 3. 可选功能：开机检查文件系统（通过环境变量 FIRSTBOOT_CHECK_FS 控制）
if [ "$FIRSTBOOT_CHECK_FS" = "1" ]; then
    # 确保 fstab 配置节存在
    if uci -q get fstab.@global[0] >/dev/null 2>&1; then
        uci -q set fstab.@global[0].check_fs=1
        log "Enabled filesystem check on boot"
    else
        # 创建全局节（如果不存在）
        uci -q add fstab global
        uci -q set fstab.@global[0].check_fs=1
        log "Created fstab global and enabled check_fs"
    fi
fi

# 提交所有更改
uci commit
log "All changes committed"

exit 0
