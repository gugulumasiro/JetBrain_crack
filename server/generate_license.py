#!/usr/bin/env python3
"""
离线许可证生成器（配合 activate.sh / activate.ps1 的 OFFLINE_LICENSE_* 钩子使用）。
不启动服务器，直接复用 local_server 的签名逻辑，用 keys/ 下的私钥生成本地 .key 许可证。

用法：
    python server/generate_license.py --product-code "II,PCWMP,PSI" \
        --license-name JetBrain --expiry 2099-12-31 -o idea.key
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from local_server import generate_license_key


def main():
    ap = argparse.ArgumentParser(description="离线生成 JetBrains 许可证 (.key 文件)")
    ap.add_argument("--product-code", required=True,
                    help='产品代码，逗号分隔，如 "II,PCWMP,PSI"')
    ap.add_argument("--license-name", default="JetBrain")
    ap.add_argument("--expiry", default="2099-12-31", help="过期日期 yyyy-MM-dd")
    ap.add_argument("--assignee", default="")
    ap.add_argument("-o", "--output", required=True, help="输出 .key 文件路径")
    args = ap.parse_args()

    try:
        data = generate_license_key(args.assignee, args.expiry,
                                    args.license_name, args.product_code)
    except RuntimeError as e:
        print(f"[错误] {e}", file=sys.stderr)
        sys.exit(1)

    out = os.path.abspath(args.output)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(data)
    print(f"[OK] 许可证已写入: {out}")


if __name__ == "__main__":
    main()
