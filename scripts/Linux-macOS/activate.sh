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

# ============ 语言检测 =============
detect_language() {
    local lang=${LANG:-}
    if [[ $lang == zh* ]]; then
        LANGUAGE="zh"
    else
        LANGUAGE="en"
    fi
}
detect_language
# ============ 国际化支持 =============
# 初始化国际化字符串
init_i18n_strings() {
    # processing_env_vars
    processing_env_vars_zh="处理 {0} 环境变量"
    processing_env_vars_en="Processing {0} environment variables"

    # checking_env
    checking_env_zh="检查 [{0}]: {1} = '{2}'"
    checking_env_en="Checking [{0}]: {1} = '{2}'"

    # deleting_env
    deleting_env_zh="删除 [{0}]: {1}"
    deleting_env_en="Deleting [{0}]: {1}"

    # welcome_msg
    welcome_msg_zh="欢迎使用 JetBrains 激活工具 | JetBrain"
    welcome_msg_en="Welcome to JetBrains Activation Tool | JetBrain"

    # script_date
    script_date_zh="脚本日期：2026-1-28"
    script_date_en="Script Date: 2026-1-28"

    # warning_msg
    warning_msg_zh="注意，执行脚本默认会将所有产品全部激活一遍，无论之前是否激活过！！！"
    warning_msg_en="Warning: This script will forcibly re-activate all products!!!"

    # close_products
    close_products_zh="请确保激活的软件处于关闭状态，请按回车继续..."
    close_products_en="Please make sure all JetBrains software is closed, press Enter to continue..."

    # processing
    processing_zh="处理中，请耐心等待..."
    processing_en="Processing, please wait patiently..."

    # processing_configs
    processing_configs_zh="开始处理配置..."
    processing_configs_en="Starting to process configurations..."

    # not_found_dir
    not_found_dir_zh="未找到 {0} 目录!"
    not_found_dir_en="Directory not found: {0}!"

    # processing_product
    processing_product_zh="处理: {0}"
    processing_product_en="Processing: {0}"

    # not_found_home
    not_found_home_zh="未找到 .home 文件: {0}"
    not_found_home_en=".home file not found: {0}"

    # path_not_exist
    path_not_exist_zh="路径不存在: {0}"
    path_not_exist_en="Path does not exist: {0}"

    # not_found_bin
    not_found_bin_zh="未找到 bin 目录: {0}"
    not_found_bin_en="bin directory not found: {0}"

    # config_exists_cleaning
    config_exists_cleaning_zh="{0} 配置文件已存在，正在清理..."
    config_exists_cleaning_en="{0} configuration file already exists, cleaning..."

    # key_exists_cleaning
    key_exists_cleaning_zh="key已存在，正在清理..."
    key_exists_cleaning_en="Key already exists, cleaning..."

    # activation_success
    activation_success_zh="{0} 激活成功！"
    activation_success_en="{0} activated successfully!"

    # manual_activation_required
    manual_activation_required_zh="{0} 需要手动输入激活码！"
    manual_activation_required_en="{0} requires manual activation code entry!"

    # download_failed
    download_failed_zh="下载失败: {0}"
    download_failed_en="Download failed: {0}"

    # request_failed
    request_failed_zh="{0} 请求失败: {1}"
    request_failed_en="{0} request failed: {1}"

    # file_in_use
    file_in_use_zh="文件被占用，请先关闭所有 JetBrains IDE 后再试！"
    file_in_use_en="File is in use, please close all JetBrains IDEs and try again!"

    # processing_completed
    processing_completed_zh="所有项处理结束，现在可以启动 JetBrains IDE 了！"
    processing_completed_en="All items processed. You can now start your JetBrains IDE!"

    # format_error
    format_error_zh="格式错误：请使用 yyyy-MM-dd 格式"
    format_error_en="Format error: Please use yyyy-MM-dd format"

    # invalid_date
    invalid_date_zh="非法日期：{0}"
    invalid_date_en="Invalid date: {0}"

    # reading_config
    reading_config_zh="读取配置文件：{0}, 寻找键：{1}"
    reading_config_en="Reading config file: {0}, looking for key: {1}"

    # found_key
    found_key_zh="找到键 '{0}'，值为 '{1}'"
    found_key_en="Found key '{0}' with value '{1}'"

    # failed_read_config
    failed_read_config_zh="读取配置文件失败：{0}"
    failed_read_config_en="Failed to read config file: {0}"

    # cleaning_vmoptions
    cleaning_vmoptions_zh="清理 VMOptions: {0}"
    cleaning_vmoptions_en="Cleaning VMOptions: {0}"

    # updating_vmoptions
    updating_vmoptions_zh="更新 VMOptions: {0}"
    updating_vmoptions_en="Updating VMOptions: {0}"

    # processing_disabled_plugins
    processing_disabled_plugins_zh="已处理文件: {0} 中com.intellij.modules.ultimate项"
    processing_disabled_plugins_en="Processed file: {0} com.intellij.modules.ultimate item"

    # file_not_exist_skip
    file_not_exist_skip_zh="文件不存在,跳过: {0}"
    file_not_exist_skip_en="File does not exist, skipping: {0}"

    # error_processing_plugins
    error_processing_plugins_zh="处理禁用插件文件时出错: {0}"
    error_processing_plugins_en="Error processing disabled plugins file: {0}"

    # processing_config
    processing_config_zh="处理配置: {0}, {1}, {2}"
    processing_config_en="Processing config: {0}, {1}, {2}"

    # requesting_key
    requesting_key_zh="请求key: {0},请求body: {1},保存地址: {2}"
    requesting_key_en="Requesting key: {0}, request body: {1}, save path: {2}"

    # writing_key
    writing_key_zh="写入key,激活中: {0}"
    writing_key_en="Writing key, activating: {0}"

    # source_address
    source_address_zh="源ja-netfilter项目地址: https://gitee.com/ja-netfilter/ja-netfilter/releases/tag/2025.3.0"
    source_address_en="Source ja-netfilter address: https://gitee.com/ja-netfilter/ja-netfilter/releases/tag/2025.3.0"

    # source_privacy
    source_privacy_zh="源 privacy.jar 地址: https://gitea.998043.xyz/novice/plugin-privacy/releases/tag/release"
    source_privacy_en="Source privacy.jar address: https://gitea.998043.xyz/novice/plugin-privacy/releases/tag/release"

    # suggest_check_sha1
    suggest_check_sha1_zh="如需检查下载的.jar是否被篡改请核对sha1的值是否与源项目文件一致"
    suggest_check_sha1_en="It is recommended to verify the SHA1 value to ensure integrity"

    # configuring_ja_netfilter
    configuring_ja_netfilter_zh="配置 ja-netfilter..."
    configuring_ja_netfilter_en="Configuring ja-netfilter..."

    # custom_license_name
    custom_license_name_zh="自定义授权名称 (回车默认 JetBrain)"
    custom_license_name_en="Custom license name (Press Enter to use the default JetBrain)"

    # custom_expiry_date
    custom_expiry_date_zh="自定义授权日期 (回车默认 2099-12-31, 格式 yyyy-MM-dd)"
    custom_expiry_date_en="Custom expiration date (Press Enter to use the default 2099-12-31, format yyyy-MM-dd)"

    # default_license_name
    default_license_name="JetBrain"

    # default_expiry_date
    default_expiry_date="2099-12-31"

    # file_path_empty
    file_path_empty_zh="文件路径为空，跳过处理"
    file_path_empty_en="File path is empty, skipping processing"

    # found_home_file
    found_home_file_zh="找到.home文件: {0}"
    found_home_file_en="Found .home file: {0}"

    # read_home_content
    read_home_content_zh="读取.home文件内容: {0}"
    read_home_content_en="Read .home file content: {0}"

    # found_bin_dir
    found_bin_dir_zh="找到bin目录: {0}"
    found_bin_dir_en="Found bin directory: {0}"

    # sha1_info
    sha1_info="{0} :sha1: {1}"

    # request_fail
    request_fail_zh="请求失败: {0}"
    request_fail_en="Request failed: {0}"

    # all_deps_installed
    all_deps_installed_zh="所有依赖已安装。"
    all_deps_installed_en="All dependencies are installed."

    # missing_deps
    missing_deps_zh="缺少以下依赖：{0}，正在尝试自动安装..."
    missing_deps_en="Missing dependencies: {0}, trying to install automatically..."

    # homebrew_not_found
    homebrew_not_found_zh="检测到 macOS但未安装 Homebrew"
    homebrew_not_found_en="Detected macOS but Homebrew is not installed"

    # install_homebrew_prompt
    install_homebrew_prompt_zh="是否要自动安装 Homebrew?(y/n) "
    install_homebrew_prompt_en="Do you want to install Homebrew automatically? (y/n) "

    # installing_homebrew
    installing_homebrew_zh="正在安装 Homebrew..."
    installing_homebrew_en="Installing Homebrew..."

    # homebrew_post_install
    homebrew_post_install_zh="Homebrew 安装后仍不可用，请手动重启终端后重试"
    homebrew_post_install_en="Homebrew is still not available after installation, please restart the terminal and try again"

    # homebrew_required
    homebrew_required_zh="必须安装 Homebrew 才能继续!"
    homebrew_required_en="Homebrew must be installed to continue!"

    # installing_deps_with_brew
    installing_deps_with_brew_zh="使用 Homebrew 安装依赖"
    installing_deps_with_brew_en="Installing dependencies with Homebrew"

    # unrecognized_linux_distro
    unrecognized_linux_distro_zh="无法识别的 Linux 发行版，请手动安装依赖：{0}"
    unrecognized_linux_distro_en="Unrecognized Linux distribution, please manually install dependencies: {0}"

    # unsupported_os
    unsupported_os_zh="不支持的操作系统"
    unsupported_os_en="Unsupported operating system"

    # install_failed
    install_failed_zh="安装失败：{0}"
    install_failed_en="Installation failed: {0}"

    # all_deps_installed_success
    all_deps_installed_success_zh="所有依赖已成功安装！"
    all_deps_installed_success_en="All dependencies have been successfully installed!"

    # env_cleanup_start
    env_cleanup_start_zh="开始清理 JetBrains 相关环境变量"
    env_cleanup_start_en="Start cleaning JetBrains related environment variables"

    # no_env_files_found
    no_env_files_found_zh="未找到任何环境变量文件,跳过"
    no_env_files_found_en="No environment variable files found, skipping"

    # file_not_writable
    file_not_writable_zh="文件 {0} 不可写，跳过修改"
    file_not_writable_en="File {0} is not writable, skipping modification"

    # backup_env_file
    backup_env_file_zh="备份环境变量文件: {0}, {1}, {2}"
    backup_env_file_en="Backup environment variable file: {0}, {1}, {2}"

    # removing_env_var
    removing_env_var_zh="删除环境变量: {0},{1}"
    removing_env_var_en="Removing environment variable: {0},{1}"

    # other_tools_env_cleanup
    other_tools_env_cleanup_zh="清理三方工具环境变量完成"
    other_tools_env_cleanup_en="Cleanup of third-party tool environment variables completed"

    # enter_license_name
    enter_license_name_zh="自定义授权名称 (回车默认 JetBrain): "
    enter_license_name_en="Custom license name (Enter for default JetBrain): "

    # enter_expiry_date
    enter_expiry_date_zh="自定义授权日期 (回车默认 {0}, 格式 yyyy-MM-dd): "
    enter_expiry_date_en="Custom expiration date (Enter for default {0}, format yyyy-MM-dd): "

    # entered_expiry_date
    entered_expiry_date_zh="输入的授权日期: {0}"
    entered_expiry_date_en="Entered expiration date: {0}"

    # invalid_date_format
    invalid_date_format_zh="日期格式不合法，请输入正确的 yyyy-MM-dd 格式(例如：2099-12-31)"
    invalid_date_format_en="Invalid date format, please enter the correct yyyy-MM-dd format (e.g. 2099-12-31)"

    # illegal_path_detected
    illegal_path_detected_zh="检测到非法路径: {0}，请检查配置。"
    illegal_path_detected_en="Illegal path detected: {0}, please check configuration."

    # creating_work_dirs
    creating_work_dirs_zh="创建工作目录: {0}"
    creating_work_dirs_en="Creating work directories: {0}"

    # download_progress
    download_progress_zh="正在下载: {0} -> {1}"
    download_progress_en="Downloading: {0} -> {1}"

    # sha1_verification_skipped
    sha1_verification_skipped_zh="未找到 {0} 工具，跳过 SHA-1 校验"
    sha1_verification_skipped_en="{0} tool not found, skipping SHA-1 verification"

    # cleaning_vm_file
    cleaning_vm_file_zh="清理vm: {0}"
    cleaning_vm_file_en="Cleaning vm: {0}"

    # cleaning_vm_file_not_exist
    cleaning_vm_file_not_exist_zh="清理vm: 文件不存在，跳过清理: {0}"
    cleaning_vm_file_not_exist_en="Cleaning vm: File does not exist, skipping cleanup: {0}"

    # generating_vm_file
    generating_vm_file_zh="生成vm: {0}"
    generating_vm_file_en="Generating vm: {0}"

    # generating_vm_file_failed
    generating_vm_file_failed_zh="生成vm: 创建失败: {0}"
    generating_vm_file_failed_en="Generating vm: Failed to create: {0}"

    # processing_disabled_plugins_file
    processing_disabled_plugins_file_zh="已处理文件 {0} 中com.intellij.modules.ultimate 项"
    processing_disabled_plugins_file_en="Processed com.intellij.modules.ultimate item in file {0}"

    # url_license_params
    url_license_params="URL_LICENSE:{0},params:{1},save_path:{2}"

    # home_path
    home_path_zh=".home路径: {0}"
    home_path_en=".home path: {0}"

    # home_content
    home_content_zh=".home内容: {0}"
    home_content_en=".home content: {0}"

    # bin_dir_not_exist
    bin_dir_not_exist_zh="{0} 的 bin 目录不存在，请确认是否正确安装！"
    bin_dir_not_exist_en="The bin directory of {0} does not exist, please confirm if it is installed correctly!"

    # vmoptions_not_found_creating
    vmoptions_not_found_creating_zh="未找到{0} 的.vmoptions文件，将创建一个默认的"
    vmoptions_not_found_creating_en=".vmoptions file for {0} not found, will create a default one"

    # config_dir
    config_dir_zh="config目录：{0}"
    config_dir_en="config directory: {0}"

    # dir_not_found
    dir_not_found_zh="未找到{0}目录"
    dir_not_found_en="Directory {0} not found"

    # offline_requires_repo
    offline_requires_repo_zh="已指定 --offline，但未定位到仓库（缺少 ja-netfilter/ 与 server/generate_license.py）！请到仓库内运行或改用环境变量指定离线资源。"
    offline_requires_repo_en="-offline specified but the repo was not found (missing ja-netfilter/ and server/generate_license.py)! Run inside the repo or set the OFFLINE_* env vars instead."

    # python_not_found
    python_not_found_zh="未找到 Python（需要 3.8+），离线模式需要 Python 生成本地许可证！"
    python_not_found_en="Python 3.8+ not found; offline mode requires Python to generate local licenses!"
}

# 获取国际化字符串
get_i18n_string() {
    local key="$1"
    local var_name="${key}_${LANGUAGE}"

    # 使用间接引用获取变量值
    if [[ -n "${!var_name}" ]]; then
        echo "${!var_name}"
    else
        # 如果找不到对应语言的字符串，返回键名本身
        echo "${!key}"
    fi
}

# 格式化字符串（最多支持3个参数）
format_string() {
    local template="$1"
    local arg1="$2"
    local arg2="$3"
    local arg3="$4"

    # 替换 {0}, {1}, {2} 占位符
    local result="$template"
    result="${result//\{0\}/$arg1}"
    result="${result//\{1\}/$arg2}"
    result="${result//\{2\}/$arg3}"

    echo "$result"
}

# 初始化国际化字符串字典
init_i18n_strings

# ============ 配置 =============
DEBUG=false
ENABLE_COLOR=true

URL_BASE="http://localhost:10768"
URL_DOWNLOAD="${URL_BASE}/ja-netfilter"
URL_LICENSE="${URL_BASE}/generateLicense/file"

# 离线模式。判定优先级：显式环境变量 > --offline 参数 > 自动检测仓库位置。
#   OFFLINE_RESOURCES_DIR   仓库内 ja-netfilter/ 目录，资源改从本地复制而非 HTTP
#   OFFLINE_LICENSES_DIR    预生成许可证目录（内嵌 licenses/<name>.key，目标机器无需 Python）
#   OFFLINE_LICENSE_CMD     python 可执行程序（仅仓库内 Python 离线模式需要）
#   OFFLINE_LICENSE_SCRIPT  离线许可证生成器 server/generate_license.py（同上）
# 自动检测与 --offline 参数解析在下方“离线模式解析”执行（需等 error 函数定义完成）。
OFFLINE_RESOURCES_DIR="${OFFLINE_RESOURCES_DIR:-}"
OFFLINE_LICENSES_DIR="${OFFLINE_LICENSES_DIR:-}"
OFFLINE_LICENSE_CMD="${OFFLINE_LICENSE_CMD:-}"
OFFLINE_LICENSE_SCRIPT="${OFFLINE_LICENSE_SCRIPT:-}"

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
dir_config="${dir_work}/config"
dir_plugins="${dir_work}/plugins"
dir_backups="${dir_work}/backups"
file_netfilter_jar="${dir_work}/ja-netfilter.jar"

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

# 产品列表（name|productCode）
PRODUCTS=(
    "idea|II,PCWMP,PSI"
    "clion|CL,PSI,PCWMP"
    "phpstorm|PS,PCWMP,PSI"
    "goland|GO,PSI,PCWMP"
    "pycharm|PC,PSI,PCWMP"
    "webstorm|WS,PCWMP,PSI"
    "rider|RD,PDB,PSI,PCWMP"
    "datagrip|DB,PSI,PDB"
    "rubymine|RM,PCWMP,PSI"
    "appcode|AC,PCWMP,PSI"
    "dataspell|DS,PSI,PDB,PCWMP"
    "rustrover|RR,PSI,PCWP"
)

# ============ 工具函数 =============

# ============ 日期验证 =============
check_and_install_deps() {
    local deps=("curl")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        info "all_deps_installed"
        return
    fi

    local missing_str=$(IFS=", "; echo "${missing[*]}")
    warning "missing_deps" "$missing_str"

    # 先检测系统类型
    case "$(uname -s)" in
        Darwin)
          # 检测 Homebrew 是否存在
          if ! command -v brew &>/dev/null; then
              warning "homebrew_not_found"
              local prompt_msg=$(get_i18n_string "install_homebrew_prompt")
              read -p "$prompt_msg" install_brew
              if [[ "$install_brew" =~ [yY] ]]; then
                  info "installing_homebrew"
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
                      error "homebrew_post_install"
                      exit 1
                  fi
              else
                  error "homebrew_required"
                  exit 1
              fi
          fi

          # 安装依赖
          info "installing_deps_with_brew"
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
                error "unrecognized_linux_distro" "$missing_str"
                exit 1
            fi
            ;;
        *)
            error "unsupported_os"
            exit 1
            ;;
    esac

    # 验证安装结果
    for dep in "${missing[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            error "install_failed" "$dep"
            exit 1
        fi
    done

    success "all_deps_installed_success"
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

debug()   {
    local msg=$(get_i18n_string "$1")
    if [[ $# -gt 1 ]]; then
        msg=$(format_string "$msg" "$2" "$3" "$4")
    fi
    log "DEBUG" "$msg"
}

info()    {
    local msg=$(get_i18n_string "$1")
    if [[ $# -gt 1 ]]; then
        msg=$(format_string "$msg" "$2" "$3" "$4")
    fi
    log "INFO" "$msg"
}

warning() {
    local msg=$(get_i18n_string "$1")
    if [[ $# -gt 1 ]]; then
        msg=$(format_string "$msg" "$2" "$3" "$4")
    fi
    log "WARNING" "$msg"
}

error()   {
    local msg=$(get_i18n_string "$1")
    if [[ $# -gt 1 ]]; then
        msg=$(format_string "$msg" "$2" "$3" "$4")
    fi
    log "ERROR" "$msg"
}

success() {
    local msg=$(get_i18n_string "$1")
    if [[ $# -gt 1 ]]; then
        msg=$(format_string "$msg" "$2" "$3" "$4")
    fi
    log "SUCCESS" "$msg"
}

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

# ============ 清理环境变量 =============
#清理其它工具产留
remove_env_other(){
  OS_NAME=$(uname -s)
  JB_PRODUCTS="idea clion phpstorm goland pycharm webstorm webide rider datagrip rubymine appcode dataspell gateway jetbrains_client jetbrainsclient"

  KDE_ENV_DIR="${USER_HOME}/.config/plasma-workspace/env"

  PROFILE_PATH="${USER_HOME}/.profile"
  ZSH_PROFILE_PATH="${USER_HOME}/.zshrc"
  PLIST_PATH="${USER_HOME}/Library/LaunchAgents/jetbrains.vmoptions.plist"

  if [ $OS_NAME = "Darwin" ]; then
    BASH_PROFILE_PATH="${USER_HOME}/.bash_profile"
  else
    BASH_PROFILE_PATH="${USER_HOME}/.bashrc"
  fi

  touch "${PROFILE_PATH}"
  touch "${BASH_PROFILE_PATH}"
  touch "${ZSH_PROFILE_PATH}"

  MY_VMOPTIONS_SHELL_NAME="jetbrains.vmoptions.sh"
  MY_VMOPTIONS_SHELL_FILE="${USER_HOME}/.${MY_VMOPTIONS_SHELL_NAME}"

  rm -rf "${MY_VMOPTIONS_SHELL_FILE}"

  if [ $OS_NAME = "Darwin" ]; then
    for PRD in $JB_PRODUCTS; do
      ENV_NAME=$(echo $PRD | tr '[a-z]' '[A-Z]')"_VM_OPTIONS"

      launchctl unsetenv "${ENV_NAME}"
    done

    rm -rf "${PLIST_PATH}"
    sed -i '' '/___MY_VMOPTIONS_SHELL_FILE="${HOME}\/\.jetbrains\.vmoptions\.sh"; if /d' "${PROFILE_PATH}" >/dev/null 2>&1
    sed -i '' '/___MY_VMOPTIONS_SHELL_FILE="${HOME}\/\.jetbrains\.vmoptions\.sh"; if /d' "${BASH_PROFILE_PATH}" >/dev/null 2>&1
    sed -i '' '/___MY_VMOPTIONS_SHELL_FILE="${HOME}\/\.jetbrains\.vmoptions\.sh"; if /d' "${ZSH_PROFILE_PATH}" >/dev/null 2>&1
  else
    sed -i '/___MY_VMOPTIONS_SHELL_FILE="${HOME}\/\.jetbrains\.vmoptions\.sh"; if /d' "${PROFILE_PATH}" >/dev/null 2>&1
    sed -i '/___MY_VMOPTIONS_SHELL_FILE="${HOME}\/\.jetbrains\.vmoptions\.sh"; if /d' "${BASH_PROFILE_PATH}" >/dev/null 2>&1
    sed -i '/___MY_VMOPTIONS_SHELL_FILE="${HOME}\/\.jetbrains\.vmoptions\.sh"; if /d' "${ZSH_PROFILE_PATH}" >/dev/null 2>&1
    rm -rf "${KDE_ENV_DIR}/${MY_VMOPTIONS_SHELL_NAME}"
  fi

  debug "other_tools_env_cleanup"
}

remove_env_item_vars() {
    local shell_files=(
        "${USER_HOME}/.bash_profile"
        "${USER_HOME}/.bashrc"
        "${USER_HOME}/.zshrc"
        "${USER_HOME}/.profile"
    )

    # 解析产品
    local product_count=${#PRODUCTS[@]}

    # 先过滤出实际存在的文件
    local existing_files=()
    for file in "${shell_files[@]}"; do
        [ -f "$file" ] && existing_files+=("$file")
    done

    # 如果没有存在的文件则直接返回
    [ ${#existing_files[@]} -eq 0 ] && {
        debug "no_env_files_found"
        return
    }

    # 环境变量备份目录
    local dir_date_backup="$dir_backups/$(date +%s)"
    for file in "${existing_files[@]}"; do
      # 判断文件中是否包含指定环境变量
        if [ ! -w "$file" ]; then
            warning "file_not_writable" "$file" >&2
            continue
        fi

        # 备份环境变量文件到dir_backups/时间
        if [ ! -d "$dir_date_backup" ]; then
            mkdir -p "$dir_date_backup"
        fi

        cp "$file" "${dir_date_backup}/_$(basename ${file})"
        debug "backup_env_file" "$file" "$dir_date_backup" "_$(basename ${file})"

        # 检测环境变量配置文件
        local index=0
        while [ $index -lt $product_count ]; do
            IFS='|' read -r name code <<< "${PRODUCTS[$index]}"

            if [ -z "$name" ]; then
                break
            fi

            local upper_key="$(echo "${name}" | tr '[:lower:]' '[:upper:]')_VM_OPTIONS"
            # 判断file里面是否包含upper_key
            if grep -q "^${upper_key}" "$file"; then
                sed -i -E "/${upper_key}/d" "$file"
                debug "removing_env_var" "$file" "$upper_key"
            fi
            ((index++))
        done
        source "$file"
    done
}

remove_env_vars() {
    info "env_cleanup_start"
    remove_env_item_vars
    # 删除其它激活工具残留
    remove_env_other
}

# ============ 用户输入授权信息 =============
validate_date_format() {
    local input="$1"

    # 第一步：检查是否符合 yyyy-MM-dd 格式
    if [[ ! "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        warning "format_error"
        return 1
    fi

    # 第二步：直接返回原值（无需调用 date 验证真实性）
    echo "$input"
    return 0
}

read_license_info() {
    local enter_license_name_msg=$(get_i18n_string "enter_license_name")
    read -p "$enter_license_name_msg" license_name
    license_name=${license_name:-JetBrain}

    local default_expiry="2099-12-31"
    local expiry_input
    local valid=false

    while [ "$valid" == "false" ]; do
        local enter_expiry_date_msg=$(get_i18n_string "enter_expiry_date")
        read -p "$(format_string "$enter_expiry_date_msg" "$default_expiry") " expiry_input
        expiry_input=${expiry_input:-$default_expiry}
        debug "entered_expiry_date" "$expiry_input"
        if expiry=$(validate_date_format "$expiry_input"); then
            expiry="$expiry"
            valid=true
        else
            warning "invalid_date_format"
        fi
    done

}

# ============ 创建工作目录 =============
do_create_work_dir() {
    if [[ "${dir_work}" == "/" || -z "${dir_work}" ]]; then
        error "illegal_path_detected" "${dir_work}"
        exit 1
    fi

    if [ -d "${dir_work}" ]; then
        rm -rf "${dir_plugins}" "${dir_config}" "${file_netfilter_jar}" || {
            error "file_in_use"
            exit 1
        }
    fi
    mkdir -p "${dir_config}" "${dir_plugins}" "${dir_backups}" || {
         error  "dir_not_found" "${dir_config}"
         exit 1
     }
     debug "creating_work_dirs" "${dir_work}"
}

# ============ 下载文件 =============
download_one_file() {
    local url="$1"
    local file_save_path="$2"
    debug "download_progress" "${url}" "${file_save_path}"

    if [[ "${url}" == file://* ]]; then
        # 离线模式：从本地 ja-netfilter 目录复制
        local src="${url#file://}"
        if [ ! -f "${src}" ]; then
            error "dir_not_found" "$(dirname "${src}")"
            exit 1
        fi
        cp "${src}" "${file_save_path}"
    else
        curl -s -o "${file_save_path}" "${url}"
    fi

    if [ $? -ne 0 ]; then
        error "download_failed" "${url}"
        exit 1
    fi

    if [[ "$file_save_path" == *.jar ]]; then
        local sha1_hash
        if command -v $SHA_TOOL &>/dev/null; then
            sha1_hash=$($SHA_TOOL "$file_save_path" | awk '{print $1}')
        else
            warning "sha1_verification_skipped" "$SHA_TOOL"
            return
        fi
        debug "sha1_info" "$url" "$sha1_hash \n"
    fi
}

progress_bar() {
  # 如果处于DEBUG模式，则不显示进度条
    if [ "$DEBUG" = true ]; then
      return
    fi
    local current=$1
    local total=$2
    local bar_length=30
    local percent=$((current * 100 / total))
    local filled=$((percent * bar_length / 100))
    local bar="["
    bar+=$(printf '#%.0s' $(seq 1 $filled))
    bar+=$(printf '.%.0s' $(seq 1 $((bar_length - filled))))
    bar+="]"
    local configuring_msg=$(get_i18n_string "configuring_ja_netfilter")
    printf "\r%s %d/%d %s %d%%" "$configuring_msg" "$current" "$total" "$bar" "$percent"
}

do_download_resources() {
    local src_prefix="${URL_DOWNLOAD}"
    if [ -n "${OFFLINE_RESOURCES_DIR}" ]; then
        src_prefix="file://${OFFLINE_RESOURCES_DIR}"
        if [ ! -d "${OFFLINE_RESOURCES_DIR}" ]; then
            error "dir_not_found" "${OFFLINE_RESOURCES_DIR}"
            exit 1
        fi
    fi

    local resources=(
        "${src_prefix}/ja-netfilter.jar|${file_netfilter_jar}"
        "${src_prefix}/config/dns.conf|${dir_config}/dns.conf"
        "${src_prefix}/config/env.conf|${dir_config}/env.conf"
        "${src_prefix}/config/native.conf|${dir_config}/native.conf"
        "${src_prefix}/config/power.conf|${dir_config}/power.conf"
        "${src_prefix}/config/url.conf|${dir_config}/url.conf"

        "${src_prefix}/plugins/dns.jar|${dir_plugins}/dns.jar"
        "${src_prefix}/plugins/env.jar|${dir_plugins}/env.jar"
        "${src_prefix}/plugins/native.jar|${dir_plugins}/native.jar"
        "${src_prefix}/plugins/power.jar|${dir_plugins}/power.jar"
        "${src_prefix}/plugins/url.jar|${dir_plugins}/url.jar"
        "${src_prefix}/plugins/hideme.jar|${dir_plugins}/hideme.jar"
        "${src_prefix}/plugins/privacy.jar|${dir_plugins}/privacy.jar"
    )

    local total_files=${#resources[@]}
    local count=0

    debug "source_address"
    debug "source_privacy"
    debug "suggest_check_sha1"

    for item in "${resources[@]}"; do
        IFS='|' read -r url path <<< "$item"
        download_one_file "$url" "$path"
        ((count++))
        progress_bar "$count" "$total_files"
    done
    echo -e "\n"
}

# ============ 清理并更新 .vmoptions 文件 =============
clean_vmoptions() {
    local file="$1"
    if [ ! -f "$file" ]; then
        debug "cleaning_vm_file_not_exist" "$file"
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
    debug "cleaning_vm_file" "$file"
}

append_vmoptions() {
    local file="$1"
    if [ ! -f "$file" ]; then
        touch "$file" || {
            error "generating_vm_file_failed" "$file"
            return
        }
    fi

    cat >> "$file" <<EOF
-javaagent:${file_netfilter_jar}
EOF
    debug "generating_vm_file" "$file"
}


# 读取文件，如果文件中有com.intellij.modules.ultimate，则清空这行
process_disabled_plugins() {
    local file_disabled_plugins="$1"
    # 参数验证
    if [ -z "$file_disabled_plugins" ]; then
        debug "file_path_empty"
        return
    fi

    # 检查文件是否存在
    if [ ! -f "$file_disabled_plugins" ]; then
        debug "file_not_exist_skip" "$file_disabled_plugins"
        return
    fi

    # 直接在原文件中将匹配的行替换为空（即删除该行）
    # 兼容 macOS 和 Linux 上的 sed 命令
    if [[ "$OS" == "macOS" ]]; then
        sed -i '' '/^com.intellij.modules.ultimate$/d' "$file_disabled_plugins"
    else
        sed -i '/^com.intellij.modules.ultimate$/d' "$file_disabled_plugins"
    fi
    debug "processing_disabled_plugins_file" "$file_disabled_plugins"
}

# ============ 生成激活码 =============
generate_license() {
    local obj_product_name="$1"
    local obj_product_code="$2"
    local dir_product_name="$3"
    local file_license="${dir_config_jb}/${dir_product_name}/${obj_product_name}.key"
    local file_disabled_plugins="${dir_config_jb}/${dir_product_name}/disabled_plugins.txt"

    process_disabled_plugins "$file_disabled_plugins"

    [ -f "$file_license" ] && rm -f "$file_license"

    local rc
    if [ -n "${OFFLINE_LICENSES_DIR}" ]; then
        # 预生成许可证模式：直接拷贝内嵌的 <name>.key（目标机器无需 Python、无需输入授权信息）
        if [ -f "${OFFLINE_LICENSES_DIR}/${obj_product_name}.key" ]; then
            cp "${OFFLINE_LICENSES_DIR}/${obj_product_name}.key" "$file_license"
            rc=0
        else
            warning "manual_activation_required" "$dir_product_name"
            return
        fi
    elif [ -n "${OFFLINE_LICENSE_CMD}" ] && [ -n "${OFFLINE_LICENSE_SCRIPT}" ]; then
        # 离线模式：调用本地许可证生成器（不启动服务器）
        "${OFFLINE_LICENSE_CMD}" "${OFFLINE_LICENSE_SCRIPT}" \
            --product-code "$obj_product_code" \
            --license-name "$license_name" \
            --expiry "$expiry" \
            --assignee "" \
            -o "${file_license}"
        rc=$?
    else
        local json_body=$(printf '{"assigneeName":"","expiryDate":"%s","licenseName":"%s","productCode":"%s"}' "$expiry" "$license_name" "$obj_product_code")
        debug "url_license_params" "$URL_LICENSE" "$json_body" "$file_license"
        curl -s -X POST "$URL_LICENSE" \
            -H "Content-Type: application/json" \
            -d "$json_body" \
            -o "$file_license" > /dev/null
        rc=$?
    fi

    if [ ${rc} -eq 0 ]; then
        success "activation_success" "$dir_product_name"
    else
        warning "manual_activation_required" "$dir_product_name"
    fi
}

# ============ 处理单个 Jetbrains 产品 =============
handle_jetbrains_dir() {
    local dir="$1"
    local dir_product_name=$(basename "$dir")
    local obj_product_name=""
    local obj_product_code=""

    for ((i = 0; i < ${#PRODUCTS[@]}; i++)); do
        IFS='|' read -r name code <<< "${PRODUCTS[$i]}"
        local lowercase_dir=$(echo "${dir_product_name}" | tr '[:upper:]' '[:lower:]')
        if [[ "$lowercase_dir" == *"$name"* ]]; then
            obj_product_name="$name"
            obj_product_code="$code"
            break
        fi
    done

    [ -z "$obj_product_name" ] && return

    info "processing_product" "$dir_product_name"

    local file_home="${dir}/.home"
    [ -f "$file_home" ] || {
        warning "not_found_home" "$file_home"
        return
    }

    debug "home_path" "$file_home"

    local install_path=$(cat "$file_home")
    [ -d "$install_path" ] || {
        warning "path_not_exist" "$install_path"
        return
    }

    debug "home_content" "$install_path"

    local dir_bin="${install_path}/bin"
    [ -d "$dir_bin" ] || {
        warning "bin_dir_not_exist" "$dir_product_name"
        return
    }

    local dir_config_product="${dir_config_jb}/${dir_product_name}"

    # 先查找所有 .vmoptions 文件
    files=("${dir_config_product}"/*${FILE_VMOPTIONS})

    # 判断是否真的找到了文件
    if [[ -f "${files[0]}" ]]; then
      for file_vmoption in "${files[@]}"; do
        clean_vmoptions "$file_vmoption"
        append_vmoptions "$file_vmoption"
      done
    else
      debug "vmoptions_not_found_creating" "$dir_product_name"
      append_vmoptions "${dir_config_product}/${obj_product_name}${FILE_VMOPTIONS}"
    fi

    # 判断${dir_config_product}/jetbrains_client.vmoptions是否存在，如果不存在则创建一个默认的
   local file_jetbrains_client="${dir_config_product}/jetbrains_client.vmoptions"
    if [ ! -f "${file_jetbrains_client}" ]; then
        append_vmoptions "${file_jetbrains_client}"
        else
        clean_vmoptions "${file_jetbrains_client}"
        append_vmoptions "${file_jetbrains_client}"
    fi

    generate_license "$obj_product_name" "$obj_product_code" "$dir_product_name"
}

# ============ 离线模式解析 =============
# 离线优先级：显式环境变量 > --offline 参数 > 自动检测仓库位置。
# 自动检测：脚本位于仓库 scripts/Linux-macOS/ 时，其上级两级即仓库根目录。
OFFLINE_FROM_REPO=false
OFFLINE_ARG=false
for offline_arg in "$@"; do
    case "$offline_arg" in
        --offline|-offline) OFFLINE_ARG=true ;;
    esac
done

if [ -z "${OFFLINE_RESOURCES_DIR}" ]; then
    OFFLINE_SCRIPT_DIR=""
    # BASH_SOURCE 在 curl | bash 管道下不可靠（为 - 或 bash），需 -f 守卫
    if [ -n "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" != "-" ] && [ -f "${BASH_SOURCE[0]}" ]; then
        OFFLINE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    fi
    if [ -n "${OFFLINE_SCRIPT_DIR}" ] &&
       [ -d "${OFFLINE_SCRIPT_DIR}/../../ja-netfilter" ] &&
       [ -f "${OFFLINE_SCRIPT_DIR}/../../server/generate_license.py" ]; then
        OFFLINE_RESOURCES_DIR="${OFFLINE_SCRIPT_DIR}/../../ja-netfilter"
        OFFLINE_LICENSE_SCRIPT="${OFFLINE_SCRIPT_DIR}/../../server/generate_license.py"
        OFFLINE_FROM_REPO=true
    elif [ "${OFFLINE_ARG}" = true ]; then
        error "offline_requires_repo"
        exit 1
    fi
fi

if [ -n "${OFFLINE_RESOURCES_DIR}" ] && [ -z "${OFFLINE_LICENSES_DIR}" ] && [ -z "${OFFLINE_LICENSE_CMD}" ]; then
    # 离线需本地 Python 生成许可证（预生成许可证模式下跳过）
    if command -v python3 >/dev/null 2>&1; then
        OFFLINE_LICENSE_CMD="$(command -v python3)"
    elif command -v python >/dev/null 2>&1; then
        OFFLINE_LICENSE_CMD="$(command -v python)"
    else
        error "python_not_found"
        exit 1
    fi
fi
unset OFFLINE_SCRIPT_DIR

# ============ 主流程 =============
main() {
    clear
    show_ascii_jb

    info "welcome_msg"

    warning "script_date"

    error "warning_msg"

    warning "close_products"
    read -r

    if [ -z "${OFFLINE_LICENSES_DIR}" ]; then
        read_license_info
    fi

    info "processing"

    if [ -z "${OFFLINE_RESOURCES_DIR}" ] && [ -z "${OFFLINE_LICENSES_DIR}" ]; then
        check_and_install_deps
    fi

    if [ ! -d "${dir_config_jb}" ]; then
        error "dir_not_found" "${dir_config_jb}"
        exit 1
    fi

    debug "config_dir" "${dir_config_jb}"

    do_create_work_dir

    remove_env_vars

    do_download_resources

    for dir in "${dir_cache_jb}"/*; do
        [ -d "$dir" ] && handle_jetbrains_dir "$dir"
    done

    info "processing_completed"
    sleep 1
    # [OFFLINE] browser redirect removed
}

main "$@"
# 删除自己（仓库自动检测运行时保留仓库内脚本，避免误删；临时副本 / 管道运行仍会自删）
if [ "${OFFLINE_FROM_REPO}" != "true" ]; then
    rm -f "${BASH_SOURCE[0]}"
fi
