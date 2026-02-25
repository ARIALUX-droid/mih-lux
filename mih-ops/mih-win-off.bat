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
:: 定义需要检查的端口标签名 (空格分隔)
set "PORT_LABELS=mixed-port socks-port redir-port tproxy-port port"

:: [3] 多维度端口扫描与清理
if exist "%CONFIG_FILE%" (
    for %%l in (%PORT_LABELS%) do (
        for /f "tokens=2 delims=: " %%a in ('findstr /r "^[ ]*%%l:" "%CONFIG_FILE%"') do (
            set "P=%%a"
            :: 针对提取到的每个有效端口，执行 netstat 溯源杀进程
            for /f "tokens=5" %%p in ('netstat -aon ^| findstr /r ":!P![^0-9]"') do (
                taskkill /f /pid %%p >nul 2>&1
            )
        )
    )
)

:: [4] 强制结束主进程树 (防止无端口挂起的僵尸进程)
taskkill /f /im mihomo.exe /t >nul 2>&1
taskkill /f /im clash-meta.exe /t >nul 2>&1

:: [6] 瞬时退出
exit