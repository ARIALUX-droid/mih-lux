#!/system/bin/sh
# mihomo 服务管理脚本
# ================= 配置区 =================
SERVICE_NAME="mihomo"
WORK_DIR="/data/adb/services/${SERVICE_NAME}"
BIN_PATH="${WORK_DIR}/${SERVICE_NAME}"
RUN_DIR="${WORK_DIR}/run"
mkdir -p "${RUN_DIR}"

# ---将所有运行时文件路径指向新的目录 ---
PID_FILE="${RUN_DIR}/${SERVICE_NAME}.pid"
LOG_FILE="${RUN_DIR}/run.log"
ERROR_LOG="${RUN_DIR}/run_error.log"
CORE_LOG="${RUN_DIR}/core.log"
HOTSPOT_STATE_FILE="${RUN_DIR}/hotspot.state"

# --- 配置：TUN覆写状态文件 ---
# 用于记录 TUN 配置覆写的开关状态
TUN_OVERRIDE_STATE_FILE="${RUN_DIR}/tun_override.state"

# 定义TUN接口名称，用于iptables规则和配置覆写
tun_name="Meta"

# 确保工作目录存在
mkdir -p "${WORK_DIR}"

# ================= 基础函数 =================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "${LOG_FILE}"
}

error_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${ERROR_LOG}"
}

# 获取进程 PID
get_pid() {
    pidof -s "${SERVICE_NAME}" 2> /dev/null
}

# --- 基础函数：添加iptables规则 ---
add_iptables_rules() {
    log "正在添加 iptables 转发规则..."
    # IPv4 规则
    iptables -C FORWARD -i "$tun_name" -j ACCEPT 2>/dev/null || iptables -I FORWARD -i "$tun_name" -j ACCEPT
    iptables -C FORWARD -o "$tun_name" -j ACCEPT 2>/dev/null || iptables -I FORWARD -o "$tun_name" -j ACCEPT
    # IPv6 规则
    ip6tables -C FORWARD -i "$tun_name" -j ACCEPT 2>/dev/null || ip6tables -I FORWARD -i "$tun_name" -j ACCEPT
    ip6tables -C FORWARD -o "$tun_name" -j ACCEPT 2>/dev/null || ip6tables -I FORWARD -o "$tun_name" -j ACCEPT
    log "iptables 规则添加完成。"
}


# --- 基础函数：删除iptables规则 ---
del_iptables_rules() {
    log "正在删除 iptables 转发规则..."
    # IPv4 规则
    iptables -D FORWARD -i "$tun_name" -j ACCEPT 2>/dev/null
    iptables -D FORWARD -o "$tun_name" -j ACCEPT 2>/dev/null
    # IPv6 规则
    ip6tables -D FORWARD -i "$tun_name" -j ACCEPT 2>/dev/null
    ip6tables -D FORWARD -o "$tun_name" -j ACCEPT 2>/dev/null
    log "iptables 规则删除完成。"
}

# --- 覆写 TUN 配置 (极致安全版，绝不干扰其他模块) ---
apply_tun_override() {
    local config_file="$1"
    if [ ! -f "$config_file" ]; then
        error_log "未找到配置文件: $config_file，跳过 TUN 覆写。"
        return 1
    fi

    log "正在安全覆写 TUN 配置 (仅作用于 tun: 模块)..."
    
    # 备份原配置，防止覆写出错
    cp -f "$config_file" "${config_file}.bak"

    # 使用 awk 状态机精准修改 yaml：
    # 1. 严格匹配行首的 tun: (允许后面有空格或注释)，注入 4 个核心参数
    # 2. 在 tun 块内 (in_tun=1)，仅跳过旧的这 4 个参数，保留 stack/mtu 等其他参数
    # 3. 遇到下一个顶级配置 (行首无缩进且非注释)，立即退出 tun 块状态 (in_tun=0)
    # 4. 其他所有模块 (dns, rules, proxies 等) 原封不动输出
    awk -v dev="$tun_name" '
    BEGIN { in_tun = 0; found_tun = 0 }
    
    # 严格匹配顶级 tun: 块
    /^tun:[ \t]*($|#)/ {
        found_tun = 1
        in_tun = 1
        print "tun:"
        print "  enable: true"
        print "  device: " dev
        print "  auto-route: true"
        print "  auto-detect-interface: true"
        next
    }
    
    # 在 tun 块内，精准剔除旧的 4 个核心参数（防重复）
    in_tun && /^[ \t]+enable:/ { next }
    in_tun && /^[ \t]+device:/ { next }
    in_tun && /^[ \t]+auto-route:/ { next }
    in_tun && /^[ \t]+auto-detect-interface:/ { next }
    
    # 核心安全机制：遇到下一个顶级 key（行首没有空格、Tab，且不是 # 注释），立即关闭 tun 状态
    in_tun && /^[^ \t#]/ { in_tun = 0 }
    
    # 正常打印其他所有行（包括 tun 内的其他参数，以及 tun 外的所有模块）
    { print }
    
    # 兜底：如果整个文件都没有 tun:，在末尾追加
    END {
        if (!found_tun) {
            print "tun:"
            print "  enable: true"
            print "  device: " dev
            print "  auto-route: true"
            print "  auto-detect-interface: true"
        }
    }
    ' "$config_file" > "${config_file}.tmp"
    
    if [ $? -eq 0 ]; then
        mv "${config_file}.tmp" "$config_file"
        log "TUN 配置安全覆写完成。"
    else
        error_log "TUN 配置覆写失败，已自动恢复备份。"
        mv "${config_file}.bak" "$config_file"
    fi
}

# ================= 状态检查 =================
display_status() {
    bin_pid=$(get_pid)
    if [ -n "${bin_pid}" ]; then
        log "${SERVICE_NAME} 服务正在运行 (PID: ${bin_pid})"
        # 1. 内存使用 (VmRSS) - 自动转换单位
        mem_kb=$(awk '/VmRSS/ {print $2}' /proc/${bin_pid}/status 2> /dev/null)
        if [ -n "${mem_kb}" ]; then
            if [ "${mem_kb}" -ge 1048576 ]; then
                mem_display="$(awk "BEGIN {printf \"%.2f\", ${mem_kb}/1048576}") GB"
            elif [ "${mem_kb}" -ge 1024 ]; then
                mem_display="$(awk "BEGIN {printf \"%.2f\", ${mem_kb}/1024}") MB"
            else
                mem_display="${mem_kb} kB"
            fi
            log "内存占用: ${mem_display}"
        fi
        # 2. CPU 使用
        cpu_usage=$(/system/bin/ps -eo %CPU,NAME 2> /dev/null | awk -v name="${SERVICE_NAME}" '$2 == name {print $1"%"}')
        [ -n "${cpu_usage}" ] && log "CPU 占用: ${cpu_usage}" || log "CPU 占用: 无法获取"
        # 3. 运行时间
        if [ -r "/proc/${bin_pid}/stat" ]; then
            sys_uptime=$(awk '{print int($1)}' /proc/uptime 2> /dev/null)
            proc_starttime=$(awk '{print $22}' /proc/${bin_pid}/stat 2> /dev/null)
            clk_tck=$(getconf CLK_TCK 2>/dev/null || echo 100)
            if [ -n "${sys_uptime}" ] && [ -n "${proc_starttime}" ]; then
                total_secs=$(( sys_uptime - proc_starttime / clk_tck ))
                if [ "${total_secs}" -ge 0 ] 2>/dev/null; then
                    days=$((total_secs / 86400))
                    hours=$(( (total_secs % 86400) / 3600 ))
                    mins=$(( (total_secs % 3600) / 60 ))
                    secs=$((total_secs % 60))
                    time_display=""
                    [ "${days}" -gt 0 ] && time_display="${time_display}${days}天 "
                    [ "${hours}" -gt 0 ] && time_display="${time_display}${hours}小时 "
                    [ "${mins}" -gt 0 ] && time_display="${time_display}${mins}分 "
                    time_display="${time_display}${secs}秒"
                    log "运行时间: ${time_display}"
                fi
            fi
        fi
        # 4. 网络连接数
        net_sockets=$(ls -l /proc/${bin_pid}/fd 2> /dev/null | grep -c 'socket:')
        [ "${net_sockets}" -gt 0 ] && log "网络套接字: ${net_sockets} 个"
        # 5. 磁盘 IO 统计
        if [ -r "/proc/${bin_pid}/io" ]; then
            read_bytes=$(awk '/^read_bytes:/ {print $2}' /proc/${bin_pid}/io 2> /dev/null)
            write_bytes=$(awk '/^write_bytes:/ {print $2}' /proc/${bin_pid}/io 2> /dev/null)
            read_mb=$(awk "BEGIN {printf \"%.2f\", ${read_bytes:-0}/1048576}")
            write_mb=$(awk "BEGIN {printf \"%.2f\", ${write_bytes:-0}/1048576}")
            log "磁盘IO: 读 ${read_mb} MB / 写 ${write_mb} MB"
        fi
        # 更新 PID 文件
        echo "${bin_pid}" > "${PID_FILE}"
        return 0
    else
        log "${SERVICE_NAME} 服务已停止."
        [ -f "${PID_FILE}" ] && rm -f "${PID_FILE}"
        return 1
    fi
}

# ================= 核心操作 =================
start() {
    ulimit -SHn 1000000 2> /dev/null || log "Warn: ulimit 设置失败，使用系统默认值"
    if get_pid > /dev/null 2>&1; then
        log "${SERVICE_NAME} 已在运行，无需重复启动."
        display_status
        return 0
    fi
    # 清理旧 PID 文件
    [ -f "${PID_FILE}" ] && rm -f "${PID_FILE}"
    log "正在启动 ${SERVICE_NAME}..."
    # 检查二进制文件是否存在，若无执行权限则尝试自动修复
    if [ ! -x "${BIN_PATH}" ]; then
      if [ -f "${BIN_PATH}" ]; then
        # 文件存在但无执行权限，尝试自动赋予
        log "检测到内核文件无执行权限，正在尝试自动修复..."
        chmod 755 "${BIN_PATH}"
        # 再次检查权限是否修复成功
        if [ ! -x "${BIN_PATH}" ]; then
          error_log "自动修复权限失败，请检查文件系统或手动执行: chmod 755 ${BIN_PATH}"
          return 1
        else
          log "权限修复成功，继续启动流程。"
        fi
      else
        # 文件根本不存在
        error_log "二进制文件不存在: ${BIN_PATH}"
        return 1
      fi
    fi
    # 进入工作目录
    cd "${WORK_DIR}" || { error_log "无法进入工作目录: ${WORK_DIR}"; return 1; }
    
    # --- 功能：启动前根据状态决定是否覆写 TUN 配置 ---
    if [ -f "${TUN_OVERRIDE_STATE_FILE}" ]; then
        CONFIG_FILE=""
        if [ -f "${WORK_DIR}/config.yaml" ]; then
            CONFIG_FILE="${WORK_DIR}/config.yaml"
        elif [ -f "${WORK_DIR}/config.yml" ]; then
            CONFIG_FILE="${WORK_DIR}/config.yml"
        fi

        if [ -n "$CONFIG_FILE" ]; then
            apply_tun_override "$CONFIG_FILE"
        else
            log "未找到 config.yaml 或 config.yml，跳过 TUN 覆写。"
        fi
    else
        log "TUN 配置覆写已关闭，使用原始配置文件启动。"
    fi

    # 后台启动服务 (将内核日志输出到 CORE_LOG)
    nohup "${BIN_PATH}" -d "${WORK_DIR}" < /dev/null > "${CORE_LOG}" 2>&1 &
    new_pid=$!
    echo "${new_pid}" > "${PID_FILE}"
    # 等待并检查启动状态
    sleep 2
    if display_status; then
    log "${SERVICE_NAME} 启动成功!"
    add_iptables_rules

        echo "----- 内核启动日志反馈 -----"
        tail -n 15 "${CORE_LOG}"
        echo "----------------------------"
    else
        error_log "${SERVICE_NAME} 启动失败！请检查内核日志: ${CORE_LOG}"
        echo "----- 内核错误日志反馈 -----"
        tail -n 15 "${CORE_LOG}"
        echo "----------------------------"
        return 1
    fi
}

stop() {
    bin_pid=$(get_pid)
    if [ -z "${bin_pid}" ]; then
        log "${SERVICE_NAME} 未在运行."
        [ -f "${PID_FILE}" ] && rm -f "${PID_FILE}"
        return 0
    fi
    log "正在停止 ${SERVICE_NAME} (PID: ${bin_pid})..."
    # 优雅停止 (SIGTERM)
    kill "${bin_pid}" 2> /dev/null
    sleep 1
    # 如果仍在运行，强制停止 (SIGKILL)
    if kill -0 "${bin_pid}" 2> /dev/null; then
        log "进程未响应，正在强制终止..."
        kill -9 "${bin_pid}" 2> /dev/null
        sleep 1
    fi
    
    # --- 功能：停止后始终清理iptables规则，但不改变状态文件 ---
    del_iptables_rules
    
    # 清理 PID 文件
    [ -f "${PID_FILE}" ] && rm -f "${PID_FILE}"
    log "${SERVICE_NAME} 已停止."
}

restart() {
    stop
    sleep 1
    start
}

status() {
    display_status
}

# --- 启停内核切换 ---
toggle_service() {
    if get_pid > /dev/null 2>&1; then
        stop
    else
        start
    fi
}

# ================= 配置区补充 =================
# 自启动钩子文件路径 (Magisk 开机执行目录)
AUTOSTART_SCRIPT="/data/adb/service.d/99_${SERVICE_NAME}_autostart.sh"

# ================= 自启动管理逻辑 =================
enable_autostart() {
    log "正在配置开机自启动..."
    mkdir -p /data/adb/service.d
    cat << EOF > "${AUTOSTART_SCRIPT}"
#!/system/bin/sh
# mihomo 开机自启动钩子
nohup ${WORK_DIR}/mihomo.sh autostart > /dev/null 2>&1 &
EOF
    chmod 755 "${AUTOSTART_SCRIPT}"
    chmod 755 "$0"
    if [ -f "${AUTOSTART_SCRIPT}" ]; then
        log "开机自启动已成功启用。"
    else
        error_log "开机自启动启用失败，请检查 root 权限。"
        return 1
    fi
}

disable_autostart() {
    log "正在取消开机自启动..."
    if [ -f "${AUTOSTART_SCRIPT}" ]; then
        rm -f "${AUTOSTART_SCRIPT}"
        log "开机自启动已成功禁用。"
    else
        log "开机自启动当前未启用，无需操作。"
    fi
}

# --- 启停自启切换 ---
toggle_autostart() {
    if [ -f "${AUTOSTART_SCRIPT}" ]; then
        disable_autostart
    else
        enable_autostart
    fi
}

autostart() {
    sleep 20
    if ! get_pid > /dev/null 2>&1; then
        log "自启动任务：延迟结束，正在尝试启动 ${SERVICE_NAME}..."
        start >> "${LOG_FILE}" 2>&1
    else
        log "自启动任务：${SERVICE_NAME} 已在运行，跳过。"
    fi
}

# --- 基础函数：开启/关闭/切换热点代理 ---
enable_hotspot() {
    touch "${HOTSPOT_STATE_FILE}"
    if get_pid > /dev/null 2>&1; then
        add_iptables_rules
        log "热点代理已开启，状态已保存。"
    else
        log "热点代理状态已设为开启。Mihomo 未运行，iptables 规则将在下次启动时应用。"
    fi
}

disable_hotspot() {
    rm -f "${HOTSPOT_STATE_FILE}"
    if get_pid > /dev/null 2>&1; then
        del_iptables_rules
        log "热点代理已关闭，状态已保存。"
    else
        log "热点代理状态已设为关闭。Mihomo 未运行，无需清理 iptables 规则。"
    fi
}

toggle_hotspot() {
    if [ -f "${HOTSPOT_STATE_FILE}" ]; then
        disable_hotspot
    else
        enable_hotspot
    fi
}

# --- 基础函数：开启/关闭/切换 TUN 覆写 ---
enable_tun_override() {
    touch "${TUN_OVERRIDE_STATE_FILE}"
    log "TUN 配置覆写已开启，状态已保存。下次启动内核时生效。"
}

disable_tun_override() {
    rm -f "${TUN_OVERRIDE_STATE_FILE}"
    log "TUN 配置覆写已关闭，状态已保存。下次启动内核时将使用原始配置。"
}

toggle_tun_override() {
    if [ -f "${TUN_OVERRIDE_STATE_FILE}" ]; then
        disable_tun_override
    else
        enable_tun_override
    fi
}

#================= 入口 =================
TARGET_DIR="/data/adb/services/mihomo"
TARGET_SCRIPT="${TARGET_DIR}/mihomo.sh"

CURRENT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
CURRENT_SCRIPT="${CURRENT_DIR}/$(basename "$0")"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 完整的交互菜单函数
show_menu() {
    # 初始化状态 (默认全选)
    local PROXY_ENABLED=true
    local DL_KERNEL=true
    local DL_CONFIG=true
    local DL_APP=true

    # 获取 pm 命令绝对路径
    local PM_CMD=$(command -v pm 2>/dev/null || echo "/system/bin/pm")

    while true; do
        # ★★★ 使用 ANSI 转义序列彻底清屏，避免叠加 ★★★
        printf '\033[2J\033[H'
        
        # --- 菜单显示：动态获取状态并合并选项 ---
        # 1. 获取内核状态
        if get_pid > /dev/null 2>&1; then
            mihomo_status="运行中"
            service_action="停止"
        else
            mihomo_status="已停止"
            service_action="启动"
        fi

        # 2. 获取自启状态
        if [ -f "${AUTOSTART_SCRIPT}" ]; then
            autostart_status="已启用"
            autostart_action="禁用"
        else
            autostart_status="已禁用"
            autostart_action="启用"
        fi

        # 3. 获取热点状态
        if [ -f "${HOTSPOT_STATE_FILE}" ]; then
            hotspot_status="开启"
            hotspot_action="关闭"
        else
            hotspot_status="关闭"
            hotspot_action="开启"
        fi

        # 4. 获取 TUN 覆写状态
        if [ -f "${TUN_OVERRIDE_STATE_FILE}" ]; then
            tun_override_status="开启"
            tun_override_action="关闭"
        else
            tun_override_status="关闭"
            tun_override_action="开启"
        fi
        
        # 5. 获取下载组件状态
        if $PROXY_ENABLED; then local PROXY_STR="启用"; else local PROXY_STR="关闭"; fi
        
        local COMP_STR=""
        $DL_KERNEL && COMP_STR="${COMP_STR}内核, "
        $DL_CONFIG && COMP_STR="${COMP_STR}配置, "
        $DL_APP && COMP_STR="${COMP_STR}zashboard套壳App"
        COMP_STR=$(echo "$COMP_STR" | sed 's/, $//')
        [ -z "$COMP_STR" ] && COMP_STR="无"

        echo -e "${CYAN}==========================${NC}"
        echo -e "${GREEN}     Mihomo 服务管理器${NC}"
        echo -e "${CYAN}==========================${NC}"
        
        echo -e "${YELLOW}       --- 核心控制 ---${NC}"
        echo -e "1. ${service_action} Mihomo 内核 (当前: ${GREEN}${mihomo_status}${NC})"
        echo -e "2. 重启 Mihomo 内核"
        echo -e "3. 查看运行状态"
        
        echo -e "${YELLOW}       --- 功能配置 ---${NC}"
        echo -e "4. ${autostart_action}开机自启 (当前: ${GREEN}${autostart_status}${NC})"
        echo -e "5. ${tun_override_action}TUN覆写 (当前: ${GREEN}${tun_override_status}${NC})"
        
        echo -e "${YELLOW}      --- 下载与更新 ---${NC}"
        echo -e "6. 套加速链接 (当前: ${GREEN}${PROXY_STR}${NC})"
        echo -e "7. 选择并下载组件 (当前: ${GREEN}${COMP_STR}${NC})"

        echo -e "${CYAN}==========================${NC}"
        echo -e "0. 退出脚本"
        echo -e "${CYAN}==========================${NC}"
        
        # --- 输入提示范围 ---
        printf "请选择操作 [0-8]: "
        
        read num
        case "$num" in
            # ---菜单路由逻辑 ---
            1) toggle_service ;;
            2) restart ;;
            3) status ;;
            4) toggle_autostart ;;
            5) toggle_tun_override ;;
            6) 
                if $PROXY_ENABLED; then 
                    PROXY_ENABLED=false
                    echo -e "\n${GREEN}加速链接已关闭${NC}"
                else 
                    PROXY_ENABLED=true
                    echo -e "\n${GREEN}加速链接已启用${NC}"
                fi 
                ;;
            7)
                cd "${WORK_DIR}" || { echo -e "${RED}无法进入工作目录${NC}"; continue; }
                # 选择组件
                echo -e "\n--- 选择下载组件 (输入数字，空格分隔，直接回车全选) ---"
                echo "1. 内核"
                echo "2. 配置"
                echo "3. zashboard套壳App"
                read -p "请选择 [1 2 3]: " COMP_OPT
                
                # 先清空状态
                DL_KERNEL=false; DL_CONFIG=false; DL_APP=false
                
                # 如果直接回车，则全选
                if [ -z "$COMP_OPT" ]; then
                    DL_KERNEL=true; DL_CONFIG=true; DL_APP=true
                else
                    for i in $COMP_OPT; do
                        case $i in
                            1) DL_KERNEL=true ;;
                            2) DL_CONFIG=true ;;
                            3) DL_APP=true ;;
                        esac
                    done
                fi
                
                # ================= 开始执行下载 =================
                # 设置代理前缀
                local PROXY=""
                if $PROXY_ENABLED; then
                    PROXY="https://ghfast.top/"
                fi

                # 3. 下载 mihomo 内核
                if $DL_KERNEL; then
                    echo -e "\n${GREEN}--- 正在下载 mihomo 内核 ---${NC}"
                    API_URL="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
                    KERN_URL=$(curl -s "$API_URL" | grep '"browser_download_url"' | grep "android-arm64-v8" | grep "\.gz\"" | grep -v "\.tar\.gz" | head -n 1 | awk -F '"' '{print $4}')

                    if [ -z "$KERN_URL" ]; then
                        echo -e "${RED}❌ 获取内核链接失败${NC}"
                    else
                        # 清理可能残留的旧临时文件
                        rm -f "mihomo_temp" "mihomo_temp.gz"
                        curl -L --progress-bar -o "mihomo_temp.gz" "${PROXY}${KERN_URL}"
                        
                        if [ -s "mihomo_temp.gz" ]; then
                            # 强制解压 (-f)，解压后文件名为 mihomo_temp
                            gzip -d -f "mihomo_temp.gz"
                            
                            if [ -f "mihomo_temp" ]; then
                                # 删除旧内核，直接替换
                                rm -f "mihomo"
                                mv "mihomo_temp" "mihomo"
                                chmod 755 "mihomo"
                                echo -e "${GREEN}✅ 内核下载并替换完成${NC}"
                            else
                                echo -e "${RED}❌ 内核解压失败${NC}"
                            fi
                            # 确保压缩包被彻底删除
                            rm -f "mihomo_temp.gz"
                        else
                            echo -e "${RED}❌ 内核下载失败${NC}"
                            rm -f "mihomo_temp.gz"
                        fi
                    fi
                fi

                # 4. 下载配置文件
                if $DL_CONFIG; then
                    echo -e "\n${GREEN}--- 正在下载配置文件 ---${NC}"
                    CONFIG_URL="https://github.com/ARIALUX-droid/mih-lux/raw/main/configs/config.yaml"
                    TEMP_CONFIG="config.yaml.new"

                    curl -L --progress-bar -o "$TEMP_CONFIG" "${PROXY}${CONFIG_URL}"

                    if [ -s "$TEMP_CONFIG" ]; then
                        if [ -f "config.yaml" ]; then
                            mv "config.yaml" "旧配置config.yaml"
                            echo -e "${YELLOW}⚠️ 旧配置已备份为 旧配置config.yaml${NC}"
                        fi
                        mv "$TEMP_CONFIG" "config.yaml"
                        echo -e "${GREEN}✅ 配置文件更新完成${NC}"
                    else
                        echo -e "${RED}❌ 配置文件下载失败，保留原配置${NC}"
                        rm -f "$TEMP_CONFIG"
                    fi
                fi

                # 5. 下载并静默安装 App
                if $DL_APP; then
                    echo -e "\n${GREEN}--- 正在下载并安装 zashboard套壳App ---${NC}"
                    APK_URL="https://github.com/ARIALUX-droid/mih-lux/raw/main/bin/android/app/zashboard.apk"
                    APK_NAME="zashboard.apk"

                    curl -L --progress-bar -o "$APK_NAME" "${PROXY}${APK_URL}"

                    if [ -s "$APK_NAME" ]; then
                        echo -e "${YELLOW}ℹ️ 正在尝试 Root 静默安装...${NC}"
                        
                        APK_ABS_PATH="$(pwd)/$APK_NAME"
                        INSTALL_SUCCESS=false
                        
                        # 尝试 1: 直接安装
                        INSTALL_OUT=$($PM_CMD install -r -g --user 0 "$APK_ABS_PATH" 2>&1)
                        
                        if [[ "$INSTALL_OUT" == *"Success"* ]]; then
                            echo -e "${GREEN}✅ App 静默安装成功${NC}"
                            INSTALL_SUCCESS=true
                        else
                            # 尝试 2: 复制到 /data/local/tmp 绕过 SELinux 拦截
                            cp "$APK_ABS_PATH" /data/local/tmp/zashboard.apk
                            chmod 644 /data/local/tmp/zashboard.apk
                            INSTALL_OUT2=$($PM_CMD install -r -g --user 0 /data/local/tmp/zashboard.apk 2>&1)
                            rm -f /data/local/tmp/zashboard.apk # 清理 tmp 目录下的中转包
                            
                            if [[ "$INSTALL_OUT2" == *"Success"* ]]; then
                                echo -e "${GREEN}✅ App 静默安装成功 (通过 tmp 中转)${NC}"
                                INSTALL_SUCCESS=true
                            else
                                echo -e "${RED}❌ 静默安装失败: $INSTALL_OUT2${NC}"
                                echo -e "${YELLOW}请手动点击安装: $APK_ABS_PATH${NC}"
                            fi
                        fi

                        # 核心：安装成功后，立刻删除当前目录的 APK 安装包
                        if $INSTALL_SUCCESS; then
                            rm -f "$APK_NAME"
                            echo -e "${GREEN}🗑️ 已自动清理 APK 安装包${NC}"
                        fi
                    else
                        echo -e "${RED}❌ App 下载失败${NC}"
                    fi
                fi

                echo -e "\n${GREEN}=== 所有任务执行完毕 ===${NC}"
                ;;
            0) echo "正在退出..."; exit 0 ;;
            *) echo "输入错误，请输入 0 到 8 之间的数字。" ;;
        esac
        printf "\n按回车键返回主菜单..."
        read _
    done
}

# 核心路由
case "$1" in
    start|stop|restart|status)
        "$1"
        ;;
    enable)
        enable_autostart
        ;;
    disable)
        disable_autostart
        ;;
    autostart)
        autostart
        ;;
    toggle)
        toggle_hotspot
        ;;
    # --- 行参数支持 ---
    toggle_service)
        toggle_service
        ;;
    toggle_autostart)
        toggle_autostart
        ;;
    toggle_tun_override)
        toggle_tun_override
        ;;
    menu|"")
        if [ "$CURRENT_SCRIPT" != "$TARGET_SCRIPT" ]; then
            mkdir -p "$TARGET_DIR"
            cp -f "$0" "$TARGET_SCRIPT"
            chmod 755 "$TARGET_SCRIPT"
            echo "=========================================="
            echo "[提示] 检测到非标准路径或文件名错误(如带有(1))！"
            echo "[成功] 脚本已自动部署并强制重命名为:"
            echo " $TARGET_SCRIPT"
            echo "=========================================="
            echo "以后请直接点击该路径的脚本，或使用命令："
            echo " sh $TARGET_SCRIPT start"
            echo " sh $TARGET_SCRIPT stop"
            echo "=========================================="
            exit 0
        fi
        show_menu
        ;;
    *)
        # --- 用法提示 ---
        echo "用法: $0 {start|stop|restart|status|enable|disable|toggle|toggle_service|toggle_autostart|toggle_tun_override|menu}"
        exit 1
        ;;
esac