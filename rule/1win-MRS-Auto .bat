@echo off
setlocal enabledelayedexpansion
title Mihomo Rule Auto Converter (Fixed & Stable)
cd /d "%~dp0"

REM ==== 1. 智能内核检测与双重下载逻辑 ====
set "BIN_NAME=mihomo.exe"
set "CORE_PATH="

REM 探测当前或上级目录
if exist "%BIN_NAME%" (
    set "CORE_PATH=%BIN_NAME%"
) else if exist "..\%BIN_NAME%" (
    set "CORE_PATH=..\%BIN_NAME%"
    echo [发现] 在上级目录找到内核: ..\%BIN_NAME%
)

REM 如果都没找到，执行带回退机制的下载 [cite: 11, 12, 13]
if "%CORE_PATH%"=="" (
    echo [状态] 未找到内核，正在尝试加速下载...
    powershell -Command ^
        "$api_fast = 'https://gh-proxy.org/https://api.github.com/repos/MetaCubeX/mihomo/releases/latest';" ^
        "$api_raw  = 'https://api.github.com/repos/MetaCubeX/mihomo/releases/latest';" ^
        "try { $json = Invoke-RestMethod -Uri $api_fast -ErrorAction Stop } " ^
        "catch { $json = Invoke-RestMethod -Uri $api_raw };" ^
        "$tag = $json.tag_name;" ^
        "$dl_fast = \"https://gh-proxy.org/https://github.com/MetaCubeX/mihomo/releases/download/$tag/mihomo-windows-amd64-v3-$tag.zip\";" ^
        "$dl_raw  = \"https://github.com/MetaCubeX/mihomo/releases/download/$tag/mihomo-windows-amd64-v3-$tag.zip\";" ^
        "try { Write-Host \"正在下载版本 $tag ...\"; Invoke-WebRequest -Uri $dl_fast -OutFile 'mihomo.zip' -ErrorAction Stop } " ^
        "catch { Write-Host '>> 加速下载失败，尝试官方直连...'; Invoke-WebRequest -Uri $dl_raw -OutFile 'mihomo.zip' };" ^
        "Expand-Archive -Path 'mihomo.zip' -DestinationPath '.' -Force;" ^
        "Move-Item 'mihomo-windows-amd64-v3.exe' 'mihomo.exe' -ErrorAction SilentlyContinue;" ^
        "Remove-Item 'mihomo.zip';"
    
    if exist "mihomo.exe" (
        set "CORE_PATH=mihomo.exe"
        echo [成功] 内核已就绪
    ) else (
        echo [错误] 内核下载失败
        pause & exit /b
    )
)

REM ==== 2. 处理文件 (支持拖放) ====
if "%~1" == "" (
    echo [提示] 请将文件拖放到此脚本上。
    set /p "USER_INPUT=路径: "
    call :ProcessFile "!USER_INPUT!"
) else (
    :Loop
    if "%~1" == "" goto End
    call :ProcessFile "%~1"
    shift
    goto Loop
)

:End
echo.
echo [完成] 所有任务已处理 [cite: 8]
pause
exit /b

:ProcessFile
set "SRC=%~1"
set "EXT=%~x1"
set "FILENAME=%~n1"
if not exist "%SRC%" goto :eof

REM 自动识别格式 [cite: 8]
set "FMT=yaml"
if /i "%EXT%"==".txt" set "FMT=text"
if /i "%EXT%"==".mrs" set "FMT=mrs"
if /i "%EXT%"==".yaml" set "FMT=yaml"

REM 自动识别类型 [cite: 8, 17]
set "MODE=domain"
for /f "usebackq tokens=* delims=" %%a in ("%SRC%") do (
    echo %%a | findstr /r "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*" >nul
    if !errorlevel! == 0 (set "MODE=ipcidr" & goto :DoConvert)
)

:DoConvert
echo [处理] %FILENAME% (模式: %MODE%)
if /i "%FMT%"=="mrs" (
    "%CORE_PATH%" convert-ruleset %MODE% mrs "%SRC%" "%FILENAME%.yaml"
) else (
    "%CORE_PATH%" convert-ruleset %MODE% %FMT% "%SRC%" "%FILENAME%.mrs"
)
goto :eof