# JetBrain 离线激活 — 免交互版本
# 用法 (管理员 PowerShell): .\offline_activate.ps1
# 或: irm http://localhost:10768/activate | iex

param(
    [string]$Server = "http://localhost:10768",
    [string]$LicenseName = "JetBrain",
    [string]$ExpiryDate = "2099-12-31",
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ====== 检查管理员权限 ======
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrator")) {
    if ($Elevated) {
        Write-Host "[错误] 提权未生效，无法继续。请关闭此窗口，右键『以管理员身份运行』PowerShell 后再执行。" -ForegroundColor Red
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    Write-Host "[INFO] 需要管理员权限，正在提权..." -ForegroundColor Yellow
    # 优先用本脚本的绝对路径重启；若为 irm | iex 内联执行（$PSCommandPath 为空），先下载脚本到临时目录
    if ($PSCommandPath) {
        $scriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PSCommandPath)
    } else {
        Write-Host "[INFO] 检测到管道执行，正在下载脚本到临时目录..." -ForegroundColor Gray
        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "offline_activate.ps1"
        Invoke-WebRequest -UseBasicParsing "$Server/export/offline_activate.ps1" -OutFile $scriptPath
    }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Server `"$Server`" -LicenseName `"$LicenseName`" -ExpiryDate `"$ExpiryDate`" -Elevated" -Verb RunAs
    exit 0
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  JetBrains 离线激活 (免交互)" -ForegroundColor Cyan
Write-Host "  服务器: $Server" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# ====== 路径配置 ======
$userPath = [Environment]::GetEnvironmentVariable("USERPROFILE")
$publicPath = [Environment]::GetEnvironmentVariable("PUBLIC")
$dirWork = "$publicPath\.jb_run"
$dirConfig = "$dirWork\config"
$dirPlugins = "$dirWork\plugins"
$fileNetfilterJar = "$dirWork\ja-netfilter.jar"
$dirLocalJB = "$userPath\AppData\Local\JetBrains"
$dirRoamingJB = "$userPath\AppData\Roaming\JetBrains"

# ====== 产品列表 ======
$products = @(
    @{name="idea";     code="II,PCWMP,PSI"}
    @{name="clion";    code="CL,PSI,PCWMP"}
    @{name="phpstorm"; code="PS,PCWMP,PSI"}
    @{name="goland";   code="GO,PSI,PCWMP"}
    @{name="pycharm";  code="PC,PSI,PCWMP"}
    @{name="webstorm"; code="WS,PCWMP,PSI"}
    @{name="rider";    code="RD,PDB,PSI,PCWMP"}
    @{name="datagrip"; code="DB,PSI,PDB"}
    @{name="rubymine"; code="RM,PCWMP,PSI"}
    @{name="appcode";  code="AC,PCWMP,PSI"}
    @{name="dataspell";code="DS,PSI,PDB,PCWMP"}
    @{name="rustrover";code="RR,PSI,PCWP"}
)

# ====== 创建 HttpClient ======
Add-Type -AssemblyName System.Net.Http
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.UseDefaultCredentials = $true
$client = New-Object System.Net.Http.HttpClient($handler)
$client.Timeout = [System.TimeSpan]::FromSeconds(60)

# ====== 下载文件 ======
function Download-File($url, $path) {
    Write-Host "  下载: $url" -ForegroundColor Gray
    $resp = $client.GetAsync($url).Result
    $resp.EnsureSuccessStatusCode() | Out-Null
    $bytes = $resp.Content.ReadAsByteArrayAsync().Result
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    [System.IO.File]::WriteAllBytes($path, $bytes)
}

# ====== 生成许可证 ======
function Get-License($productCode) {
    $body = @{
        assigneeName = ""
        expiryDate = $ExpiryDate
        licenseName = $LicenseName
        productCode = $productCode
    } | ConvertTo-Json
    $content = [System.Net.Http.StringContent]::new($body, [System.Text.Encoding]::UTF8, "application/json")
    $resp = $client.PostAsync("$Server/generateLicense/file", $content).Result
    $resp.EnsureSuccessStatusCode() | Out-Null
    return $resp.Content.ReadAsByteArrayAsync().Result
}

# ====== 主流程 ======
Write-Host "`n[1/4] 准备环境..." -ForegroundColor Yellow

# 清理旧目录
if (Test-Path $dirWork) {
    Remove-Item -Path $dirWork -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -Path $dirConfig -ItemType Directory -Force | Out-Null
New-Item -Path $dirPlugins -ItemType Directory -Force | Out-Null

Write-Host "`n[2/4] 下载 ja-netfilter..." -ForegroundColor Yellow

$files = @(
    @{url="$Server/ja-netfilter/ja-netfilter.jar"; path=$fileNetfilterJar}
    @{url="$Server/ja-netfilter/config/dns.conf"; path="$dirConfig\dns.conf"}
    @{url="$Server/ja-netfilter/config/env.conf"; path="$dirConfig\env.conf"}
    @{url="$Server/ja-netfilter/config/native.conf"; path="$dirConfig\native.conf"}
    @{url="$Server/ja-netfilter/config/power.conf"; path="$dirConfig\power.conf"}
    @{url="$Server/ja-netfilter/config/url.conf"; path="$dirConfig\url.conf"}
    @{url="$Server/ja-netfilter/plugins/dns.jar"; path="$dirPlugins\dns.jar"}
    @{url="$Server/ja-netfilter/plugins/env.jar"; path="$dirPlugins\env.jar"}
    @{url="$Server/ja-netfilter/plugins/native.jar"; path="$dirPlugins\native.jar"}
    @{url="$Server/ja-netfilter/plugins/power.jar"; path="$dirPlugins\power.jar"}
    @{url="$Server/ja-netfilter/plugins/url.jar"; path="$dirPlugins\url.jar"}
    @{url="$Server/ja-netfilter/plugins/hideme.jar"; path="$dirPlugins\hideme.jar"}
    @{url="$Server/ja-netfilter/plugins/privacy.jar"; path="$dirPlugins\privacy.jar"}
)

foreach ($f in $files) {
    Download-File $f.url $f.path
}

Write-Host "`n[3/4] 处理 JetBrains 产品..." -ForegroundColor Yellow

if (-not (Test-Path $dirLocalJB)) {
    Write-Host "  未找到 JetBrains 安装目录: $dirLocalJB" -ForegroundColor Red
    Write-Host "  请先安装 JetBrains IDE" -ForegroundColor Red
    $client.Dispose()
    exit 1
}

$processed = 0
foreach ($dir in (Get-ChildItem -Path $dirLocalJB -Directory)) {
    $dirName = $dir.Name
    $prod = $null
    foreach ($p in $products) {
        if ($dirName.ToLower().Contains($p.name)) {
            $prod = $p
            break
        }
    }
    if (-not $prod) { continue }

    Write-Host "  处理: $dirName" -ForegroundColor Green

    # 读取 .home 文件获取安装路径
    $homeFile = "$($dir.FullName)\.home"
    if (-not (Test-Path $homeFile)) {
        Write-Host "    跳过: 未找到 .home" -ForegroundColor Gray
        continue
    }
    $installPath = Get-Content $homeFile -Encoding UTF8
    $binDir = "$installPath\bin"
    if (-not (Test-Path $binDir)) {
        Write-Host "    跳过: bin 目录不存在" -ForegroundColor Gray
        continue
    }

    # 读取 idea.config.path 自定义配置目录 (与 activate.sh / activate.ps1 对齐)
    $customConfigPath = $null
    $fileProperties = "$binDir\idea.properties"
    if (Test-Path $fileProperties) {
        $propLine = Get-Content $fileProperties -Encoding UTF8 | Where-Object {
            $_ -match '^idea\.config\.path\s*=' -and $_ -notmatch '^\s*#'
        } | Select-Object -First 1
        if ($propLine) {
            $customConfigPath = (($propLine -split '=', 2)[1]).Trim().Trim('"')
            $customConfigPath = $customConfigPath.Replace('${user.home}', $userPath)
        }
    }
    $roamingDir = if ($customConfigPath) { $customConfigPath } else { "$dirRoamingJB\$dirName" }

    # 更新 .vmoptions 文件 (用户级优先级高于安装目录 bin，必须注入 javaagent)
    if (-not (Test-Path $roamingDir)) { New-Item -Path $roamingDir -ItemType Directory -Force | Out-Null }
    $vmFiles = @(Get-ChildItem -Path $roamingDir -Filter "*.vmoptions" -ErrorAction SilentlyContinue)
    if ($vmFiles.Count -eq 0) {
        $vmFiles = @(New-Item -Path "$roamingDir\$($prod.name)64.exe.vmoptions" -ItemType File -Force)
    }
    # jetbrains_client.vmoptions (与 bash 对齐: 不存在则创建，存在则清理后追加)
    $fileClientVm = "$roamingDir\jetbrains_client.vmoptions"
    if (-not (Test-Path $fileClientVm)) { New-Item -Path $fileClientVm -ItemType File -Force | Out-Null }
    $vmFiles += Get-Item $fileClientVm
    foreach ($vm in $vmFiles) {
        Write-Host "    更新: $($vm.Name)" -ForegroundColor Gray
        $lines = Get-Content $vm.FullName -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object {
            $_ -notmatch '-javaagent:.*\.jar' -and
            $_ -notmatch '--add-opens=java.base/jdk.internal'
        }
        $lines += "-javaagent:$($fileNetfilterJar.Replace('\', '/'))"
        Set-Content -Path $vm.FullName -Value $lines -Encoding UTF8 -Force
    }

    # 获取许可证
    Write-Host "    生成 $($prod.name).key..." -ForegroundColor Gray
    $keyBytes = Get-License $prod.code
    $keyFile = "$roamingDir\$($prod.name).key"
    if (-not (Test-Path $roamingDir)) { New-Item -Path $roamingDir -ItemType Directory -Force | Out-Null }
    [System.IO.File]::WriteAllBytes($keyFile, $keyBytes)

    # 处理 disabled_plugins
    $disabledFile = "$roamingDir\disabled_plugins.txt"
    if (Test-Path $disabledFile) {
        $lines = Get-Content $disabledFile -Encoding UTF8 | Where-Object { $_ -ne "com.intellij.modules.ultimate" }
        Set-Content -Path $disabledFile -Value $lines -Encoding UTF8 -Force
    }

    $processed++
}

$client.Dispose()

Write-Host "`n[4/4] 完成!" -ForegroundColor Green
Write-Host "  处理了 $processed 个产品" -ForegroundColor Green
Write-Host "  许可证名称: $LicenseName" -ForegroundColor Green
Write-Host "  有效期至: $ExpiryDate" -ForegroundColor Green
Write-Host "`n  现在可以启动 JetBrains IDE 了" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# 不打开浏览器，不自毁
Write-Host "`n按任意键退出..." -ForegroundColor Gray
$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
