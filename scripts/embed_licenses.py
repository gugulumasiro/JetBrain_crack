#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把预生成的 12 款产品许可证内嵌到三个一键激活脚本中。

在仓库机器上运行（需已存在 keys/ 密钥与证书）：

    python scripts/embed_licenses.py

脚本用当前 keys/ 为 12 款产品签发固定身份（许可证名称 JetBrain、被授权人为空、
有效期 2099-12-31）的 .key，打包成 zip 后 base64 内嵌到
scripts/Windows/one-click-activate.ps1 / one-click-activate.cmd 与
scripts/Linux-macOS/one-click-activate.sh 的 __JB_OFFLINE_PACK__ /
__JB_OFFLINE_END__ 标记区间（字节级替换，.cmd 的 GBK 编码原样保留）。
目标机器运行时自行解压即可激活，无需安装 Python。

轮换 keys/ 密钥后需重新运行本脚本刷新内嵌许可证。

子命令：
  embed   内嵌许可证（默认）
  verify  仅校验三个脚本的内嵌载荷能否解出 12 个 .key，不写入
"""

import base64
import io
import os
import re
import sys
import zipfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
sys.path.insert(0, os.path.join(REPO_ROOT, "server"))

import local_server  # noqa: E402

MARKER_BEGIN = "__JB_OFFLINE_PACK__"
MARKER_END = "__JB_OFFLINE_END__"

TARGETS = [
    os.path.join(SCRIPT_DIR, "Windows", "one-click-activate.ps1"),
    os.path.join(SCRIPT_DIR, "Windows", "one-click-activate.cmd"),
    os.path.join(SCRIPT_DIR, "Linux-macOS", "one-click-activate.sh"),
]

# 匹配 __JB_OFFLINE_PACK__ 到 __JB_OFFLINE_END__ 的整段（含两端标记与末尾换行）。
# 非贪婪；引导代码内的标记均拆分开写，文件里唯一的完整标记对位于内嵌区。
# 兼容 LF 与 CRLF（.cmd 为 CRLF 编码）。
_PAYLOAD_RE = re.compile(
    re.escape(MARKER_BEGIN.encode()) + rb"\r?\n.*?" + re.escape(MARKER_END.encode()) + rb"\r?\n", re.S
)


def _check_keys():
    if getattr(local_server, "_SIGNING_KEY", None) is None:
        print("[错误] 未加载到签名密钥 keys/private.pem。")
        print("       请先运行 python scripts/generate_keys.py 生成密钥与证书，再执行本脚本。")
        sys.exit(1)


def build_payload(eol=b"\n"):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, codes in local_server._PREGEN_PRODUCTS:
            key = local_server.generate_license_key("", "2099-12-31", "JetBrain", codes)
            zf.writestr(f"{name}.key", key)
    b64 = base64.b64encode(buf.getvalue())
    lines = eol.join(b64[i:i + 76] for i in range(0, len(b64), 76))
    return MARKER_BEGIN.encode() + eol + lines + eol + MARKER_END.encode() + eol


def embed(payload):
    for path in TARGETS:
        with open(path, "rb") as f:
            data = f.read()
        eol = b"\r\n" if b"\r\n" in data else b"\n"
        payload = build_payload(eol)
        new_data, n = _PAYLOAD_RE.subn(payload, data)
        if n != 1:
            print(f"[错误] {os.path.basename(path)} 中未找到唯一的 {MARKER_BEGIN} / {MARKER_END} 标记区间（匹配数 {n}）。")
            sys.exit(1)
        with open(path, "wb") as f:
            f.write(new_data)
        eol_name = "CRLF" if eol == b"\r\n" else "LF"
        print(f"[OK] 已内嵌许可证到 {os.path.relpath(path, REPO_ROOT)}（{len(payload)} 字节，{eol_name}）")


def _region_to_zip_bytes(region):
    lines = [ln.rstrip(b"\r") for ln in region.split(b"\n")[1:-2]]
    return base64.b64decode(b"\n".join(lines))


def verify():
    expected = sorted(f"{name}.key" for name, _ in local_server._PREGEN_PRODUCTS)
    ok = True
    for path in TARGETS:
        with open(path, "rb") as f:
            data = f.read()
        m = _PAYLOAD_RE.search(data)
        if not m:
            print(f"[FAIL] {os.path.basename(path)}: 未找到内嵌载荷")
            ok = False
            continue
        try:
            zip_bytes = _region_to_zip_bytes(m.group(0))
        except Exception as e:
            print(f"[FAIL] {os.path.basename(path)}: base64 解码失败 - {e}")
            ok = False
            continue
        with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
            names = sorted(zf.namelist())
        good = names == expected
        ok = ok and good
        print(f"[{'OK' if good else 'FAIL'}] {os.path.basename(path)}: {len(names)} 个 .key {names}")
    return ok


def main():
    _check_keys()
    action = sys.argv[1] if len(sys.argv) > 1 else "embed"
    if action == "verify":
        sys.exit(0 if verify() else 1)
    if action != "embed":
        print(f"用法: python {os.path.basename(__file__)} [embed|verify]")
        sys.exit(2)
    payload = build_payload()
    embed(payload)
    print("完成。可用 `python scripts/embed_licenses.py verify` 校验内嵌载荷。")


if __name__ == "__main__":
    main()
