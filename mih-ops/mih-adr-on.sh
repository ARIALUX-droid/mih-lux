#!/system/bin/sh
# IDENTIFIER: ARIALUX-droid/mih-lux/mih-adr-on
# 以上是唯一特征码，不要删除

# 1. 用户配置区
# ==================================
# 填入订阅链接（每行一个），启动时将自动覆写配置
#仅接受 http(s)，其他无效不会覆写
URLS="
订阅1
订阅2
订阅3
"

# 配置模式：1-通用配置（666大佬OneTouch），2-自用配置
CONFIG_MODE=1

# 自启动开关：1开启，0关闭
AUTO_START=1

#1开启加速链接，0直接使用原链接
ENABLE_PROXY=1

# 面板下载：1-执行下载安装，0-跳过（安装成功后会自动变为0）
INSTALL_PANEL=1

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

# ==================================
# 执行目录安全检查、自动迁移并立即执行
case "$WORK_DIR" in
    /data/local/tmp*|/data/adb*)
        # 处于允许的目录及其子目录下，跳过检测
        ;;
    *)
        # 不在允许范围内，执行迁移并后续执行
        NEW_HOME="/data/adb/mih-lux"
        NEW_PATH="$NEW_HOME/mih-adr-on.sh"
        echo "⚠️ 当前目录 $WORK_DIR 不在允许范围内。
        推荐放在/data/adb/中执行"
        echo "🚚 正在迁移脚本至 $NEW_HOME 并启动..."
        [ ! -d "$NEW_HOME" ] && mkdir -p "$NEW_HOME" && chmod 755 "$NEW_HOME"
        mv "$SELF_PATH" "$NEW_PATH"
        chmod +x "$NEW_PATH"
        # 迁移后立即替换当前进程并执行新路径下的脚本
        exec /system/bin/sh "$NEW_PATH"
        ;;
esac
# ==================================

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
# ==================================
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

#echo "启动中"

if ! check_and_prepare_env; then
    echo "❌ 环境修复失败，请检查网络。"
    exit 1
fi

# 权限与归属
chmod 777 "$BIN_NAME"
chown root:root "$BIN_NAME" 2>/dev/null 

# 自动处理配置注入
# =============tun覆写================
# 锁定 tun 模块的作用域
TUN_START=$(grep -n "^tun:" "$CONF_NAME" | head -n 1 | cut -d: -f1)
if [ -z "$TUN_START" ]; then
    echo "🔧 配置文件缺少 tun 模块，正在注入默认 tun 配置..."
    sed -i '1i \
tun:\
  enable: true\
  stack: gvisor\
  device: Meta\
  udp-timeout: 300\
  auto-route: true\
  auto-redirect: true\
  auto-detect-interface: true\
  strict-route: true\
  dns-hijack:\
    - any:53\
    - tcp://any:53' "$CONF_NAME"
else
    # 计算 tun 块的结束行
    TUN_END=$(sed -n "$((TUN_START + 1)),\$p" "$CONF_NAME" | grep -n "^[^ #]" | head -n 1 | cut -d: -f1)
    if [ -n "$TUN_END" ]; then TUN_END=$((TUN_START + TUN_END)); else TUN_END=$(wc -l < "$CONF_NAME"); fi
    
    # 在锁定区间内强制修改 enable 和 auto-redirect
    sed -i "${TUN_START},${TUN_END}s/enable: .*/enable: true/" "$CONF_NAME"
    sed -i "${TUN_START},${TUN_END}s/auto-redirect: .*/auto-redirect: true/" "$CONF_NAME"
fi
# ==================================

# =======加固型 pid-file 处理 =========
sed -i '/^pid-file:/d' "$CONF_NAME"
MIXED_LINE=$(grep -n "^mixed-port:" "$CONF_NAME" | head -n 1 | cut -d: -f1)
if [ -n "$MIXED_LINE" ]; then
    sed -i "${MIXED_LINE}a pid-file: $WORK_DIR/mihomo.pid" "$CONF_NAME"
else
    sed -i "1i pid-file: $WORK_DIR/mihomo.pid" "$CONF_NAME"
fi
#============订阅覆写功能=============
# 仅在 proxy-providers 存在时执行
if grep -q "proxy-providers:" "$CONF_NAME"; then
    
    # 导出 URLS 给 awk 使用
    export URLS_STR="$URLS"
    
    awk '
    BEGIN {
        split(ENVIRON["URLS_STR"], url_list, /[[:space:]\n]+/)
        # 过滤空值，确保索引准确
        j=1; for(i in url_list) if(url_list[i] ~ /^https?:\/\//) real_urls[j++]=url_list[i]
        u_idx = 1; in_pp = 0; pp_indent = -1; node_indent = -1; in_hc = 0
    }
    # 文档分割符重置
    /^---/ { in_pp = 0; in_hc = 0; pp_indent = -1; print; next }
    # 识别 PP 块
    /^[[:space:]]*["'\'']?proxy-providers["'\'']?:/ {
        in_pp = 1; match($0, /^[[:space:]]*/); pp_indent = RLENGTH
        print; next
    }
    in_pp {
        match($0, /^[[:space:]]*/); curr_indent = RLENGTH
        content = $0; sub(/^[[:space:]]*/, "", content)
        # 退出 PP 块判定
        if (curr_indent <= pp_indent && content ~ /^[^#]/ && $0 !~ /proxy-providers:/) {
            in_pp = 0; in_hc = 0; node_indent = -1
        }
        if (in_pp) {
            # 识别新 Provider 节点 (排除关键字和特殊锚点)
            if (content ~ /^[^[:space:]]+:/ && content !~ /^(type|url|path|interval|filter|exclude|override|health-check|header|skip-cert|<<|&)/) {
                node_indent = curr_indent; in_hc = 0
            }
            # 识别并进入 health-check 块
            if (content ~ /^health-check:/) { in_hc = 1; hc_indent = curr_indent }
            else if (in_hc && curr_indent <= hc_indent && content ~ /^[^#]/) { in_hc = 0 }
            # 执行精准替换：必须在节点下、非 HC 块内、缩进正确
            if (!in_hc && node_indent != -1 && curr_indent > node_indent && content ~ /^url:/) {
                if (real_urls[u_idx] != "") {
                    sub(/url:[[:space:]]*.*/, "url: \"" real_urls[u_idx] "\"", $0)
                    u_idx++
                }
            }
        }
    }
    { print }
    ' "$CONF_NAME" > "${CONF_NAME}.tmp" && mv "${CONF_NAME}.tmp" "$CONF_NAME"
fi

#============

# 进程清理与启动
if [ -f "$WORK_DIR/$OFF_SCRIPT" ]; then
    OFF_OUTPUT=$(sh "$WORK_DIR/$OFF_SCRIPT" 2>&1)
    OFF_STATUS=$?
    if [ $OFF_STATUS -ne 0 ]; then
       # echo "$OFF_OUTPUT"
        echo "❌ 错误：旧环境清理失败。"
       # exit 1
    fi
    # 成功时可选择静默或提示
  #  echo "$OFF_OUTPUT"
fi

sleep 1
export GOMEMLIMIT=$MEM_LIMIT
ulimit -m 524288

# ===========启动与检验===============
./"$BIN_NAME" -d "$WORK_DIR" -f "$CONF_NAME" > "$LOG_NAME" 2>&1 &
PID=$!

# 等待内核初始化及网络挂载
sleep 4

# 多维状态校验逻辑
CHECK_SUCCESS=1

# 1. 进程存活校验
if ! ps -p $PID > /dev/null; then
    CHECK_SUCCESS=0
fi

# 2. 端口监听校验 (从 config.yaml 动态获取端口)
# 提取第一个可用的代理端口用于连通性测试
CHECK_PORTS=$(grep -E "^(mixed-port|socks-port|redir-port|tproxy-port):" "$CONF_NAME" | awk '{print $2}' | tr -d ' \r')
TEST_PORT=$(echo "$CHECK_PORTS" | grep -v "^0$" | head -n 1)

for cp in $CHECK_PORTS; do
    if [ "$cp" != "0" ] && ! netstat -tulnp | grep -q ":$cp "; then
        CHECK_SUCCESS=0
        break
    fi
done

# 3. TUN 设备校验
CHECK_TUN=$(grep -A 10 "^tun:" "$CONF_NAME" | grep "device:" | awk '{print $2}' | tr -d ' \r ')
[ -z "$CHECK_TUN" ] && CHECK_TUN="Meta"

if ! ip link show "$CHECK_TUN" > /dev/null 2>&1; then
    CHECK_SUCCESS=0
fi

#---新增---
# 4. 真实连通性校验 (Google 访问测试)
if [ "$CHECK_SUCCESS" -eq 1 ] && [ -n "$TEST_PORT" ]; then
    # 使用 curl 通过本地代理端口进行握手测试，超时设为 3 秒
    if ! curl -I -s --connect-timeout 3 -x "127.0.0.1:$TEST_PORT" http://www.google.com/generate_204 | grep -q "204"; then
        CHECK_SUCCESS=0
    fi
fi
#-------

if [ "$CHECK_SUCCESS" -eq 1 ]; then
    echo -800 > /proc/"$PID"/oom_score_adj 2>/dev/null
    echo "✅ 启动完成，TUN代理及互联网出境已就绪"
else
    echo "❌ 启动失败：内核异常、端口冲突或无法连接至外部网络。"
    echo "🔍 诊断建议：检查 /data/adb/mih-lux/$LOG_NAME 并确认订阅节点是否有效"
    # 启动失败时执行清理
    [ -f "$WORK_DIR/$OFF_SCRIPT" ] && sh "$WORK_DIR/$OFF_SCRIPT" >/dev/null 2>&1
    exit 1
fi