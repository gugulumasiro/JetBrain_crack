#!/usr/bin/env python3
"""
重新生成 keys/ 下的本地 RSA 密钥与证书，并同步重算 ja-netfilter/config/power.conf。

keys/ 已在 .gitignore 中排除、不入库。克隆仓库后首次使用前运行本脚本一次，
即可生成私钥/证书并让 power.conf 与当前证书严格匹配；已有密钥需要更换时用 --force。

用法：
    python scripts/generate_keys.py          # 补齐缺失的密钥/证书，并校准 power.conf
    python scripts/generate_keys.py --force  # 忽略已有文件，全新生成一套
"""

import argparse
import os

from cryptography import x509
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.dirname(SERVER_DIR)
KEYS_DIR = os.path.join(BASE_DIR, "keys")
PRIVATE_KEY_PATH = os.path.join(KEYS_DIR, "private.pem")
PUBLIC_KEY_PATH = os.path.join(KEYS_DIR, "public.pem")
CERT_PATH = os.path.join(KEYS_DIR, "cert.der")
POWER_CONF = os.path.join(BASE_DIR, "ja-netfilter", "config", "power.conf")

# EMSA-PKCS1v15(SHA-256) 的 DigestInfo 前缀
_SHA256_DIGESTINFO = bytes.fromhex("3031300d060960864801650304020105000420")
# JetBrains CA 为 4096 位（512 字节），其模数（power.conf 参数3）不可改动
_CA_MODULUS_BYTES = 512


def _emsa_pkcs1v15_sha256(tbs: bytes) -> int:
    """计算 EMSA-PKCS1v15(SHA256(tbs), k=512) 的整数值，即 power.conf 参数4。"""
    h = hashes.Hash(hashes.SHA256(), backend=default_backend())
    h.update(tbs)
    digest = h.finalize()
    pad_len = _CA_MODULUS_BYTES - 3 - len(_SHA256_DIGESTINFO) - len(digest)
    em = b"\x00\x01" + b"\xff" * pad_len + b"\x00" + _SHA256_DIGESTINFO + digest
    return int.from_bytes(em, "big")


def _generate_private_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=4096, backend=default_backend())


def _generate_cert(key):
    """生成与 local_server.py 完全一致的自签名证书：issuer 必须为 JetProfile CA。"""
    now = x509.CertificateBuilder()
    pubkey = key.public_key()
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Jetbrains-Help")])
    issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "JetProfile CA")])
    cert = (now.subject_name(subject)
            .issuer_name(issuer)
            .public_key(pubkey)
            .serial_number(x509.random_serial_number())
            .not_valid_before(__import__("datetime").datetime(2000, 1, 1))
            .not_valid_after(__import__("datetime").datetime(2100, 1, 1))
            .sign(key, hashes.SHA256(), default_backend()))
    return cert


def _write_key_files(key):
    os.makedirs(KEYS_DIR, exist_ok=True)
    with open(PRIVATE_KEY_PATH, "wb") as f:
        f.write(key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ))
    with open(PUBLIC_KEY_PATH, "wb") as f:
        f.write(key.public_key().public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        ))


def _load_cert():
    with open(CERT_PATH, "rb") as f:
        return x509.load_der_x509_certificate(f.read(), default_backend())


def _cert_params(cert):
    param1 = int.from_bytes(cert.signature, "big")          # 证书签名
    param4 = _emsa_pkcs1v15_sha256(cert.tbs_certificate_bytes)  # EMSA(SHA256(TBS), k=512)
    return param1, param4


def _patch_power_conf(param1, param4):
    """仅替换 EQUAL 行中的参数1与参数4，参数3（JetBrains CA 模数）、行尾风格及文件其它内容原样保留。

    power.conf 格式为：EQUAL,<参数1>,65537,<参数3>-><参数4>（参数3 与参数4 以 '->' 分隔）
    """
    with open(POWER_CONF, "rb") as f:
        raw = f.read()
    nl = b"\r\n" if b"\r\n" in raw else b"\n"
    lines = [l.rstrip("\r") for l in raw.decode("utf-8").split("\n")]
    if lines and lines[-1] == "":
        lines.pop()
    for i, line in enumerate(lines):
        if line.startswith("EQUAL,"):
            parts = line.split(",")
            parts[1] = str(param1)
            if "->" not in parts[3]:
                raise SystemExit(f"EQUAL 行缺少 '->' 分隔符，请保留原始 {POWER_CONF} 后重试")
            modulus, _ = parts[3].split("->", 1)
            parts[3] = f"{modulus}->{param4}"
            lines[i] = ",".join(parts)
            break
    else:
        raise SystemExit(f"在 {POWER_CONF} 中找不到 EQUAL 行，请保留原始文件后重试")
    with open(POWER_CONF, "wb") as f:
        f.write(nl.join(l.encode("utf-8") for l in lines) + nl)


def main():
    ap = argparse.ArgumentParser(description="重新生成签名密钥并校准 power.conf")
    ap.add_argument("--force", action="store_true", help="忽略已有文件，全新生成")
    args = ap.parse_args()

    force = args.force
    private_exists = os.path.exists(PRIVATE_KEY_PATH)
    cert_exists = os.path.exists(CERT_PATH)

    if force or not private_exists:
        key = _generate_private_key()
        _write_key_files(key)
        cert = _generate_cert(key)
        with open(CERT_PATH, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.DER))
        print(f"[OK] 已生成新密钥与证书: {KEYS_DIR}")
    elif not cert_exists:
        key = serialization.load_pem_private_key(open(PRIVATE_KEY_PATH, "rb").read(), password=None, backend=default_backend())
        cert = _generate_cert(key)
        with open(CERT_PATH, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.DER))
        print("[OK] 私钥已存在，仅补生成证书 cert.der")
    else:
        cert = _load_cert()
        print("[INFO] 已有密钥与证书，将按当前证书校准 power.conf")

    cert = _load_cert()
    param1, param4 = _cert_params(cert)
    _patch_power_conf(param1, param4)
    print("[OK] power.conf 参数 1/4 已按当前证书重算（参数3 保持不变）")


if __name__ == "__main__":
    main()
