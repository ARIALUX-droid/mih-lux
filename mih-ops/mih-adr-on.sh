#!/system/bin/sh
# IDENTIFIER: ARIALUX-droid/mih-lux/mih-adr-on
# 以上是唯一特征码，不要删除

# 1. 用户配置区
# ==================================
# 填入订阅链接（每行一个），启动时将自动覆写配置
URLS="
订阅1
订阅2
订阅3
"
# 自启动开关：1开启，0关闭
AUTO_START=1

MEM_LIMIT="256MiB"

# 2. 系统变量定义
# ==========================================
REPO="MetaCubeX/mihomo"
BIN_NAME="mihomo"
CONF_NAME="config.yaml"
LOG_NAME="clash.log"
OFF_SCRIPT="mih-adr-off.sh"

#mihomo配置文件下载地址
CONF_URLS="
https://cdn.jsdelivr.net/gh/ARIALUX-droid/mih-lux@main/configs/config.yaml
https://raw.githubusercontent.com/ARIALUX-droid/mih-lux/main/configs/config.yaml
"

#停止脚本下载地址
OFF_URLS="
https://gh-proxy.org/https://github.com/ARIALUX-droid/mih-lux/raw/main/mih-ops/mih-adr-off.sh
https://github.com/ARIALUX-droid/mih-lux/raw/refs/heads/main/mih-ops/mih-adr-off.sh
"

WORK_DIR=$(cd "$(dirname "$0")"; pwd)
cd "$WORK_DIR" || exit 1

SELF_PATH=$(realpath "$0")
SERVICE_D="/data/adb/service.d"
TARGET_CONF="$SERVICE_D/mihomo_start.sh"

# --- 自启动逻辑处理 ---
if [ "$AUTO_START" -eq 1 ]; then
    # 检查文件是否存在，或内容是否指向当前脚本
    if [ ! -f "$TARGET_CONF" ] || ! grep -q "$SELF_PATH" "$TARGET_CONF"; then
        [ ! -d "$SERVICE_D" ] && mkdir -p "$SERVICE_D" && chmod 755 "$SERVICE_D"
        cat <<EOF > "$TARGET_CONF"
#!/system/bin/sh
# Mihomo Auto Start Script
sleep 10
/system/bin/sh "$SELF_PATH"
EOF
        chmod 755 "$TARGET_CONF"
    fi
else
    # 执行删除逻辑
    if [ -f "$TARGET_CONF" ]; then
        rm -f "$TARGET_CONF"
    fi
fi

# ==========================================
# 3. 功能函数
# ==========================================

download_file() {
    local target_name=$1
    shift
    for url in "$@"; do
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
        # 顺序已调整：仅在本地确无文件后才执行下方联网指令
        LATEST_TAG=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        [ -z "$LATEST_TAG" ] && return 1

        GZ_NAME="mihomo-android-arm64-v8-${LATEST_TAG}.gz"
        CORE_PATH="releases/download/$LATEST_TAG/$GZ_NAME"
        CORE_URLS="
            https://gh-proxy.org/https://github.com/$REPO/$CORE_PATH
            https://github.com/$REPO/$CORE_PATH
        "
        if download_file "$GZ_NAME" $CORE_URLS; then
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
            if ! download_file "$CONF_NAME" $CONF_URLS; then
                 return 1
            fi
        fi
    fi

    # --- 1. 检查数据库 ---
    FILE="geoip.metadb"
    URL="https://gh-proxy.org/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"

    if [ ! -f "$FILE" ]; then
        echo "🔍 $FILE 不存在，正在下载..."
        curl -L -f -# -o "$FILE" "$URL"
        if [ $? -ne 0 ]; then
            echo "❌ $FILE 下载失败，请检查网络。"
        fi
    fi
    
# --- 停止脚本检查与下载 ---
    if [ ! -f "$OFF_SCRIPT" ]; then
        echo "🔍 未找到停止脚本 $OFF_SCRIPT，正在下载..."
        if ! download_file "$OFF_SCRIPT" $OFF_URLS; then
            echo "⚠️ 停止脚本下载失败，但不影响核心启动。"
        else
            chmod +x "$OFF_SCRIPT"
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

sed -i '/pid-file:/d' "$CONF_NAME"
sed -i "/mixed-port:/a pid-file: $WORK_DIR/mihomo.pid" "$CONF_NAME"


START_LINE=$(grep -n "proxy-providers:" "$CONF_NAME" | cut -d: -f1)
if [ -n "$START_LINE" ]; then
    URL_REL_LINES=$(sed -n "$START_LINE,\$p" "$CONF_NAME" | grep -n "url:" | grep -v "#" | cut -d: -f1)

    set -- $URLS

    for rel_line in $URL_REL_LINES; do
        [ -z "$1" ] && break
        REAL_LINE=$((START_LINE + rel_line - 1))
        TARGET_URL="$1"
        sed -i "${REAL_LINE}s#\(url:[[:space:]]*\)['\" ]*[^,'\" }]*['\" ]*#\1\"$TARGET_URL\"#" "$CONF_NAME"
        shift # 移动到下一个 URL
    done
fi

# 进程清理与启动
if [ -f "$WORK_DIR/$OFF_SCRIPT" ]; then
    (sh "$WORK_DIR/$OFF_SCRIPT" >/dev/null 2>&1 &)
    sleep 1
fi


sleep 1
export GOMEMLIMIT=$MEM_LIMIT
ulimit -m 524288

./"$BIN_NAME" -d "$WORK_DIR" -f "$CONF_NAME" > "$LOG_NAME" 2>&1 &
PID=$!

sleep 2
if ps -p $PID > /dev/null; then
    echo -800 > /proc/"$PID"/oom_score_adj 2>/dev/null
    echo "✅ 启动完成 "
else
    echo "❌ 启动失败，日志尾部内容："
    tail -n 5 "$LOG_NAME"
fi