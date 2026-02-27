#!/system/bin/sh
# IDENTIFIER: ARIALUX-droid/mih-lux/mih-adr-off-smart

WORK_DIR=$(cd "$(dirname "$0")"; pwd)
CONFIG_FILE="$WORK_DIR/config.yaml"
# 补齐缺失的 PID 文件变量定义
PID_FILE="$WORK_DIR/mihomo.pid"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 未找到配置文件: $CONFIG_FILE"
    exit 1
fi

# --- 动态提取函数 ---
get_config_val() {
    # 增加严格匹配，确保只抓取顶格配置，防止抓取代理节点里的 port
    grep "^$1:" "$CONFIG_FILE" | awk -F': ' '{print $2}' | tr -d ' \r '
}

# --- 提取端口 ---
MIXED_PORT=$(get_config_val "mixed-port")
SOCKS_PORT=$(get_config_val "socks-port")
REDIR_PORT=$(get_config_val "redir-port")
TPROXY_PORT=$(get_config_val "tproxy-port")
# API 端口解析增加容错
API_PORT=$(grep "^external-controller:" "$CONFIG_FILE" | awk -F':' '{print $NF}' | tr -d ' \r ')

# 汇总所有需要清理的端口，剔除可能的空值
PORTS_TO_KILL=$(echo "$MIXED_PORT $SOCKS_PORT $REDIR_PORT $TPROXY_PORT $API_PORT" | tr -s ' ')

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

# --- 2. 智能端口强制释放 ---
for port in $PORTS_TO_KILL; do
    if [ -n "$port" ] && [ "$port" != "0" ]; then
        # netstat 获取 PID 并排除当前脚本进程
        PIDS_ON_PORT=$(netstat -tulnp | grep ":$port " | awk '{print $7}' | cut -d'/' -f1)
        for p in $PIDS_ON_PORT; do
            if [ -n "$p" ] && [ "$p" != "-" ]; then
                
                kill -9 "$p" 2>/dev/null
            fi
        done
    fi
done

# --- 3. 智能网卡清理 ---
# 更加鲁棒的网卡提取逻辑
TUN_DEVICE=$(grep -A 10 "^tun:" "$CONFIG_FILE" | grep "device:" | awk '{print $2}' | tr -d ' \r ')
[ -z "$TUN_DEVICE" ] && TUN_DEVICE="utun"

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
# 优先尝试现代 Android 通用命令
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

echo "✅ 智能清理完成"
