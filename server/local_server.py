#!/usr/bin/env python3
"""
JetBrains 离线激活本地服务器
提供 JetBrains 许可证离线激活所需的本地 API 端点，用于离线研究和教学目的。

启动方式：
    python local_server.py              # 默认监听 0.0.0.0:10768
    python local_server.py --port 8080  # 自定义端口
    python local_server.py --host 127.0.0.1  # 仅本地访问

端点：
    GET  /                              → 浏览器返回操作面板；PowerShell/curl 返回激活脚本（快捷运行，无 BOM）
    GET  /export/<name>                 → 导出单文件自包含离线脚本（内嵌完整离线包：脚本+资源+密钥，下载后即可离线激活）
    GET  /ja-netfilter/<path>           → 返回 ja-netfilter 资源文件
    POST /generateLicense/file          → 生成并返回 .key 许可证文件
"""

import http.server
import json
import os
import sys
import socket
import subprocess
import time
import argparse
import base64
import hashlib
from datetime import datetime

# ===================== 配置 =====================
SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.dirname(SERVER_DIR)
WEB_DIR = os.path.join(BASE_DIR, "web")
SCRIPTS_DIR = os.path.join(BASE_DIR, "scripts")
SCRIPTS_WIN_DIR = os.path.join(SCRIPTS_DIR, "Windows")
SCRIPTS_UNIX_DIR = os.path.join(SCRIPTS_DIR, "Linux-macOS")
JA_NETFILTER_DIR = os.path.join(BASE_DIR, "ja-netfilter")
KEYS_DIR = os.path.join(BASE_DIR, "keys")
DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 10768

# ===================== 加载本地 RSA 密钥对 =====================

_SIGNING_KEY = None
_CERT_B64 = None
_CERT_DER = None

def _load_signing_key():
    """加载本地生成的 RSA 私钥和证书，用于真正签名每个许可证。"""
    global _SIGNING_KEY, _CERT_B64, _CERT_DER

    private_path = os.path.join(KEYS_DIR, "private.pem")
    cert_path = os.path.join(KEYS_DIR, "cert.der")

    if not os.path.exists(private_path):
        return False

    try:
        from cryptography.hazmat.primitives import serialization, hashes
        from cryptography.hazmat.primitives.asymmetric import rsa, padding
        from cryptography.hazmat.backends import default_backend
        from cryptography import x509

        with open(private_path, "rb") as f:
            _SIGNING_KEY = serialization.load_pem_private_key(
                f.read(), password=None, backend=default_backend()
            )

        # 加载或生成证书
        if os.path.exists(cert_path):
            with open(cert_path, "rb") as f:
                _CERT_DER = f.read()
        else:
            # 生成证书：issuer 必须为 JetProfile CA（IDE 的信任锚点），否则证书链校验失败
            from datetime import datetime, timedelta
            from cryptography.x509.oid import NameOID

            pubkey = _SIGNING_KEY.public_key()
            subject = x509.Name([
                x509.NameAttribute(NameOID.COMMON_NAME, "Jetbrains-Help"),
            ])
            issuer = x509.Name([
                x509.NameAttribute(NameOID.COMMON_NAME, "JetProfile CA"),
            ])
            cert = x509.CertificateBuilder().subject_name(subject).issuer_name(issuer)\
                .public_key(pubkey)\
                .serial_number(x509.random_serial_number())\
                .not_valid_before(datetime.utcnow() - timedelta(days=1))\
                .not_valid_after(datetime.utcnow() + timedelta(days=36500))\
                .sign(_SIGNING_KEY, hashes.SHA256(), default_backend())
            _CERT_DER = cert.public_bytes(serialization.Encoding.DER)
            with open(cert_path, "wb") as f:
                f.write(_CERT_DER)

        _CERT_B64 = base64.b64encode(_CERT_DER).decode()
        print(f"[INFO] Loaded local RSA key ({_SIGNING_KEY.key_size} bits), cert {len(_CERT_DER)} bytes")
        return True

    except ImportError:
        print("[WARN] cryptography not installed; falling back to sample signature")
        return False
    except Exception as e:
        print(f"[WARN] Failed to load signing key: {e}; falling back to sample signature")
        return False


def _sign_json(json_bytes):
    """用本地私钥对 JSON 做 RSA SHA1 签名（IDE 按 SHA1 校验 JSON 签名）"""
    if _SIGNING_KEY is None:
        return None
    try:
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import padding
        sig = _SIGNING_KEY.sign(json_bytes, padding.PKCS1v15(), hashes.SHA1())
        return base64.b64encode(sig).decode()
    except Exception:
        return None


# 启动时加载本地签名密钥
_load_signing_key()

# ===================== 许可证生成逻辑 =====================

def generate_license_key(assignee_name, expiry_date, license_name, product_code):
    """
    生成 JetBrains 许可证（对应 /generateLicense/file 端点）。
    文件格式与官方服务器完全一致。

    许可证文件结构（UTF-16 LE 编码）：
        第1行: ￿<certificate-key>
        第2行: <LicenseId>-<Base64(JSON)>-<Base64(签名)>-<Base64(证书)>

    参数：
        assignee_name: 被授权人姓名（可为空）
        expiry_date:   过期日期，格式 yyyy-MM-dd
        license_name:  许可证名称（显示在 IDE 中）
        product_code:  产品代码，逗号分隔，如 "II,PCWMP,PSI"
    """
    # 1. 生成 LicenseId（与真实格式一致：12位大写 hex）
    raw_hash = hashlib.md5(
        f"{license_name}{product_code}{expiry_date}".encode()
    ).hexdigest()[:12].upper()

    # 2. 解析产品代码
    product_codes = [c.strip() for c in product_code.split(",") if c.strip()]

    # 3. 构造产品数组（与真实 JSON 结构完全一致）
    products = []
    for code in product_codes:
        products.append({
            "code": code,
            "fallbackDate": expiry_date,
            "paidUpTo": expiry_date
        })

    # 4. 构造许可证 JSON
    license_data = {
        "licenseId": raw_hash,
        "licenseeName": license_name,
        "assigneeName": assignee_name,
        "products": products,
        "metadata": "0120230914PSAX000005"  # 真实 metadata 格式
    }

    # 5. 紧凑 JSON → Base64
    json_str = json.dumps(license_data, separators=(",", ":"))
    b64_json = base64.b64encode(json_str.encode()).decode()

    # 6. 用本地私钥真正签名；密钥未加载时拒绝生成（回退样本永远无法通过校验）
    sig_b64 = _sign_json(json_str.encode())
    cert_b64 = _CERT_B64
    if not sig_b64 or not cert_b64:
        raise RuntimeError("本地 RSA 密钥未加载 (keys/private.pem + cert.der)")

    # 7. 按真实格式拼接 (chr(0xFFFF) 前缀 + UTF-16 LE 编码)
    line1 = chr(0xFFFF) + "<certificate-key>"
    line2 = f"{raw_hash}-{b64_json}-{sig_b64}-{cert_b64}"
    content = line1 + "\n" + line2

    return content.encode("utf-16-le")


def generate_license_key_text(assignee_name, expiry_date, license_name, product_code):
    """
    生成纯文本格式激活码 — 与网站 POST /generateLicense 返回的完全一致。
    格式: <licenseId>-<Base64JSON>-<Base64Signature>-<Base64Certificate>
    纯 ASCII 单行，不含 UTF-16 LE，不含文件头。
    """
    raw_hash = hashlib.md5(
        f"{license_name}{product_code}{expiry_date}{os.urandom(8)}".encode()
    ).hexdigest()[:10].upper()

    product_codes = [c.strip() for c in product_code.split(",") if c.strip()]
    products = [{"code": c, "fallbackDate": expiry_date, "paidUpTo": expiry_date}
                for c in product_codes]

    license_data = {
        "licenseId": raw_hash,
        "licenseeName": license_name,
        "assigneeName": assignee_name,
        "products": products,
        "metadata": "0120230914PSAX000005"
    }

    json_str = json.dumps(license_data, separators=(",", ":"))
    b64_json = base64.b64encode(json_str.encode()).decode()

    sig_b64 = _sign_json(json_str.encode())
    cert_b64 = _CERT_B64
    if not sig_b64 or not cert_b64:
        raise RuntimeError("本地 RSA 密钥未加载 (keys/private.pem + cert.der)")

    # 单行格式，纯 ASCII
    return f"{raw_hash}-{b64_json}-{sig_b64}-{cert_b64}"


# ===================== 单文件自包含离线脚本模板 =====================
# 模板代码中严禁出现完整标记字符串 __JB_OFFLINE_PACK__ / __JB_OFFLINE_END__
# （bootstrap 需按原字节在自身文件里定位载荷，标记被拆开写入以避免自匹配）。

_SELFEXTRACT_PS = r'''# Self-extracting offline JetBrains activate script
# 自解压离线激活脚本（单文件自包含：脚本+资源+密钥全部内嵌，无需服务器、无需仓库配套文件）
$ErrorActionPreference = 'Stop'

if (-not $PSCommandPath) { $self = $MyInvocation.MyCommand.Path } else { $self = $PSCommandPath }
if (-not $self) {
    Write-Host '无法定位自身文件路径。' -ForegroundColor Red
    Read-Host
    exit 1
}

# ---------- 0. 请求管理员权限 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')
if (-not $isAdmin) {
    Write-Host '需要管理员权限，正在请求 UAC 提权...'
    try {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$self`"" -Verb RunAs
    } catch {
        Write-Host 'UAC 提权被取消，需要管理员权限才能继续。' -ForegroundColor Red
        Read-Host
    }
    exit 0
}

# ---------- 1. 从自身提取内嵌离线包 ----------
$mStart = '__JB_OFFLINE_' + 'PACK__'
$mEnd = '__JB_OFFLINE_' + 'END__'
try {
    $raw = [IO.File]::ReadAllBytes($self)
} catch {
    Write-Host '无法读取自身文件。' -ForegroundColor Red
    Read-Host
    exit 1
}
$text = [Text.Encoding]::ASCII.GetString($raw)
$i = $text.IndexOf($mStart)
$j = $text.IndexOf($mEnd)
if ($i -lt 0 -or $j -lt 0) {
    Write-Host '未找到内嵌离线包，文件可能已损坏。' -ForegroundColor Red
    Read-Host
    exit 1
}
$mid = $text.Substring($i + $mStart.Length, $j - $i - $mStart.Length)
$zipBytes = [Convert]::FromBase64String(($mid -replace '\s', ''))

$tmpZip = Join-Path $env:TEMP ('jb-offline-' + [guid]::NewGuid().ToString('N') + '.zip')
$extract = Join-Path $env:TEMP ('jb-offline-' + [guid]::NewGuid().ToString('N'))
[IO.File]::WriteAllBytes($tmpZip, $zipBytes)
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($tmpZip, $extract)

# ---------- 2. 以离线模式运行内嵌激活脚本 ----------
$root = Join-Path $extract 'JetBrain-offline'
$env:OFFLINE_RESOURCES_DIR = Join-Path $root 'ja-netfilter'
$env:OFFLINE_LICENSE_SCRIPT = Join-Path $root 'server\generate_license.py'
$inner = Join-Path $root 'scripts\Windows\activate.ps1'

$rc = 0
try {
    $p = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$inner`"" -Wait -PassThru
    $rc = $p.ExitCode
} finally {
    Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
}
exit $rc'''

_SELFEXTRACT_CMD = r'''@echo off
chcp 936 >nul
setlocal EnableExtensions

rem ============================================================
rem  JetBrains 一键激活（Windows CMD）—— 单文件自包含离线版
rem  本文件已内嵌完整离线包（脚本/资源/密钥），运行即可离线激活，
rem  不依赖服务器、不依赖仓库配套文件，可直接拷贝到其它机器使用。
rem ============================================================

rem ---------- 0. 请求管理员权限 ----------
net session >nul 2>&1
if errorlevel 1 (
    echo 需要管理员权限，正在请求 UAC 提权...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

rem ---------- 1. 从自身提取内嵌离线包 ----------
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d=Join-Path $env:TEMP 'jb-offline-export';if(Test-Path -LiteralPath $d){Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue};$self='%~f0';$t=[IO.File]::ReadAllBytes($self);$s=[Text.Encoding]::ASCII.GetString($t);$b='__JB_OFFLINE_'+'PACK__';$e='__JB_OFFLINE_'+'END__';$i=$s.IndexOf($b);$j=$s.IndexOf($e);if($i -lt 0 -or $j -lt 0){Write-Output 'embedded pack not found';exit 1};$m=$s.Substring($i+$b.Length,$j-$i-$b.Length);$z=[Convert]::FromBase64String(($m -replace '\s',''));$zp=Join-Path $env:TEMP 'jb-offline-export.zip';[IO.File]::WriteAllBytes($zp,$z);Add-Type -AssemblyName System.IO.Compression.FileSystem;[IO.Compression.ZipFile]::ExtractToDirectory($zp,$d)"
if errorlevel 1 (
    echo [错误] 解压内嵌离线包失败。
    pause
    exit /b 1
)

rem ---------- 2. 运行内嵌一键激活脚本 ----------
set "INNER=%TEMP%\jb-offline-export\JetBrain-offline\scripts\Windows\one-click-activate.cmd"
if not exist "%INNER%" (
    echo [错误] 离线包内容不完整。
    pause
    exit /b 1
)
call "%INNER%"
set "RC=%errorlevel%"

rem ---------- 3. 清理临时文件 ----------
cd /d "%TEMP%"
rmdir /s /q "%TEMP%\jb-offline-export" >nul 2>&1
del /f /q "%TEMP%\jb-offline-export.zip" >nul 2>&1

exit /b %RC%'''

_SELFEXTRACT_SH = r'''#!/bin/bash
# Self-extracting offline JetBrains activate script
# 自解压离线激活脚本（单文件自包含：脚本+资源+密钥全部内嵌，无需服务器、无需仓库配套文件）

set -e

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

if ! command -v python3 >/dev/null 2>&1; then
    echo "[错误] 未找到 python3。离线激活需要 Python 3.8+（用于生成许可证）。" >&2
    exit 1
fi

python3 - "$SELF" "$TMPDIR" <<'PYEOF'
import base64, io, sys, zipfile
self_path, dest = sys.argv[1], sys.argv[2]
begin = b'__JB_OFFLINE_' + b'PACK__'
end = b'__JB_OFFLINE_' + b'END__'
data = open(self_path, 'rb').read()
i = data.find(begin)
j = data.find(end, i)
if i == -1 or j == -1:
    sys.stderr.write('[错误] 未找到内嵌离线包，文件可能已损坏。\n')
    sys.exit(1)
b64 = data[i + len(begin):j].replace(b'\r', b'').replace(b'\n', b'')
with zipfile.ZipFile(io.BytesIO(base64.b64decode(b64))) as zf:
    zf.extractall(dest)
PYEOF

ROOT="$TMPDIR/JetBrain-offline"
export OFFLINE_RESOURCES_DIR="$ROOT/ja-netfilter"
export OFFLINE_LICENSE_SCRIPT="$ROOT/server/generate_license.py"

if [ ! -f "$ROOT/scripts/Linux-macOS/activate.sh" ]; then
    echo "[错误] 离线包内容不完整。" >&2
    exit 1
fi

bash "$ROOT/scripts/Linux-macOS/activate.sh"
RC=$?
exit $RC'''


# ===================== HTTP 请求处理器 =====================

class JetBrainsHandler(http.server.BaseHTTPRequestHandler):
    """JetBrains 离线激活 HTTP 请求处理器"""

    def log_message(self, format, *args):
        """自定义日志格式"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] {self.client_address[0]} - {format % args}")

    def _send_file(self, filepath, content_type="application/octet-stream"):
        """发送文件内容"""
        if os.path.exists(filepath) and os.path.isfile(filepath):
            with open(filepath, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", len(content))
            self.end_headers()
            self.wfile.write(content)
            print(f"  → 200 OK ({len(content)} bytes) - {filepath}")
        else:
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"File not found")
            print(f"  → 404 Not Found - {filepath}")

    def _send_error(self, code, message):
        """发送 JSON 错误响应"""
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"error": message}).encode())
        print(f"  → {code} - {message}")

    def _local_base(self):
        """从 Host 头解析出客户端可访问的服务器基址（兼容 IPv4/IPv6/自定义端口）"""
        host = self.headers.get("Host", "").strip() or f"localhost:{DEFAULT_PORT}"
        # IPv6 中括号形式，如 [::1]:8080
        if host.startswith("["):
            end = host.find("]")
            if end != -1:
                ip = host[1:end]
                rest = host[end + 1:]
                if rest.startswith(":") and rest[1:].isdigit():
                    return f"http://[{ip}]:{rest[1:]}"
                return f"http://[{ip}]:{DEFAULT_PORT}"
        if ":" in host:
            host_part, _, port = host.rpartition(":")
            if host_part and port.isdigit():
                return f"http://{host_part}:{port}"
            return f"http://{host}:{DEFAULT_PORT}"
        return f"http://{host}:{DEFAULT_PORT}"

    @staticmethod
    def _rewrite_script(content, local_base):
        """改写激活脚本：把脚本内默认服务器地址替换为客户端可访问的地址。

        提权重下载行（`irm http://localhost:10768|iex`）改写为走 /export/
        端点保存脚本（保留 BOM），保证 PS 5.1 能解析落盘的文件。
        """
        content = content.replace(
            b'$script:url_base = "http://localhost:10768"',
            f'$script:url_base = "{local_base}"'.encode())
        content = content.replace(
            b'URL_BASE="http://localhost:10768"',
            f'URL_BASE="{local_base}"'.encode())
        content = content.replace(
            b'irm http://localhost:10768|iex',
            f'irm {local_base}/export/activate.ps1 -OutFile activate.ps1; .\\activate.ps1'.encode())
        return content

    def _read_rewritten(self, filepath):
        """读取脚本并做 URL 改写；文件缺失返回 None。"""
        if not (os.path.exists(filepath) and os.path.isfile(filepath)):
            return None
        with open(filepath, "rb") as f:
            content = f.read()
        local_base = self._local_base()
        return self._rewrite_script(content, local_base)

    @staticmethod
    def _strip_bom(content):
        """去掉 UTF-8 BOM —— 快捷运行走 irm ... | iex / curl ... | bash 时必须无 BOM
        （PS 5.1 的 iex 无法容忍以 U+FEFF 开头，而 irm 又不会剥离它）。"""
        if content.startswith(b"\xef\xbb\xbf"):
            return content[3:]
        return content

    def _send_script(self, filepath):
        """发送激活脚本（快捷运行，无 BOM）—— bash/PowerShell 均可直接管道执行"""
        content = self._read_rewritten(filepath)
        if content is None:
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Script not found")
            print(f"  → 404 Not Found - {filepath}")
            return

        content = self._strip_bom(content)
        local_base = self._local_base()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", len(content))
        self.end_headers()
        self.wfile.write(content)
        print(f"  → 200 OK ({len(content)} bytes) - script (URLs rewritten to {local_base})")

    _EXPORT_NAMES = ("activate.ps1", "one-click-activate.cmd", "activate.sh")

    def _build_offline_pack(self):
        """构建离线包（内存 zip）：脚本 + ja-netfilter 资源树 + 许可证生成器 + 预生成密钥。

        缺少 keys/ 密钥时返回 None。该 zip 被内嵌进自包含离线导出脚本
        （activate.ps1 / one-click-activate.cmd / activate.sh），由脚本解压后离线激活，
        不依赖服务器在线、不依赖仓库配套文件。"""
        import zipfile
        from io import BytesIO

        if not (os.path.isfile(os.path.join(KEYS_DIR, "private.pem"))
                and os.path.isfile(os.path.join(KEYS_DIR, "cert.der"))):
            return None

        root = "JetBrain-offline"
        files = [
            ("scripts/generate_keys.py", f"{root}/scripts/generate_keys.py"),
            ("scripts/Windows/activate.ps1", f"{root}/scripts/Windows/activate.ps1"),
            ("scripts/Windows/one-click-activate.ps1", f"{root}/scripts/Windows/one-click-activate.ps1"),
            ("scripts/Windows/one-click-activate.cmd", f"{root}/scripts/Windows/one-click-activate.cmd"),
            ("scripts/Linux-macOS/activate.sh", f"{root}/scripts/Linux-macOS/activate.sh"),
            ("scripts/Linux-macOS/one-click-activate.sh", f"{root}/scripts/Linux-macOS/one-click-activate.sh"),
            ("server/local_server.py", f"{root}/server/local_server.py"),
            ("server/generate_license.py", f"{root}/server/generate_license.py"),
        ]
        key_files = ["private.pem", "public.pem", "cert.der"]

        buf = BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            for disk, arc in files:
                src = os.path.join(BASE_DIR, disk)
                if os.path.isfile(src):
                    zf.write(src, arc)
            if os.path.isdir(JA_NETFILTER_DIR):
                for dirpath, _dirnames, filenames in os.walk(JA_NETFILTER_DIR):
                    for fn in filenames:
                        full = os.path.join(dirpath, fn)
                        rel = os.path.relpath(full, JA_NETFILTER_DIR).replace(os.sep, "/")
                        zf.write(full, f"{root}/ja-netfilter/{rel}")
            for kf in key_files:
                src = os.path.join(KEYS_DIR, kf)
                if os.path.isfile(src):
                    zf.write(src, f"{root}/keys/{kf}")

        return buf.getvalue()

    def _render_self_extracting(self, name, pack_bytes):
        """把离线包 base64 内嵌进脚本，生成单文件自包含的自解压脚本。

        .ps1 为 UTF-8 BOM + 块注释包裹载荷（PowerShell 整文件解析）；.cmd 为 GBK + CRLF；
        .sh 为 UTF-8。载荷放在脚本末尾，cmd/bash 惰性读取不会解析它们。"""
        b64 = base64.b64encode(pack_bytes)
        lines = b"\n".join(b64[i:i + 76] for i in range(0, len(b64), 76))
        payload = b"__JB_OFFLINE_PACK__\n" + lines + b"\n__JB_OFFLINE_END__\n"

        if name == "activate.ps1":
            return ("﻿" + _SELFEXTRACT_PS + "\n<#\n").encode("utf-8") + payload + b"#>\n"
        if name == "one-click-activate.cmd":
            return _SELFEXTRACT_CMD.replace("\n", "\r\n").encode("gbk") + b"\r\n" + payload
        return _SELFEXTRACT_SH.encode("utf-8") + b"\n" + payload

    def _send_export(self, name):
        """导出单文件自包含离线激活脚本（内嵌完整离线包，下载后即可离线使用，不依赖其它文件）。"""
        if name not in self._EXPORT_NAMES:
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Script not found")
            print(f"  → 404 Not Found - export/{name}")
            return

        pack = self._build_offline_pack()
        if pack is None:
            self._send_error(400, "keys/ 密钥不存在，请先运行 python scripts/generate_keys.py "
                                  "生成密钥后再导出离线脚本。")
            return

        content = self._render_self_extracting(name, pack)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Disposition", f'attachment; filename="{name}"')
        self.send_header("Content-Length", len(content))
        self.end_headers()
        self.wfile.write(content)
        print(f"  → 200 OK ({len(content)} bytes) - export/{name} (self-extracting offline)")

    def _generate_license(self):
        """处理许可证生成请求"""
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else b"{}"

        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Invalid JSON"}).encode())
            return

        assignee_name = data.get("assigneeName", "")
        expiry_date = data.get("expiryDate", "2099-12-31")
        license_name = data.get("licenseName", "JetBrain")
        product_code = data.get("productCode", "")

        print(f"  → Generating license: name={license_name}, "
              f"product={product_code}, expiry={expiry_date}")

        try:
            key_content = generate_license_key(
                assignee_name, expiry_date, license_name, product_code
            )
        except RuntimeError as e:
            self._send_error(500, str(e))
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", len(key_content))
        self.send_header("Content-Disposition",
                         f'attachment; filename="{license_name}.key"')
        self.end_headers()
        self.wfile.write(key_content)
        print(f"  → 200 OK - License generated ({len(key_content)} bytes)")

    def _is_browser(self):
        """检测请求是否来自浏览器"""
        ua = self.headers.get("User-Agent", "").lower()
        accept = self.headers.get("Accept", "").lower()
        # PowerShell 7 的 Invoke-RestMethod 使用 Chrome 风格 UA
        # (含 "Microsoft Windows NT 10.0.0.0")，必须识别为非浏览器
        is_ps = ("powershell" in ua or "windowspowershell" in ua
                 or "microsoft windows nt" in ua)
        is_curl = "curl" in ua
        is_wget = "wget" in ua
        # 真实浏览器导航请求: 浏览器 UA + Accept 含 text/html，
        # 仅凭 UA 无法区分 PS 7 与真实浏览器
        has_browser_ua = ("mozilla" in ua or "chrome" in ua or "safari" in ua
                          or "edge" in ua or "firefox" in ua)
        is_browser = has_browser_ua and "text/html" in accept
        return is_browser and not is_ps and not is_curl and not is_wget

    def do_GET(self):
        """处理 GET 请求"""
        path = self.path.split("?")[0]  # 去除查询参数

        print(f"GET {self.path}")

        if path == "/":
            # 浏览器 → 返回操作面板; curl/PS → 返回激活脚本
            if self._is_browser():
                self._send_file(os.path.join(WEB_DIR, "dashboard.html"), "text/html; charset=utf-8")
                return
            # 根据 User-Agent 判断返回 bash 还是 PowerShell
            ua = self.headers.get("User-Agent", "").lower()
            if "powershell" in ua or "windows" in ua:
                script = os.path.join(SCRIPTS_WIN_DIR, "activate.ps1")
            else:
                script = os.path.join(SCRIPTS_UNIX_DIR, "activate.sh")
            self._send_script(script)

        elif path.startswith("/export/"):
            name = path[len("/export/"):]
            self._send_export(name)

        elif path.startswith("/ja-netfilter/"):
            # 提供 ja-netfilter 资源文件
            subpath = path[len("/ja-netfilter/"):]
            # 安全检查：防止路径遍历
            if ".." in subpath:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Forbidden")
                return

            filepath = os.path.join(JA_NETFILTER_DIR, subpath)
            if subpath.endswith(".jar"):
                self._send_file(filepath, "application/java-archive")
            elif subpath.endswith(".conf"):
                self._send_file(filepath, "text/plain; charset=utf-8")
            else:
                self._send_file(filepath)

        elif path == "/css/index.css" or path == "/js/" or path == "/images/":
            # 静态资源 — 返回 204（离线模式下不需要这些）
            self.send_response(204)
            self.end_headers()

        else:
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Not found. Available: / /export/<name> /ja-netfilter/*")

    def _generate_license_text(self, body_data):
        """
        生成纯文本格式激活码（与网站 /generateLicense 端点一致）。
        格式: <licenseId>-<Base64(JSON)>-<Base64(签名)>-<Base64(证书)>
        纯 ASCII 单行字符串，不含 UTF-16 编码，不含文件头前缀。
        """
        return generate_license_key_text(
            body_data.get("assigneeName", ""),
            body_data.get("expiryDate", "2099-12-31"),
            body_data.get("licenseName", "JetBrain"),
            body_data.get("productCode", "")
        )

    def do_POST(self):
        """处理 POST 请求"""
        print(f"POST {self.path}")

        if self.path == "/generateLicense/file":
            self._generate_license()

        elif self.path == "/generateLicense":
            # 纯文本激活码（网页显示用）
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Invalid JSON"}).encode())
                return
            try:
                text_code = self._generate_license_text(data)
            except RuntimeError as e:
                self._send_error(500, str(e))
                return
            text_bytes = text_code.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", len(text_bytes))
            self.end_headers()
            self.wfile.write(text_bytes)
            print(f"  → 200 OK - Text license generated ({len(text_code)} chars)")

        else:
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Not found")


def _check_port_in_use(host, port):
    """探测指定端口是否已被占用。占用返回 True，空闲返回 False。"""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        if os.name == "nt":
            s.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        s.bind((host, port))
        return False
    except OSError:
        return True
    finally:
        s.close()


def _find_pids_on_port(port):
    """尽力找出监听指定端口的进程 PID 列表（跨平台）。"""
    pids = set()
    try:
        if os.name == "nt":
            out = subprocess.run(
                ["netstat", "-ano", "-p", "tcp"],
                capture_output=True, text=True).stdout
            for line in out.splitlines():
                parts = line.split()
                if len(parts) >= 5 and parts[3] == "LISTENING":
                    local, pid = parts[1], parts[-1]
                    if local.endswith(f":{port}") and pid.isdigit():
                        pids.add(int(pid))
        else:
            out = subprocess.run(
                ["lsof", "-t", f"-iTCP:{port}", "-sTCP:LISTEN"],
                capture_output=True, text=True).stdout
            for pid in out.split():
                if pid.isdigit():
                    pids.add(int(pid))
    except Exception:
        pass
    return sorted(pids)


def _get_process_cmdline(pid):
    """尽力获取指定进程的命令行（跨平台）。获取失败返回空字符串。"""
    try:
        if os.name == "nt":
            out = subprocess.run(
                ["powershell", "-NoProfile", "-NonInteractive", "-Command",
                 f"Get-CimInstance Win32_Process -Filter \"ProcessId={pid}\" "
                 "| Select-Object -ExpandProperty CommandLine"],
                capture_output=True, text=True, timeout=15).stdout.strip()
            return out
        if os.path.isfile(f"/proc/{pid}/cmdline"):
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                return f.read().replace(b"\x00", b" ").decode("utf-8", "replace").strip()
        out = subprocess.run(["ps", "-p", str(pid), "-o", "command="],
                             capture_output=True, text=True).stdout
        return out.strip()
    except Exception:
        return ""


def _is_our_server_cmdline(cmdline):
    """判断命令行是否属于本服务（特征：运行 local_server.py）。"""
    return "local_server.py" in cmdline.lower()


def _kill_pids(pids):
    """强制结束指定进程（跨平台）。"""
    for pid in pids:
        try:
            if os.name == "nt":
                subprocess.run(["taskkill", "/F", "/PID", str(pid)],
                               capture_output=True, text=True)
            else:
                os.kill(pid, 9)
        except Exception:
            pass


def _pick_free_port(host):
    """让系统分配一个当前可用的随机端口。失败返回 0。"""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind((host, 0))
        return s.getsockname()[1]
    except OSError:
        return 0
    finally:
        s.close()


class _JetBrainsServer(http.server.ThreadingHTTPServer):
    """
    独占端口监听：
    - Windows 上 HTTPServer 默认 allow_reuse_address=1，SO_REUSEADDR 允许两个 socket
      绑同一端口，残留旧实例与新实例"双绑"，请求被旧实例抢走而 404。
      这里改用 SO_EXCLUSIVEADDRUSE 独占端口，第二个实例启动时会立即失败。
    - Linux/macOS 保留 SO_REUSEADDR，便于 Ctrl+C 后立刻重启（TIME_WAIT 不阻塞）。
    """
    allow_reuse_address = (os.name != "nt")

    def server_bind(self):
        if os.name == "nt":
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


def main():
    parser = argparse.ArgumentParser(
        description="JetBrains 离线激活本地服务器",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
    python local_server.py                    # 默认 0.0.0.0:10768
    python local_server.py --port 8080        # 自定义端口
    python local_server.py --host 127.0.0.1   # 仅本地访问

快捷运行 (Linux/Mac):
    curl -Ls http://localhost:10768 | bash

快捷运行 (Windows PowerShell, 右键管理员运行):
    irm http://localhost:10768 | iex

导出为本地脚本 (Linux/Mac):
    curl -Ls http://localhost:10768/export/activate.sh -o activate.sh && bash activate.sh

导出为本地脚本 (Windows PowerShell):
    irm http://localhost:10768/export/activate.ps1 -OutFile activate.ps1; .\\activate.ps1
        """
    )
    parser.add_argument("--host", default=DEFAULT_HOST,
                        help=f"监听地址 (默认: {DEFAULT_HOST})")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help=f"监听端口 (默认: {DEFAULT_PORT})")

    args = parser.parse_args()

    # 验证 ja-netfilter 资源目录
    if not os.path.isdir(JA_NETFILTER_DIR):
        print(f"[错误] 资源目录不存在: {JA_NETFILTER_DIR}")
        print("请确保 ja-netfilter/ 目录包含部署所需的全部文件。")
        sys.exit(1)

    jar_file = os.path.join(JA_NETFILTER_DIR, "ja-netfilter.jar")
    if not os.path.isfile(jar_file):
        print(f"[警告] 未找到 ja-netfilter.jar: {jar_file}")
        print("许可证生成功能可正常使用，但 ja-netfilter 激活需要此文件。")

    # 启动前检测端口占用
    # - 占用者是本服务的残留实例（命令行含 local_server.py）→ 自动结束残留进程，仍用原端口启动
    # - 占用者是其它程序 → 不结束它，改用随机可用端口启动并告知
    if _check_port_in_use(args.host, args.port):
        pids = _find_pids_on_port(args.port)
        our_pids = [p for p in pids if _is_our_server_cmdline(_get_process_cmdline(p))]
        if our_pids:
            pid_list = ", ".join(str(p) for p in our_pids)
            print(f"[INFO] 检测到本服务残留实例 (PID: {pid_list})，自动结束并重启...")
            _kill_pids(our_pids)
            for _ in range(25):  # 最多等 5 秒让端口释放
                if not _check_port_in_use(args.host, args.port):
                    break
                time.sleep(0.2)
        if _check_port_in_use(args.host, args.port):
            new_port = _pick_free_port(args.host)
            if not new_port:
                print(f"[错误] 端口 {args.port} 仍被占用且无法获取随机端口，请先手动释放。")
                if pids:
                    print(f"       占用进程 PID: {', '.join(str(p) for p in pids)}")
                sys.exit(1)
            print(f"[提示] 端口 {args.port} 被其它程序占用，已改用随机可用端口: {new_port}")
            args.port = new_port
        elif our_pids:
            print(f"[INFO] 残留实例已结束，使用原端口 {args.port} 启动。")

    # 启动服务器（Windows 独占端口，杜绝旧实例双绑）
    server = _JetBrainsServer((args.host, args.port), JetBrainsHandler)
    print("=" * 60)
    print("  JetBrains 离线激活本地服务器")
    print("  仅供教学和研究使用")
    print("=" * 60)
    print(f"  监听地址: http://{args.host}:{args.port}")
    print(f"  资源目录: {JA_NETFILTER_DIR}")
    print()
    print("  可用端点:")
    print(f"    GET  http://{args.host}:{args.port}/")
    print(f"    GET  http://{args.host}:{args.port}/export/<name>")
    print(f"    POST http://{args.host}:{args.port}/generateLicense/file")
    print(f"    GET  http://{args.host}:{args.port}/ja-netfilter/<path>")
    print()
    print("  使用方法:")
    print(f"    # 快捷运行 Linux/Mac:")
    print(f"    curl -Ls http://{args.host}:{args.port} | bash")
    print(f"    # 快捷运行 Windows PowerShell (右键管理员运行):")
    print(f"    irm http://{args.host}:{args.port} | iex")
    print(f"    # 导出为单文件离线脚本（内嵌资源与密钥，下载后即可离线激活，无需服务器）:")
    print(f"    curl -Ls http://{args.host}:{args.port}/export/activate.sh -o activate.sh && bash activate.sh")
    print(f"    irm http://{args.host}:{args.port}/export/activate.ps1 -OutFile activate.ps1; .\\activate.ps1")
    print(f"    curl -Ls http://{args.host}:{args.port}/export/one-click-activate.cmd -o one-click-activate.cmd && one-click-activate.cmd")
    print()
    print("  按 Ctrl+C 停止服务器")
    print("=" * 60)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n服务器已停止。")
        server.server_close()


if __name__ == "__main__":
    main()
