@echo off
chcp 936 >nul
setlocal EnableExtensions

rem ============================================================
rem  JetBrains 一键激活（Windows CMD）— 离线版，全程不启动服务器
rem
rem  一条命令完成全部激活流程：
rem    1. 生成/补齐签名密钥与证书（scripts\generate_keys.py，幂等，可重复运行）
rem    2. 激活本机 JetBrains IDE（离线执行 activate.ps1：
rem       ja-netfilter 资源从仓库本地复制，许可证由本地密钥离线生成）
rem
rem  需要管理员权限，脚本会自动弹出 UAC 请求。
rem  请在 CMD 终端中运行本脚本，不要双击打开。
rem ============================================================

set "SCRIPT_DIR=%~dp0"

rem ---------- 0. 请求管理员权限 ----------
net session >nul 2>&1
if errorlevel 1 (
    echo 需要管理员权限，正在请求提升（UAC）...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

rem ---------- 定位仓库根目录 ----------
for %%I in ("%SCRIPT_DIR%..\..") do set "REPO_ROOT=%%~fI"
cd /d "%REPO_ROOT%"

if not exist "scripts\generate_keys.py" (
    echo [错误] 未找到 scripts\generate_keys.py，请确认脚本位于仓库内。
    pause
    exit /b 1
)

echo.
echo ========================================
echo   JetBrains 一键激活（Windows CMD）
echo   离线模式 · 不启动服务器
echo ========================================
echo.

rem ---------- 1. 检查 Python ----------
set "PY="
for /f "usebackq delims=" %%i in (`py -3 -c "import sys;print(sys.executable)" 2^>nul`) do set "PY=%%i"
if not defined PY for /f "delims=" %%i in ('where python 2^>nul') do set "PY=%%i"
if not defined PY goto no_python
echo [1/3] 检测到 Python: %PY%

rem ---------- 2. 检查/安装 cryptography ----------
"%PY%" -c "import cryptography" >nul 2>&1
if errorlevel 1 goto install_crypto
echo [2/3] cryptography 已就绪
goto key_gen

:install_crypto
echo [2/3] 安装 cryptography 依赖...
"%PY%" -m pip install "cryptography>=3.0"
if errorlevel 1 (
    echo [错误] cryptography 安装失败，请手动执行：
    echo        "%PY%" -m pip install cryptography
    pause
    exit /b 1
)
goto key_gen

:no_python
echo [错误] 未找到 Python（需要 3.8+）。
echo        请安装 Python 并勾选 “Add python.exe to PATH” 后重试。
pause
exit /b 1

:key_gen
rem ---------- 3. 生成/补齐密钥 ----------
echo [3/3] 生成/补齐签名密钥与证书（幂等，可重复运行）...
"%PY%" scripts\generate_keys.py
if errorlevel 1 (
    echo [错误] 密钥生成失败，请检查上方输出。
    pause
    exit /b 1
)

rem ---------- 4. 离线激活（不启动服务器） ----------
echo.
echo 开始激活。请按提示选择产品并填写许可证信息。
set "OFFLINE_RESOURCES_DIR=%REPO_ROOT%\ja-netfilter"
set "OFFLINE_LICENSE_CMD=%PY%"
set "OFFLINE_LICENSE_SCRIPT=%REPO_ROOT%\server\generate_license.py"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%activate.ps1"
set "RC=%errorlevel%"
set "OFFLINE_RESOURCES_DIR="
set "OFFLINE_LICENSE_CMD="
set "OFFLINE_LICENSE_SCRIPT="
echo.
echo 激活流程已结束。
pause
exit /b %RC%
