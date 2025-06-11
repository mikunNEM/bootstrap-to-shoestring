#!/bin/bash

# bootstrap_to_shoestring.sh - Symbol Bootstrap から Shoestring への移行スクリプト
# 誰でも簡単に移行！依存自動インストール、権限エラー解決、初心者向けガイダンス付き。
#
# 使い方:
#   1. スクリプトをダウンロード: curl -O https://github.com/mikunNEM/bootstrap-to-shoestring/raw/main/bootstrap_to_shoestring.sh
#   2. 実行権限: chmod +x ./bootstrap_to_shoestring.sh
#   3. 実行: bash ./bootstrap_to_shoestring.sh [-y]
#      -y: 確認をスキップ（上級者向け）

# --- Ubuntu バージョンチェック & アップグレード案内 ---
if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [[ "$ID" == "ubuntu" && "${VERSION_ID%%.*}" -eq 20 ]]; then
    echo -e "\e[33m⚠️ 現在の Ubuntu バージョンは $VERSION_ID です。\e[0m"
    echo "Symbol ノードを停止して、Ubuntu 20 → 22.04 にアップグレードしてから再度このスクリプトを実行してください。"
    echo
    echo "  1. ノード停止: cd \$BOOTSTRAP_DIR && docker-compose down"
    echo "  2. システムアップグレード:"
    echo "       sudo apt update && sudo apt upgrade -y"
    echo "       sudo do-release-upgrade -d"
    echo "  3. サーバー再起動後、再ログインしてこのスクリプトを再実行"
    exit 1
  fi
fi

set -eu

# utils.sh をソース（同じディレクトリにあることを確認）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
else
    echo "ERROR: utils.sh が見つかりません。同じディレクトリに utils.sh があることを確認してください。"
    echo "現在のディレクトリ: $SCRIPT_DIR"
    echo "探しています: $SCRIPT_DIR/utils.sh"
    exit 1
fi

# スクリプトバージョン
SCRIPT_VERSION="2025-06-11-v26"

# グローバル変数
SHOESTRING_DIR=""
SHOESTRING_DIR_DEFAULT="$HOME/shoestring"
BOOTSTRAP_DIR=""
BOOTSTRAP_DIR_DEFAULT="$HOME/symbol-bootstrap/target"
BACKUP_DIR=""
BACKUP_DIR_DEFAULT="$HOME/symbol-bootstrap-backup-$(date +%Y%m%d_%H%M%S)"
ENCRYPTED=false
SKIP_CONFIRM=false
NODE_KEY_FOUND=false
LOG_FILE=""
ADDRESSES_YML=""
SHOESTRING_RESOURCES=""

# コマンドライン引数
while [ $# -gt 0 ]; do
    case "$1" in
        -y) SKIP_CONFIRM=true ;;
        *) error_exit "不明なオプション: $1" ;;
    esac
    shift
done

# --- APT ロックファイルのチェックと削除 ---
check_apt_locks() {
    print_info "APT ロックファイルのチェック中..."
    local lock_files=(
        "/var/lib/apt/lists/lock"
        "/var/cache/apt/archives/lock"
        "/var/cache/apt/pkgcache.bin"
        "/var/cache/apt/srcpkgcache.bin"
        "/var/lib/dpkg/lock-frontend"
    )
    for lock in "${lock_files[@]}"; do
        if [ -f "$lock" ]; then
            print_warning "ロックファイル検出: $lock。削除を試みます..."
            sudo rm -f "$lock" || error_exit "ロックファイル $lock の削除に失敗。手動で削除してください: sudo rm -f $lock"
            print_success "ロックファイル $lock を削除しました。"
        fi
    done
    # dpkg の修復
    sudo dpkg --configure -a >> "$LOG_FILE" 2>&1 || print_warning "dpkg の修復に失敗しましたが、続行します。"
}

# ディレクトリ権限の修正
fix_dir_permissions() {
    local dir="$1"
    print_info "Checking and fixing for $dir..."
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

# リトライコマンド（エラーメッセージを詳細に表示）
retry_command() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1
    while [ $attempt -le "$max_attempts" ]; do
        print_info "試行 $attempt/$max_attempts: $cmd"
        if eval "$cmd" >> "$LOG_FILE" 2>&1; then
            return 0
        else
            print_warning "失敗したよ。詳細なエラーログ:"
            tail -n 10 "$LOG_FILE"
            print_warning "5秒後に再試行..."
            sleep 5
            ((attempt++))
        fi
    done
    # apt-get update の場合、command-not-found エラーは無視して続行
    if [[ "$cmd" == *"apt-get update"* ]] && grep -q "command-not-found" "$LOG_FILE"; then
        print_warning "apt-get update で command-not-found エラーが発生しましたが、続行します。"
        return 0
    fi
    error_exit "コマンドに失敗: $cmd。ログを確認してください: cat $LOG_FILE"
}

# 依存のインストール
install_dependencies() {
    print_info "依存ツールをチェック＆インストールするよ"
    log "version $SCRIPT_VERSION" "INFO"

    # OS 判定
    local os_name="unknown"
    if [ -f /etc/os-release ]; then
        os_name=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    elif [ "$(uname -s)" = "Darwin" ]; then
        os_name="macos"
    fi
    print_info "OS: $os_name"

    # Ubuntu/Debian 環境では Python3.12 を導入
    if [[ $os_name == "ubuntu" || $os_name == "debian" ]]; then
        print_info "APT ロックファイルをチェックして削除..."
        check_apt_locks
        retry_command "sudo apt-get install -y python3-apt"
        retry_command "sudo apt-get update"
        retry_command "sudo apt-get install -y software-properties-common"
        retry_command "sudo add-apt-repository --yes ppa:deadsnakes/ppa"
        retry_command "sudo apt-get update"
        retry_command "sudo apt-get install -y python3.12 python3.12-venv python3.12-dev python3-distutils python3-pip build-essential libssl-dev"
        print_info "Checking /etc/alternatives permissions..."
        sudo chown root:root /etc/alternatives
        sudo chmod 755 /etc/alternatives
        if update-alternatives --display python3 2>/dev/null | grep -q "broken"; then
            print_warning "python3 link group is broken. Resetting..."
            sudo update-alternatives --remove-all python3
        fi
        retry_command "sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 2"
        if ! /usr/bin/python3.12 --version 2>/dev/null | grep -q "3.12"; then
            print_warning "Python 3.12 が正しくインストールされていません。再度インストールを試みます..."
            retry_command "sudo apt-get install --reinstall -y python3.12 python3.12-venv"
        fi
        print_info "Python 3.12: $(/usr/bin/python3.12 --version)"
    else
        if [ "$os_name" = "macos" ]; then
            retry_command "brew install python"
        elif [ "$os_name" = "centos" ]; then
            retry_command "yum install -y python3 python3-venv python3-pip"
        fi
    fi
    print_info "Python: $(python3 --version)"

    # Node.js
    if ! command -v node >/dev/null 2>&1; then
        print_warning "Node.js が無いのでインストール"
        case $os_name in
            ubuntu|debian) retry_command "sudo apt-get install -y nodejs npm" ;;
            centos)        retry_command "yum install -y nodejs npm" ;;
            macos)         retry_command "brew install node" ;;
            *)             error_exit "Node.js を手動でインストールしてください。" ;;
        esac
    fi
    print_info "Node.js: $(node -v)"

    # Docker Compose
    if ! command -v docker compose >/dev/null 2>&1; then
        print_warning "Docker Compose が無いのでインストール"
        case $os_name in
            ubuntu|debian) retry_command "sudo apt-get install -y docker-compose-plugin" ;;
            centos)        retry_command "yum install -y docker-compose" ;;
            macos)         retry_command "brew install docker-compose" ;;
            *)             error_exit "Docker Compose を手動でインストールしてください。" ;;
        esac
    fi
    print_info "Docker Compose: $(docker compose version)"

    # pv（進捗表示用、オプション）
    if ! command -v pv >/dev/null 2>&1; then
        print_warning "pv が見つからないよ。データコピーの進捗表示に使うからインストールするね！"
        case $os_name in
            ubuntu|debian)
                check_apt_locks
                retry_command "sudo apt-get update"
                retry_command "sudo apt-get install -y pv"
                ;;
            centos)
                retry_command "sudo yum install -y pv"
                ;;
            macos)
                retry_command "brew install pv"
                ;;
            *)
                print_warning "pv のインストールはスキップ。進捗表示なしでコピーするよ。"
                ;;
        esac
    fi
    if command -v pv >/dev/null 2>&1; then
        print_info "pv: $(pv --version | head -n 1)"
    fi

    # OpenSSL（ca.key.pem 生成用）
    if ! command -v openssl >/dev/null 2>&1; then
        print_warning "OpenSSL が見つからないよ。ca.key.pem 生成に必要だからインストールするね！"
        case $os_name in
            ubuntu|debian)
                check_apt_locks
                retry_command "sudo apt-get update"
                retry_command "sudo apt-get install -y openssl"
                ;;
            centos)
                retry_command "sudo yum install -y openssl"
                ;;
            macos)
                retry_command "brew install openssl"
                ;;
            *)
                error_exit "サポートされていないOS: $os_name。OpenSSL をインストールしてね: https://www.openssl.org/"
                ;;
        esac
    fi
    local openssl_version=$(openssl version)
    print_info "OpenSSL: $openssl_version"

    # 仮想環境
    local venv_dir="$SHOESTRING_DIR/shoestring-env"
    print_info "仮想環境パス: $venv_dir"
    fix_dir_permissions "$SHOESTRING_DIR"
    if [ -d "$venv_dir" ]; then
        print_warning "既存の仮想環境が見つかりました: $venv_dir。削除して再作成します..."
        rm -rf "$venv_dir"
    fi
    if [ ! -f "$venv_dir/bin/activate" ]; then
        print_info "仮想環境を作成するよ..."
        /usr/bin/python3.12 -m venv "$venv_dir" >> "$LOG_FILE" 2>&1 || {
            print_warning "仮想環境の作成に失敗しました。pip なしで再試行します..."
            /usr/bin/python3.12 -m venv --without-pip "$venv_dir" >> "$LOG_FILE" 2>&1 || error_exit "仮想環境の作成に失敗: $venv_dir。ログを確認してください: cat $LOG_FILE"
            source "$venv_dir/bin/activate"
            curl https://bootstrap.pypa.io/get-pip.py -o "$SHOESTRING_DIR/get-pip.py" >> "$LOG_FILE" 2>&1
            /usr/bin/python3.12 "$SHOESTRING_DIR/get-pip.py" >> "$LOG_FILE" 2>&1 || error_exit "pip のインストールに失敗しました。ログを確認してください: cat $LOG_FILE"
            rm -f "$SHOESTRING_DIR/get-pip.py"
        }
        source "$venv_dir/bin/activate"
        local pip_version=$(python3 -m pip --version 2>>"$LOG_FILE")
        print_info "pip バージョン: $pip_version"
        retry_command "pip install --upgrade pip"
        print_info "symbol-shoestring をインストール中…"
        set +e
        pip install symbol-shoestring==0.2.1 >>"$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
            print_warning "symbol-shoestring のビルドに失敗しました。Python 開発ヘッダをインストールします…"
            check_apt_locks
            retry_command "sudo apt-get update"
            retry_command "sudo apt-get install -y python3.12-dev build-essential libssl-dev"
            print_info "再度 symbol-shoestring をインストール中…"
            pip install symbol-shoestring==0.2.1 >>"$LOG_FILE" 2>&1
            if [ $? -ne 0 ]; then
                error_exit "symbol-shoestring の再インストールにも失敗しました。ログを確認してください: cat $LOG_FILE"
            fi
            print_success "symbol-shoestring のインストールに成功しました！"
        else
            print_success "symbol-shoestring のインストールに成功しました！"
        fi
        pip install setuptools >>"$LOG_FILE" 2>&1 || print_warning "setuptools のインストールに失敗しましたが、続行します。"
        set -e
        pip list > "$SHOESTRING_DIR/pip_list.log" 2>&1
        if grep -q symbol-shoestring "$SHOESTRING_DIR/pip_list.log"; then
            print_info "symbol-shoestring インストール済み: $(grep symbol-shoestring "$SHOESTRING_DIR/pip_list.log")"
            local shoestring_version=$(pip show symbol-shoestring | grep Version | awk '{print $2}')
            log "symbol-shoestring version: $shoestring_version" "INFO"
        else
            log "pip list: $(cat "$SHOESTRING_DIR/pip_list.log")" "DEBUG"
            error_exit "symbol-shoestring が未インストール。インストールコマンド: pip install symbol-shoestring"
        fi
        deactivate
    fi
    print_info "仮想環境: $venv_dir"
}

# ディレクトリ自動検出
auto_detect_dirs() {
    print_info "ディレクトリを自動で探すよ！"
    local bootstrap_dirs=(
        "$HOME/symbol-bootstrap/target"
        "$HOME/symbol-bootstrap"
        "$(find "$HOME" -maxdepth 3 -type d -name target 2>/dev/null | grep symbol-bootstrap | head -n 1)"
    )
    for dir in "${bootstrap_dirs[@]}"; do
        if [ -d "$dir" ] && [ -f "$dir/addresses.yml" ]; then
            BOOTSTRAP_DIR_DEFAULT="$dir"
            print_info "Bootstrap フォルダを検出: $BOOTSTRAP_DIR_DEFAULT"
            break
        fi
    done
    local shoestring_dirs=(
        "$HOME/shoestring"
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
        SHOESTRING_DIR="$(expand_tilde "${input:-$SHOESTRING_DIR_DEFAULT}")"
        fix_dir_permissions "$SHOESTRING_DIR"
        echo -e "${YELLOW}Bootstrap の target フォルダパスを入力してね:${NC}"
        echo -e "${YELLOW}デフォルト（Enterで選択）: $BOOTSTRAP_DIR_DEFAULT${NC}"
        read -r input
        BOOTSTRAP_DIR="$(expand_tilde "${input:-$BOOTSTRAP_DIR_DEFAULT}")"
        echo -e "${YELLOW}バックアップの保存先フォルダを入力してね:${NC}"
        echo -e "${YELLOW}デフォルト（Enterで選択）: $BACKUP_DIR_DEFAULT${NC}"
        read -r input
        BACKUP_DIR="$(expand_tilde "${input:-$BACKUP_DIR_DEFAULT}")"
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
    local files=(
        "addresses.yml"
        "nodes/node/server-config/resources/config-harvesting.properties"
        "nodes/node/cert/node.key.pem"
    )
    mkdir -p "$BACKUP_DIR"
    for file in "${files[@]}"; do
        if [ -f "$src_dir/$file" ]; then
            cp -r "$src_dir/$file" "$BACKUP_DIR/" 2>/dev/null || true
            print_info "Backed up $file"
        else
            print_warning "$file not found"
        fi
    done
    print_info "Backup completed: $BACKUP_DIR"
}

# 設定ファイルの検証
validate_ini() {
    local ini_file="$1"
    print_info "$ini_file を検証するよ"
    python3 -c "import configparser; config = configparser.ConfigParser(); config.read('$ini_file')" > "$SHOESTRING_DIR/validate_ini.log" 2>&1 || {
        log "INI 検証エラー: $(cat "$SHOESTRING_DIR/validate_ini.log")" "ERROR"
        error_exit "$ini_file の形式が不正だよ。内容を確認してね: cat $ini_file"
    }
    print_info "$ini_file の形式はOK！"
}

# INIファイルの確認と編集ループ
confirm_and_edit_ini() {
    local ini_file="$1"
    local file_name=$(basename "$ini_file")
    while true; do
        echo -e "${YELLOW}${file_name} の内容を確認してね:${NC}"
        cat "$ini_file"
        if confirm "この設定で大丈夫？ 別のターミナルでINIファイルを編集したら、nを押すと更新が確認出来るよ"; then
            break
        else
            echo -e "${YELLOW}別のターミナルで nano $ini_file を開いて編集して、保存（Ctrl+O, Enter, Ctrl+X）してね！${NC}"
            echo -e "${YELLOW}編集が終わったら、ここで 'y' を押して続行、または 'n' で再編集してね。${NC}"
            validate_ini "$ini_file"
        fi
    done
}

# ホスト抽出
extract_host() {
    local config_file="$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-node.properties"
    local host
    if [ -f "$config_file" ]; then
        host=$(grep -A 10 '^\[localnode\]' "$config_file" | grep '^host' | awk -F '=' '{print $2}' | tr -d ' ')
        if [ -n "$host" ]; then
            echo "$host"
            return
        fi
    fi
    echo "localhost"
}

# ネットワークとノード情報の検出
detect_network_and_roles() {
    print_info "ネットワークとノード情報を検出するよ"
    log "Detecting network and roles from $BOOTSTRAP_DIR" "DEBUG"
    local network_type=""
    if [ -f "$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-network.properties" ]; then
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
    if [ -z "$network_type" ]; then
        network_type="sai"
        log "Network type set to default: $network_type" "INFO"
    fi
    local friendly_name
    local config_file="$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-node.properties"
    if [ -f "$config_file" ]; then
        print_info "Extracting friendlyName from $config_file"
        friendly_name=$(grep -A 10 '^\[localnode\]' "$config_file" | grep '^friendlyName' | awk -F '=' '{print $2}' | tr -d ' ')
        log "config-node.properties snippet: $(grep -A 10 '^\[localnode\]' "$config_file" | head -n 15)" "DEBUG"
        if [ -z "$friendly_name" ]; then
            log "friendlyName not found" "WARNING"
            friendly_name="mikun-$network_type-node"
        fi
    else
        log "$config_file not found" "WARNING"
        friendly_name="mikun-$network_type-node"
    fi
    if [ -z "$friendly_name" ]; then
        friendly_name="mikun-$network_type-node"
        log "friendly_name set to: $friendly_name" "INFO"
    fi
    log "Extracted - friendlyName: $friendly_name" "INFO"
    echo "$network_type $friendly_name"
}

# node.key.pem の存在確認
check_node_key() {
    local node_key_paths=(
        "$BOOTSTRAP_DIR/node.key.pem"
        "$BOOTSTRAP_DIR/nodes/node/server-config/resources/node.key.pem"
        "$BOOTSTRAP_DIR/nodes/node/cert/node.key.pem"
    )
    for path in "${node_key_paths[@]}"; do
        if [ -f "$path" ]; then
            print_info "Bootstrap の node.key.pem を見つけました: $path"
            NODE_KEY_FOUND=true
            return 0
        fi
    done
    print_warning "Bootstrap の node.key.pem が見つからないよ。新しいca.key.pemを生成するね！"
    NODE_KEY_FOUND=false
    return 1
}

# ディスク容量の確認
check_disk_space() {
    local dir="$1"
    local required_space_mb=120000 # 120GB
    local available_space_mb
    available_space_mb=$(df -m "$dir" | tail -n 1 | awk '{print $4}')
    if [ "$available_space_mb" -lt "$required_space_mb" ]; then
        error_exit "ディスク容量が不足してるよ！$dir に ${required_space_mb}MB 必要だけど、${available_space_mb}MB しかない。スペースを空けて！"
    fi
    print_info "ディスク容量は十分だよ: ${available_space_mb}MB 利用可能"
}

# データコピー
copy_data() {
    local src_db="$BOOTSTRAP_DIR/databases/db"
    local src_data="$BOOTSTRAP_DIR/nodes/node/data"
    local dest_db="$SHOESTRING_DIR/shoestring/dbdata"
    local dest_data="$SHOESTRING_DIR/shoestring/data"
    
    print_info "Bootstrap のデータベースとデータをコピーするよ（再同期を回避！）"
    
    check_disk_space "$SHOESTRING_DIR"
    
    print_info "Bootstrap と Shoestring のノードを停止するよ"
    if [ -d "$BOOTSTRAP_DIR" ]; then
        cd "$BOOTSTRAP_DIR" && sudo docker-compose down >> "$SHOESTRING_DIR/data_copy.log" 2>&1 || print_warning "Bootstrap のノード停止に失敗したけど、続行するよ"
    fi
    if [ -d "$SHOESTRING_DIR/shoestring" ]; then
        cd "$SHOESTRING_DIR/shoestring" && sudo docker-compose down >> "$SHOESTRING_DIR/data_copy.log" 2>&1 || print_warning "Shoestring のノード停止に失敗したけど、続行するよ"
    fi
    
    if [ -d "$src_db" ]; then
        mkdir -p "$dest_db" || error_exit "$dest_db の作成に失敗"
        fix_dir_permissions "$dest_db"
        if command -v pv >/dev/null 2>&1; then
            echo -e "${YELLOW}データベースコピー中... sudo のパスワードを入力してね:${NC}"
            print_info "データベース（db）をコピー中（進捗は画面に表示、詳細は: $SHOESTRING_DIR/data_copy.log）"
            sudo tar -C "$src_db" -cf - . 2>>"$SHOESTRING_DIR/data_copy.log" \
              | pv \
              | sudo tar -C "$dest_db" -xf - 2>>"$SHOESTRING_DIR/data_copy.log" \
              || error_exit "データベースのコピーに失敗。ログを確認してね: cat $SHOESTRING_DIR/data_copy.log"
            print_info "データベースコピー完了！"
        else
            sudo cp -a "$src_db/." "$dest_db/" 2>>"$SHOESTRING_DIR/data_copy.log" \
              || error_exit "データベースコピーに失敗。ログを確認してね: cat $SHOESTRING_DIR/data_copy.log"
            print_info "データベースコピー完了！（進捗なし）"
        fi
        print_info "データベースをコピーしたよ: $dest_db"
    else
        print_warning "データベースが見つからないよ: $src_db。コピーはスキップ。"
    fi

    if [ -d "$src_data" ]; then
        mkdir -p "$dest_data" || error_exit "$dest_data の作成に失敗"
        fix_dir_permissions "$dest_data"
        if command -v pv >/dev/null 2>&1; then
            echo -e "${YELLOW}チェーンデータコ its ピー中... sudo のパスワードを入力してね:${NC}"
            print_info "チェーンデータをコピー中（進捗は画面に表示）…"
            sudo tar -C "$src_data" -cf - . 2>>"$SHOESTRING_DIR/data_copy.log" \
              | pv \
              | sudo tar -C "$dest_data" -xf - 2>>"$SHOESTRING_DIR/data_copy.log" \
              || error_exit "チェーンデータのコピーに失敗。ログを確認してね: cat $SHOESTRING_DIR/data_copy.log"
            print_info "チェーンデータコピー完了！"
        else
            sudo cp -a "$src_data/." "$dest_data/" 2>>"$SHOESTRING_DIR/data_copy.log" \
              || error_exit "チェーンデータコピーに失敗。ログを確認してね: cat $SHOESTRING_DIR/data_copy.log"
            print_info "データコピー完了！（進捗なし）"
        fi
        print_info "データをコピーしたよ: $dest_data"
    else
        print_warning "データが見つからないよ: $src_data。コピーはスキップ。"
    fi
}

# Shoestring セットアップ
setup_shoestring() {
    print_info "Shoestring ノードをセットアップするよ"
    source "$SHOESTRING_DIR/shoestring-env/bin/activate" || error_exit "仮想環境の有効化に失敗"
    local shoestring_subdir="$SHOESTRING_DIR/shoestring"
    mkdir -p "$shoestring_subdir" || error_exit "$shoestring_subdir の作成に失敗"
    fix_dir_permissions "$shoestring_subdir"
    local network_type friendly_name
    IFS=' ' read -r network_type friendly_name <<< "$(detect_network_and_roles)"
    print_info "検出したネットワーク: $network_type、ノード名: $friendly_name"
    log "Parsed - network_type: $network_type, friendly_name: $friendly_name" "DEBUG"
    local host_name
    host_name=$(extract_host)
    print_info "検出したホスト: $host_name"
    local config_file="$shoestring_subdir/shoestring.ini"
    print_info "shoestring.ini を初期化するよ"
    log "python3 -m shoestring init \"$config_file\" --package $network_type" "DEBUG"
    python3 -m shoestring init "$config_file" --package "$network_type" > "$SHOESTRING_DIR/install_shoestring.log" 2>&1 || error_exit "shoestring.ini の初期化に失敗。手動で確認してね: python3 -m shoestring init $config_file"
    local ca_key_path="$shoestring_subdir/ca.key.pem"
    check_node_key
    if [ "$NODE_KEY_FOUND" = true ]; then
        print_info "node.key.pem を移行するよ"
        local src_node_key="$BOOTSTRAP_DIR/nodes/node/cert/node.key.pem"
        local dest_node_key="$shoestring_subdir/node.key.pem"
        if [ -f "$src_node_key" ]; then
            cp "$src_node_key" "$dest_node_key" || error_exit "node.key.pem のコピーに失敗: $src_node_key"
            print_info "node.key.pem をコピー: $dest_node_key"
        fi
        log "python3 -m shoestring import-bootstrap --config \"$config_file\" --bootstrap \"$BOOTSTRAP_DIR\" --include-node-key" "DEBUG"
        python3 -m shoestring import-bootstrap --config "$config_file" --bootstrap "$BOOTSTRAP_DIR" --include-node-key > "$SHOESTRING_DIR/import_bootstrap.log" 2>&1 || error_exit "import-bootstrap に失敗。ログを確認してね: cat $SHOESTRING_DIR/import_bootstrap.log"
        if [ ! -f "$ca_key_path" ]; then
            print_info "新しい ca.key.pem を生成するよ"
            log "新しい ca.key.pem を生成するよ" "INFO"
            local private_key=$(openssl rand -hex 32)
            if [ -z "$private_key" ]; then
                error_exit "プライベートキーの生成に失敗したよ。OpenSSLを確認してね: openssl rand -hex 32"
            fi
            local temp_key_file=$(mktemp)
            echo "$private_key" > "$temp_key_file"
            log "プライベートキー（最初の12文字）: ${private_key:0:12}..." "DEBUG"
            python3 -m shoestring pemtool --input "$temp_key_file" --output "$ca_key_path" >> "$SHOESTRING_DIR/pemtool.log" 2>&1 || error_exit "ca.key.pem の生成に失敗したよ。ログを確認してね: cat $SHOESTRING_DIR/pemtool.log"
            rm -f "$temp_key_file"
            print_info "ca.key.pem を生成: $ca_key_path"
        else
            print_info "既存の ca.key.pem を使用: $ca_key_path"
            log "既存の ca.key.pem 検出: $ca_key_path" "DEBUG"
        fi
    else
        print_info "新しい ca.key.pem を生成するよ"
        log "新しい ca.key.pem を生成するよ" "INFO"
        local private_key=$(openssl rand -hex 32)
        if [ -z "$private_key" ]; then
            error_exit "プライベートキーの生成に失敗したよ。OpenSSLを確認してね: openssl rand -hex 32"
        fi
        local temp_key_file=$(mktemp)
        echo "$private_key" > "$temp_key_file"
        log "プライベートキー（最初の12文字）: ${private_key:0:12}..." "DEBUG"
        python3 -m shoestring pemtool --input "$temp_key_file" --output "$ca_key_path" >> "$SHOESTRING_DIR/pemtool.log" 2>&1 || error_exit "ca.key.pem の生成に失敗したよ。ログを確認してね: cat $SHOESTRING_DIR/pemtool.log"
        rm -f "$temp_key_file"
        print_info "ca.key.pem を生成: $ca_key_path"
        log "python3 -m shoestring import-bootstrap --config \"$config_file\" --bootstrap \"$BOOTSTRAP_DIR\"" "DEBUG"
        python3 -m shoestring import-bootstrap --config "$config_file" --bootstrap "$BOOTSTRAP_DIR" > "$SHOESTRING_DIR/import_bootstrap.log" 2>&1 || error_exit "import-bootstrap に失敗。ログを確認してね: cat $SHOESTRING_DIR/import_bootstrap.log"
    fi
    local src_harvesting="$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-harvesting.properties"
    local dest_harvesting="$shoestring_subdir/config-harvesting.properties"
    if [ -f "$src_harvesting" ]; then
        cp "$src_harvesting" "$dest_harvesting" || error_exit "Failed to copy config-harvesting.properties"
        print_info "config-harvesting.properties をコピーしました: $dest_harvesting"
    else
        error_exit "config-harvesting.properties が見つからないよ: $src_harvesting"
    fi
    local absolute_harvesting=$(realpath "$dest_harvesting")
    local absolute_node_key
    if [ "$NODE_KEY_FOUND" = true ]; then
        absolute_node_key=$(realpath "$dest_node_key")
    else
        absolute_node_key=$(realpath "$ca_key_path")
    fi
    print_info "shoestring.ini の [imports] を更新するよ"
    local absolute_harvesting_escaped=$(printf '%s' "$absolute_harvesting" | sed 's/[\/&]/\\&/g')
    local absolute_node_key_escaped=$(printf '%s' "$absolute_node_key" | sed 's/[\/&]/\\&/g')
    sed -i "/^\[imports\]/,/^\[.*\]/ s|^harvesting\s*=.*|harvesting = $absolute_harvesting_escaped|" "$config_file"
    sed -i "/^\[imports\]/,/^\[.*\]/ s|^nodeKey\s*=.*|nodeKey = $absolute_node_key_escaped|" "$config_file"
    grep -A 5 '^\[imports\]' "$config_file" > "$SHOESTRING_DIR/imports_snippet.log" 2>&1
    log "[imports] 更新後: $(cat "$SHOESTRING_DIR/imports_snippet.log" | sed 's/["'\''$]/\\&/g')" "DEBUG"
    validate_ini "$config_file"
    if ! $SKIP_CONFIRM; then
        confirm_and_edit_ini "$config_file"
    fi
    print_info "shoestring.ini を生成: $config_file"
    local overrides_file="$shoestring_subdir/overrides.ini"
    print_info "overrides.ini を生成するよ"
    if [ -f "$overrides_file" ]; then
        mv "$overrides_file" "$overrides_file.bak-$(date +%Y%m%d_%H%M%S)"
        print_info "既存の overrides.ini をバックアップ: $overrides_file.bak-$(date +%Y%m%d_%H%M%S)"
    fi
cat > "$overrides_file" << EOF
[user.account]
enableDelegatedHarvestersAutoDetection = true

[harvesting.harvesting]
maxUnlockedAccounts =5
beneficiaryAddress = 

[node.node]
minFeeMultiplier =100

[node.localnode]
host = $host_name
friendlyName = $friendly_name
EOF
    # 変数展開のための置換
    #sed -i "s/\$host_name/$host_name/g" "$overrides_file"
    #sed -i "s/\$friendly_name/$friendly_name/g" "$overrides_file"
    
    log "overrides.ini 内容: $(cat "$overrides_file" | sed 's/["'\''$]/\\&/g')" "DEBUG"
    validate_ini "$overrides_file"
    if ! $SKIP_CONFIRM; then
        confirm_and_edit_ini "$overrides_file"
    fi
    print_info "overrides.ini を生成しました"
    print_info "Shoestring のセットアップを実行するよ"
    log "python3 -m shoestring setup --ca-key-path \"$ca_key_path\" --config \"$config_file\" --overrides \"$overrides_file\" --directory \"$shoestring_subdir\" --package $network_type" "DEBUG"
    python3 -m shoestring setup --ca-key-path "$ca_key_path" --config "$config_file" --overrides "$overrides_file" --directory "$shoestring_subdir" --package "$network_type" > "$SHOESTRING_DIR/setup_shoestring.log" 2>&1 || error_exit "Shoestring ノードのセットアップに失敗。ログを確認してね: cat $SHOESTRING_DIR/setup_shoestring.log"
    copy_data
    print_info "Shoestring ノードを起動するよ"
    cd "$shoestring_subdir" || error_exit "ディレクトリ移動に失敗したよ: $shoestring_subdir"
    print_info "Docker の古いリソースをクリアするよ(ネットワーク競合を回避)"
    docker system prune -a --volumes --force >> "$SHOESTRING_DIR/docker_cleanup.log" 2>&1
    docker-compose up -d > "$SHOESTRING_DIR/docker_compose.log" 2>&1 || error_exit "Shoestring ノードの起動に失敗。ログを確認してね: cat $SHOESTRING_DIR/docker_compose.log"
    print_info "Shoestring ノードを起動したよ！"
    deactivate
}

# 移行後のガイド
show_post_migration_guide() {
    print_info "移行が終わった！これからやること："
    echo -e "${GREEN}Symbol Bootstrap から Shoestring への移行が完了！${NC}"
    echo
    print_info "大事なファイル："
    if [ "$NODE_KEY_FOUND" = true ]; then
        echo "  - ノード秘密鍵: $SHOESTRING_DIR/shoestring/node.key.pem"
        echo "  - Bootstrap の node.key.pem を移行したよ！証明書がそのまま使えるからスッキリ！"
    else
        echo "  - CA秘密鍵: $SHOESTRING_DIR/shoestring/ca.key.pem"
    fi
    echo "  - ハーベスト設定: $SHOESTRING_DIR/shoestring/config-harvesting.properties"
    echo "  - バックアップ: $BACKUP_DIR"
    echo "  - ログ: $SHOESTRING_DIR/setup.log"
    echo "  - 設定: $SHOESTRING_DIR/shoestring/shoestring.ini"
    echo "  - 上書き設定: $SHOESTRING_DIR/shoestring/overrides.ini"
    echo "  - Docker Compose: $SHOESTRING_DIR/shoestring/docker-compose.yml"
    echo "  - データベース: $SHOESTRING_DIR/shoestring/dbdata"
    echo "  - データ: $SHOESTRING_DIR/shoestring/data"
    echo
    if [ "$NODE_KEY_FOUND" = true ]; then
        print_warning "node.key.pem と config-harvesting.properties は安全な場所にバックアップして保管してね！"
    else
        print_warning "ca.key.pem と config-harvesting.properties は安全な場所にバックアップして保管してね！"
    fi
    print_info "ノードの状態を確認するには:"
    echo "  1. コンテナ確認: docker ps"
    echo "  2. ログ確認: cd \"$SHOESTRING_DIR/shoestring\" && docker-compose logs -f"
    echo "  3. REST API 確認: curl http://localhost:3000"
    print_info "ノードタイプを変更したい場合: nano $SHOESTRING_DIR/shoestring/shoestring.ini で [node] の features や lightApi を編集"
    print_info "ログの詳細を確認: tail -f $SHOESTRING_DIR/setup.log"
    print_info "データコピーエラー: cat $SHOESTRING_DIR/data_copy.log"
    print_info "import-bootstrap が失敗した場合、yq を使った方法を試してね: https://github.com/mikunNEM/bootstrap-to-shoestring"
    print_info "サポート: https://x.com/mikunNEM"
}

# 主処理
main() {
    print_info "Symbol Bootstrap から Shoestring への移行を始めるよ！"
    
    # グローバル変数を初期化
    auto_detect_dirs
    LOG_FILE="$SHOESTRING_DIR/setup.log"
    
    # ログディレクトリを作成
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    log "Starting migration process..." "INFO"
    
    # 基本的な環境チェック（symbol-bootstrap を除く）
    print_info "基本環境をチェックするよ"
    #check_command "python3" || error_exit "python3 が見つからないよ。インストール: sudo apt install python3"
    #check_python_version
    
    install_dependencies
    collect_user_info
    
    # LOG_FILE と関連変数を再設定
    LOG_FILE="$SHOESTRING_DIR/setup.log"
    ADDRESSES_YML="$BOOTSTRAP_DIR/addresses.yml"
    SHOESTRING_RESOURCES="$SHOESTRING_DIR/shoestring"
    
    if ! check_node_key; then
        print_info "node.key.pemが見つからなかったけど、ca.key.pemを生成して進むよ！"
    fi
    
    validate_file "$ADDRESSES_YML"
    create_backup
    setup_shoestring
    show_post_migration_guide
}

main "$@"
