#!/system/bin/sh

# 1. 用户配置区
# ==================================
# 填入订阅链接（每行一个），启动时将自动覆写配置
URLS=(
    "订阅链接"
    "订阅链接"
)
MEM_LIMIT="256MiB"

# 2. 系统变量定义
# ==========================================
REPO="MetaCubeX/mihomo"
BIN_NAME="mihomo"
CONF_NAME="config.yaml"
LOG_NAME="clash.log"

CONF_URLS=(
    "https://xget.xi-xu.me/gh/ARIALUX-droid/mihomo-custom.mrs/raw/refs/heads/main/config.yaml" 
    "https://gh-proxy.org/https://raw.githubusercontent.com/ARIALUX-droid/mihomo-custom.mrs/main/config.yaml"
    "https://raw.githubusercontent.com/ARIALUX-droid/mihomo-custom.mrs/main/config.yaml"
)

WORK_DIR=$(cd "$(dirname "$0")"; pwd)
cd "$WORK_DIR" || exit 1

SELF_PATH=$(realpath "$0")
SERVICE_D="/data/adb/service.d"
TARGET_CONF="$SERVICE_D/mihomo_start.sh"

if [ ! -f "$TARGET_CONF" ] || ! grep -q "$SELF_PATH" "$TARGET_CONF"; then
    [ ! -d "$SERVICE_D" ] && mkdir -p "$SERVICE_D" && chmod 755 "$SERVICE_D"
    cat <<EOF > "$TARGET_CONF"
#!/system/bin/sh
sleep 10
/system/bin/sh "$SELF_PATH" start
EOF
    chmod 755 "$TARGET_CONF"
    echo "已修改自启动配置"
fi

# ==========================================
# 3. 功能函数
# ==========================================

download_file() {
    local target_name=$1
    shift
    local urls=("$@")
    for url in "${urls[@]}"; do
        echo "⬇️  下载 $target_name: $url"
        curl -L -f -# -o "$target_name" "$url"
        [ -s "$target_name" ] && return 0
        rm -f "$target_name"
    done
    return 1
}

check_and_prepare_env() {

    if [ ! -f "$BIN_NAME" ]; then
        LOCAL_BIN=$(ls | grep -iE "mihomo|clash" | grep -vE "\.(db|dat|mmdb|metadb|yaml|yml|sh|log|gz|txt)$" | head -n 1)
        
        if [ -n "$LOCAL_BIN" ]; then
            echo "📦 发现本地内核文件: $LOCAL_BIN"
            echo "   正在重命名为 $BIN_NAME..."
            mv "$LOCAL_BIN" "$BIN_NAME"
            chmod +x "$BIN_NAME"
        fi
    fi

    if [ ! -f "$BIN_NAME" ]; then
        echo "🔍 未找到内核，正在下载..."
        LATEST_TAG=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        [ -z "$LATEST_TAG" ] && return 1

        GZ_NAME="mihomo-android-arm64-v8-${LATEST_TAG}.gz"
        CORE_PATH="releases/download/$LATEST_TAG/$GZ_NAME"
        CORE_URLS=(
            "https://xget.xi-xu.me/gh/https://github.com/$REPO/$CORE_PATH"
            "https://gh-proxy.org/https://github.com/$REPO/$CORE_PATH"
            "https://github.com/$REPO/$CORE_PATH"
        )

        if download_file "$GZ_NAME" "${CORE_URLS[@]}"; then
            gunzip -c "$GZ_NAME" > "$BIN_NAME"
            rm -f "$GZ_NAME"
            chmod +x "$BIN_NAME"
        else
            return 1
        fi
    fi

    # --- 3. 配置文件智能检测 ---
    if [ ! -f "$CONF_NAME" ]; then
        LOCAL_YAML=$(ls -t *.yaml 2>/dev/null | grep -vx "$CONF_NAME" | head -n 1)
        if [ -n "$LOCAL_YAML" ]; then
            echo "📦 发现本地配置 $LOCAL_YAML，正在重命名为 $CONF_NAME..."
            mv "$LOCAL_YAML" "$CONF_NAME"
        else
            echo "🔍 无本地配置，准备从云端下载默认模板..."
            if ! download_file "$CONF_NAME" "${CONF_URLS[@]}"; then
                 return 1
            fi
        fi
    fi
    
    [ -f "$BIN_NAME" ] && [ -f "$CONF_NAME" ]
}

# ==========================================
# 4. 主执行流程
# ==========================================

echo "启动中"

if ! check_and_prepare_env; then
    echo "❌ 环境修复失败，请检查网络。"
    exit 1
fi

# 权限与归属
chmod 777 "$BIN_NAME"
chown root:root "$BIN_NAME" 2>/dev/null 

# 自动处理配置注入
sed -i '/^tun:/,/enable:/ s/enable: .*/enable: true/' "$CONF_NAME"
START_LINE=$(grep -n "proxy-providers:" "$CONF_NAME" | cut -d: -f1)
if [ -n "$START_LINE" ]; then
    URL_REL_LINES=$(sed -n "$START_LINE,\$p" "$CONF_NAME" | grep -n "url:" | grep -v "#" | cut -d: -f1)
    index=0
    for rel_line in $URL_REL_LINES; do
        [ $index -ge ${#URLS[@]} ] && break
        REAL_LINE=$((START_LINE + rel_line - 1))
        TARGET_URL="${URLS[$index]}"
        sed -i "${REAL_LINE}s#\(url:[[:space:]]*\)['\" ]*[^,'\" }]*['\" ]*#\1\"$TARGET_URL\"#" "$CONF_NAME"
        index=$((index + 1))
    done
fi

# 进程清理与启动
# --- 自动检测并创建停止脚本 ---
OFF_SCRIPT="mih-adr-off.sh"
if [ ! -f "$OFF_SCRIPT" ]; then
    echo "🔍 未检测到停止脚本，正在创建..." 
    cat <<'EOF' > "$OFF_SCRIPT"
#!/system/bin/sh

PROCESSES=("mihomo" "clash" "v2ray")
for proc in "${PROCESSES[@]}"; do
    PIDS=$(pgrep -if "$proc")
    if [ -n "$PIDS" ]; then
        echo "正在停止进程: $proc ($PIDS)"
        echo "$PIDS" | xargs kill -15 2>/dev/null
        sleep 1
        STILL_ALIVE=$(pgrep -if "$proc")
        if [ -n "$STILL_ALIVE" ]; then
            echo "$STILL_ALIVE" | xargs kill -9 2>/dev/null
        fi
    fi
done

for port in 7890 9090; do
    PID_PORT=$(netstat -anp | grep ":$port " | grep -oE '[0-9]+/+' | cut -d'/' -f1 | head -n 1)
    if [ -n "$PID_PORT" ]; then
        kill -15 "$PID_PORT" 2>/dev/null
        sleep 0.5
        kill -9 "$PID_PORT" 2>/dev/null
    fi
done

for dev in "tun0" "Meta" "utun" "clash" "clash0"; do
    if ip link show "$dev" > /dev/null 2>&1; then
        ip link set "$dev" down 2>/dev/null
        ip link delete "$dev" 2>/dev/null
    fi
done

echo "✅ 环境清理完成"
EOF
    chmod 755 "$OFF_SCRIPT"
fi

sleep 1
export GOMEMLIMIT=$MEM_LIMIT
ulimit -m 524288

./"$BIN_NAME" -d "$WORK_DIR" -f "$CONF_NAME" > "$LOG_NAME" 2>&1 &
PID=$!
disown $PID

sleep 2
if ps -p $PID > /dev/null; then
    echo -800 > /proc/"$PID"/oom_score_adj 2>/dev/null
    echo "✅ 启动完成 "
else
    echo "❌ 启动失败，日志尾部内容："
    tail -n 5 "$LOG_NAME"
fi
