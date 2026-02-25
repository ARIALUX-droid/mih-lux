@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

:: [1] 自动申请管理员权限 (UAC)
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B
)

:: [2] 参数配置
set "CONFIG_FILE=config.yaml"
set "PORT_LABELS=mixed-port socks-port redir-port tproxy-port port"

:: [3] 多维度端口扫描与清理 [cite: 1, 2]
if exist "%CONFIG_FILE%" (
    for %%l in (%PORT_LABELS%) do (
        for /f "tokens=2 delims=: " %%a in ('findstr /r "^[ ]*%%l:" "%CONFIG_FILE%"') do (
            set "P=%%a"
            for /f "tokens=5" %%p in ('netstat -aon ^| findstr /r ":!P![^0-9]"') do (
                taskkill /f /pid %%p >nul 2>&1
            )
        )
    )
)

:: [4] 强制结束主进程树 [cite: 3]
taskkill /f /im mihomo.exe /t >nul 2>&1
taskkill /f /im clash-meta.exe /t >nul 2>&1

:: [5] 智能检测与恢复模块 (降低副作用的关键)
echo 正在检查系统代理状态...

:: 读取注册表 ProxyEnable 键值
for /f "tokens=3" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2^>nul') do (
    set "PROXY_STATUS=%%a"
)

:: 逻辑判断：如果 ProxyEnable 为 0x1 (1)，说明代理残留，执行清理
if "!PROXY_STATUS!"=="0x1" (
    echo [警告] 检测到代理残留，正在强制重置...
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >nul 2>&1
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "" /f >nul 2>&1
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v AutoConfigURL /t REG_SZ /d "" /f >nul 2>&1
    
    :: 仅在修改后触发系统刷新，减少系统负担
    Rundll32.exe USER32.DLL,UpdatePerUserSystemParameters
    echo [成功] 网络已恢复正常。
) else (
    echo [正常] 系统代理未开启，无需干预。
)

:: [6] 瞬时退出
timeout /t 1 >nul
exit