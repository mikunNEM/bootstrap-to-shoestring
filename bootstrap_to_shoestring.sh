#!/bin/bash

# bootstrap_to_shoestring.sh - Symbol Bootstrap から Shoestring への移行スクリプト
# 誰でも簡単に移行！依存自動インストール、権限エラー解決、初心者向けガイダンス付き。
#
# 使い方:
#   1. スクリプトをダウンロード: curl -O https://github.com/mikunNEM/bootstrap-to-shoestring/raw/main/bootstrap_to_shoestring.sh
#   2. 実行権限: chmod +x ./bootstrap_to_shoestring.sh
#   3. 実行: bash ./bootstrap_to_shoestring.sh [-y]
#      -y: 確認をスキップ（上級者向け）
#
# 必要環境:
#   - OS: Ubuntu/Debian（推奨）、CentOS、macOS
#   - Node.js: v22.16.0 以上
#   - Python: 3.10 以上（推奨: 3.12.10）
#   - ツール: symbol-bootstrap@1.1.11、symbol-shoestring、yq
#   - ディスク: 1GB 以上
#
# 注意:
# - shoestring.ini の [node] は DUAL ノード（features = API | HARVESTER, lightApi = false）で固定。
# - 他のノードタイプ（例：Peer ノード）は、セットアップ後に手動で shoestring.ini を編集。
# - overrides.ini のセクション名は [category.subcategory] 形式（例： [account.user]）で設定。
#
# FAQ:
# - エラー時: setup.log を確認（tail -f ~/work/shoestring/setup.log）
# - 仮想環境欠落: rm -rf ~/work/shoestring/shoestring-env; python3 -m venv ~/work/shoestring/shoestring-env
# - 権限エラー: chmod u+rwx ~/work/shoestring; chown $(whoami):$(whoami) ~/work/shoestring
# - YAMLエラー: head -n 20 ~/work/symbol-bootstrap/target/addresses.yml
# - yqインストール: sudo snap install yq
# - 翻訳エラー: cat ~/work/shoestring/shoestring-env/lib/python3.12/site-packages/shoestring/__main__.py | grep -E -A 10 'lang ='
# - import-bootstrapエラー: python3 -m shoestring import-bootstrap --help
# - setupエラー: cat ~/work/shoestring/setup_shoestring.log
# - shoestring.iniエラー: find /home/mikun/work -name shoestring.ini
# - 日本語サポートブランチ: pip install git+https://github.com/ccHarvestasya/product.git@master
# - pipエラー: pip install --yes --verbose symbol-shoestring > pip.log 2>&1
# - TabError: cat ~/work/shoestring/py_compile.log
# - unexpected EOF: bash -n ./bootstrap_to_shoestring.sh
# - UnboundLocalError: cat ~/work/shoestring/import_bootstrap.log
# - ParsingError: cat /home/mikun/work/shoestring/shoestring-env/shoestring.ini
# - サポート: https://x.com/mikunNEM
#
# 作成者: mikun (@mikunNEM, 2025-06-05)
# バージョン: 2025-06-06-v4

set -eu

source "$(dirname "$0")/utils.sh"

# スクリプトバージョン
SCRIPT_VERSION="2025-06-06-v4"

# グローバル変数
SHOESTRING_DIR=""
SHOESTRING_DIR_DEFAULT="$HOME/work/shoestring"
BOOTSTRAP_DIR_DEFAULT="$HOME/work/symbol-bootstrap/target"
BACKUP_DIR_DEFAULT="$HOME/symbol-bootstrap-backup-$(date +%Y%m%d_%H%M%S)"
ENCRYPTED=false
SKIP_CONFIRM=false

# コマンドライン引数
while [ $# -gt 0 ]; do
    case "$1" in
        -y) SKIP_CONFIRM=true ;;
        *) error_exit "不明なオプション: $1" ;;
    esac
    shift
done

# --- 前半: 初期化、依存インストール、ディレクトリ検出 ---

# ディレクトリ権限の修正
fix_dir_permissions() {
    local dir="$1"
    print_info "Checking and fixing permissions for $dir..."
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || error_exit "Failed to create directory $dir"
        print_success "Created directory $dir!"
    fi
    if ! touch "$dir/.write_test" 2>/dev/null; then
        print_warning "$dir に書き込み権限がないよ。修正するね！"
        chmod u+rwx "$dir" || error_exit "Failed to change permissions of $dir"
        chown "$(whoami):$(whoami)" "$dir" || error_exit "Failed to change owner of $dir"
        if ! touch "$dir/.write_test" 2>/dev/null; then
            error_exit "Failed to fix permissions for $dir. Check manually: chmod u+rwx $dir"
        fi
        print_success "Fixed permissions for $dir!"
    fi
    rm -f "$dir/.write_test"
}

# 依存のインストール
install_dependencies() {
    print_info "必要なツールをチェック＆インストールするよ！"
    log "Running bootstrap_to_shoestring.sh version: $SCRIPT_VERSION" "INFO"
    
    # OS 検出
    local os_name="unknown"
    if [ -f /etc/os-release ]; then
        os_name=$(grep -E '^ID=' /etc/os-release | awk -F= '{print $2}' | tr -d '"')
    elif [ "$(uname -s)" = "Darwin" ]; then
        os_name="macos"
    fi
    print_info "OS: $os_name"

    # Node.js と npm
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        print_warning "Node.js または npm が見つからないよ。インストールするね！"
        case $os_name in
            ubuntu|debian)
                retry_command "sudo apt update"
                retry_command "sudo apt install -y nodejs npm"
                ;;
            centos)
                retry_command "sudo yum install -y nodejs npm"
                ;;
            macos)
                if ! command -v brew >/dev/null 2>&1; then
                    print_info "Homebrew をインストール..."
                    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                fi
                retry_command "brew install node"
                ;;
            *)
                error_exit "サポートされていないOS: $os_name。Node.js をインストールしてね: https://nodejs.org"
                ;;
        esac
    fi
    local node_version=$(node -v)
    print_info "Node.js: $node_version"

    # Python
    if ! command -v python3 >/dev/null 2>&1; then
        print_warning "Python3 が見つからないよ。インストールするね！"
        case $os_name in
            ubuntu|debian)
                retry_command "sudo apt update"
                retry_command "sudo apt install -y python3 python3-pip python3-venv"
                ;;
            centos)
                retry_command "sudo yum install -y python3 python3-pip"
                ;;
            macos)
                retry_command "brew install python"
                ;;
            *)
                error_exit "サポートされていないOS: $os_name。Python 3.10 以上をインストールしてね: https://python.org"
                ;;
        esac
    fi
    local python_version=$(python3 --version)
    print_info "Python: $python_version"

    # yq
    if ! command -v yq >/dev/null 2>&1; then
        print_warning "yq が見つからないよ。インストールするね！"
        case $os_name in
            ubuntu|debian)
                retry_command "sudo apt update"
                retry_command "sudo apt install -y jq"
                if ! retry_command "sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"; then
                    print_warning "wget 失敗。特定バージョンで試すよ..."
                    retry_command "sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v4.35.2/yq_linux_amd64"
                fi
                retry_command "sudo chmod +x /usr/local/bin/yq"
                if ! command -v yq >/dev/null 2>&1; then
                    retry_command "sudo curl -fsSL -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v4.35.2/yq_linux_amd64"
                    retry_command "sudo chmod +x /usr/local/bin/yq"
                fi
                if ! command -v yq >/dev/null 2>&1; then
                    print_warning "curl 失敗。snap で試すよ..."
                    retry_command "sudo snap install yq"
                fi
                ;;
            centos)
                retry_command "sudo yum install -y jq"
                retry_command "sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
                retry_command "sudo chmod +x /usr/local/bin/yq"
                ;;
            macos)
                if ! command -v brew >/dev/null 2>&1; then
                    print_info "Homebrew をインストール..."
                    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                fi
                retry_command "brew install yq"
                ;;
            *)
                error_exit "サポートされていないOS: $os_name。yq をインストールしてね: https://github.com/mikefarah/yq"
                ;;
        esac
    fi
    if command -v yq >/dev/null 2>&1; then
        print_info "yq: $(yq --version)"
    else
        print_warning "yq のインストールに失敗。grep で対応するよ"
    fi

    # 仮想環境
    local venv_dir="$SHOESTRING_DIR/shoestring-env"
    print_info "仮想環境パス: $venv_dir"
    fix_dir_permissions "$SHOESTRING_DIR"
    if [ ! -f "$venv_dir/bin/activate" ]; then
        print_info "仮想環境を作成するよ..."
        python3 -m venv "$venv_dir" >> "$SHOESTRING_DIR/setup.log" 2>&1 || error_exit "仮想環境の作成に失敗: $venv_dir"
        source "$venv_dir/bin/activate"
        # pip バージョンチェック
        local pip_version=$(python3 -m pip --version 2>>"$SHOESTRING_DIR/setup.log")
        print_info "pip バージョン: $pip_version"
        retry_command "pip install --upgrade pip" >> "$SHOESTRING_DIR/setup.log" 2>&1 || error_exit "pip のアップグレードに失敗"
        # symbol-shoestring インストール
        retry_command "pip install symbol-shoestring" >> "$SHOESTRING_DIR/setup.log" 2>&1 || error_exit "symbol-shoestring のインストールに失敗"
        # インストール確認
        pip list > "$SHOESTRING_DIR/pip_list.log" 2>&1
        if grep -q symbol-shoestring "$SHOESTRING_DIR/pip_list.log"; then
            print_info "symbol-shoestring インストール済み: $(grep symbol-shoestring "$SHOESTRING_DIR/pip_list.log")"
            local shoestring_version=$(pip show symbol-shoestring | grep Version | awk '{print $2}')
            log "symbol-shoestring version: $shoestring_version" "INFO"
        else
            log "pip list: $(cat "$SHOESTRING_DIR/pip_list.log")" "DEBUG"
            error_exit "symbol-shoestring が未インストール。インストールコマンド: pip install symbol-shoestring"
        fi
        # 翻訳エラー回避
        local main_py="$venv_dir/lib/python3.12/site-packages/shoestring/__main__.py"
        if [ -f "$main_py" ]; then
            cp "$main_py" "$main_py.bak"
            sed -i 's/\t/    /g' "$main_py" 2>>"$SHOESTRING_DIR/setup.log"
            local line_num=$(grep -n 'lang = gettext.translation' "$main_py" | cut -d: -f1 | head -n 1)
            if [ -n "$line_num" ]; then
                sed -i "${line_num},$((line_num+2))d" "$main_py" 2>>"$SHOESTRING_DIR/setup.log"
                sed -i "${line_num}i\    try:" "$main_py" 2>>"$SHOESTRING_DIR/setup.log"
                sed -i "${line_num}a\        lang = gettext.translation('messages', localedir='locale', languages=(os.getenv('LC_MESSAGES', 'en_US').split('.')[0], 'en'))" "$main_py" 2>>"$SHOESTRING_DIR/setup.log"
                sed -i "${line_num}a\        lang.install()" "$main_py" 2>>"$SHOESTRING_DIR/setup.log"
                sed -i "${line_num}a\    except FileNotFoundError:" "$main_py" 2>>"$SHOESTRING_DIR/setup.log"
                sed -i "${line_num}a\        gettext.install('messages')" "$main_py" 2>>"$SHOESTRING_DIR/setup.log"
            else
                log "lang = gettext.translation が見つからない: $(cat "$main_py" | grep -A 5 'lang')" "ERROR"
                error_exit "翻訳エラー回避コードの適用に失敗。$main_py を確認してね: cat $main_py"
            fi
            log "翻訳エラー回避コード適用後: $(grep -A 10 'try:' "$main_py" | head -n 15)" "DEBUG"
            if ! python3 -m py_compile "$main_py" >> "$SHOESTRING_DIR/py_compile.log" 2>&1; then
                print_warning "翻訳エラー回避コードの適用に失敗。バックアップから復元するよ..."
                cp "$main_py.bak" "$main_py"
                log "翻訳エラー回避失敗: $(cat "$main_py" | grep -A 10 'data')" "ERROR"
                log "py_compile エラー: $(cat "$SHOESTRING_DIR/py_compile.log")" "ERROR"
                error_exit "翻訳エラー回避コードの適用に失敗。手動で修正してね: cat $main_py"
            fi
            if grep -q "gettext.install('messages')" "$main_py"; then
                print_info "翻訳エラー回避コードを適用したよ！"
            else
                print_warning "翻訳エラー回避コードの適用に失敗。手動で修正してね: $main_py"
            fi
        else
            print_error "翻訳エラー回避コードの適用失敗。ファイルが見つからないよ: $main_py"
            error_exit "shoestring の __main__.py が見つからない。pip install symbol-shoestring を再実行してね"
        fi
        deactivate
    fi
    print_info "仮想環境: $venv_dir"
}

# リトライコマンド
retry_command() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        print_info "試行 $attempt/$max_attempts: $cmd"
        if eval "$cmd" >> "$SHOESTRING_DIR/setup.log" 2>&1; then
            return 0
        fi
        print_warning "失敗したよ。5秒後に再試行..."
        sleep 5
        ((attempt++))
    done
    error_exit "コマンドに失敗: $cmd"
}

# ディレクトリ自動検出
auto_detect_dirs() {
    print_info "ディレクトリを自動で探すよ！"
    
    # Bootstrap ディレクトリ
    local bootstrap_dirs=(
        "$HOME/work/symbol-bootstrap/target"
        "$HOME/symbol-bootstrap/target"
        "$(find "$HOME" -maxdepth 3 -type d -name target 2>/dev/null | grep symbol-bootstrap | head -n 1)"
    )
    for dir in "${bootstrap_dirs[@]}"; do
        if [ -d "$dir" ] && [ -f "$dir/addresses.yml" ]; then
            BOOTSTRAP_DIR_DEFAULT="$dir"
            print_info "Bootstrap フォルダを検出: $BOOTSTRAP_DIR_DEFAULT"
            break
        fi
    done

    # Shoestring ディレクトリ
    local shoestring_dirs=(
        "$HOME/work/shoestring"
        "$HOME/shoestring"
        "$HOME/shoestring-node"
    )
    for dir in "${shoestring_dirs[@]}"; do
        if [ -d "$dir" ]; then
            SHOESTRING_DIR_DEFAULT="$dir"
            SHOESTRING_DIR="$dir"
            fix_dir_permissions "$SHOESTRING_DIR"
            print_info "Shoestring フォルダを検出: $SHOESTRING_DIR_DEFAULT"
            break
        fi
    done
    if [ -z "$SHOESTRING_DIR" ]; then
        SHOESTRING_DIR="$SHOESTRING_DIR_DEFAULT"
        fix_dir_permissions "$SHOESTRING_DIR"
    fi
}

# ユーザー情報の収集
collect_user_info() {
    print_info "移行に必要な情報を集めるよ！"
    
    if $SKIP_CONFIRM; then
        SHOESTRING_DIR="$SHOESTRING_DIR_DEFAULT"
        BOOTSTRAP_DIR="$BOOTSTRAP_DIR_DEFAULT"
        BACKUP_DIR="$BACKUP_DIR_DEFAULT"
    else
        echo -e "${YELLOW}Shoestring ノードのフォルダパスを入力してね:${NC}"
        echo -e "${YELLOW}デフォルト（Enterで選択）: $SHOESTRING_DIR_DEFAULT${NC}"
        read -r input
        SHOESTRING_DIR=$(expand_tilde "${input:-$SHOESTRING_DIR_DEFAULT}")
        fix_dir_permissions "$SHOESTRING_DIR"

        echo -e "${YELLOW}Bootstrap の target フォルダパスを入力してね:${NC}"
        echo -e "${YELLOW}デフォルト（Enterで選択）: $BOOTSTRAP_DIR_DEFAULT${NC}"
        read -r input
        BOOTSTRAP_DIR=$(expand_tilde "${input:-$BOOTSTRAP_DIR_DEFAULT}")

        echo -e "${YELLOW}バックアップの保存先フォルダを入力してね:${NC}"
        echo -e "${YELLOW}デフォルト（Enterで選択）: $BACKUP_DIR_DEFAULT${NC}"
        read -r input
        BACKUP_DIR=$(expand_tilde "${input:-$BACKUP_DIR_DEFAULT}")
    fi

    validate_dir "$BOOTSTRAP_DIR"
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR" || error_exit "$BACKUP_DIR の作成に失敗"
        print_info "$BACKUP_DIR を作成したよ！"
    fi
    print_info "バックアップフォルダ: $BACKUP_DIR"

    if $SKIP_CONFIRM; then
        ENCRYPTED=false
    else
        if confirm "addresses.yml は暗号化されてる？"; then
            ENCRYPTED=true
            if [ -n "${SYMBOL_BOOTSTRAP_PASSWORD+x}" ]; then
                print_info "環境変数 SYMBOL_BOOTSTRAP_PASSWORD を使うよ"
            else
                echo -e "${YELLOW}addresses.yml のパスワードを入力してね（非表示）:${NC}" >&2
                read -rs password
                echo
                if [ -z "$password" ]; then
                    error_exit "暗号化された addresses.yml にはパスワードが必要だよ"
                fi
                export SYMBOL_BOOTSTRAP_PASSWORD="$password"
            fi
        else
            ENCRYPTED=false
            print_info "addresses.yml は平文だね！"
        fi
    fi
}

# バックアップ作成
create_backup() {
    print_info "大事なファイルをバックアップするよ..."
    local src_dir="$BOOTSTRAP_DIR"
    local files=("addresses.yml" "config-harvesting.properties" "node.key.pem")
    mkdir -p "$BACKUP_DIR"
    for file in "${files[@]}"; do
        if [ -f "$src_dir/$file" ] || [ -f "$src_dir/nodes/node/server-config/resources/$file" ]; then
            cp -r "$src_dir/$file" "$src_dir/nodes/node/server-config/resources/$file" "$BACKUP_DIR/" 2>/dev/null || true
            print_info "$file をバックアップしたよ"
        else
            print_warning "$file が見つからなかったよ"
        fi
    done
    print_info "バックアップ完了: $BACKUP_DIR"
}

# --- 後半: 設定抽出、セットアップ、ガイド ---

# メインアカウントの秘密鍵抽出
extract_main_account() {
    local yml_file="$1"
    print_info "$yml_file からメインアカウントの秘密鍵を取り出すよ"
    
    if [ "$ENCRYPTED" = true ]; then
        print_info "addresses.yml を復号するよ"
        local decrypted_yml="$BOOTSTRAP_DIR/decrypted_addresses.yml"
        printf "%s" "$SYMBOL_BOOTSTRAP_PASSWORD" | symbol-bootstrap decrypt --source "$yml_file" --destination "$decrypted_yml" >> "$SHOESTRING_DIR/setup.log" 2>&1 || error_exit "addresses.yml の復号に失敗"
        yml_file="$decrypted_yml"
    fi

    local main_key
    if command -v yq >/dev/null 2>&1; then
        main_key=$(yq eval '.main' "$yml_file" 2>>"$SHOESTRING_DIR/setup.log")
        if [[ "$main_key" != "null" && -n "$main_key" ]]; then
            echo "$main_key"
            return 0
        fi
    fi

    # grep と sed でフォールバック
    main_key=$(grep -A 1 '^main:' "$yml_file" | tail -n 1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [ -n "$main_key" ]; then
        echo "$main_key"
    else
        error_exit "メインアカウントの秘密鍵が見つからないよ: $yml_file"
    fi
}

# 設定ファイルの検証
validate_ini() {
    local ini_file="$1"
    print_info "$ini_file を検証するよ"
    python3 -c "import configparser; config = configparser.ConfigParser(); config.read('$ini_file')" > "$SHOESTRING_DIR/validate_ini.log" 2>&1 || {
        log "INI 検証エラー: $(cat "$SHOESTRING_DIR/validate_ini.log")" "ERROR"
        error_exit "$ini_file の形式が不正だよ。内容を確認してね: cat $ini_file"
    }
    # ドット形式のセクション名をチェック
    if grep -q '^\[.*\]' "$ini_file" && grep '^\[.*\]' "$ini_file" | grep -qv '\.'; then
        log "Invalid section names: $(grep '^\[.*\]' "$ini_file" | grep -v '\.')" "ERROR"
        error_exit "Invalid section name in $ini_file: must be [category.subcategory]"
    fi
    print_info "$ini_file の形式はOK！"
}

# ホスト抽出
extract_host() {
    local config_file="$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-node.properties"
    local host
    if [ -f "$config_file" ]; then
        host=$(grep -A 10 '^\[localnode\]' "$config_file" | grep '^host' | awk -F '=' '{print $2}' | tr -d ' ' 2>/dev/null)
        if [ -n "$host" ]; then
            echo "$host"
            return
        fi
    fi
    echo "localhost" # デフォルト
}

# ネットワークとノード情報の検出
detect_network_and_roles() {
    local yml_file="$1"
    print_info "ネットワークとノード情報を検出するよ: $yml_file"
    log "Detecting network and roles from $yml_file" "DEBUG"
    
    # ネットワーク検出
    local network_type
    if command -v yq >/dev/null 2>&1; then
        local yq_output=$(mktemp)
        yq eval '.networkType' "$yml_file" > "$yq_output" 2>>"$SHOESTRING_DIR/setup.log"
        network_type=$(cat "$yq_output")
        log "yq raw output for .networkType: $(cat "$yq_output")" "DEBUG"
        rm -f "$yq_output"
        
        if [[ "$network_type" =~ ^[0-9]+$ ]]; then
            log "yq network type: $network_type" "DEBUG"
            if [ "$network_type" = "152" ]; then
                network_type="sai"
            elif [ "$network_type" = "104" ]; then
                network_type="mainnet"
            else
                network_type=""
                log "Invalid networkType: $network_type, falling back" "WARNING"
            fi
        else
            network_type=""
            log "Invalid yq output for .networkType: $network_type, falling back" "WARNING"
        fi
    else
        log "yq not found, skipping yq network detection" "WARNING"
    fi
    
    # フォールバック: config-network.properties
    if [ -z "$network_type" ] && [ -f "$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-network.properties" ]; then
        network_type=$(grep 'identifier' "$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-network.properties" | cut -d'=' -f2 | tr -d ' ' | tr '[:upper:]' '[:lower:]')
        log "Network type from config-network.properties: $network_type" "DEBUG"
        if [ "$network_type" = "testnet" ]; then
            network_type="sai"
        elif [ "$network_type" = "mainnet" ]; then
            network_type="mainnet"
        else
            network_type=""
            log "Invalid network type in config-network.properties: $network_type" "WARNING"
        fi
    fi
    
    # 最終フォールバック: デフォルト
    if [ -z "$network_type" ]; then
        network_type="sai" # デフォルト
        log "Network type set to default: $network_type" "INFO"
    fi
    
    # friendlyName 検出
    local friendly_name
    local config_file="$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-node.properties"
    if [ -f "$config_file" ]; then
        print_info "Extracting friendlyName from $config_file"
        friendly_name=$(grep -A 10 '^\[localnode\]' "$config_file" | grep '^friendlyName' | awk -F '=' '{print $2}' | tr -d ' ' 2>/dev/null)
        log "config-node.properties snippet: $(grep -A 10 '^\[localnode\]' "$config_file" | head -n 15)" "DEBUG"
        if [ -z "$friendly_name" ]; then
            log "friendlyName not found in $config_file, falling back to default" "WARNING"
            friendly_name="mikun-testnet-node"
        fi
    else
        log "$config_file not found, using default" "WARNING"
        friendly_name="mikun-testnet-node"
    fi
    log "Extracted - friendlyName: $friendly_name" "DEBUG"
    
    # friendly_name が空の場合、デフォルトを設定
    if [ -z "$friendly_name" ]; then
        friendly_name="mikun-testnet-node"
        log "friendly_name set to default: $friendly_name" "INFO"
    fi
    
    # 出力
    echo "$network_type $friendly_name"
}

# Shoestring ノードのセットアップ
setup_shoestring() {
    local main_key="$1"
    print_info "Shoestring ノードをセットアップするよ"
    
    source "$SHOESTRING_DIR/shoestring-env/bin/activate" || error_exit "仮想環境の有効化に失敗"
    
    # shoestring サブディレクトリ作成
    local shoestring_subdir="$SHOESTRING_DIR/shoestring"
    mkdir -p "$shoestring_subdir" || error_exit "$shoestring_subdir の作成に失敗"
    fix_dir_permissions "$shoestring_subdir"
    
    # ネットワークとノード情報検出
    local network_type friendly_name
    IFS=' ' read -r network_type friendly_name <<< "$(detect_network_and_roles "$ADDRESSES_YML")"
    print_info "検出したネットワーク: $network_type, ノード名: $friendly_name"
    log "Parsed - network_type: $network_type, friendly_name: $friendly_name" "DEBUG"
    
    # ホスト抽出
    local host_name
    host_name=$(extract_host)
    print_info "検出したホスト: $host_name"
    
    # ネットワーク設定の動的生成
    local network_config nodewatch_url
    if [ "$network_type" = "mainnet" ]; then
        network_config=$(cat << EOF
[network]
name = mainnet
identifier = 104
epochAdjustment = 1615853185
generationHashSeed = 57F7DA205008026C776CB6AED843393F04CD458E0AA2D9F1D5F31A402072B2D6
EOF
        )
        nodewatch_url="https://nodewatch.symbol.tools/mainnet"
    else
        network_config=$(cat << EOF
[network]
name = testnet
identifier = 152
epochAdjustment = 1667250467
generationHashSeed = 49D6E1CE276A85B70EAFE52349AACCA389302E7A9754BCF1221E79494FC665A4
EOF
        )
        network_type="sai" # デフォルトは testnet
        nodewatch_url="https://nodewatch.symbol.tools/testnet"
    fi
    
    # shoestring.ini の初期化
    local config_file="$SHOESTRING_DIR/shoestring-env/shoestring.ini"
    print_info "shoestring.ini を初期化するよ"
    log "python3 -m shoestring init \"$config_file\" --package $network_type" "DEBUG"
    python3 -m shoestring init "$config_file" --package "$network_type" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' > "$SHOESTRING_DIR/install_shoestring.log" 2>&1 || {
        log "init エラー: $(cat "$SHOESTRING_DIR/install_shoestring.log")" "ERROR"
        error_exit "shoestring.ini の初期化に失敗。手動で確認してね: python3 -m shoestring init $config_file"
    }
    
    # shoestring.ini 編集
    print_info "shoestring.ini を編集するよ"
    cat > "$config_file" << EOF
$network_config

[images]
client = symbolplatform/symbol-server:gcc-1.0.3.8
rest = symbolplatform/symbol-rest:2.5.0
mongo = mongo:7.0.17

[services]
nodewatch = $nodewatch_url

[transaction]
feeMultiplier = 100
timeoutHours = 2
minCosignaturesCount = 0
hashLockDuration = 1440
currencyMosaicId = 0x72C0212E67A08BCE
lockedFundsPerAggregate = 10000000

[imports]
harvester = $shoestring_subdir/config-harvesting.properties
voter = 
nodeKey =

[node]
main_private_key = $main_key
features = API | HARVESTER
userId = 1000
groupId = 1000
caPassword = 
apiHttps = true
lightApi = false
caCommonName = CA $friendly_name
nodeCommonName = $friendly_name
EOF
    log "shoestring.ini 内容: $(cat "$config_file")" "DEBUG"
    validate_ini "$config_file"
    if ! $SKIP_CONFIRM; then
        echo -e "${YELLOW}shoestring.ini の内容を確認してね:${NC}"
        cat "$config_file"
        if ! confirm "この設定で大丈夫？"; then
            error_exit "shoestring.ini を手動で修正して再実行してね: nano $config_file"
        fi
    fi
    print_info "shoestring.ini を生成: $config_file"
    
    # overrides.ini の作成
    local overrides_file="$shoestring_subdir/overrides.ini"
    print_info "overrides.ini を生成するよ"
    if [ -f "$overrides_file" ]; then
        mv "$overrides_file" "$overrides_file.bak-$(date +%Y%m%d_%H%M%S)"
        print_info "既存の overrides.ini をバックアップ: $overrides_file.bak"
    fi
    cat > "$overrides_file" << EOF
# User account settings
[account.user]
enableDelegatedHarvestersAutoDetection = YES
# Harvesting settings
[harvesting.node]
maxUnlockedAccounts = 4
beneficiaryAddress = 
# Node settings
[node.node]
minFeeMultiplier = 100
language = en
# Local node settings
[localnode.node]
host = $host_name
friendlyName = $friendly_name
EOF
    log "overrides.ini 内容: $(cat "$overrides_file")" "DEBUG"
    log "overrides.ini sections: $(grep '^\[' "$overrides_file")" "DEBUG"
    validate_ini "$config_file"
    if ! $SKIP_CONFIRM; then
        echo -e "${YELLOW}overrides.ini の内容を確認してね:${NC}"
        cat "$overrides_file"
        if ! confirm "この設定で大丈夫？"; then
            error_exit "overrides.ini を手動で調整して再実行してね: nano $config_file"
        fi
    fi
    print_info "overrides.ini を生成: $BACKUP_DIR"

    # 必要ファイルのコピー
    print_info "Bootstrap のデータをコピーするよ"
    local src_harvesting="$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-harvesting.properties"
    if [ -f "$src_harvesting" ]; then
        cp "$src_harvesting" "$shoestring_subdir/" || error_exit "Failed to copy config-harvesting.properties"
        print_info "config-harvesting.properties をコピー: $shoestring_subdir"
    else
        error_exit "config-harvesting.properties が見つからないよ: $src_harvesting"
    fi
    
    # import-bootstrap 実行
    print_info "Bootstrap のデータをインポートするよ"
    log "python3 -m shoestring import-bootstrap \"$@\" --config \"$config_file\" --bootstrap-dir \"$BOOTSTRAP_DIR\" -- $SHOESTRING_DIR" "DEBUG"
    python3 -m shoestring import-bootstrap bootstrap --config "$config_file" --bootstrap-dir "$BOOTSTRAP_DIR" "$SHOESTRING_DIR" | sed 's/\x1B\[.*\]//g' "$@" > "$SHOESTRING_DIR/import-bootstrap.log" 2>&1 || {
        log "import-bootstrap エラー: $(cat "$SHOESTRING_DIR/import-bootstrap.log")" "ERROR"
        print_warning "import-bootstrap に失敗したかったけど、ファイルはコピー済みだから続行するよ"
    }
    
    # CA秘密鍵のパス
    local ca_key_path="$SHOESTRING_DIR/resources/ca.key.pem"
    
    print_info "Shoestring のセットアップを実行するよ"
    log "python3 -m shoestring setup \"$@\" --config-file \"$config_file\" --ca-key \"$ca_key_path\" --override-dir \"$overrides_file\" --dir \"$SHOESTRING_DIR\" --pkg $network_type" "DEBUG"
    python3 -m shoestring setup --config-file "$config_file" --ca-key "$ca_key_path" --override-dir "$overrides_file" --dir "$SHOESTRING_DIR" --pkg "$network_type" "$@" | sed 's/\x1B\[.*\]//g' "$@" > "$SHOESTRING_DIR/setup_shoestring.log" 2>&1 || {
        log "setup エラー: $(cat "$SHOESTRING_DIR/setup_shoestring.log")" "ERROR"
        log "overrides.ini（エラー時）: $(cat "$overrides_file")" "ERROR"
        error_exit "Shoestring ノードのセットアップに失敗。ログを確認してね: cat $SHOESTRING_DIR/setup_shoestring.log"
    }
    
    deactivate
}

# 移行後のガイド
show_post_migration_guide() {
    print_info "移行が終わった！これからやること："
    echo -e "${GREEN}🎉 Symbol Bootstrap から Shoestring への移行が完了！${NC}"
    echo
    print_info "大事なファイル："
    echo "  🔑 CA秘密鍵: $SHOESTRING_DIR/resources/ca.key.pem"
    echo "  📂 バックアップ: $BACKUP_DIR"
    echo "  📜 ログ: $SHOESTRING_DIR/setup.log"
    echo "  📜 設定: $SHOESTRING_DIR/shoestring-env/shoestring.ini"
    echo "  📜 上書き設定: $SHOESTRING_DIR/shoestring/overrides.ini"
    echo "  🐳 Docker Compose: $SHOESTRING_DIR/docker-compose.yml"
    echo
    print_warning "ca.key.pem は安全な場所にバックアップしてね！"
    print_info "ノードを起動するには:"
    echo "  1. ディレクトリに移動: cd $SHOESTRING_DIR"
    echo "  2. Docker Compose で起動: docker-compose up -d"
    echo "  3. ログを確認: docker-compose logs -f"
    print_info "ノードタイプを変更したい場合: nano $SHOESTRING_DIR/shoestring-env/shoestring.ini で [node] の features や lightApi を編集"
    print_info "overrides.ini のセクション名は [category.subcategory] 形式（例： [account.user]）で設定されています"
    print_info "ログの詳細は確認: tail -f $SHOESTRING_DIR/setup.log"
    print_info "困ったらサポート: https://x.com/mikunNEM"
}

# 主処理
main() {
    print_info "Symbol Bootstrap から Shoestring への移行を始めるよ！"
    log "Starting migration process..." "INFO"
    
    auto_detect_dirs
    install_dependencies
    collect_user_info
    if ! check_utils; then
        error_exit "環境チェックに失敗したよ。ログを確認してね: cat $SHOESTRING_DIR/setup.log"
    fi
    ADDRESSES_YML="$BOOTSTRAP_DIR/addresses.yml"
    SHOESTRING_RESOURCES="$SHOESTRING_DIR/resources"
    LOG_FILE="$SHOESTRING_DIR/setup.log"
    
    validate_file "$ADDRESSES_YML"
    create_backup
    main_private_key=$(extract_main_account "$ADDRESSES_YML")
    print_info "メインアカウントの秘密キーをゲット！"
    setup_shoestring "$main_private_key"
    
    ca_key_pem="$SHOESTRING_RESOURCES/ca.key.pem"
    if [ -f "$ca_key_pem" ]; then
        validate_file "$ca_key_pem"
        print_info "ca.key.pem を生成: $ca_key_pem"
    else
        print_warning "ca.key.pem が見つからないよ。setup_shoestring で生成されてないかも"
    fi
    
    show_post_migration_guide
}

main
