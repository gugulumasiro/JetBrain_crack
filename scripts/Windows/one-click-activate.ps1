#encoding: utf-8
<#
  JetBrains 一键激活（Windows）— 离线版，全程不启动服务器

  一条命令完成全部激活流程：
    1. 生成/补齐签名密钥与证书（scripts/generate_keys.py，幂等，可重复运行）
    2. 激活本机 JetBrains IDE（离线执行 activate.ps1：
       ja-netfilter 资源从仓库本地复制，许可证由本地密钥离线生成）

  需要管理员权限，脚本会自动弹出 UAC 请求。
#>
$ErrorActionPreference = 'Stop'

# ---------- 0. 请求管理员权限 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '需要管理员权限，正在请求提升（UAC）...' -ForegroundColor Yellow
    $shell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    Start-Process $shell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit 0
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $repoRoot

# ---------- 工具函数 ----------
function Find-Python {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $exe = (py -3 -c 'import sys; print(sys.executable)' 2>$null).Trim()
        if ($exe -and (Test-Path -LiteralPath $exe)) { return $exe }
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $exe = (Get-Command python).Source
        if ($exe -and (Test-Path -LiteralPath $exe)) { return $exe }
    }
    return $null
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  JetBrains 一键激活（Windows）' -ForegroundColor Cyan
Write-Host '  离线模式 · 不启动服务器' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

# ---------- 1. 检查 Python ----------
$py = Find-Python
if (-not $py) {
    Write-Host '[错误] 未找到 Python（需要 3.8+）。' -ForegroundColor Red
    Write-Host '       请安装 Python 并勾选 “Add python.exe to PATH” 后重试。' -ForegroundColor Red
    Read-Host '按回车退出'
    exit 1
}
Write-Host "[1/3] 检测到 Python: $py" -ForegroundColor Green

# ---------- 2. 安装 cryptography 依赖 ----------
& $py -c 'import cryptography' 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host '[2/3] 安装 cryptography 依赖...' -ForegroundColor Yellow
    & $py -m pip install 'cryptography>=3.0'
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[错误] cryptography 安装失败，请手动执行：' -ForegroundColor Red
        Write-Host "       `"$py`" -m pip install cryptography" -ForegroundColor Red
        Read-Host '按回车退出'
        exit 1
    }
} else {
    Write-Host '[2/3] cryptography 已就绪' -ForegroundColor Green
}

# ---------- 3. 生成/补齐密钥 ----------
Write-Host '[3/3] 生成/补齐签名密钥与证书（幂等，可重复运行）...' -ForegroundColor Yellow
& $py scripts\generate_keys.py
if ($LASTEXITCODE -ne 0) {
    Write-Host '[错误] 密钥生成失败，请检查上方输出。' -ForegroundColor Red
    Read-Host '按回车退出'
    exit 1
}

# ---------- 4. 离线激活（不启动服务器） ----------
Write-Host ''
Write-Host '开始激活。请按提示选择产品并填写许可证信息。' -ForegroundColor Yellow
$env:OFFLINE_RESOURCES_DIR = Join-Path $repoRoot 'ja-netfilter'
$env:OFFLINE_LICENSE_CMD = $py
$env:OFFLINE_LICENSE_SCRIPT = Join-Path $repoRoot 'server\generate_license.py'
& (Join-Path $PSScriptRoot 'activate.ps1')
Write-Host ''
Write-Host '激活流程已结束。' -ForegroundColor Green
Remove-Item Env:OFFLINE_RESOURCES_DIR, Env:OFFLINE_LICENSE_CMD, Env:OFFLINE_LICENSE_SCRIPT -ErrorAction SilentlyContinue

Read-Host '按回车退出'
