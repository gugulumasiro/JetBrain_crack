#!/bin/bash
#set -e

# ============ 平台检测 =============
detect_platform() {
    case "$(uname -s)" in
        Darwin)
            OS="macOS"
            SHA_TOOL="shasum"
            OPEN_CMD="open"
            DATE_PARSER="mac"
            FILE_VMOPTIONS=".vmoptions"
            ;;
        Linux)
            OS="Linux"
            SHA_TOOL="sha1sum"
            OPEN_CMD="xdg-open"
            DATE_PARSER="linux"
            FILE_VMOPTIONS="64.vmoptions"
            ;;
        *)
            OS="Unknown"
            SHA_TOOL="sha1sum"
            OPEN_CMD="xdg-open"
            DATE_PARSER="linux"
            FILE_VMOPTIONS=".vmoptions"
            ;;
    esac
}
# 自动检测平台
detect_platform
# ============ 配置 =============
DEBUG=true
ENABLE_COLOR=true

URL_BASE="http://localhost:10768"


# 获取原始用户和家目录
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    ORIGINAL_USER="$SUDO_USER"
    USER_HOME="/home/${SUDO_USER}"
else
    ORIGINAL_USER="$(whoami)"
    USER_HOME="${HOME}"
fi

# macOS 用户路径修正
if [[ "$OS" == "macOS" ]]; then
    USER_HOME="/Users/${ORIGINAL_USER}"
fi

# 工作路径
dir_work="${USER_HOME}/.jb_run"

# JetBrains 目录
if [[ "$OS" == "macOS" ]]; then
    dir_cache_jb="${USER_HOME}/Library/Caches/JetBrains"
    dir_config_jb="${USER_HOME}/Library/Application Support/JetBrains"
else
    dir_cache_jb="${USER_HOME}/.cache/JetBrains"
    dir_config_jb="${USER_HOME}/.config/JetBrains"
fi

# 日志颜色设置
if $ENABLE_COLOR; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    GRAY='\033[38;5;240m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    GRAY=''
    NC=''
fi

# 产品列表
PRODUCTS='[
    {"name":"idea","productCode":"II,PCWMP,PSI"},
    {"name":"clion","productCode":"CL,PSI,PCWMP"},
    {"name":"phpstorm","productCode":"PS,PCWMP,PSI"},
    {"name":"goland","productCode":"GO,PSI,PCWMP"},
    {"name":"pycharm","productCode":"PC,PSI,PCWMP"},
    {"name":"webstorm","productCode":"WS,PCWMP,PSI"},
    {"name":"rider","productCode":"RD,PDB,PSI,PCWMP"},
    {"name":"datagrip","productCode":"DB,PSI,PDB"},
    {"name":"rubymine","productCode":"RM,PCWMP,PSI"},
    {"name":"appcode","productCode":"AC,PCWMP,PSI"},
    {"name":"dataspell","productCode":"DS,PSI,PDB,PCWMP"},
    {"name":"dotmemory","productCode":"DM"},
    {"name":"rustrover","productCode":"RR,PSI,PCWP"}
]'

# ============ 工具函数 =============

# ============ 日期验证 =============
check_and_install_deps() {
    local deps=("curl" "jq")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        info "所有依赖已安装。"
        return
    fi

    warning "缺少以下依赖：${missing[*]}，正在尝试自动安装..."

    # 先检测系统类型
    case "$(uname -s)" in
        Darwin)
          # 检测 Homebrew 是否存在
          if ! command -v brew &>/dev/null; then
              warning "检测到 macOS但未安装 Homebrew"
              read -p "是否要自动安装 Homebrew?(y/n) " install_brew
              if [[ "$install_brew" =~ [yY] ]]; then
                  info "正在安装 Homebrew..."
                  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

                  # 自动配置环境变量
                  if [ -x "/opt/homebrew/bin/brew" ]; then  # Apple Silicon
                      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
                      source ~/.zshrc
                  elif [ -x "/usr/local/bin/brew" ]; then  # Intel
                      echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zshrc
                      source ~/.zshrc
                  fi

                  # 再次验证
                  if ! command -v brew &>/dev/null; then
                      error "Homebrew 安装后仍不可用，请手动重启终端后重试"
                      exit 1
                  fi
              else
                  error "必须安装 Homebrew 才能继续!"
                  exit 1
              fi
          fi

          # 安装依赖
          brew install "${missing[@]}"
          ;;
        Linux)
            # Linux 系统 (原逻辑)
            if command -v apt-get &>/dev/null; then
                sudo apt update && sudo apt install -y "${missing[@]}"
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y "${missing[@]}"
            elif command -v yum &>/dev/null; then
                sudo yum install -y "${missing[@]}"
            elif command -v pacman &>/dev/null; then
                sudo pacman -Sy --noconfirm "${missing[@]}"
            else
                error "无法识别的 Linux 发行版，请手动安装依赖：${missing[*]}"
                exit 1
            fi
            ;;
        *)
            error "不支持的操作系统"
            exit 1
            ;;
    esac

    # 验证安装结果
    for dep in "${missing[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            error "安装失败：$dep"
            exit 1
        fi
    done

    success "所有依赖已成功安装！"
}

# ============ 解析产品 =============
parse_product_from_json() {
    local index="$1"
    local name=$(echo "$PRODUCTS" | jq -r ".[$index].name")
    local code=$(echo "$PRODUCTS" | jq -r ".[$index].productCode")
    echo "$name|$code"
}

# ============ 日志函数 =============
log() {
    local level="$1"
    local message="$2"
    local color=""
case "$level" in
    "INFO")
        color="$NC"
        ;;
    "DEBUG")
        [[ "$DEBUG" == true ]] || return
        color="$GRAY"
        ;;
    "WARNING")
        color="$YELLOW"
        ;;
    "ERROR")
        color="$RED"
        ;;
    "SUCCESS")
        color="$GREEN"
        ;;
    *)
        color="$NC"
        ;;
esac
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')][$level] ${message}${NC}"
}

debug()   { log "DEBUG" "$1"; }
info()    { log "INFO" "$1"; }
warning() { log "WARNING" "$1"; }
error()   { log "ERROR" "$1"; }
success() { log "SUCCESS" "$1"; }

# ============ ASCII Art =============
show_ascii_jb() {
    cat <<'EOF'
JJJJJJ   EEEEEEE   TTTTTTTT  BBBBBBB    RRRRRR    AAAAAA    IIIIIIII  NNNN   NN   SSSSSS
   JJ    EE           TT     BB    BB   RR   RR   AA  AA       II     NNNNN  NN  SS
   JJ    EE           TT     BB    BB   RR   RR   AA  AA       II     NN NNN NN   SS
   JJ    EEEEE        TT     BBBBBBB    RRRRRR    AAAAAA       II     NN  NNNNN    SSSSS
   JJ    EE           TT     BB    BB   RR   RR   AA  AA       II     NN   NNNN         SS
JJ JJ    EE           TT     BB    BB   RR   RR   AA  AA       II     NN    NNN          SS
 JJJJ    EEEEEEE      TT     BBBBBBB    RR   RR   AA  AA    IIIIIIII  NN    NNN    SSSSSS
EOF
}

# ============ 删除工作目录 =============
do_delete_work_dir() {
    if [[ "${dir_work}" == "/" || -z "${dir_work}" ]]; then
        error "检测到非法路径: ${dir_work}，请检查配置。"
        exit 1
    fi

    if [ -d "${dir_work}" ]; then
        rm -rf "${dir_work}" || {
            error "文件被占用，请先关闭所有Jetbrains IDE后再试！"
            exit 1
        }
    fi
    debug "删除工作目录: ${dir_work}"
}

# ============ 清理并更新 .vmoptions 文件 =============
clean_vmoptions() {
    local file="$1"
    if [ ! -f "$file" ]; then
        debug "清理vm: 文件不存在，跳过清理: $file"
        return 0
    fi

    local temp_lines=()
    local keywords=(
        "-javaagent"
        "--add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED"
        "--add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED"
    )

    while IFS= read -r line; do
        local matched=false
        for keyword in "${keywords[@]}"; do
            [[ "$line" == *"$keyword"* ]] && matched=true && break
        done
        [[ "$matched" == false ]] && temp_lines+=("$line")
    done < "$file"

    printf "%s\n" "${temp_lines[@]}" > "$file"
    debug "清理vm: $file"
}

# ============ 生成激活码 =============
delete_license() {
    local obj_product_name="$1"
    local obj_product_code="$2"
    local dir_product_name="$3"
    local file_license="${dir_config_jb}/${dir_product_name}/${obj_product_name}.key"

    [ -f "$file_license" ] && rm -f "$file_license"
    debug "删除key: $file_license"
}

# ============ 处理单个 Jetbrains 产品 =============
handle_jetbrains_dir() {
    local dir="$1"
    local dir_product_name=$(basename "$dir")
    local obj_product_name=""
    local obj_product_code=""

    for ((i = 0; i < $(echo "$PRODUCTS" | jq length); i++)); do
        IFS='|' read -r name code <<< "$(parse_product_from_json "$i")"
        local lowercase_dir=$(echo "${dir_product_name}" | tr '[:upper:]' '[:lower:]')
        if [[ "$lowercase_dir" == *"$name"* ]]; then
            obj_product_name="$name"
            obj_product_code="$code"
            break
        fi
    done

    [ -z "$obj_product_name" ] && return

    info "处理: ${dir_product_name}"

    local file_home="${dir}/.home"
    [ -f "$file_home" ] || {
        warning "未找到 ${dir_product_name} 的 .home 文件"
        return
    }

    debug ".home路径: $file_home"

    local install_path=$(cat "$file_home")
    [ -d "$install_path" ] || {
        warning "未找到 ${dir_product_name} 的安装路径！"
        return
    }

    debug ".home内容: $install_path"

    local dir_bin="${install_path}/bin"
    [ -d "$dir_bin" ] || {
        warning "${dir_product_name} 的 bin 目录不存在，请确认是否正确安装！"
        return
    }

    local dir_config_product="${dir_config_jb}/${dir_product_name}"

    # 先查找所有 .vmoptions 文件
    files=("${dir_config_product}"/*${FILE_VMOPTIONS})

    # 判断是否真的找到了文件
    if [[ -f "${files[0]}" ]]; then
      for file_vmoption in "${files[@]}"; do
        clean_vmoptions "$file_vmoption"
      done
    else
      debug "未找到${dir_product_name} 的.vmoptions文件"
    fi

    # 判断${dir_config_product}/jetbrains_client.vmoptions是否存在，如果不存在则创建一个默认的
   local file_jetbrains_client="${dir_config_product}/jetbrains_client.vmoptions"
    if [  -f "${file_jetbrains_client}" ]; then
       clean_vmoptions "${file_jetbrains_client}"
    fi

    delete_license "$obj_product_name" "$obj_product_code" "$dir_product_name"
}

# ============ 主流程 =============
main() {
    clear
    show_ascii_jb
    info "\r欢迎使用 JetBrains 取消激活工具 | JetBrain"
    warning "脚本日期：2025-7-1 15:12:48"
    error "注意：此脚本将取消激活所有产品！！！"
    warning "请确保激活的软件处于关闭状态，请按回车继续..."
    read -r

    info "处理中，请耐心等待..."

    check_and_install_deps

    if [ ! -d "${dir_config_jb}" ]; then
        error "未找到${dir_config_jb}目录"
        exit 1
    fi

    debug "config目录：${dir_config_jb}"

    do_delete_work_dir

    for dir in "${dir_cache_jb}"/*; do
        [ -d "$dir" ] && handle_jetbrains_dir "$dir"
    done

    info "所有项处理完成，欢迎下次使用！"
    sleep 1
    # [OFFLINE] browser redirect removed
}

main "$@"
# 删除自己
rm -f "${BASH_SOURCE[0]}"
