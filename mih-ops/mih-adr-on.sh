#!/system/bin/sh
# IDENTIFIER: ARIALUX-droid/mih-lux/mih-adr-on

# 1. 用户配置区
# ==================================
# 填入订阅链接（每行一个），启动时将自动覆写配置
#仅接受 http(s)，其他无效不会覆写
URLS="
订阅
订阅
"
# 订阅链接与UA配置（用于 CONFIG_MODE=0）
SUB_URL="订阅"
UA="ClashMetaForAndroid/2.11.2.Meta"

# 配置模式：0-订阅配置（推荐）默认面板密码：mihomo 0可能兼容不好无法运行请手动修改配置
# 1-通用配置（666大佬OneTouch），2-自用配置
CONFIG_MODE=0

# 开机自启动：1开启，0关闭
AUTO_START=1

# 内核版本选择：1-稳定版(Release)，2-预览版(Alpha)，3-智能版(Smart Alpha)
CORE_TYPE=1

#数据库下载，留空不下载，内核也会自动下载
# 可选值：geoip, geosite, country, asn, model
MANUAL_GEO_LIST=

#1开启加速链接，0直接使用原链接
ENABLE_PROXY=1

# 面板下载：1-执行下载安装，0-跳过（安装成功后会自动变为0）
INSTALL_PANEL=1

MEM_LIMIT="256MiB"

# 2. 系统变量 definition
# ==========================================
REPO="MetaCubeX/mihomo"
SMART_REPO="vernesong/mihomo"
BIN_NAME="mihomo"
CONF_NAME="config.yaml"
SUB_CONF_NAME="config.sub.yaml"
LOG_NAME="run.log"
OFF_SCRIPT="mih-adr-off.sh"
GEOIP_NAME="geoip.metadb"
GEOSITE_NAME="geosite.dat"
COUNTRY_NAME="country.mmdb"
ASN_NAME="asn.mmdb"
MODEL_NAME="Model.bin"
PANEL_PKG="top.zashboard.toapp.app"

#下载地址可自行修改
#通用配置（666大佬OneTouch）
COMMON_CONF_URL="https://raw.githubusercontent.com/666OS/YYDS/main/mihomo/config/OneTouch.yaml"
#自用配置
CONF_URL="https://github.com/ARIALUX-droid/mih-lux/raw/main/configs/config.yaml"  
GEOIP_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
GEOSITE_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
COUNTRY_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"
ASN_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb"

#停止脚本下载地址
OFF_URL="https://github.com/ARIALUX-droid/mih-lux/raw/refs/heads/main/mih-ops/mih-adr-off.sh"
# 面板下载链接
PANEL_URL="https://github.com/ARIALUX-droid/mih-lux/raw/main/bin/android/app/zashboard.apk"
# LightGBM Model-large.bin
MODEL_URL="https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model-large.bin"

APK_NAME="zashboard_tmp.apk"

WORK_DIR=$(cd "$(dirname "$0")"; pwd)
cd "$WORK_DIR" || exit 1

SELF_PATH=$(realpath "$0")
SERVICE_D="/data/adb/service.d"
TARGET_CONF="$SERVICE_D/mihomo_start.sh"

# ==================================
# --- 必须先定义以下变量以确保逻辑生效 ---
# 获取当前脚本所在的绝对目录 [1]
WORK_DIR=$(cd "$(dirname "$0")"; pwd)
# 获取当前脚本的完整绝对路径 [1]
SELF_PATH=$(realpath "$0")

# 执行目录安全检查、自动迁移并立即执行 [2]
case "$WORK_DIR" in
    /data/local/tmp*|/data/adb*)
        # 处于允许的目录及其子目录下，跳过检测 [2]
        ;;
    *)
        # 不在允许范围内，执行迁移
        NEW_HOME="/data/adb/mih-lux"
        NEW_PATH="$NEW_HOME/mih-adr-on.sh"
        
        echo "⚠️ 当前目录 $WORK_DIR 不在允许范围内。"
        echo "💡 推荐将脚本放在 /data/adb/ 目录下以保证内核执行权限。"
        echo "🚚 正在迁移脚本至 $NEW_HOME 并重新启动..."

        # 1. 创建目标目录并设置权限 [2]
        if [ ! -d "$NEW_HOME" ]; then
            mkdir -p "$NEW_HOME" || { echo "❌ 无法创建目录，请检查 Root 权限"; exit 1; }
            chmod 755 "$NEW_HOME"
        fi

        # 2. 复制脚本到新路径（比直接 mv 更安全，防止执行中的脚本丢失）
        cp "$SELF_PATH" "$NEW_PATH" || { echo "❌ 迁移文件失败"; exit 1; }
        chmod +x "$NEW_PATH"

        # 3. 使用 exec 立即替换当前进程，执行新位置的脚本 [2]
        # 这样脚本会从头开始在新目录下运行，并进入上面的允许目录分支
        exec /system/bin/sh "$NEW_PATH"
        ;;
esac
# ==================================

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
# ==============内核下载====================
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
# ================版本选择==================
    if [ ! -f "$BIN_NAME" ]; then
        echo "🔍 未找到内核，正在根据配置下载对应版本..."
        
        if [ "$CORE_TYPE" -eq 1 ]; then
            LATEST_TAG=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            [ -z "$LATEST_TAG" ] && return 1
            GZ_NAME="mihomo-android-arm64-v8-${LATEST_TAG}.gz"
            raw_core_url="https://github.com/$REPO/releases/download/$LATEST_TAG/$GZ_NAME"
            
        elif [ "$CORE_TYPE" -eq 2 ]; then
            GZ_NAME=$(curl -s "https://api.github.com/repos/$REPO/releases/tags/Prerelease-Alpha" | grep '"name":' | grep -oE 'mihomo-android-arm64-v8-alpha-[a-z0-9]+\.gz' | head -n 1)
            [ -z "$GZ_NAME" ] && return 1
            raw_core_url="https://github.com/$REPO/releases/download/Prerelease-Alpha/$GZ_NAME"
            
        elif [ "$CORE_TYPE" -eq 3 ]; then
            GZ_NAME=$(curl -s "https://api.github.com/repos/$SMART_REPO/releases/tags/Prerelease-Alpha" | grep '"name":' | grep -oE 'mihomo-android-arm64-v8-alpha-smart-[a-z0-9]+\.gz' | head -n 1)
            [ -z "$GZ_NAME" ] && return 1
            raw_core_url="https://github.com/$SMART_REPO/releases/download/Prerelease-Alpha/$GZ_NAME"
            
            if [ ! -f "$MODEL_NAME" ]; then
                echo "🔍 CORE_TYPE=3，正在自动下载环境依赖 $MODEL_NAME..."
                download_file "$MODEL_NAME" "$(get_real_url "$MODEL_URL")" "$MODEL_URL"
            fi
        else
            echo "❌ 未知的 CORE_TYPE=$CORE_TYPE，无法下载内核。"
            return 1
        fi

        local final_core_url=$(get_real_url "$raw_core_url")
        if download_file "$GZ_NAME" "$final_core_url" "$raw_core_url"; then
            gunzip -c "$GZ_NAME" > "$BIN_NAME"
            rm -f "$GZ_NAME"
            chmod +x "$BIN_NAME"
        else
            return 1
        fi
    fi
# ==================================
    # --- 3. 配置文件智能检测 ---
#------ 模式0 深度识别与多配置并存逻辑
    if [ "$CONFIG_MODE" -eq 0 ]; then
        MATCH_FILE=""
        # 遍历所有 config.sub 开头的 yaml 文件，寻找匹配的 URL 标签
        for f in config.sub*.yaml; do
            [ -e "$f" ] || continue
            EXISTING_URL=$(tail -n 2 "$f" | grep "^#url:" | cut -d: -f2-)
            if [ "$EXISTING_URL" = "$SUB_URL" ]; then
                MATCH_FILE="$f"
                break
            fi
        done

        if [ -n "$MATCH_FILE" ]; then
            echo "✅ 发现匹配订阅的配置: $MATCH_FILE，直接复用。"
            CURRENT_CONF="$MATCH_FILE"
            # 更新 SUB_CONF_NAME 变量，确保后续注入逻辑指向正确文件
            SUB_CONF_NAME="$MATCH_FILE"
        else
            echo "🔍 未发现匹配订阅的配置，准备执行新下载..."
            # 自动分配新文件名：若 config.sub.yaml 已存在（且不匹配），则尝试 (1), (2)...
            if [ ! -f "config.sub.yaml" ]; then
                NEW_NAME="config.sub.yaml"
            else
                idx=1
                while [ -f "config.sub($idx).yaml" ]; do idx=$((idx + 1)); done
                NEW_NAME="config.sub($idx).yaml"
            fi
            
            echo "🌐 正在拉取订阅至 $NEW_NAME ..."
            curl -L -k -s -f --connect-timeout 15 --max-time 30 --retry 5 --retry-delay 2 -H "User-Agent: $UA" -o "$NEW_NAME" "$SUB_URL"
            if [ $? -eq 0 ] && [ -s "$NEW_NAME" ]; then
                printf "\n#mih-lux\n#url:%s\n" "$SUB_URL" >> "$NEW_NAME"
                CURRENT_CONF="$NEW_NAME"
                SUB_CONF_NAME="$NEW_NAME"
            else
                echo "❌ 订阅下载失败。"
                rm -f "$NEW_NAME"
                return 1
            fi
        fi
        
    else
        CURRENT_CONF="$CONF_NAME"
    fi

    if [ ! -f "$CURRENT_CONF" ]; then
        LOCAL_YAML=$(ls -t *.yaml 2>/dev/null | grep -vx "$CONF_NAME" | grep -vx "$SUB_CONF_NAME" | head -n 1)
        if [ -n "$LOCAL_YAML" ]; then
            echo "📦 发现本地配置 $LOCAL_YAML，正在重命名为 $CURRENT_CONF..."
            mv "$LOCAL_YAML" "$CURRENT_CONF"
        else
            echo "🔍 无本地配置，准备从云端下载默认模板..."

          # 配置文件下载地址动态转换
            if [ "$CONFIG_MODE" -eq 1 ]; then
                SELECTED_URL="$COMMON_CONF_URL"
                echo "使用通用配置模式"
                if ! download_file "$CURRENT_CONF" "$(get_real_url "$SELECTED_URL")" "$SELECTED_URL"; then return 1; fi
            else
                SELECTED_URL="$CONF_URL"
                echo "使用自用配置模式"
                if ! download_file "$CURRENT_CONF" "$(get_real_url "$SELECTED_URL")" "$SELECTED_URL"; then return 1; fi
            fi
        fi
    fi

    # --- 1. 检查数据库 ---
 # 数据库下载

if [ -n "$MANUAL_GEO_LIST" ]; then
    for item in $MANUAL_GEO_LIST; do
        case "$item" in
            "geoip")
                [ ! -f "$GEOIP_NAME" ] && download_file "$GEOIP_NAME" "$(get_real_url "$GEOIP_URL")" "$GEOIP_URL"
                ;;
            "geosite")
                [ ! -f "$GEOSITE_NAME" ] && download_file "$GEOSITE_NAME" "$(get_real_url "$GEOSITE_URL")" "$GEOSITE_URL"
                ;;
            "country")
                [ ! -f "$COUNTRY_NAME" ] && download_file "$COUNTRY_NAME" "$(get_real_url "$COUNTRY_URL")" "$COUNTRY_URL"
                ;;
            "asn")
                [ ! -f "$ASN_NAME" ] && download_file "$ASN_NAME" "$(get_real_url "$ASN_URL")" "$ASN_URL"
                ;;
            "model")
                [ ! -f "$MODEL_NAME" ] && download_file "$MODEL_NAME" "$(get_real_url "$MODEL_URL")" "$MODEL_URL"
                ;;
            *)
                echo "⚠️ 跳过未知项目: $item"
                ;;
        esac
    done
else
    echo "ℹ️ MANUAL_GEO_LIST 为空，跳过所有数据库检查。"
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

    [ -f "$BIN_NAME" ] && [ -f "$CURRENT_CONF" ]
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
# =============核心覆写逻辑================
if [ "$CONFIG_MODE" -eq 0 ]; then
    echo "🔧 执行模式0：执行加固级配置重组与块覆写..."
    
    # 1. 物理清洗：移除所有可能冲突的单行配置与多行块（profile, tun, cors）
    # 使用 awk 状态机实现暴力且安全的块擦除，避免 YAML 层级残留
    awk '
    BEGIN { 
        # 定义需要擦除的顶级块
        split("profile: tun: external-controller-cors:", blocks) 
        for(i in blocks) target[blocks[i]]=1
    }
    # 状态切换：遇到目标块起始
    $1 ~ /^(profile:|tun:|external-controller-cors:)$/ { flag=1; next }
    # 状态切换：遇到非缩进的其它顶级配置，停止擦除
    /^[^ #]/ { flag=0 }
    # 仅在非擦除状态下打印
    !flag { print }
    ' "$SUB_CONF_NAME" > "${SUB_CONF_NAME}.tmp" && mv "${SUB_CONF_NAME}.tmp" "$SUB_CONF_NAME"

    # 移除单行关键参数
    sed -i '/^port:/d; /^socks-port:/d; /^redir-port:/d; /^mixed-port:/d; /^tproxy-port:/d; /^secret:/d; /^external-controller:/d; /^ipv6:/d; /^unified-delay:/d' "$SUB_CONF_NAME"
    
    # 2. 顶层注入：强制注入用户定义的基准参数与复杂块
    # 采用 1i 确保优先级，并严格遵守 YAML 缩进
    sed -i '1i \
mixed-port: 7890\
ipv6: false\
external-controller: 127.0.0.1:9090\
secret: mihomo\
unified-delay: false\
profile:\
  store-selected: true\
external-controller-cors:\
  allow-private-network: true\
  allow-origins:\
    - tauri://localhost\
    - http://tauri.localhost\
    - https://yacd.metacubex.one\
    - https://metacubex.github.io\
    - https://board.zash.run.place\
tun:\
  enable: true\
  auto-detect-interface: true\
  auto-route: true\
  device: Mihomo\
  dns-hijack:\
    - any:53\
  mtu: 1500\
  route-exclude-address: []\
  stack: gvisor\
  strict-route: false' "$SUB_CONF_NAME"

else
    # 仅检测 tun 块是否存在
    TUN_START=$(grep -n "^tun:" "$CONF_NAME" | head -n 1 | cut -d: -f1)
    if [ -z "$TUN_START" ]; then
        echo "   配置文件缺少 tun 模块，追加基础 tun 结构..."
        sed -i '1i \
tun:\
  enable: true\
  auto-redirect: true\
  stack: gvisor\
  device: Meta' "$CONF_NAME"
    else
        # 计算 tun 块作用域并执行精准替换
        TUN_END=$(sed -n "$((TUN_START + 1)),\$p" "$CONF_NAME" | grep -n "^[^ #]" | head -n 1 | cut -d: -f1)
        if [ -n "$TUN_END" ]; then TUN_END=$((TUN_START + TUN_END)); else TUN_END=$(wc -l < "$CONF_NAME"); fi
        
        sed -i "${TUN_START},${TUN_END}s/^[[:space:]]*enable:.*/  enable: true/" "$CONF_NAME"
        sed -i "${TUN_START},${TUN_END}s/^[[:space:]]*auto-redirect:.*/  auto-redirect: true/" "$CONF_NAME"
    fi
fi
# ==================================

# =======加固型 pid-file 处理 =========
if [ "$CONFIG_MODE" -eq 0 ]; then
    ACTIVE_CONF="$SUB_CONF_NAME"
else
    ACTIVE_CONF="$CONF_NAME"
fi

sed -i '/^pid-file:/d' "$ACTIVE_CONF"
MIXED_LINE=$(grep -n "^mixed-port:" "$ACTIVE_CONF" | head -n 1 | cut -d: -f1)
if [ -n "$MIXED_LINE" ]; then
    sed -i "${MIXED_LINE}a pid-file: $WORK_DIR/mihomo.pid" "$ACTIVE_CONF"
else
    sed -i "1i pid-file: $WORK_DIR/mihomo.pid" "$ACTIVE_CONF"
fi

#============ 优化版：高兼容性订阅覆写 =============
if grep -q "proxy-providers:" "$ACTIVE_CONF"; then
  #  echo "🔄 正在执行顺序兼容性覆写..."
    
    # 获取 proxy-providers 模块开始的行号
    START_L=$(grep -n "^proxy-providers:" "$ACTIVE_CONF" | head -n 1 | cut -d: -f1)
    
    # 计数器，用于匹配 URLS 变量中的第 N 个链接
    idx=0
    for u in $URLS; do
        idx=$((idx + 1))
        
        # 寻找在 proxy-providers 之后出现的第 idx 个 "url:" 所在的相对行号
        REL_L=$(sed -n "$((START_L + 1)),\$p" "$ACTIVE_CONF" | grep -n "url:" | sed -n "${idx}p" | cut -d: -f1)
        
        if [ -n "$REL_L" ]; then
            # 计算在文件中的实际行号
            ABS_L=$((START_L + REL_L))
            
            # 精准替换逻辑：
            # 1. 匹配 url: 及其后面可能存在的空格和引号
            # 2. 替换原有内容，直到遇到下一个引号、逗号、右花括号或行尾
            # 这种写法兼容 666yyds 的 {url: ""} 格式和标准的缩进格式 [1, 2]
            sed -i "${ABS_L}s|\(url:[[:space:]]*[\"']\?\)[^\"',}]*|\1$u|" "$ACTIVE_CONF"
         #   echo "   [第 $idx 组] 已写入目标行: $ABS_L"
        else
         #   echo "   [提示] 配置文件中仅发现 $((idx-1)) 个可覆写槽位，跳过后续链接"
            break
        fi
    done
  #  echo "✅ 订阅覆写完成"
fi
#================================================

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
./"$BIN_NAME" -d "$WORK_DIR" -f "$ACTIVE_CONF" > "$LOG_NAME" 2>&1 &
PID=$!

# 等待内核初始化及网络挂载
sleep 4

# 多维状态校验 logic
CHECK_SUCCESS=1

# 1. 进程存活校验
if ! ps -p $PID > /dev/null; then
    CHECK_SUCCESS=0
fi

# 2. 真实连通性校验 (Google 访问测试)
if [ "$CHECK_SUCCESS" -eq 1 ] && [ -n "$TEST_PORT" ]; then
    # 使用 curl 通过本地代理端口进行握手测试，超时设为 5 秒
    if ! curl -I -s --connect-timeout 5 -x "127.0.0.1:$TEST_PORT" http://www.google.com/generate_204 | grep -q "204"; then
        CHECK_SUCCESS=0
    fi
fi

if [ "$CHECK_SUCCESS" -eq 1 ]; then
    echo -800 > /proc/"$PID"/oom_score_adj 2>/dev/null
    echo "✅ 启动完成，互联网出境已就绪"
else
    echo "❌ 启动失败：内核异常、端口冲突或无法连接至外部网络。"
    exit 1
fi
