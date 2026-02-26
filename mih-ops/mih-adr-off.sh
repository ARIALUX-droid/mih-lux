#!/system/bin/sh
# IDENTIFIER: ARIALUX-droid/mih-lux/mih-adr-off
# 以上是唯一特征码，不要删除

WORK_DIR=$(cd "$(dirname "$0")"; pwd)
SELF_PID=$$

# 1. 进程清理
# 优先处理 PID 文件
PID_FILE="$WORK_DIR/mihomo.pid"
if [ -f "$PID_FILE" ]; then
    TARGET_PID=$(cat "$PID_FILE")
    if [ -n "$TARGET_PID" ] && [ "$TARGET_PID" -ne "$SELF_PID" ]; then
        kill -9 "$TARGET_PID" 2>/dev/null
    fi
    rm -f "$PID_FILE"
fi

PIDS=$(pgrep "mihomo" | grep -v "$SELF_PID")
if [ -n "$PIDS" ]; then
    echo "$PIDS" | xargs kill -9 2>/dev/null
fi

# 2. 端口强制释放
for port in 7890 9090; do
    PIDS_ON_PORT=$(netstat -tulnp | grep ":$port " | awk '{print $7}' | cut -d'/' -f1)
    for p in $PIDS_ON_PORT; do
        if [ -n "$p" ] && [ "$p" != "-" ] && [ "$p" -ne "$SELF_PID" ]; then
            kill -9 "$p" 2>/dev/null
        fi
    done
done

# 3. 网络栈复位 
# 撤销 TUN 网卡
for dev in "Meta" "utun" "tun0" "clash"; do
    if ip link show "$dev" > /dev/null 2>&1; then
        ip link set "$dev" down
        ip link delete "$dev"
    fi
done

# 4. 系统环境参数回归
settings put global http_proxy :0
settings put global global_http_proxy_host ""
settings put global global_http_proxy_port "0"

ndc resolver flushdefaultif 2>/dev/null

echo "✅ 代理已断开。"