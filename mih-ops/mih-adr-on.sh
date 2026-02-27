#!/system/bin/sh
# IDENTIFIER: ARIALUX-droid/mih-lux/mih-adr-on
# 以上是唯一特征码，不要删除

# 1. 用户配置区
# ==================================
# 填入订阅链接（每行一个），启动时将自动覆写配置
URLS="
订阅1
订阅3
订阅3
"

# 配置模式：1-通用配置（666大佬OneTouch），2-自用配置
CONFIG_MODE=2

# 自启动开关：1开启，0关闭
AUTO_START=1

#1开启加速链接，0直接使用原链接
ENABLE_PROXY=1

# 面板下载：1-执行下载安装，0-跳过（安装成功后会自动变为0）
INSTALL_PANEL=0

MEM_LIMIT="256MiB"

# 2. 系统变量定义
# ==========================================
REPO="MetaCubeX/mihomo"
BIN_NAME="mihomo"
CONF_NAME="config.yaml"
LOG_NAME="clash.log"
OFF_SCRIPT="mih-adr-off.sh"
GEOIP_NAME="geoip.metadb"
PANEL_PKG="top.zashboard.toapp.app"

#mihomo配置文件下载地址
#通用配置（666大佬OneTouch）
COMMON_CONF_URL="https://raw.githubusercontent.com/666OS/YYDS/main/mihomo/config/OneTouch.yaml"
#自用配置 geoip.metadb
CONF_URL="https://github.com/ARIALUX-droid/mih-lux/raw/main/configs/config.yaml"  
# 数据库下载地址
GEOIP_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
#停止脚本下载地址
OFF_URL="https://github.com/ARIALUX-droid/mih-lux/raw/refs/heads/main/mih-ops/mih-adr-off.sh"
# 面板下载链接
PANEL_URL="https://github.com/ARIALUX-droid/mih-lux/raw/main/bin/android/app/zashboard.apk"

APK_NAME="zashboard_tmp.apk"

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
# 获取处理后的URL函数
get_real_url() {
    local raw_url=$1
    if [ "$ENABLE_PROXY" -eq 1 ]; then
    #可自定义修改加速链接
        echo "https://gh-proxy.org/$raw_url"
    else
        echo "$raw_url"
    fi
}

# --- 【面板下载】 ---
run_install_panel() {
    if [ "$INSTALL_PANEL" -ne 1 ]; then
        return 0
    fi

    echo "🚀 开始处理面板安装任务..."
    
# 动态获取下载链接
    local final_panel_url=$(get_real_url "$PANEL_URL")
    echo "⬇️ 尝试下载: $final_panel_url"
    curl -L -f -# -o "$WORK_DIR/$APK_NAME" "$final_panel_url"

    # 下载逻辑
    for url in $PANEL_URLS; do
        echo "⬇️ 尝试下载: $url"
        curl -L -f -# -o "$WORK_DIR/$APK_NAME" "$url"
        if [ -s "$WORK_DIR/$APK_NAME" ]; then
            echo "✅ 下载成功。"
            break
        fi
        rm -f "$WORK_DIR/$APK_NAME"
    done

    if [ -s "$WORK_DIR/$APK_NAME" ]; then
        INSTALL_SUCCESS=0
        echo "📦 正在尝试增强型静默安装..."
        LD_LIBRARY_PATH=/system/lib64:/system/lib pm install -r -t -d "$WORK_DIR/$APK_NAME" > /dev/null 2>&1
        
        if pm list packages | grep -q "$PANEL_PKG"; then
            INSTALL_SUCCESS=1
        else
            echo "⚠️ 方法 A 失败，尝试方法 B (管道流安装)..."
            cat "$WORK_DIR/$APK_NAME" | pm install -S $(stat -c%s "$WORK_DIR/$APK_NAME")
            [ $? -eq 0 ] && INSTALL_SUCCESS=1
        fi

        if [ "$INSTALL_SUCCESS" -eq 1 ]; then
            echo "✅ 面板安装成功。"
            rm -f "$WORK_DIR/$APK_NAME"
            sed -i "s/^INSTALL_PANEL=1/INSTALL_PANEL=0/" "$SELF_PATH"
            echo "🔒 已将脚本开关重置为 0。"
        else
            echo "❌ 自动安装被系统拦截。请手动安装: $WORK_DIR/$APK_NAME"
        fi
    fi
}
# ------ ------ ------ ------ ------
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

    run_install_panel    

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

        # 内核下载地址动态转换
        local raw_core_url="https://github.com/$REPO/$CORE_PATH"
        local final_core_url=$(get_real_url "$raw_core_url")
        if download_file "$GZ_NAME" "$final_core_url" "$raw_core_url"; then

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

          # 配置文件下载地址动态转换
            if [ "$CONFIG_MODE" -eq 1 ]; then
                SELECTED_URL="$COMMON_CONF_URL"
                echo "使用通用配置模式"
            else
                SELECTED_URL="$CONF_URL"
                echo "使用自用配置模式"
            fi
            if ! download_file "$CONF_NAME" "$(get_real_url "$SELECTED_URL")" "$SELECTED_URL"; then
                 return 1
            fi
        fi
    fi

    # --- 1. 检查数据库 ---
 # 数据库下载
    if [ ! -f "$GEOIP_NAME" ]; then
        echo "🔍 $GEOIP_NAME 不存在，正在下载..."
        download_file "$GEOIP_NAME" "$(get_real_url "$GEOIP_URL")" "$GEOIP_URL"
    fi
    
# --- 停止脚本检查与下载 ---
    if [ ! -f "$OFF_SCRIPT" ]; then
        echo "🔍 未找到停止脚本 $OFF_SCRIPT，正在下载..."
       # 停止脚本下载地址动态转换
        if ! download_file "$OFF_SCRIPT" "$(get_real_url "$OFF_URL")" "$OFF_URL"; then
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