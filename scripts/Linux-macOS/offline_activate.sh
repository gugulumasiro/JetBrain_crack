#!/usr/bin/env bash
# JetBrain 离线激活 — 免交互版本 (macOS / Linux)
# 用法: bash offline_activate.sh [服务器地址] [许可证名称] [过期日期]
#   或: curl -Ls http://localhost:10768/activate -o offline_activate.sh && bash offline_activate.sh

set -u

SERVER="${1:-http://localhost:10768}"
LICENSE_NAME="${2:-JetBrain}"
EXPIRY_DATE="${3:-2099-12-31}"

# ============ 平台检测 =============
detect_platform() {
    case "$(uname -s)" in
        Darwin)
            OS="macOS"
            FILE_VMOPTIONS=".vmoptions"
            ;;
        Linux)
            OS="Linux"
            FILE_VMOPTIONS="64.vmoptions"
            ;;
        *)
            echo "[错误] 不支持的操作系统: $(uname -s)"
            exit 1
            ;;
    esac
}
detect_platform

# ============ 获取原始用户和家目录 =============
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    ORIGINAL_USER="$SUDO_USER"
    USER_HOME="/home/${SUDO_USER}"
else
    ORIGINAL_USER="$(whoami)"
    USER_HOME="${HOME}"
fi
if [ "$OS" = "macOS" ]; then
    USER_HOME="/Users/${ORIGINAL_USER}"
fi

# ============ 路径配置 =============
DIR_WORK="${USER_HOME}/.jb_run"
DIR_CONFIG="${DIR_WORK}/config"
DIR_PLUGINS="${DIR_WORK}/plugins"
JAR_FILE="${DIR_WORK}/ja-netfilter.jar"

if [ "$OS" = "macOS" ]; then
    DIR_CACHE_JB="${USER_HOME}/Library/Caches/JetBrains"
    DIR_CONFIG_JB="${USER_HOME}/Library/Application Support/JetBrains"
else
    DIR_CACHE_JB="${USER_HOME}/.cache/JetBrains"
    DIR_CONFIG_JB="${USER_HOME}/.config/JetBrains"
fi

# ============ 产品列表 (name:code) =============
PRODUCTS="idea:II,PCWMP,PSI
clion:CL,PSI,PCWMP
phpstorm:PS,PCWMP,PSI
goland:GO,PSI,PCWMP
pycharm:PC,PSI,PCWMP
webstorm:WS,PCWMP,PSI
rider:RD,PDB,PSI,PCWMP
datagrip:DB,PSI,PDB
rubymine:RM,PCWMP,PSI
appcode:AC,PCWMP,PSI
dataspell:DS,PSI,PDB,PCWMP
rustrover:RR,PSI,PCWP"

# ============ 工具函数 =============
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

download() {
    local url="$1"
    local out="$2"
    mkdir -p "$(dirname "$out")" 2>/dev/null || true
    log "  下载: $url"
    curl -fsSL "$url" -o "$out" || {
        log "[错误] 下载失败: $url"
        exit 1
    }
}

find_product() {
    local dir_name="$1"
    local lower
    lower=$(printf '%s' "$dir_name" | tr '[:upper:]' '[:lower:]')
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name="${line%%:*}"
        if [[ "$lower" == *"$name"* ]]; then
            printf '%s' "$line"
            return 0
        fi
    done <<< "$PRODUCTS"
    return 1
}

# 清理旧 javaagent 行并追加新行（grep+mv，兼容 macOS/Linux）
inject_vmoptions() {
    local file="$1"
    mkdir -p "$(dirname "$file")" 2>/dev/null || true
    local tmp="${file}.tmp.$$"
    if [ -f "$file" ]; then
        grep -vE '(-javaagent|--add-opens=java.base/jdk\.internal)' "$file" > "$tmp" 2>/dev/null || true
    else
        : > "$tmp"
    fi
    printf '%s\n' "-javaagent:${JAR_FILE}" >> "$tmp"
    mv -f "$tmp" "$file"
}

process_disabled_plugins() {
    local file="$1"
    [ -f "$file" ] || return 0
    local tmp="${file}.tmp.$$"
    grep -v '^com.intellij.modules.ultimate$' "$file" > "$tmp" || true
    mv -f "$tmp" "$file"
}

# 读取 bin/idea.properties 中的 idea.config.path 自定义配置目录
read_custom_config() {
    local file_properties="$1"
    [ -f "$file_properties" ] || return 1
    local line
    line=$(grep -E '^idea\.config\.path[[:space:]]*=' "$file_properties" 2>/dev/null | grep -v '^[[:space:]]*#' | head -n 1)
    [ -z "$line" ] && return 1
    local val="${line#*=}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    val="${val%\"}"; val="${val#\"}"
    val="${val//\$\{user.home\}/$USER_HOME}"
    printf '%s' "$val"
}

request_license() {
    local code="$1"
    local out="$2"
    local body
    body=$(printf '{"assigneeName":"","expiryDate":"%s","licenseName":"%s","productCode":"%s"}' \
        "$(json_escape "$EXPIRY_DATE")" "$(json_escape "$LICENSE_NAME")" "$(json_escape "$code")")
    log "  生成 $(basename "$out") ($code)..."
    curl -fsSL -X POST "${SERVER}/generateLicense/file" \
        -H "Content-Type: application/json" \
        -d "$body" -o "$out" || {
        log "[错误] 许可证请求失败: $code"
        return 1
    }
}

# ============ 主流程 =============
main() {
    echo "============================================"
    echo "  JetBrains 离线激活 (免交互)"
    echo "  服务器: $SERVER"
    echo "  许可证: $LICENSE_NAME"
    echo "  有效期: $EXPIRY_DATE"
    echo "============================================"

    echo ""
    echo "[1/4] 准备环境..."
    if [ -d "$DIR_WORK" ]; then
        rm -rf "$DIR_WORK" || { log "[错误] 无法清理 $DIR_WORK，请关闭 JetBrains IDE 后重试"; exit 1; }
    fi
    mkdir -p "$DIR_CONFIG" "$DIR_PLUGINS"

    echo ""
    echo "[2/4] 下载 ja-netfilter..."
    download "${SERVER}/ja-netfilter/ja-netfilter.jar" "$JAR_FILE"
    download "${SERVER}/ja-netfilter/config/dns.conf"    "$DIR_CONFIG/dns.conf"
    download "${SERVER}/ja-netfilter/config/env.conf"    "$DIR_CONFIG/env.conf"
    download "${SERVER}/ja-netfilter/config/native.conf" "$DIR_CONFIG/native.conf"
    download "${SERVER}/ja-netfilter/config/power.conf"  "$DIR_CONFIG/power.conf"
    download "${SERVER}/ja-netfilter/config/url.conf"    "$DIR_CONFIG/url.conf"
    download "${SERVER}/ja-netfilter/plugins/dns.jar"    "$DIR_PLUGINS/dns.jar"
    download "${SERVER}/ja-netfilter/plugins/env.jar"    "$DIR_PLUGINS/env.jar"
    download "${SERVER}/ja-netfilter/plugins/native.jar" "$DIR_PLUGINS/native.jar"
    download "${SERVER}/ja-netfilter/plugins/power.jar"  "$DIR_PLUGINS/power.jar"
    download "${SERVER}/ja-netfilter/plugins/url.jar"    "$DIR_PLUGINS/url.jar"
    download "${SERVER}/ja-netfilter/plugins/hideme.jar" "$DIR_PLUGINS/hideme.jar"
    download "${SERVER}/ja-netfilter/plugins/privacy.jar" "$DIR_PLUGINS/privacy.jar"

    echo ""
    echo "[3/4] 处理 JetBrains 产品..."
    if [ ! -d "$DIR_CACHE_JB" ]; then
        echo "[错误] 未找到 JetBrains 配置缓存目录: $DIR_CACHE_JB"
        echo "  请先安装并运行一次 JetBrains IDE"
        exit 1
    fi

    local processed=0
    for dir in "$DIR_CACHE_JB"/*; do
        [ -d "$dir" ] || continue
        local dir_name
        dir_name=$(basename "$dir")
        local prod
        prod=$(find_product "$dir_name") || continue

        local name="${prod%%:*}"
        local code="${prod#*:}"
        echo "  处理: $dir_name"

        # 读取 .home 获取安装路径
        local file_home="${dir}/.home"
        [ -f "$file_home" ] || { echo "    跳过: 未找到 .home"; continue; }
        local install_path
        install_path=$(cat "$file_home")
        local dir_bin="${install_path}/bin"
        [ -d "$dir_bin" ] || { echo "    跳过: bin 目录不存在"; continue; }

        # 读取 idea.config.path 自定义配置目录
        local dir_config_product="${DIR_CONFIG_JB}/${dir_name}"
        local custom_cfg=""
        if [ -f "${dir_bin}/idea.properties" ]; then
            custom_cfg=$(read_custom_config "${dir_bin}/idea.properties")
        fi
        if [ -n "$custom_cfg" ]; then
            dir_config_product="$custom_cfg"
        fi

        # 更新 .vmoptions 注入 javaagent (用户级配置目录优先于安装目录 bin)
        mkdir -p "$dir_config_product" 2>/dev/null || true
        local vm_files
        vm_files=( "$dir_config_product"/*"$FILE_VMOPTIONS" )
        if [ ! -f "${vm_files[0]}" ]; then
            vm_files=( "$dir_config_product/${name}${FILE_VMOPTIONS}" )
        fi
        local file_client_vm="${dir_config_product}/jetbrains_client.vmoptions"
        vm_files+=( "$file_client_vm" )
        local vm
        for vm in "${vm_files[@]}"; do
            inject_vmoptions "$vm"
            echo "    更新: $(basename "$vm")"
        done

        # 获取许可证
        request_license "$code" "$dir_config_product/${name}.key"

        # 处理 disabled_plugins
        process_disabled_plugins "$dir_config_product/disabled_plugins.txt"

        processed=$((processed + 1))
    done

    echo ""
    echo "[4/4] 完成!"
    echo "  处理了 $processed 个产品"
    echo "  许可证名称: $LICENSE_NAME"
    echo "  有效期至: $EXPIRY_DATE"
    echo ""
    echo "  现在可以启动 JetBrains IDE 了"
    echo "============================================"
}

main
