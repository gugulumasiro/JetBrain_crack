#!/usr/bin/env bash
# JetBrains 一键激活（Linux / macOS）— 离线版，全程不启动服务器
#
# 一条命令完成全部激活流程：
#   1. 生成/补齐签名密钥与证书（scripts/generate_keys.py，幂等，可重复运行）
#   2. 激活本机 JetBrains IDE（离线执行 scripts/Linux-macOS/activate.sh：
#      ja-netfilter 资源从仓库本地复制，许可证由本地密钥离线生成）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log() { printf '\033[0;36m%s\033[0m\n' "$1"; }
ok()  { printf '\033[0;32m%s\033[0m\n' "$1"; }
err() { printf '\033[0;31m%s\033[0m\n' "$1"; }

log '========================================'
log '  JetBrains 一键激活（Linux / macOS）'
log '  离线模式 · 不启动服务器'
log '========================================'

# ---------- 1. 检查 Python ----------
if ! command -v python3 >/dev/null 2>&1; then
    err '[错误] 未找到 python3（需要 3.8+）。'
    exit 1
fi
PY="$(command -v python3)"
ok "[1/3] 检测到 python3: $PY"

# ---------- 2. 安装 cryptography 依赖 ----------
if "$PY" -c 'import cryptography' >/dev/null 2>&1; then
    ok '[2/3] cryptography 已就绪'
else
    log '[2/3] 安装 cryptography 依赖...'
    "$PY" -m pip install --user 'cryptography>=3.0' \
        || "$PY" -m pip install 'cryptography>=3.0' \
        || { err '[错误] cryptography 安装失败，请手动执行：'
             err "       $PY -m pip install cryptography"
             exit 1; }
fi

# ---------- 3. 生成/补齐密钥 ----------
log '[3/3] 生成/补齐签名密钥与证书（幂等，可重复运行）...'
( cd "$REPO_ROOT" && "$PY" scripts/generate_keys.py ) || {
    err '[错误] 密钥生成失败，请检查上方输出。'
    exit 1
}

# ---------- 4. 激活（离线执行，复制临时副本以免 activate.sh 自删仓库文件） ----------
log ''
log '开始激活。请按提示选择产品并填写许可证信息。'
TMP_SCRIPT="$(mktemp /tmp/jb_activate.XXXXXX.sh)" || exit 1
cp "$SCRIPT_DIR/activate.sh" "$TMP_SCRIPT" || {
    err '[错误] 复制激活脚本失败。'
    exit 1
}
OFFLINE_RESOURCES_DIR="$REPO_ROOT/ja-netfilter" \
OFFLINE_LICENSE_CMD="$PY" \
OFFLINE_LICENSE_SCRIPT="$REPO_ROOT/server/generate_license.py" \
    bash "$TMP_SCRIPT"
rm -f "$TMP_SCRIPT"
ok ''
ok '激活流程已结束。'

exit 0
