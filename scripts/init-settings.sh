#!/bin/bash
# 固件首次启动初始化脚本（uci-defaults）
# 会在系统首次启动时自动执行

# 设置默认主题为 argon
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci

# Disable IPV6 ula prefix（如需禁用 IPv6 ULA 前缀，取消注释）
# sed -i 's/^[^#].*option ula/#&/' /etc/config/network

# Check file system during boot（如需开机检查文件系统，取消注释）
# uci set fstab.@global[0].check_fs=1
# uci commit fstab

exit 0
