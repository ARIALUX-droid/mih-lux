@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ============================================================
:: 1. 用户配置区 (每行一个订阅)
:: ============================================================
set "URLS=订阅1"
set "URLS=!URLS!|订阅2"
set "URLS=!URLS!|订阅3"
set "URLS=!URLS!|订阅4"

:: TUN模式开关：1开启(使用TUN)，0关闭(使用系统代理)
set TUN_SWITCH=1

:: 开机自启开关：1开启(注册系统任务)，0关闭(移除系统任务)
set AUTO_START_SWITCH=1

:: ============================================================
:: 2. 环境 definition
:: ============================================================
set "WORK_DIR=%~dp0"
cd /d "%WORK_DIR%"
set "TASK_NAME=MihomoSystemService"
set "EXE_NAME=mihomo.exe"
set "CONF_NAME=config.yaml"
set "DB_NAME=geoip.metadb"

:: 资源配置 (MetaCubeX 官方源与镜像)
set "REPO=MetaCubeX/mihomo"
set "DB_URL_1=https://gh-proxy.org/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
set "DB_URL_2=https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
set "CONF_URL_1=https://gh-proxy.org/https://github.com/ARIALUX-droid/mih-lux/raw/main/configs/config.yaml"
set "CONF_URL_2=https://github.com/ARIALUX-droid/mih-lux/raw/main/configs/config.yaml"

goto :main

:: ============================================================
:: 3. 辅助功能模块 (去日志文件版)
:: ============================================================
:_LOG
for /f "tokens=1-3 delims=/: " %%a in ("%DATE%") do set "date_str=%%a-%%b-%%c"
for /f "tokens=1-3 delims=/:." %%a in ("%TIME%") do set "time_str=%%a:%%b:%%c"
set "timestamp=[!date_str! !time_str!]"
:: 仅在控制台输出，不写入文件
echo %timestamp% [%~1] %~2
goto :eof

:_DOWNLOAD
call :_LOG "INFO" "正在下载 %~1..."
curl -L -f -# -o "%~1" "%~2"
if %errorlevel% neq 0 (
    call :_LOG "WARN" "%~1 镜像地址失效，尝试原始地址..."
    curl -L -f -# -o "%~1" "%~3"
)
goto :eof

:_OVERWRITE_CONF
:: 自动处理配置注入
call :_LOG "INFO" "正在覆写配置 (订阅链接及 TUN 状态)..."
set "TUN_VAL=false"
if "!TUN_SWITCH!"=="1" set "TUN_VAL=true"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$urlStr = '!URLS!'; " ^
    "$urls = $urlStr.Split('|'); " ^
    "$lines = Get-Content '%CONF_NAME%' -Encoding UTF8; " ^
    "$newLines = @(); " ^
    "$inZone = $false; " ^
    "$inTunZone = $false; " ^
    "$idx = 0; " ^
    "foreach ($line in $lines) { " ^
    "    if ($line -match '^proxy-providers:') { $inZone = $true; $newLines += $line; continue } " ^
    "    if ($line -match '^tun:') { $inTunZone = $true; $newLines += $line; continue } " ^
    "    if ($inTunZone -and $line -match '^\s*enable:\s*') { " ^
    "        $indent = $line.Substring(0, $line.IndexOf('enable:')); " ^
    "        $newLines += $indent + 'enable: !TUN_VAL!'; " ^
    "        $inTunZone = $false; continue; " ^
    "    } " ^
    "    if ($inZone -and $line -match '^\s*url:\s*') { " ^
    "        if ($idx -lt $urls.Count) { " ^
    "            $indent = $line.Substring(0, $line.IndexOf('url:')); " ^
    "            $newLines += $indent + 'url: \"' + $urls[$idx] + '\"'; " ^
    "            $idx++; " ^
    "        } else { " ^
    "            $newLines += $line; " ^
    "        } " ^
    "    } else { " ^
    "        $newLines += $line; " ^
    "    } " ^
    "} " ^
    "$newLines | Set-Content '%CONF_NAME%' -Encoding UTF8"

if %errorlevel% equ 0 (
    call :_LOG "INFO" "✅ 配置覆写成功 (TUN: !TUN_VAL!)。"
) else (
    call :_LOG "WARN" "⚠️ 配置覆写失败，请检查配置文件。"
)
goto :eof

:: ============================================================
:: 4. 核心执行逻辑
:: ============================================================
:main
cls
call :_LOG "INFO" "--- 启动序列开始 ---"

:: A. 管理员权限校验
net file 1>nul 2>nul
if not '%errorlevel%' == '0' (
    call :_LOG "WARN" "权限不足，尝试请求管理员权限..."
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: B. 内核处理
if not exist "%EXE_NAME%" (
    set "found_exe="
    for /f "delims=" %%i in ('dir /b /o-d *mihomo*.exe 2^>nul') do (
        if /i not "%%i"=="%EXE_NAME%" (
            set "found_exe=%%i"
            call :_LOG "INFO" "检测到本地文件 !found_exe!，正在重命名..."
            move "!found_exe!" "%EXE_NAME%" >nul
            goto :check_config
        )
    )
    if not defined found_exe (
        call :_LOG "INFO" "本地无内核，准备从云端补全..."
        for /f "tokens=2 delims=:, " %%i in ('curl -s https://api.github.com/repos/%REPO%/releases/latest ^| findstr "tag_name"') do set "LATEST_TAG=%%~i"
        set "LATEST_TAG=!LATEST_TAG:"=!"
        if "!LATEST_TAG!"=="" (call :_LOG "ERR" "无法获取版本号" && pause && exit)
        
        set "ZIP_NAME=mihomo-windows-amd64-v3-!LATEST_TAG!.zip"
        call :_DOWNLOAD "!ZIP_NAME!" "https://gh-proxy.org/https://github.com/%REPO%/releases/download/!LATEST_TAG!/!ZIP_NAME!" "https://github.com/%REPO%/releases/download/!LATEST_TAG!/!ZIP_NAME!"
        
        powershell -Command "Expand-Archive -Path '!ZIP_NAME!' -DestinationPath '.' -Force"
        for /f "delims=" %%i in ('dir /b mihomo-windows-amd64*.exe 2^>nul') do move "%%i" "%EXE_NAME%" >nul
        del /f /q "!ZIP_NAME!" 2>nul
    )
)

:check_config
:: C. 配置处理
if not exist "%CONF_NAME%" (
    set "found_conf="
    for /f "delims=" %%i in ('dir /b /o-d *.yaml *.yml 2^>nul') do (
        if /i not "%%i"=="%CONF_NAME%" (
            set "found_conf=%%i"
            call :_LOG "INFO" "检测到本地配置 !found_conf!，正在重命名..."
            move "!found_conf!" "%CONF_NAME%" >nul
            goto :apply_overwrite
        )
    )
    if not defined found_conf (
        call :_DOWNLOAD "%CONF_NAME%" "%CONF_URL_1%" "%CONF_URL_2%"
    )
)

:apply_overwrite
:: D. 应用配置覆写
if exist "%CONF_NAME%" (
    call :_OVERWRITE_CONF
)

:check_db
:: E. 数据库处理
if not exist "%DB_NAME%" (
    call :_DOWNLOAD "%DB_NAME%" "%DB_URL_1%" "%DB_URL_2%"
)

:check_task
:: ============================================================
:: F. 系统级任务管理 (开机自启同步)
:: ============================================================
set "CURRENT_SCRIPT_PATH=%~f0"

if "!AUTO_START_SWITCH!"=="1" (
    :: --- 开启逻辑：检查并注册/更新 ---
    set "NEED_UPDATE=0"
    schtasks /query /tn "%TASK_NAME%" >nul 2>&1
    if %errorlevel% neq 0 (
        set "NEED_UPDATE=1"
        call :_LOG "INFO" "自动启动：任务不存在，准备注册..."
    ) else (
        for /f "usebackq delims=" %%p in (`powershell -Command "(Get-ScheduledTask -TaskName '%TASK_NAME%').Actions.Execute"`) do (
            if /i "%%p" neq "!CURRENT_SCRIPT_PATH!" (
                set "NEED_UPDATE=1"
                call :_LOG "WARN" "自动启动：检测到路径变更，准备更新..."
            )
        )
    )

    if "!NEED_UPDATE!"=="1" (
        schtasks /create /tn "%TASK_NAME%" /tr "'!CURRENT_SCRIPT_PATH!' /start" /sc onstart /ru SYSTEM /rl highest /f >nul
        if %errorlevel% equ 0 (
            call :_LOG "INFO" "✅ 系统级自启任务已启用。"
        ) else (
            call :_LOG "ERR" "❌ 自启任务注册失败，请检查权限。"
        )
    ) else (
        call :_LOG "INFO" "自动启动：配置已是最新。"
    )
) else (
    :: --- 关闭逻辑：检测并移除 ---
    schtasks /query /tn "%TASK_NAME%" >nul 2>&1
    if %errorlevel% equ 0 (
        call :_LOG "WARN" "自动启动：正在根据配置移除系统任务..."
        schtasks /delete /tn "%TASK_NAME%" /f >nul
        if %errorlevel% equ 0 (
            call :_LOG "INFO" "✅ 系统级自启任务已移除。"
        )
    ) else (
        call :_LOG "INFO" "自动启动：当前已处于关闭状态。"
    )
)

:: ============================================================
:: G. 进程清理与启动 (集成停止逻辑)
:: ============================================================
:: [1] 检测并尝试下载停止脚本 (作为备份留存)
if not exist "mih-win-off.bat" (
    call :_LOG "WARN" "未检测到停止脚本，正在下载备份..."
    call :_DOWNLOAD "mih-win-off.bat" "https://gh-proxy.org/https://github.com/ARIALUX-droid/mih-lux/raw/main/mih-ops/mih-win-off.bat" "https://github.com/ARIALUX-droid/mih-lux/raw/refs/heads/main/mih-ops/mih-win-off.bat"
)

call :_LOG "INFO" "正在执行集成停止逻辑，清理端口占用..."

:: [2] 参数配置 (从原 off 脚本迁移)
set "PORT_LABELS=mixed-port socks-port redir-port tproxy-port port"

:: [3] 多维度端口扫描与清理 (从原 off 脚本迁移)
if exist "%CONF_NAME%" (
    for %%l in (%PORT_LABELS%) do (
        for /f "tokens=2 delims=: " %%a in ('findstr /r "^[ ]*%%l:" "%CONF_NAME%"') do (
            set "P=%%a"
            :: 针对提取到的每个有效端口，执行 netstat 溯源杀进程
            for /f "tokens=5" %%p in ('netstat -aon ^| findstr /r ":!P![^0-9]"') do (
                taskkill /f /pid %%p >nul 2>&1
            )
        )
    )
)

:: [4] 强制结束主进程树 
taskkill /f /im "%EXE_NAME%" /t >nul 2>&1
taskkill /f /im clash-meta.exe /t >nul 2>&1

:: [5] 继续执行原启动逻辑
call :_LOG "INFO" "停止序列完成，正在启动内核流程..."

call :_LOG "INFO" "正在精确解析 YAML 配置模式..."

:: 1. 深度解析 TUN 状态 (由 TUN_SWITCH 变量控制)
set "TUN_ENABLED=false"
if "!TUN_SWITCH!"=="1" (
    set "TUN_ENABLED=true"
) else (
    set "TUN_ENABLED=false"
)

:: 2. 自动识别 mixed-port 
set "M_PORT=7890"
for /f "tokens=2 delims=: " %%a in ('findstr /r "^[ ]*mixed-port:" "%CONF_NAME%"') do (
    set "M_PORT=%%a"
)

:: 3. 逻辑重构：严格互斥控制 
if "!TUN_ENABLED!"=="true" (
    :: 强制将注册表 ProxyEnable 设为 0 
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >nul
) else (
    :: 强制将注册表 ProxyEnable 设为 1，并填入正确端口 
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f >nul
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "127.0.0.1:!M_PORT!" /f >nul
)

call :_LOG "INFO" "正在调起内核并优化优先级..."
if not exist clash.log type nul > clash.log

:: 创建临时 VBS 脚本来无窗口启动
set "TEMP_VBS=%TEMP%\mihomo_start_!RANDOM!.vbs"
(
echo Set objShell = CreateObject("WScript.Shell"^)
echo objShell.CurrentDirectory = "%WORK_DIR%"
echo strCmd = "cmd /c ""%EXE_NAME% -d . -f %CONF_NAME% > clash.log 2>&1"""
echo objShell.Run strCmd, 0, False
echo Set objWMI = GetObject("winmgmts:\\.\root\cimv2"^)
echo WScript.Sleep 500
echo Set colProcesses = objWMI.ExecQuery("Select * from Win32_Process Where Name = '%EXE_NAME%'"^)
echo If colProcesses.Count ^> 0 Then
echo   For Each p in colProcesses
echo     p.SetPriority(128^)
echo   Next
echo End If
) > "%TEMP_VBS%"

cscript.exe "%TEMP_VBS%" >nul 2>&1
del /f /q "%TEMP_VBS%" 2>nul

:: 检查进程是否成功启动
tasklist /FI "IMAGENAME eq %EXE_NAME%" 2>nul | findstr /I "%EXE_NAME%" >nul
if %errorlevel% equ 0 (
    call :_LOG "INFO" "✅ 内核启动成功。"
) else (
    call :_LOG "ERR" "❌ 启动失败。"
)

call :_LOG "INFO" "--- 会话结束 ---"
exit