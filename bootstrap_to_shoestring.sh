#!/bin/bash

# bootstrap_to_shoestring.sh - Symbol Bootstrap から Shoestring への移行スクリプト
# 誰でも簡単に移行！依存自動インストール、権限エラー解決、初心者向けガイダンス付き。
#
# 使い方:  　　　　　　　　　　　
#   1. ~/shoestring ディレクトリを作成
#   2. スクリプトをダウンロード:  curl -O https://github.com/mikunNEM/bootstrap-to-shoestring/raw/main/bootstrap_to_shoestring.sh
#                             curl -O https://github.com/mikunNEM/bootstrap-to-shoestring/raw/main/utils.sh                             
#   3. 実行権限: chmod +x ./bootstrap_to_shoestring.sh
#   4. 実行: bash ./bootstrap_to_shoestring.sh

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
SCRIPT_VERSION="2025-06-16-v38"

# グローバル変数
SHOESTRING_DIR=""
SHOESTRING_DIR_DEFAULT="$HOME/shoestring"
BOOTSTRAP_DIR=""
BOOTSTRAP_DIR_DEFAULT="$HOME/symbol-bootstrap/target"
BOOTSTRAP_COMPOSE_DIR=""
BACKUP_DIR=""
BACKUP_DIR_DEFAULT="$HOME/symbol-bootstrap-backup-$(date +%Y%m%d_%H%M%S)"
ENCRYPTED=false
SKIP_CONFIRM=false
NODE_KEY_FOUND=false
LOG_FILE=""
ADDRESSES_YML=""
SHOESTRING_RESOURCES=""
FRIENDLY_NAME=""

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
    print_info "Checking and fixing permissions for $dir..."
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || error_exit "Failed to create directory $dir"
        print_success "Created directory $dir!"
    fi
    if ! touch "$dir/.write_test" 2>/dev/null; then
        print_warning "$dir に書き込み権限がないよ。修正するね！"
        sudo chmod u+rwx "$dir" || error_exit "Failed to change permissions of $dir"
        sudo chown "$(whoami):$(whoami)" "$dir" || error_exit "Failed to change owner of $dir"
        if ! touch "$dir/.write_test" 2>/dev/null; then
            error_exit "Failed to fix permissions for $dir. Check manually: sudo chmod u+rwx $dir"
        fi
        print_success "Fixed permissions for $dir!"
    fi
    rm -f "$dir/.write_test"
}

# ディスク容量のチェック（仮想環境用）
check_disk_space_for_venv() {
    local dir="$1"
    local required_space_mb=1000 # 1GB for virtual environment
    local available_space_mb
    available_space_mb=$(df -m "$dir" | tail -n 1 | awk '{print $4}')
    if [ "$available_space_mb" -lt "$required_space_mb" ]; then
        error_exit "ディスク容量が不足してるよ！$dir に ${required_space_mb}MB 必要だけど、${available_space_mb}MB しかない。スペースを空けて！"
    fi
    print_info "ディスク容量（仮想環境用）は十分だよ: ${available_space_mb}MB 利用可能"
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
            # パッケージが見つからないエラーの場合、即座に終了
            if grep -q "E: Unable to locate package" "$LOG_FILE"; then
                error_exit "パッケージが見つかりません: $cmd。リポジトリを確認してください: sudo apt-get update"
            fi
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

    # Ubuntu/Debian 環境
    if [[ $os_name == "ubuntu" || $os_name == "debian" ]]; then
        print_info "APT キャッシュとロックを修復..."
        check_apt_locks
        sudo apt-get clean
        sudo rm -rf /var/lib/apt/lists/* 2>>"$LOG_FILE"
        retry_command "sudo apt-get update"
        retry_command "sudo apt-get install -f -y" || error_exit "壊れたパッケージの修復に失敗しました。手動で実行してください: sudo apt-get install -f"
        retry_command "sudo dpkg --configure -a" || print_warning "dpkg の修復に失敗しましたが、続行します。"
        retry_command "sudo apt-get autoremove -y"
        retry_command "sudo apt-get autoclean"

        # サードパーティリポジトリ（focal や deadsnakes）を無効化
        print_info "サードパーティリポジトリをチェック..."
        if ls /etc/apt/sources.list.d/*.list 2>/dev/null | grep -q "focal\|deadsnakes"; then
            print_warning "focal または deadsnakes リポジトリを無効化します..."
            sudo find /etc/apt/sources.list.d/ -type f -name "*.list" -exec grep -l "focal\|deadsnakes" {} \; | while read -r file; do
                sudo mv "$file" "${file}.bak"
                print_info "無効化: $file"
            done
            retry_command "sudo apt-get update"
        fi

        # パッケージの固定を解除
        print_info "パッケージの固定を解除..."
        sudo apt-mark unhold python3.10 python3.10-dev libpython3.10 libpython3.10-dev 2>>"$LOG_FILE"

        # Python 3.10 の確認
        print_info "Python 3.10 の存在を確認..."
        if ! command -v /usr/bin/python3.10 >/dev/null 2>&1; then
            print_warning "/usr/bin/python3.10 が見つかりません。インストールを試みます..."
            retry_command "sudo apt-get install -y python3.10 python3.10-venv python3.10-distutils" || error_exit "Python 3.10 のインストールに失敗しました。手動でインストールしてください: sudo apt-get install python3.10 python3.10-venv"
        fi
        local python_version=$(/usr/bin/python3.10 --version 2>>"$LOG_FILE" || echo "unknown")
        if [[ "$python_version" != Python\ 3.10* ]]; then
            error_exit "Python 3.10 が正しくインストールされていません。バージョン: $python_version。手動で確認してください: /usr/bin/python3.10 --version"
        fi
        print_info "Python 3.10 確認OK: $python_version"

        # 既存の python3.10 を正しいバージョンに
        retry_command "sudo apt-get install --reinstall -y python3.10 python3.10-venv python3.10-distutils" || error_exit "Python 3.10 の再インストールに失敗しました。"

        # 開発ツールと依存パッケージをインストール
        print_info "開発ツールと必須パッケージをインストール..."
        retry_command "sudo apt-get install -y build-essential python3.10-dev libssl-dev python3-apt libapt-pkg-dev software-properties-common python3-pip python3-venv" || error_exit "必須パッケージのインストールに失敗しました。手動で確認してください: sudo apt-get install -y build-essential python3.10-dev libssl-dev python3-apt software-properties-common python3-pip python3-venv"

        # apt_pkg の動作確認
        if ! /usr/bin/python3.10 -c "import apt_pkg" 2>/dev/null; then
            print_warning "apt_pkg モジュールが見つかりません。再度インストールを試みます..."
            print_info "Python バージョン: $(/usr/bin/python3.10 --version)"
            find /usr/lib -name apt_pkg.cpython-*.so 2>>"$LOG_FILE" || print_warning "apt_pkg モジュールが見つかりません: find /usr/lib -name apt_pkg.cpython-*.so"
            retry_command "sudo apt-get install --reinstall -y python3-apt" || error_exit "apt_pkg モジュールのインストールに失敗しました。手動で確認してください: sudo apt-get install python3-apt && /usr/bin/python3.10 -c 'import apt_pkg'"
            if ! /usr/bin/python3.10 -c "import apt_pkg" 2>/dev/null; then
                error_exit "apt_pkg モジュールの再インストールにも失敗しました。手動で確認してください: sudo apt-get install python3-apt && /usr/bin/python3.10 -c 'import apt_pkg'"
            fi
        fi
        print_info "apt_pkg モジュール確認OK"

        # command-not-found を一時無効化
        if [ -f /usr/lib/cnf-update-db ]; then
            print_info "command-not-found を一時無効化..."
            sudo mv /usr/lib/cnf-update-db /usr/lib/cnf-update-db.bak
        fi
    else
        error_exit "サポートされていないOS: $os_name。このスクリプトは Ubuntu/Debian のみ対応しています。"
    fi

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
    if ! command -v docker-compose >/dev/null 2>&1; then
        print_warning "Docker Compose が見つからないよ。インストールするね！"
        retry_command "sudo apt-get install -y docker-compose-plugin" || error_exit "Docker Compose のインストールに失敗しました。手動でインストールしてください: sudo apt-get install docker-compose-plugin"
        # docker-compose コマンドをリンク
        if ! command -v docker-compose >/dev/null 2>&1; then
            sudo ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose 2>>"$LOG_FILE" || error_exit "docker-compose リンクの作成に失敗しました"
            sudo chmod +x /usr/local/bin/docker-compose 2>>"$LOG_FILE" || error_exit "docker-compose の権限設定に失敗しました"
        fi
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

    # yq（YAMLパーサー、オプション）
    if ! command -v yq >/dev/null 2>&1; then
        print_warning "yq が見つからないよ。addresses.yml の正確なパースに使うからインストールするね！"
        retry_command "sudo apt-get install -y yq" || print_warning "yq のインストールに失敗。簡易パースを使用します。"
    fi
    if command -v yq >/dev/null 2>&1; then
        print_info "yq: $(yq --version)"
    fi

    # 仮想環境作成前のディスク容量チェック
    check_disk_space_for_venv "$SHOESTRING_DIR"
    log "SHOESTRING_DIR for virtual environment: $SHOESTRING_DIR" "DEBUG"

    # 仮想環境
    local venv_dir="$SHOESTRING_DIR/shoestring-env"
    print_info "仮想環境パス: $venv_dir"
    fix_dir_permissions "$SHOESTRING_DIR"
    # 仮想環境を常に削除・再作成
    if [ -d "$venv_dir" ]; then
        print_warning "既存の仮想環境が見つかりました: $venv_dir。削除して再作成します..."
        sudo rm -rf "$venv_dir" || error_exit "仮想環境 $venv_dir の削除に失敗しました。手動で削除してください: sudo rm -rf $venv_dir"
    fi
    print_info "仮想環境を作成するよ..."
    /usr/bin/python3.10 -m venv "$venv_dir" >> "$LOG_FILE" 2>&1 || {
        log "仮想環境作成エラー: $(tail -n 20 "$LOG_FILE")" "ERROR"
        error_exit "仮想環境の作成に失敗しました。ログを確認してください: cat $LOG_FILE"
    }
    if [ ! -f "$venv_dir/bin/activate" ]; then
        error_exit "仮想環境の作成に失敗しました。activate ファイルが見つかりません: $venv_dir/bin/activate"
    fi
    source "$venv_dir/bin/activate" || error_exit "仮想環境の有効化に失敗しました: $venv_dir/bin/activate"
    local pip_version=$(python3 -m pip --version 2>>"$LOG_FILE")
    print_info "pip バージョン: $pip_version"
    # setuptools と pip をインストール
    retry_command "pip install setuptools" || error_exit "setuptools のインストールに失敗しました。手動でインストールしてください: pip install setuptools"
    retry_command "pip install --upgrade pip" || error_exit "pip のアップグレードに失敗しました。手動でインストールしてください: pip install --upgrade pip"
    # symbol-shoestring をインストール
    print_info "symbol-shoestring をインストール中…"
    retry_command "pip install symbol-shoestring==0.2.1" || error_exit "symbol-shoestring のインストールに失敗しました。ログを確認してください: cat $LOG_FILE"
    print_success "symbol-shoestring のインストールに成功しました！"
    pip list > "$SHOESTRING_DIR/log/pip_list.log"
    if grep -q symbol-shoestring "$SHOESTRING_DIR/log/pip_list.log"; then
        print_info "symbol-shoestring インストール済み: $(grep symbol-shoestring "$SHOESTRING_DIR/log/pip_list.log")"
        local shoestring_version=$(pip show symbol-shoestring | grep Version | awk '{print $2}')
        log "symbol-shoestring version: $shoestring_version" "INFO"
    else
        log "pip list: $(cat "$SHOESTRING_DIR/log/pip_list.log")" "DEBUG"
        error_exit "symbol-shoestring が未インストール。インストールコマンド: pip install symbol-shoestring"
    fi
    deactivate
    print_info "仮想環境: $venv_dir"
}

# ディレクトリ自動検出
auto_detect_dirs() {
    print_info "ディレクトリを自動で探すよ！"
    local bootstrap_dirs=(
        "$HOME/symbol-bootstrap/target"
        "$HOME/work/symbol-bootstrap/target"
        "$HOME/symbol-bootstrap"
        "$(find "$HOME" -maxdepth 4 -type d -name target 2>/dev/null | grep symbol-bootstrap | head -n 1)"
    )
    for dir in "${bootstrap_dirs[@]}"; do
        if [ -d "$dir" ] && [ -f "$dir/addresses.yml" ] && { [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker/docker-compose.yml" ]; }; then
            BOOTSTRAP_DIR_DEFAULT="$dir"
            print_info "Bootstrap フォルダを検出: $BOOTSTRAP_DIR_DEFAULT"
            if [ -f "$dir/docker/docker-compose.yml" ]; then
                BOOTSTRAP_COMPOSE_DIR="$dir/docker"
                print_info "docker-compose.yml を検出: $BOOTSTRAP_COMPOSE_DIR/docker-compose.yml"
            else
                BOOTSTRAP_COMPOSE_DIR="$dir"
                print_info "docker-compose.yml を検出: $BOOTSTRAP_COMPOSE_DIR/docker-compose.yml"
            fi
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

    # Bootstrap target ディレクトリの自動検出
    print_info "Bootstrap の target ディレクトリを自動で探すよ！"
    local detected_bootstrap_dir=""
    # target ディレクトリを検索し、addresses.yml が存在するディレクトリを優先
    while IFS= read -r dir; do
        if [ -f "$dir/addresses.yml" ] && { [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker/docker-compose.yml" ]; }; then
            detected_bootstrap_dir="$dir"
            break
        fi
    done < <(find "$HOME" -maxdepth 4 -type d -name target 2>/dev/null)
    
    if [ -n "$detected_bootstrap_dir" ]; then
        BOOTSTRAP_DIR_DEFAULT="$detected_bootstrap_dir"
        print_info "検出した Bootstrap target ディレクトリ: $BOOTSTRAP_DIR_DEFAULT"
    else
        print_warning "Bootstrap target ディレクトリを自動検出できなかったよ。デフォルトを使用: $BOOTSTRAP_DIR_DEFAULT"
    fi

    if $SKIP_CONFIRM; then
        SHOESTRING_DIR="$SHOESTRING_DIR_DEFAULT"
        BOOTSTRAP_DIR="$BOOTSTRAP_DIR_DEFAULT"
        BOOTSTRAP_COMPOSE_DIR="$BOOTSTRAP_DIR_DEFAULT"
        if [ -f "$BOOTSTRAP_DIR_DEFAULT/docker/docker-compose.yml" ]; then
            BOOTSTRAP_COMPOSE_DIR="$BOOTSTRAP_DIR_DEFAULT/docker"
        fi
        BACKUP_DIR="$BACKUP_DIR_DEFAULT"
    else
        echo -e "${YELLOW}Shoestring ノードのフォルダパスを入力してね:${NC}"
        echo -e "${YELLOW}デフォルト（Enterで選択）: $SHOESTRING_DIR_DEFAULT${NC}"
        read -r input
        SHOESTRING_DIR="$(expand_tilde "${input:-$SHOESTRING_DIR_DEFAULT}")"
        fix_dir_permissions "$SHOESTRING_DIR"
        
        echo -e "${YELLOW}Bootstrap の target フォルダパスを入力してね:${NC}"
        echo -e "${YELLOW}デフォルト（Enterで選択）: $BOOTSTRAP_DIR_DEFAULT${NC}"
        if [ -n "$detected_bootstrap_dir" ]; then
            echo -e "${BLUE}検出したパス: $detected_bootstrap_dir${NC}" >&2
        fi
        if confirm "このパスでOK？"; then
            BOOTSTRAP_DIR="$BOOTSTRAP_DIR_DEFAULT"
        else
            echo -e "${YELLOW}正しい target フォルダパスを入力してね:${NC}"
            read -r input
            BOOTSTRAP_DIR="$(expand_tilde "${input:-$BOOTSTRAP_DIR_DEFAULT}")"
        fi
        if [ -f "$BOOTSTRAP_DIR/docker/docker-compose.yml" ]; then
            BOOTSTRAP_COMPOSE_DIR="$BOOTSTRAP_DIR/docker"
            print_info "docker-compose.yml を検出: $BOOTSTRAP_COMPOSE_DIR/docker-compose.yml"
        else
            BOOTSTRAP_COMPOSE_DIR="$BOOTSTRAP_DIR"
            print_info "docker-compose.yml を検出: $BOOTSTRAP_COMPOSE_DIR/docker-compose.yml"
        fi
        
        echo -e "${YELLOW}バックアップの保存先フォルダを入力してね:${NC}"
        echo -e "${YELLOW}デフォルト（Enterで選択）: $BACKUP_DIR_DEFAULT${NC}"
        read -r input
        BACKUP_DIR="$(expand_tilde "${input:-$BACKUP_DIR_DEFAULT}")"
    fi
    validate_dir "$BOOTSTRAP_DIR"
    if [ -d "$BACKUP_DIR" ]; then
        print_info "$BACKUP_DIR が既に存在します。バックアップを上書きします。"
    else
        mkdir -p "$BACKUP_DIR" || error_exit "$BACKUP_DIR の作成に失敗"
        print_info "$BACKUP_DIR を作成したよ！"
    fi
    print_info "バックアップフォルダ: $BACKUP_DIR"
    log "SHOESTRING_DIR: $SHOESTRING_DIR, BOOTSTRAP_DIR: $BOOTSTRAP_DIR, BOOTSTRAP_COMPOSE_DIR: $BOOTSTRAP_COMPOSE_DIR, BACKUP_DIR: $BACKUP_DIR" "INFO"
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
        "nodes/node/votingkeys"
    )
    mkdir -p "$BACKUP_DIR"
    for file in "${files[@]}"; do
        if [ -f "$src_dir/$file" ] || [ -d "$src_dir/$file" ]; then
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
    python3 -c "import configparser; config = configparser.ConfigParser(); config.read('$ini_file')" > "$SHOESTRING_DIR/log/validate_ini.log" 2>&1 || {
        log "INI 検証エラー: $(cat "$SHOESTRING_DIR/log/validate_ini.log")" "ERROR"
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
        if confirm "この設定で大丈夫？ 別のターミナルを開いて$SHOESTRING_DIR/shoestring/${file_name}を編集してね。nを押すと更新が確認出来るよ"; then
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

# ディスク容量の確認（データ用）
check_disk_space_for_data() {
    local dir="$1"
    local required_space_mb=120000 # 120GB
    local available_space_mb
    available_space_mb=$(df -m "$dir" | tail -n 1 | awk '{print $4}')
    if [ "$available_space_mb" -lt "$required_space_mb" ]; then
        error_exit "ディスク容量が不足してるよ！$dir に ${required_space_mb}MB 必要だけど、${available_space_mb}MB しかない。スペースを空けて！"
    fi
    print_info "ディスク容量（データ用）は十分だよ: ${available_space_mb}MB 利用可能"
}

# Bootstrap パスの検証
validate_bootstrap_dir() {
    local dir="$1"
    print_info "Bootstrap ディレクトリを検証するよ: $dir"
    log "Validating BOOTSTRAP_DIR: $dir" "DEBUG"
    if [ ! -d "$dir" ]; then
        error_exit "Bootstrap ディレクトリが見つからないよ: $dir。パスを確認してね！"
    fi
    if [ -f "$dir/docker-compose.yml" ]; then
        BOOTSTRAP_COMPOSE_DIR="$dir"
        print_info "docker-compose.yml を検出: $BOOTSTRAP_COMPOSE_DIR/docker-compose.yml"
    elif [ -f "$dir/docker/docker-compose.yml" ]; then
        BOOTSTRAP_COMPOSE_DIR="$dir/docker"
        print_info "docker-compose.yml を検出: $BOOTSTRAP_COMPOSE_DIR/docker-compose.yml"
    else
        error_exit "docker-compose.yml が見つからないよ: $dir/docker-compose.yml または $dir/docker/docker-compose.yml。Bootstrap のセットアップを確認してね！"
    fi
    if [ ! -d "$dir/databases/db" ] && [ ! -d "$dir/nodes/node/data" ]; then
        error_exit "データディレクトリが見つからないよ: $dir/databases/db または $dir/nodes/node/data。Bootstrap のデータがあるか確認してね！"
    fi
    ls -l "$dir" > "$SHOESTRING_DIR/log/bootstrap_dir_contents.log" 2>&1
    log "Bootstrap ディレクトリ内容: $(cat "$SHOESTRING_DIR/log/bootstrap_dir_contents.log")" "DEBUG"
    if [ -d "$BOOTSTRAP_COMPOSE_DIR" ]; then
        ls -l "$BOOTSTRAP_COMPOSE_DIR" > "$SHOESTRING_DIR/log/bootstrap_compose_dir_contents.log" 2>&1
        log "Bootstrap Compose ディレクトリ内容: $(cat "$SHOESTRING_DIR/log/bootstrap_compose_dir_contents.log")" "DEBUG"
    fi
    print_info "Bootstrap ディレクトリ検証OK: $dir"
}

# beneficiaryAddress を設定
set_beneficiary_address() {
    local bootstrap_config="$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-harvesting.properties"
    local addresses_yml="$BOOTSTRAP_DIR/addresses.yml"
    local overrides_ini="$SHOESTRING_DIR/shoestring/overrides.ini"
    local beneficiary_address=""

    print_info "overrides.ini の beneficiaryAddress を設定するよ"

    # 1. config-harvesting.properties から beneficiaryAddress を抽出
    if [ -f "$bootstrap_config" ]; then
        beneficiary_address=$(grep -E '^beneficiaryAddress\s*=\s*' "$bootstrap_config" | sed 's/.*=\s*//')
        if [ -n "$beneficiary_address" ]; then
            print_info "Bootstrap の config-harvesting.properties から beneficiaryAddress を見つけた: $beneficiary_address"
        else
            print_warning "config-harvesting.properties に beneficiaryAddress が設定されていないよ"
        fi
    else
        print_warning "config-harvesting.properties が見つからないよ: $bootstrap_config"
    fi

    # 2. 見つからない場合、addresses.yml の main.address を抽出
    if [ -z "$beneficiary_address" ] && [ -f "$addresses_yml" ]; then
        if command -v yq >/dev/null 2>&1; then
            beneficiary_address=$(yq e '.main.address' "$addresses_yml")
            if [ -n "$beneficiary_address" ] && [ "$beneficiary_address" != "null" ]; then
                print_info "addresses.yml の main.address を使用: $beneficiary_address"
            else
                print_warning "addresses.yml に main.address が見つからないよ"
            fi
        else
            print_warning "yq コマンドが見つからないよ。簡易パースを試みる。"
            beneficiary_address=$(grep -A 2 'main:' "$addresses_yml" | grep 'address:' | sed 's/.*address:\s*//')
            if [ -n "$beneficiary_address" ]; then
                print_info "addresses.yml の main.address を使用（簡易パース）: $beneficiary_address"
            fi
        fi
    fi

    # 3. overrides.ini の存在チェックと作成
    if [ ! -f "$overrides_ini" ]; then
        print_info "overrides.ini が見つからないので作成するよ: $overrides_ini"
        echo "[harvesting.harvesting]" | sudo tee "$overrides_ini" >/dev/null
        echo "maxUnlockedAccounts = 5" | sudo tee -a "$overrides_ini" >/dev/null
        sudo chown $(whoami):$(whoami) "$overrides_ini"
        chmod u+rw "$overrides_ini"
    fi

    # 4. overrides.ini に設定
    if [ -n "$beneficiary_address" ]; then
        # [harvesting.harvesting] セクションが存在するか確認
        if grep -q "\[harvesting.harvesting\]" "$overrides_ini"; then
            # beneficiaryAddress を更新（または追加）
            if grep -q "^beneficiaryAddress\s*=" "$overrides_ini"; then
                sudo sed -i "/\[harvesting.harvesting\]/,/^\[/ s/^beneficiaryAddress\s*=.*/beneficiaryAddress = $beneficiary_address/" "$overrides_ini"
            else
                sudo sed -i "/\[harvesting.harvesting\]/a beneficiaryAddress = $beneficiary_address" "$overrides_ini"
            fi
        else
            # セクションが存在しない場合、追加
            echo -e "\n[harvesting.harvesting]\nmaxUnlockedAccounts = 5\nbeneficiaryAddress = $beneficiary_address" | sudo tee -a "$overrides_ini" >/dev/null
        fi
        sudo chown $(whoami):$(whoami) "$overrides_ini"
        chmod u+rw "$overrides_ini"
        print_info "overrides.ini に beneficiaryAddress を設定したよ: $beneficiary_address"
    else
        print_warning "beneficiaryAddress が見つからなかったよ。overrides.ini は変更せず、デフォルトのまま。"
    fi
}

# データコピー
copy_data() {
    local src_db="$BOOTSTRAP_DIR/databases/db"
    local src_data="$BOOTSTRAP_DIR/nodes/node/data"
    local dest_db="$SHOESTRING_DIR/shoestring/dbdata"
    local dest_data="$SHOESTRING_DIR/shoestring/data"
    
    print_info "Bootstrap のデータベースとデータを移動するよ（再同期を回避！）"
    
    validate_bootstrap_dir "$BOOTSTRAP_DIR"
    check_disk_space_for_data "$SHOESTRING_DIR"
    
    if ! $SKIP_CONFIRM; then
        if confirm "データベースとチェーンデータを移動する？（移動後、元データは $BOOTSTRAP_DIR から消えます。バックアップはスキップします。）"; then
            print_info "データバックアップをスキップして移動を続行します..."
        else
            error_exit "データ移動をキャンセルしました。バックアップなしで進める場合は -y フラグを使用してください。"
        fi
    fi
    
    print_info "Bootstrap のノードを安全に停止するよ"
    log "現在の Docker コンテナ: $(docker ps -a)" "DEBUG"
    
    if [ -d "$BOOTSTRAP_COMPOSE_DIR" ]; then
        print_info "Bootstrap ノードを安全に停止するよ: $BOOTSTRAP_COMPOSE_DIR"
        cd "$BOOTSTRAP_COMPOSE_DIR" || error_exit "Bootstrap ディレクトリに移動できないよ: $BOOTSTRAP_COMPOSE_DIR"
        if [ -f "docker-compose.yml" ]; then
            print_info "Bootstrap ノードを停止中（最大30秒待つよ）..."
            sudo docker-compose down >>"$SHOESTRING_DIR/log/data_copy.log" 2>&1 || {
                log "Bootstrap 停止エラー: $(tail -n 20 "$SHOESTRING_DIR/log/data_copy.log")" "ERROR"
                error_exit "Bootstrap のノード停止に失敗。ログを確認してね: cat $SHOESTRING_DIR/log/data_copy.log"
            }
            local containers
            containers=$(docker-compose ps -q 2>>"$SHOESTRING_DIR/log/data_copy.log")
            if [ -n "$containers" ]; then
                log "残存コンテナ: $(docker ps -a | grep "$BOOTSTRAP_COMPOSE_DIR")" "ERROR"
                error_exit "Bootstrap ノードがまだ動いてるよ！手動で停止してね: cd $BOOTSTRAP_COMPOSE_DIR && sudo docker-compose down"
            fi
            print_info "Bootstrap ノードを安全に停止したよ！"
        else
            error_exit "docker-compose.yml が見つからないよ: $BOOTSTRAP_COMPOSE_DIR/docker-compose.yml"
        fi
    else
        error_exit "Bootstrap ディレクトリが見つからないよ: $BOOTSTRAP_COMPOSE_DIR"
    fi
    
    # データベース移動
    if [ -d "$src_db" ]; then
        local db_size_human=$(du -sh "$src_db" | awk '{print $1}')
        print_info "データベース $db_size_human を移動します"
        log "データベースサイズ: $db_size_human" "INFO"
        mkdir -p "$dest_db" || error_exit "$dest_db の作成に失敗"
        fix_dir_permissions "$dest_db"
        # ディレクトリ内容をログに記録
        #ls -lR "$src_db" > "$SHOESTRING_DIR/log/src_db_contents.log" 2>&1
        #log "Bootstrap データベース内容: $(cat "$SHOESTRING_DIR/log/src_db_contents.log")" "DEBUG"
        # ディレクトリ構造を保持して移動
        sudo mv "$src_db"/* "$dest_db/" 2>>"$SHOESTRING_DIR/log/data_copy.log" || {
            log "データベース移動エラー: $(tail -n 20 "$SHOESTRING_DIR/log/data_copy.log")" "ERROR"
            error_exit "データベースの移動に失敗。ログを確認してね: cat $SHOESTRING_DIR/log/data_copy.log"
        }
        sudo rmdir "$src_db" 2>/dev/null || true
        #ls -lR "$dest_db" > "$SHOESTRING_DIR/log/dest_db_contents.log" 2>&1
        #log "Shoestring データベース内容: $(cat "$SHOESTRING_DIR/log/dest_db_contents.log")" "DEBUG"
        print_info "データベースを移動したよ: $dest_db"
    else
        print_warning "データベースが見つからないよ: $src_db。移動はスキップ。"
    fi
    
    # チェーンデータ移動
    if [ -d "$src_data" ]; then
        local data_size_human=$(du -sh "$src_data" | awk '{print $1}')
        print_info "チェーンデータ $data_size_human を移動します"
        log "チェーンデータサイズ: $data_size_human" "INFO"
        mkdir -p "$dest_data" || error_exit "$dest_data の作成に失敗"
        fix_dir_permissions "$dest_data"
        # ディレクトリ内容をログに記録
        #ls -lR "$src_data" > "$SHOESTRING_DIR/log/src_data_contents.log" 2>&1
        #log "Bootstrap データディレクトリ内容: $(cat "$SHOESTRING_DIR/log/src_data_contents.log")" "DEBUG"
        # ディレクトリ構造を保持して移動
        sudo mv "$src_data"/* "$dest_data/" 2>>"$SHOESTRING_DIR/log/data_copy.log" || {
            log "データ移動エラー: $(tail -n 20 "$SHOESTRING_DIR/log/data_copy.log")" "ERROR"
            error_exit "チェーンデータの移動に失敗。ログを確認してね: cat $SHOESTRING_DIR/log/data_copy.log"
        }
        sudo rmdir "$src_data" 2>/dev/null || true
        # 移動後の内容をログに記録
        #ls -lR "$dest_data" > "$SHOESTRING_DIR/log/dest_data_contents.log" 2>&1
        #log "Shoestring データディレクトリ内容: $(cat "$SHOESTRING_DIR/log/dest_data_contents.log")" "DEBUG"
        print_info "チェーンデータを移動したよ: $dest_data"
    else
        print_warning "データが見つからないよ: $src_data。移動はスキップ。"
    fi
}

# Shoestring セットアップ
setup_shoestring() {
    print_info "Shoestring ノードをセットアップするよ"
    source "$SHOESTRING_DIR/shoestring-env/bin/activate" || error_exit "仮想環境の有効化に失敗"
    local shoestring_subdir="$SHOESTRING_DIR/shoestring"
    mkdir -p "$shoestring_subdir" || error_exit "$shoestring_subdir の作成に失敗"
    fix_dir_permissions "$shoestring_subdir"
    local network_type
    IFS=' ' read -r network_type FRIENDLY_NAME <<< "$(detect_network_and_roles)"
    print_info "検出したネットワーク: $network_type、ノード名: $FRIENDLY_NAME"
    log "Parsed - network_type: $network_type, friendly_name: $FRIENDLY_NAME" "DEBUG"
    local host_name
    host_name=$(extract_host)
    print_info "検出したホスト: $host_name"
    local config_file="$shoestring_subdir/shoestring.ini"
    print_info "shoestring.ini を初期化するよ"
    log "python3 -m shoestring init \"$config_file\" --package $network_type" "DEBUG"
    python3 -m shoestring init "$config_file" --package "$network_type" > "$SHOESTRING_DIR/log/install_shoestring.log" 2>&1 || error_exit "shoestring.ini の初期化に失敗。手動で確認してね: python3 -m shoestring init $config_file"
    # --- shoestring.ini の [node] を更新 ---
    print_info "shoestring.ini の [node] を friendly_name とロールで更新するよ"
    cp "$config_file" "$SHOESTRING_DIR/log/shoestring.ini.pre-node-update-$(date +%Y%m%d_%H%M%S)"
    local friendly_name_escaped=$(printf '%s' "$FRIENDLY_NAME" | sed 's/[.*]/\\&/g')
    sed -i "/^\[node\]/,/^\[.*\]/ s|^caCommonName\s*=.*|caCommonName = CA $friendly_name_escaped|" "$config_file"
    sed -i "/^\[node\]/,/^\[.*\]/ s|^nodeCommonName\s*=.*|nodeCommonName = $friendly_name_escaped|" "$config_file"
    # --- lightApi = false を設定 ---
    sed -i "/^\[node\]/,/^\[.*\]/ s|^lightApi\s*=.*|lightApi = false|" "$config_file"
    # --- ロールの設定 ---
    local src_votingkeys="$BOOTSTRAP_DIR/nodes/node/votingkeys"
    local src_harvester="$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-harvesting.properties"
    local features="API | HARVESTER"
    if [ -f "$src_harvester" ]; then
        print_info "Bootstrap に config-harvesting.properties が見つかりました: $src_harvester。HARVESTER ロールを有効にします。"
        log "HARVESTER ロール検出: $src_harvester" "INFO"
    else
        print_warning "Bootstrap に config-harvesting.properties が見つかりません: $src_harvester。HARVESTER ロールは無効になります。"
        log "HARVESTER ロールなし: $src_harvester" "WARNING"
        features="API"
    fi
    if [ -d "$src_votingkeys" ]; then
        print_info "Bootstrap に votingkeys が見つかりました: $src_votingkeys。VOTING ノードとして設定します。"
        log "VOTING ロール検出: $src_votingkeys" "INFO"
        features="$features | VOTER"
    else
        print_info "Bootstrap に votingkeys が見つかりません: $src_votingkeys。DUAL ノードとして設定します。"
        log "VOTING ロールなし: $src_votingkeys" "INFO"
    fi
    # --- features のエスケープ ---
    log "設定する features: $features" "DEBUG"
    local features_escaped=$(printf '%s' "$features" | sed 's/|/\\|/g')
    log "エスケープした features: $features_escaped" "DEBUG"
    sed -i "/^\[node\]/,/^\[.*\]/ s|^features\s*=.*|features = $features_escaped|" "$config_file" || {
        log "sed エラー: sed -i '/^\\[node\\]/,/^\\[.*\\]/ s|^features\\s*=.*|features = $features_escaped|' $config_file" "ERROR"
        error_exit "features の設定に失敗しました。ログを確認してください: cat $SHOESTRING_DIR/log/setup.log"
    }
    grep -A 10 '^\[node\]' "$config_file" > "$SHOESTRING_DIR/log/node_snippet.log" 2>&1
    log "[node] 更新後: $(cat "$SHOESTRING_DIR/log/node_snippet.log" | sed 's/["'\'']/\\/g')" "DEBUG"
    validate_ini "$config_file"
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
        cp "$config_file" "$SHOESTRING_DIR/log/shoestring.ini.pre-import-$(date +%Y%m%d_%H%M%S)"
        log "python3 -m shoestring import-bootstrap --config \"$config_file\" --bootstrap \"$BOOTSTRAP_DIR\" --include-node-key" "DEBUG"
        python3 -m shoestring import-bootstrap --config "$config_file" --bootstrap "$BOOTSTRAP_DIR" --include-node-key > "$SHOESTRING_DIR/log/import_bootstrap.log" 2>&1 || error_exit "import-bootstrap に失敗。ログを確認してね: cat $SHOESTRING_DIR/log/import_bootstrap.log"
        # ca.key.pem 生成（main.privateKey を使用、パスフレーズなし）
        print_info "Bootstrap の main.privateKey を使用して ca.key.pem を生成するよ"
        local main_private_key
        if command -v yq >/dev/null 2>&1; then
            main_private_key=$(yq e '.main.privateKey' "$BOOTSTRAP_DIR/addresses.yml" 2>>"$SHOESTRING_DIR/log/pemtool.log")
            if [ -z "$main_private_key" ] || [ "$main_private_key" = "null" ]; then
                print_warning "yq で main.privateKey の抽出に失敗。grep を試みます..."
                main_private_key=$(grep -A 2 'main:' "$BOOTSTRAP_DIR/addresses.yml" | grep 'privateKey:' | sed 's/.*privateKey:\s*//')
            fi
        else
            print_warning "yq が見つからないよ。grep で main.privateKey を抽出します..."
            main_private_key=$(grep -A 2 'main:' "$BOOTSTRAP_DIR/addresses.yml" | grep 'privateKey:' | sed 's/.*privateKey:\s*//')
        fi
        if [ -z "$main_private_key" ]; then
            error_exit "main.privateKey の抽出に失敗しました。addresses.yml を確認してください: cat $BOOTSTRAP_DIR/addresses.yml"
        fi
        log "main.privateKey（最初の12文字）: ${main_private_key:0:12}..." "DEBUG"
        local temp_key_file=$(mktemp)
        echo "$main_private_key" > "$temp_key_file"
        python3 -m shoestring pemtool --input "$temp_key_file" --output "$ca_key_path" >> "$SHOESTRING_DIR/log/pemtool.log" 2>&1 || {
            log "pemtool エラー: $(tail -n 20 "$SHOESTRING_DIR/log/pemtool.log")" "ERROR"
            rm -f "$temp_key_file"
            error_exit "ca.key.pem の生成に失敗しました。ログを確認してください: cat $SHOESTRING_DIR/log/pemtool.log"
        }
        rm -f "$temp_key_file"
        chmod 600 "$ca_key_path" || error_exit "ca.key.pem の権限設定に失敗: chmod 600 $ca_key_path"
        print_info "ca.key.pem を生成（パスフレーズなし）: $ca_key_path"
    else
        print_info "node.key.pem が見つからないため、新しい ca.key.pem を生成するよ"
        local main_private_key
        if command -v yq >/dev/null 2>&1; then
            main_private_key=$(yq e '.main.privateKey' "$BOOTSTRAP_DIR/addresses.yml" 2>>"$SHOESTRING_DIR/log/pemtool.log")
            if [ -z "$main_private_key" ] || [ "$main_private_key" = "null" ]; then
                print_warning "yq で main.privateKey の抽出に失敗。grep を試みます..."
                main_private_key=$(grep -A 2 'main:' "$BOOTSTRAP_DIR/addresses.yml" | grep 'privateKey:' | sed 's/.*privateKey:\s*//')
            fi
        else
            print_warning "yq が見つからないよ。grep で main.privateKey を抽出します..."
            main_private_key=$(grep -A 2 'main:' "$BOOTSTRAP_DIR/addresses.yml" | grep 'privateKey:' | sed 's/.*privateKey:\s*//')
        fi
        if [ -z "$main_private_key" ]; then
            error_exit "main.privateKey の抽出に失敗しました。addresses.yml を確認してください: cat $BOOTSTRAP_DIR/addresses.yml"
        fi
        log "main.privateKey（最初の12文字）: ${main_private_key:0:12}..." "DEBUG"
        local temp_key_file=$(mktemp)
        echo "$main_private_key" > "$temp_key_file"
        python3 -m shoestring pemtool --input "$temp_key_file" --output "$ca_key_path" >> "$SHOESTRING_DIR/log/pemtool.log" 2>&1 || {
            log "pemtool エラー: $(tail -n 20 "$SHOESTRING_DIR/log/pemtool.log")" "ERROR"
            rm -f "$temp_key_file"
            error_exit "ca.key.pem の生成に失敗しました。ログを確認してください: cat $SHOESTRING_DIR/log/pemtool.log"
        }
        rm -f "$temp_key_file"
        chmod 600 "$ca_key_path" || error_exit "ca.key.pem の権限設定に失敗: chmod 600 $ca_key_path"
        print_info "ca.key.pem を生成（パスフレーズなし）: $ca_key_path"
        cp "$config_file" "$SHOESTRING_DIR/log/shoestring.ini.pre-import-$(date +%Y%m%d_%H%M%S)"
        log "python3 -m shoestring import-bootstrap --config \"$config_file\" --bootstrap \"$BOOTSTRAP_DIR\"" "DEBUG"
        python3 -m shoestring import-bootstrap --config "$config_file" --bootstrap "$BOOTSTRAP_DIR" > "$SHOESTRING_DIR/log/import_bootstrap.log" 2>&1 || error_exit "import-bootstrap に失敗。ログを確認してね: cat $SHOESTRING_DIR/log/import_bootstrap.log"
    fi
    # --- config-harvesting.properties と votingkeys をコピー ---
    local dest_harvester="$shoestring_subdir/config-harvesting.properties"
    local dest_votingkeys="$shoestring_subdir/votingkeys"
    if [ -f "$src_harvester" ]; then
        cp "$src_harvester" "$dest_harvester" || error_exit "Failed to copy config-harvesting.properties: $src_harvester"
        fix_dir_permissions "$(dirname "$dest_harvester")"
        print_info "config-harvesting.properties をコピーしました: $dest_harvester"
    else
        print_warning "config-harvesting.properties が見つからないよ: $src_harvester。コピーはスキップ。"
    fi
    if [ -d "$src_votingkeys" ]; then
        cp -r "$src_votingkeys" "$dest_votingkeys" || error_exit "Failed to copy votingkeys: $src_votingkeys"
        fix_dir_permissions "$dest_votingkeys"
        print_info "votingkeys ディレクトリをコピーしました: $dest_votingkeys"
    else
        print_info "votingkeys ディレクトリが見つからないため、コピーはスキップ: $src_votingkeys"
    fi
    # --- shoestring.ini の [imports] を更新 ---
    local absolute_harvester="$dest_harvester"
    local absolute_votingkeys="$dest_votingkeys"
    local absolute_node_key
    if [ "$NODE_KEY_FOUND" = true ]; then
        absolute_node_key=$(realpath "$dest_node_key" 2>/dev/null || echo "$dest_node_key")
    else
        absolute_node_key=$(realpath "$ca_key_path" 2>/dev/null || echo "$ca_key_path")
    fi
    print_info "shoestring.ini の [imports] を更新するよ"
    cp "$config_file" "$SHOESTRING_DIR/log/shoestring.ini.pre-imports-update-$(date +%Y%m%d_%H%M%S)"
    local absolute_harvester_escaped=$(printf '%s' "$absolute_harvester" | sed 's/[.*]/\\&/g')
    local absolute_votingkeys_escaped=$(printf '%s' "$absolute_votingkeys" | sed 's/[.*]/\\&/g')
    local absolute_node_key_escaped=$(printf '%s' "$absolute_node_key" | sed 's/[.*]/\\&/g')
    if [ -f "$src_harvester" ]; then
        sed -i "/^\[imports\]/,/^\[.*\]/ s|^harvester\s*=.*|harvester = $absolute_harvester_escaped|" "$config_file"
    else
        sed -i "/^\[imports\]/,/^\[.*\]/ s|^harvester\s*=.*|harvester =|" "$config_file"
    fi
    if [ -d "$src_votingkeys" ]; then
        sed -i "/^\[imports\]/,/^\[.*\]/ s|^voter\s*=.*|voter = $absolute_votingkeys_escaped|" "$config_file"
    else
        sed -i "/^\[imports\]/,/^\[.*\]/ s|^voter\s*=.*|voter =|" "$config_file"
    fi
    sed -i "/^\[imports\]/,/^\[.*\]/ s|^nodeKey\s*=.*|nodeKey = $absolute_node_key_escaped|" "$config_file"
    grep -A 5 '^\[imports\]' "$config_file" > "$SHOESTRING_DIR/log/imports_snippet.log" 2>&1
    log "[imports] 更新後: $(cat "$SHOESTRING_DIR/log/imports_snippet.log" | sed 's/["'\'']/\\/g')" "DEBUG"
    # --- harvester パスの検証 ---
    if [ -f "$src_harvester" ] && grep -q "^harvester\s*=\s*$absolute_harvester_escaped" "$config_file"; then
        print_info "harvester パスが正しく更新されました: $absolute_harvester"
    elif [ ! -f "$src_harvester" ] && grep -q "^harvester\s*=\s*$" "$config_file"; then
        print_info "harvester パスは空（HARVESTER ロールなし）"
    else
        print_warning "harvester パスの更新に失敗。手動で確認してね: cat $config_file"
        log "harvester パス更新失敗。現在の [imports]: $(grep -A 5 '^\[imports\]' "$config_file")" "WARNING"
    fi
    validate_ini "$config_file"
    if ! $SKIP_CONFIRM; then
        confirm_and_edit_ini "$config_file"
    fi
    print_info "shoestring.ini を生成: $config_file"
    local overrides_file="$shoestring_subdir/overrides.ini"
    print_info "overrides.ini を生成するよ"
    if [ -f "$overrides_file" ]; then
        mv "$overrides_file" "$overrides_file.bak-$(date +%Y%m%d_%H%M%S)"
        print_info "既存の overrides.ini をバックアップして: $overrides_file.bak-$(date +%Y%m%d_%H%M%S)"
    fi
    # overrides.ini の初期生成を簡略化し、set_beneficiary_address に委譲
    echo "[user.account]" | sudo tee "$overrides_file" >/dev/null
    echo "enableDelegatedHarvestersAutoDetection = true" | sudo tee -a "$overrides_file" >/dev/null
    echo "" | sudo tee -a "$overrides_file" >/dev/null
    echo "[node.node]" | sudo tee -a "$overrides_file" >/dev/null
    echo "minFeeMultiplier = 100" | sudo tee -a "$overrides_file" >/dev/null
    echo "" | sudo tee -a "$overrides_file" >/dev/null
    echo "[node.localnode]" | sudo tee -a "$overrides_file" >/dev/null
    echo "host = $host_name" | sudo tee -a "$overrides_file" >/dev/null
    echo "friendlyName = $FRIENDLY_NAME" | sudo tee -a "$overrides_file" >/dev/null
    sudo chown $(whoami):$(whoami) "$overrides_file"
    chmod u+rw "$overrides_file"
    # beneficiaryAddress を動的に設定
    set_beneficiary_address
    validate_ini "$overrides_file"
    if ! $SKIP_CONFIRM; then
        confirm_and_edit_ini "$overrides_file"
    fi
    print_info "overrides.ini を生成しました"
    print_info "Shoestring のセットアップを実行するよ"
    log "python3 -m shoestring setup --ca-key-path \"$ca_key_path\" --config \"$config_file\" --overrides \"$overrides_file\" --directory \"$shoestring_subdir\" --package $network_type" "DEBUG"
    python3 -m shoestring setup --ca-key-path "$ca_key_path" --config "$config_file" --overrides "$overrides_file" --directory "$shoestring_subdir" --package "$network_type" > "$SHOESTRING_DIR/log/setup_shoestring.log" 2>&1 || error_exit "Shoestring ノードのセットアップに失敗。ログを確認してね: cat $SHOESTRING_DIR/log/setup_shoestring.log"
    copy_data
    print_info "Shoestring ノードを起動するよ"
    cd "$shoestring_subdir" || error_exit "ディレクトリ移動に失敗したよ: $shoestring_subdir"
    print_info "Docker の古いリソースをクリアするよ(ネットワーク整理)"
    docker system prune -a --volumes --force >> "$SHOESTRING_DIR/log/docker_cleanup.log" 2>&1
    # ポート競合チェック
    print_info "ポート競合をチェックするよ..."
    if command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -E ':3000' > "$SHOESTRING_DIR/log/port_check.log" 2>&1
        if [ -s "$SHOESTRING_DIR/log/port_check.log" ]; then
            log "ポート競合検出: $(cat "$SHOESTRING_DIR/log/port_check.log")" "ERROR"
            error_exit "ポート3000が使用中だよ！Bootstrap や他のプロセスを停止してね: cat $SHOESTRING_DIR/log/port_check.log"
        fi
    else
        print_warning "netstat が見つからないよ。ポート競合チェックをスキップ。"
    fi
    docker-compose up -d > "$SHOESTRING_DIR/log/docker_compose.log" 2>&1 || error_exit "Shoestring ノードの起動に失敗。ログを確認してね: cat $SHOESTRING_DIR/log/docker_compose.log"
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
    echo "  - 投票鍵ディレクトリ: $SHOESTRING_DIR/shoestring/votingkeys"
    echo "  - バックアップ: $BACKUP_DIR"
    echo "  - ログ: $SHOESTRING_DIR/log/setup.log"
    echo "  - 設定: $SHOESTRING_DIR/shoestring/shoestring.ini"
    echo "  - 上書き設定: $SHOESTRING_DIR/shoestring/overrides.ini"
    echo "  - Docker Compose: $SHOESTRING_DIR/shoestring/docker-compose.yml"
    echo "  - データベース: $SHOESTRING_DIR/shoestring/dbdata"
    echo "  - データ: $SHOESTRING_DIR/shoestring/data"
    echo
    if [ "$NODE_KEY_FOUND" = true ]; then
        print_warning "node.key.pem, config-harvesting.properties, votingkeys は安全な場所にバックアップして保管してね！"
    else
        print_warning "ca.key.pem, config-harvesting.properties, votingkeys は安全な場所にバックアップして保管してね！"
    fi
    print_info "ノードの状態を確認するには:"
    echo "  1. コンテナ確認: docker ps"
    echo "  2. ログを確認: cd \"$SHOESTRING_DIR/shoestring\" && docker-compose logs -f"
    echo "  3. REST API 確認: curl http://localhost:3000"
    print_info "ノードタイプを変更したい場合: nano $SHOESTRING_DIR/shoestring/shoestring.ini で [node] の features や lightApi を編集"
    local display_name="${FRIENDLY_NAME:-mikun-sai-node}"
    print_info "ノード名は friendlyName（$display_name）で自動設定されました: caCommonName=CA $display_name, nodeCommonName=$display_name"
    print_info "harvester は Shoestring 内のパスに設定されました: $SHOESTRING_DIR/shoestring/config-harvesting.properties"
    print_info "ログの詳細を確認: tail -f $SHOESTRING_DIR/log/setup.log"
    print_info "データコピーエラー: cat $SHOESTRING_DIR/log/data_copy.log"
    print_info "import-bootstrap が失敗した場合は、yq を使った方法を試してね: https://github.com/mikunNEM/bootstrap-to-shoestring"
    print_info "サポート: https://x.com/mikunNEM"
}

# 主処理
main() {
    print_info "Symbol Bootstrap から Shoestring への移行を始めるよ！"
    
    # グローバル変数を初期化
    auto_detect_dirs
    mkdir -p "$SHOESTRING_DIR/log" || error_exit "ログディレクトリ $SHOESTRING_DIR/log の作成に失敗"
    fix_dir_permissions "$SHOESTRING_DIR/log"
    LOG_FILE="$SHOESTRING_DIR/log/setup.log"
    
    # ログディレクトリを作成
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    log "Starting migration process..." "INFO"
    
    # 基本的な環境チェック
    print_info "基本環境をチェックするよ"
    
    install_dependencies
    collect_user_info
    
    # LOG_FILE と関連変数を再設定
    LOG_FILE="$SHOESTRING_DIR/log/setup.log"
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
