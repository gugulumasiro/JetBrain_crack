#!/usr/bin/env python3
"""
ckey.run 离线复现本地服务器
模拟 https://ckey.run 的所有关键 API 端点，用于离线研究和教学目的。

启动方式：
    python local_server.py              # 默认监听 0.0.0.0:10768
    python local_server.py --port 8080  # 自定义端口
    python local_server.py --host 127.0.0.1  # 仅本地访问

端点：
    GET  /                              → 浏览器返回操作面板；PowerShell/curl 返回激活脚本（快捷运行，无 BOM）
    GET  /activate                      → 返回免交互激活脚本（PowerShell 客户端 → .ps1，其它 → .sh）
    GET  /debug                         → 返回 Debug 模式脚本
    GET  /uninstall                     → 返回卸载脚本
    GET  /export/<name>                 → 导出单个脚本（.ps1 保留 UTF-8 BOM，便于 PS 5.1 解析保存的文件）
    GET  /scripts.zip                   → 一次性导出各平台全部脚本（zip）
    GET  /ja-netfilter/<path>           → 返回 ja-netfilter 资源文件
    POST /generateLicense/file          → 生成并返回 .key 许可证文件
"""

import http.server
import io
import json
import os
import sys
import socket
import subprocess
import time
import argparse
import base64
import hashlib
import zipfile
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
    模拟 ckey.run 的 /generateLicense/file 端点。
    生成与真实服务器完全一致的许可证文件格式。

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


# ===================== HTTP 请求处理器 =====================

class CKeyRunHandler(http.server.BaseHTTPRequestHandler):
    """模拟 ckey.run 服务器的 HTTP 请求处理器"""

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
        """改写激活脚本：URL 基址、移除浏览器自动跳转、提权行、品牌名。

        注意：提权行必须先于品牌替换执行，否则 ckey.run 已被换成
        JetBrain，`irm ckey.run|iex` 就匹配不上了。
        """
        content = content.replace(
            b'$script:url_base = "https://ckey.run"',
            f'$script:url_base = "{local_base}"'.encode())
        content = content.replace(
            b'URL_BASE="http://localhost:10768"',
            f'URL_BASE="{local_base}"'.encode())
        content = content.replace(
            b'    $OPEN_CMD "$URL_BASE" &>/dev/null',
            b'    # [OFFLINE] browser redirect removed')
        content = content.replace(
            b'    Start-Process "https://ckey.run"',
            b'    # [OFFLINE] browser redirect removed')
        # 提权重下载走 /export/ 端点（保留 BOM），保证 PS 5.1 能解析保存的文件
        content = content.replace(
            b'irm ckey.run|iex',
            f'irm {local_base}/export/activate.ps1 -OutFile activate.ps1; .\\activate.ps1'.encode())
        content = content.replace(b'CodeKey Run', b'JetBrain')
        content = content.replace(b'ckey.run', b'JetBrain')
        return content

    @staticmethod
    def _rewrite_offline(content, local_base):
        """改写免交互激活脚本：服务器默认地址、品牌名。"""
        content = content.replace(
            b'[string]$Server = "http://localhost:10768"',
            f'[string]$Server = "{local_base}"'.encode())
        content = content.replace(
            b'SERVER="${1:-http://localhost:10768}"',
            f'SERVER="${{1:-{local_base}}}"'.encode())
        content = content.replace(b'ckey.run', b'JetBrain')
        return content

    def _read_rewritten(self, filepath, offline):
        """读取脚本并做 URL 改写；文件缺失返回 None。"""
        if not (os.path.exists(filepath) and os.path.isfile(filepath)):
            return None
        with open(filepath, "rb") as f:
            content = f.read()
        local_base = self._local_base()
        if offline:
            return self._rewrite_offline(content, local_base)
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
        content = self._read_rewritten(filepath, offline=False)
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

    def _send_offline_script(self, filepath):
        """发送免交互激活脚本（快捷运行，无 BOM）"""
        content = self._read_rewritten(filepath, offline=True)
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
        print(f"  → 200 OK ({len(content)} bytes) - offline script (URLs rewritten to {local_base})")

    _EXPORT_FILES = {
        "activate.ps1":         ("Windows/activate.ps1", False, True),
        "offline_activate.ps1": ("Windows/offline_activate.ps1", True, True),
        "activate.sh":          ("Linux-macOS/activate.sh", False, False),
        "offline_activate.sh":  ("Linux-macOS/offline_activate.sh", True, False),
        "debug.sh":             ("Linux-macOS/debug.sh", False, False),
        "uninstall.sh":         ("Linux-macOS/uninstall.sh", False, False),
    }

    def _send_export(self, name):
        """导出单个脚本：.ps1 保留 UTF-8 BOM，便于 PS 5.1 解析保存到磁盘的文件。"""
        entry = self._EXPORT_FILES.get(name)
        if entry is None:
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Script not found")
            print(f"  → 404 Not Found - export/{name}")
            return

        disk_name, offline, is_ps = entry
        content = self._read_rewritten(os.path.join(SCRIPTS_DIR, disk_name), offline)
        if content is None:
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Script not found")
            print(f"  → 404 Not Found - export/{name}")
            return

        if is_ps and not content.startswith(b"\xef\xbb\xbf"):
            content = b"\xef\xbb\xbf" + content
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Disposition", f'attachment; filename="{name}"')
        self.send_header("Content-Length", len(content))
        self.end_headers()
        self.wfile.write(content)
        print(f"  → 200 OK ({len(content)} bytes) - export/{name}")

    def _send_zip(self):
        """一次性导出各平台全部脚本（zip）：.ps1 保留 BOM，全部改写为本机服务器地址。"""
        local_base = self._local_base()
        entries = [
            ("Windows/activate.ps1", "Windows/activate.ps1", False, True),
            ("Windows/offline_activate.ps1", "Windows/offline_activate.ps1", True, True),
            ("Linux-macOS/activate.sh", "Linux-macOS/activate.sh", False, False),
            ("Linux-macOS/offline_activate.sh", "Linux-macOS/offline_activate.sh", True, False),
            ("Linux-macOS/debug.sh", "Linux-macOS/debug.sh", False, False),
            ("Linux-macOS/uninstall.sh", "Linux-macOS/uninstall.sh", False, False),
        ]
        readme = (
            "ckey 离线激活脚本包（本地服务器 %s）\n"
            "\n"
            "Windows PowerShell（管理员）：\n"
            "  快捷运行    irm %s | iex\n"
            "  导出运行    irm %s/export/activate.ps1 -OutFile activate.ps1; .\\activate.ps1\n"
            "  免交互激活  irm %s/export/offline_activate.ps1 -OutFile offline_activate.ps1; .\\offline_activate.ps1\n"
            "\n"
            "Linux / macOS 终端：\n"
            "  快捷运行    curl -Ls %s | bash\n"
            "  导出运行    curl -Ls %s/export/activate.sh -o activate.sh && bash activate.sh\n"
            "  免交互激活  curl -Ls %s/export/offline_activate.sh -o offline_activate.sh && bash offline_activate.sh\n"
            "  调试脚本    bash debug.sh\n"
            "  卸载脚本    bash uninstall.sh\n"
            "\n"
            "免交互激活可用参数：[服务器地址] [许可证名称] [过期日期]\n"
            "  bash offline_activate.sh http://192.168.1.5:10768 MyName 2099-12-31\n"
        ) % (local_base, local_base, local_base, local_base,
             local_base, local_base, local_base)
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("使用说明.txt", readme.encode("utf-8"))
            for arc, disk, offline, is_ps in entries:
                content = self._read_rewritten(os.path.join(SCRIPTS_DIR, disk), offline)
                if content is None:
                    continue
                if is_ps and not content.startswith(b"\xef\xbb\xbf"):
                    content = b"\xef\xbb\xbf" + content
                zf.writestr(arc, content)

        data = buf.getvalue()
        self.send_response(200)
        self.send_header("Content-Type", "application/zip")
        self.send_header("Content-Disposition", 'attachment; filename="ckey-scripts.zip"')
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        print(f"  → 200 OK ({len(data)} bytes) - scripts.zip")

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
        license_name = data.get("licenseName", "ckey.run")
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

        elif path == "/debug":
            self._send_script(os.path.join(SCRIPTS_UNIX_DIR, "debug.sh"))

        elif path == "/uninstall":
            self._send_script(os.path.join(SCRIPTS_UNIX_DIR, "uninstall.sh"))

        elif path == "/activate":
            # 免交互激活脚本：PowerShell/Windows → .ps1，macOS/Linux → .sh
            ua = self.headers.get("User-Agent", "").lower()
            if "powershell" in ua or "windowspowershell" in ua or "windows" in ua:
                script = os.path.join(SCRIPTS_WIN_DIR, "offline_activate.ps1")
            else:
                script = os.path.join(SCRIPTS_UNIX_DIR, "offline_activate.sh")
            self._send_offline_script(script)

        elif path == "/scripts.zip":
            self._send_zip()

        elif path.startswith("/export/"):
            self._send_export(path[len("/export/"):])

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
            self.wfile.write(b"Not found. Available: / /activate /debug /uninstall /export/<name> /scripts.zip /ja-netfilter/*")

    def _generate_license_text(self, body_data):
        """
        生成纯文本格式激活码（与网站 /generateLicense 端点一致）。
        格式: <licenseId>-<Base64(JSON)>-<Base64(签名)>-<Base64(证书)>
        纯 ASCII 单行字符串，不含 UTF-16 编码，不含文件头前缀。
        """
        return generate_license_key_text(
            body_data.get("assigneeName", ""),
            body_data.get("expiryDate", "2099-12-31"),
            body_data.get("licenseName", "ckey.run"),
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


class _CKeyServer(http.server.ThreadingHTTPServer):
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
        description="ckey.run 离线复现本地服务器",
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

免交互激活 (Linux/Mac):
    curl -Ls http://localhost:10768/export/offline_activate.sh -o offline_activate.sh && bash offline_activate.sh

一次性导出各平台全部脚本:
    curl -Ls http://localhost:10768/scripts.zip -o ckey-scripts.zip
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
    server = _CKeyServer((args.host, args.port), CKeyRunHandler)
    print("=" * 60)
    print("  ckey.run 离线复现本地服务器")
    print("  仅供教学和研究使用")
    print("=" * 60)
    print(f"  监听地址: http://{args.host}:{args.port}")
    print(f"  资源目录: {JA_NETFILTER_DIR}")
    print()
    print("  可用端点:")
    print(f"    GET  http://{args.host}:{args.port}/")
    print(f"    GET  http://{args.host}:{args.port}/debug")
    print(f"    GET  http://{args.host}:{args.port}/uninstall")
    print(f"    GET  http://{args.host}:{args.port}/activate")
    print(f"    GET  http://{args.host}:{args.port}/export/<name>")
    print(f"    GET  http://{args.host}:{args.port}/scripts.zip")
    print(f"    POST http://{args.host}:{args.port}/generateLicense/file")
    print(f"    GET  http://{args.host}:{args.port}/ja-netfilter/<path>")
    print()
    print("  使用方法:")
    print(f"    # 快捷运行 Linux/Mac:")
    print(f"    curl -Ls http://{args.host}:{args.port} | bash")
    print(f"    # 快捷运行 Windows PowerShell (右键管理员运行):")
    print(f"    irm http://{args.host}:{args.port} | iex")
    print(f"    # 导出为本地脚本 Linux/Mac:")
    print(f"    curl -Ls http://{args.host}:{args.port}/export/activate.sh -o activate.sh && bash activate.sh")
    print(f"    # 导出为本地脚本 Windows PowerShell:")
    print(f"    irm http://{args.host}:{args.port}/export/activate.ps1 -OutFile activate.ps1; .\\activate.ps1")
    print(f"    # 免交互激活 (Linux/Mac):")
    print(f"    curl -Ls http://{args.host}:{args.port}/export/offline_activate.sh -o offline_activate.sh && bash offline_activate.sh")
    print(f"    # 一次性导出各平台全部脚本:")
    print(f"    curl -Ls http://{args.host}:{args.port}/scripts.zip -o ckey-scripts.zip")
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
