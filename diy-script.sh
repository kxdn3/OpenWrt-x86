# --- Lucky (sirpdboy)：直接克隆到 package/lucky，保留原始层级 ---
echo "  - Lucky (sirpdboy 版)"
if [ ! -d package/lucky ]; then
    clone https://github.com/sirpdboy/luci-app-lucky.git \
        package/lucky

    # 校验：界面包 Makefile 和核心包 Makefile 都应存在
    if [ -f package/lucky/Makefile ]; then
        echo "    ✓ package/lucky/Makefile (界面包)"
    else
        echo "!! package/lucky/Makefile 缺失" >&2
        exit 1
    fi

    if [ -f package/lucky/lucky/Makefile ]; then
        echo "    ✓ package/lucky/lucky/Makefile (核心包)"
    else
        echo "!! package/lucky/lucky/Makefile 缺失" >&2
        exit 1
    fi
else
    echo "  - package/lucky 已存在，跳过克隆"
fi
