#!/system/bin/sh
# IDENTIFIER: ARIALUX-droid/mih-lux/mih-adr-off-smart

WORK_DIR=$(cd "$(dirname "$0")"; pwd)
CONFIG_FILE="$WORK_DIR/config.yaml"
# 补齐缺失的 PID 文件变量定义
PID_FILE="$WORK_DIR/mihomo.pid"

# #-------
if [ -f "$CONFIG_FILE" ]; then
    HAS_CONFIG=true
else
    HAS_CONFIG=false
    echo "⚠️ 未找到配置文件，将仅执行内核进程强制清理"
fi
# #-------

# --- 动态提取函数 ---
get_config_val() {
    
    grep "^$1:" "$CONFIG_FILE" | awk -F': ' '{print $2}' | tr -d ' \r '
}

# --- 提取端口 ---

if [ "$HAS_CONFIG" = true ]; then
    MIXED_PORT=$(get_config_val "mixed-port")
    SOCKS_PORT=$(get_config_val "socks-port")
    REDIR_PORT=$(get_config_val "redir-port")
    TPROXY_PORT=$(get_config_val "tproxy-port")
    # API 端口解析增加容错
    API_PORT=$(grep "^external-controller:" "$CONFIG_FILE" | awk -F':' '{print $NF}' | tr -d ' \r ')

    # 汇总所有需要清理的端口，剔除可能的空值
    PORTS_TO_KILL=$(echo "$MIXED_PORT $SOCKS_PORT $REDIR_PORT $TPROXY_PORT $API_PORT" | tr -s ' ')
fi
# #-------

# --- 1. 优先处理 PID 文件 (双重保险：PID + 进程名校验) ---
if [ -f "$PID_FILE" ]; then
    TARGET_PID=$(cat "$PID_FILE")
    if [ -n "$TARGET_PID" ]; then
        # 增加 proc 文件系统校验，确保不误杀
        if [ -d "/proc/$TARGET_PID" ] && grep -q "mihomo" "/proc/$TARGET_PID/cmdline" 2>/dev/null; then
            kill -9 "$TARGET_PID" 2>/dev/null
        fi
    fi
    rm -f "$PID_FILE"
fi

# #-------
if [ "$HAS_CONFIG" = false ]; then
    pkill -9 mihomo 2>/dev/null
fi
# #-------

# --- 2. 端口强制释放 ---
for port in $PORTS_TO_KILL; do
    if [ -n "$port" ] && [ "$port" != "0" ]; then
        # 优先使用 fuser 精准杀死占用该 TCP 端口的进程
        if command -v fuser >/dev/null 2>&1; then
            fuser -k "$port/tcp" >/dev/null 2>&1
        else
            # 备选方案：提取 PID 并清理
            PIDS=$(netstat -tulnp 2>/dev/null | grep ":$port " | awk '{print $7}' | grep -oE '^[0-9]+')
            if [ -n "$PIDS" ]; then
                for p in $PIDS; do
                    kill -9 "$p" 2>/dev/null
                done
            fi
        fi
        # 短暂缓冲，让内核处理端口释放
        sleep 0.2
    fi
done

#-------

# --- 3. 智能网卡清理 ---
if [ "$HAS_CONFIG" = true ]; then
    TUN_DEVICE=$(grep -A 10 "^tun:" "$CONFIG_FILE" | grep "device:" | awk '{print $2}' | tr -d ' \r ')
fi
[ -z "$TUN_DEVICE" ] && TUN_DEVICE="utun"
# #-------

if ip link show "$TUN_DEVICE" > /dev/null 2>&1; then
    echo "🌐 撤销虚拟网卡: $TUN_DEVICE"
    ip link set "$TUN_DEVICE" down
    ip link delete "$TUN_DEVICE"
fi

# --- 4. 环境复位 (逻辑重构版) ---
# 1. 代理参数彻底归零
settings put global http_proxy :0
settings put global global_http_proxy_host ""
settings put global global_http_proxy_port "0"

# 2. 静默刷新 DNS 缓存 (解决 500 报错)
ndc resolver flushnet >/dev/null 2>&1

# 3. 针对所有活跃接口进行地毯式刷新 (MECE原则：不留死角)
for net_if in $(ls /sys/class/net); do
    # 仅针对已启用的物理/虚拟网卡发送刷新请求
    if [ "$(cat /sys/class/net/$net_if/operstate 2>/dev/null)" = "up" ]; then
        ndc resolver flushif "$net_if" >/dev/null 2>&1
    fi
done

# 4. 内核层强制同步
ip route flush cache

# --- 5. 最终状态审计  ---
FAILED_ITEMS=""

# 核心判准：如果进程已消失且网卡已卸载，则视为内核级清理成功
# 只有在 pgrep 依然能抓到进程时，才进行深度的端口 LISTEN 状态审计

if pgrep mihomo > /dev/null 2>&1; then
    FAILED_ITEMS="$FAILED_ITEMS [mihomo进程残留]"
    
    # 仅在进程残留时，审计端口的具体占用情况
    for port in $PORTS_TO_KILL; do
        if [ -n "$port" ] && [ "$port" != "0" ]; then
            # 过滤只检查 LISTEN 状态，排除 TIME_WAIT 导致的误报
            if netstat -tulnp 2>/dev/null | grep ":$port " | grep -q "LISTEN"; then
                FAILED_ITEMS="$FAILED_ITEMS [端口:$port未释放]"
            fi
        fi
    done
fi

# TUN 设备残留校验 (独立校验)
if ip link show "$TUN_DEVICE" > /dev/null 2>&1; then
    FAILED_ITEMS="$FAILED_ITEMS [网卡:$TUN_DEVICE]"
fi

# 输出审计结果
if [ -z "$FAILED_ITEMS" ]; then
    echo "✅ 智能清理完成"
    exit 0
else
    echo "❌ 以下项目未被成功清理:$FAILED_ITEMS"
    exit 1
fi
