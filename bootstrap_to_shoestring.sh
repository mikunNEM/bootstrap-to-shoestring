#!/bin/bash

# =============================================================================
# Bootstrap → Shoestring 簡単移行スクリプト（完全版）
# 初心者でも安心してBootstrapからShoestringに移行できます
# =============================================================================

set -e  # エラーが発生したら停止

# 色付きメッセージ用の関数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${PURPLE}=================================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}=================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# ユーザー入力を求める関数
ask_user() {
    local question="$1"
    local default="$2"
    local response
    
    if [ -n "$default" ]; then
        echo -e "${BLUE}$question${NC}"
        echo -e "${BLUE}例: $default${NC}"
        echo -e "${BLUE}デフォルト（Enterで選択）: $default${NC}"
    else
        echo -e "${BLUE}$question${NC}"
        echo -e "${BLUE}例: shoestring${NC}"
    fi
    
    while true; do
        read -r response
        if [ -z "$response" ] && [ -n "$default" ]; then
            response="$default"
        fi
        if [ -z "$response" ]; then
            echo -e "${RED}❌ 入力してください。${NC}"
            continue
        fi
        # 空白文字のみの入力を拒否
        if [[ "$response" =~ ^[[:space:]]*$ ]]; then
            echo -e "${RED}❌ 空白のみの入力は無効です。${NC}"
            continue
        fi
        # 絶対パスでない場合、現在のディレクトリ基準に変換
        if [[ ! "$response" =~ ^/ ]]; then
            response="$(pwd)/$response"
        fi
        echo "$response"
        break
    done
}

# 確認を求める関数
confirm() {
    local question="$1"
    local response
    
    while true; do
        echo -e "${YELLOW}$question (y/n): ${NC}"
        read -r response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "y または n で答えてください。";;
        esac
    done
}

# Python バージョンを比較する関数
version_compare() {
    local v1=$1
    local v2=$2
    # バージョンを . で分割
    IFS='.' read -r -a v1_parts <<< "$v1"
    IFS='.' read -r -a v2_parts <<< "$v2"
    
    # メジャーバージョン（3）を比較
    if [ "${v1_parts[0]}" -lt "${v2_parts[0]}" ]; then
        return 1
    elif [ "${v1_parts[0]}" -gt "${v2_parts[0]}" ]; then
        return 0
    fi
    
    # マイナーバージョン（10、11など）を比較
    if [ "${v1_parts[1]}" -lt "${v2_parts[1]}" ]; then
        return 1
    fi
    
    return 0
}

# システム環境のチェック（修正版）
check_system_environment() {
    print_header "システム環境をチェックしています..."

    # Python バージョンの確認
    local python_version
    python_version=$(python3 --version 2>/dev/null | awk '{print $2}' || echo "不明")
    if [ "$python_version" = "不明" ]; then
        print_error "Python3が見つかりません。"
        if confirm "Python 3.10 をインストールしますか？"; then
            install_python
        else
            print_error "Python 3.10 以上をインストールしてください。例: sudo apt install python3.10"
            exit 1
        fi
    else
        # バージョン比較
        if version_compare "$python_version" "3.10"; then
            print_success "Python 3.10 以上が利用可能です: $python_version"
        else
            print_error "Python 3.10 以上が必要です。現在のバージョン: $python_version"
            if confirm "Python 3.10 をインストールしますか？"; then
                install_python
            else
                print_error "Python 3.10 以上をインストールしてください。例: sudo apt install python3.10"
                exit 1
            fi
        fi
    fi

    # pip の確認と修復
    print_info "pip をチェック中..."
    local pip_bin="$HOME/.local/bin/pip3"
    if ! command -v pip3 &> /dev/null; then
        print_warning "pip が利用できません。最新版をインストールします。"
        curl -s https://bootstrap.pypa.io/get-pip.py -o get-pip.py
        python3 get-pip.py --user || {
            print_error "pip のインストールに失敗しました。インターネット接続を確認し、以下を試してください："
            echo "curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py"
            echo "python3 get-pip.py --user"
            exit 1
        }
        rm get-pip.py
        print_success "pip をインストールしました: $(pip3 --version)"
    else
        print_success "pip は利用可能です: $(pip3 --version)"
    fi

    # PATH に ~/.local/bin を追加
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        print_info "PATH に ~/.local/bin を追加します..."
        export PATH=$HOME/.local/bin:$PATH
        echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc
        print_success "PATH を更新しました"
    fi

    # python3-venv の確認
    if ! python3 -c "import venv" &> /dev/null; then
        print_warning "python3-venv がありません。インストールします。"
        sudo apt update
        sudo apt install python3-venv -y || {
            print_error "python3-venv のインストールに失敗しました。以下を試してください："
            echo "sudo apt install python3-venv"
            exit 1
        }
        print_success "python3-venv をインストールしました"
    fi
}

# Pythonインストール関数
install_python() {
    print_info "システムを検出中..."
    if [[ -f /etc/debian_version ]]; then
        print_info "Ubuntu/Debianを検出しました"
        sudo apt update
        sudo apt install -y python3.10 python3.10-venv python3-pip
        sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1
        print_success "Python 3.10をインストールしました"
    else
        print_error "サポートされていないOSです。Ubuntuを使用してください。"
        exit 1
    fi
}

# Shoestring環境のセットアップ
setup_shoestring_environment() {
    print_header "Shoestring環境をセットアップしています..."

    # ログファイルの設定
    local log_file="$SHOESTRING_DIR/setup.log"
    print_info "セットアップの詳細は $log_file に記録されます"

    # SHOESTRING_DIRが空の場合
    while [ -z "$SHOESTRING_DIR" ]; do
        echo -e "${RED}❌ SHOESTRING_DIRが設定されていません。${NC}"
        echo -e "${GREEN}以下のプロンプトでフォルダ名を指定してください。${NC}"
        echo ""
        echo -e "${BLUE}ℹ️ 新しいShoestringノードのフォルダ名を指定してください。${NC}"
        echo -e "${BLUE}このフォルダは現在の場所（$(pwd)）に作られます。${NC}"
        echo -e "${BLUE}例: shoestring（事前に作ったフォルダ名を入力してください）${NC}"
        local default_dir="shoestring"
        if [[ "$(basename "$(pwd)")" != "shoestring" ]]; then
            default_dir="shoestring-node"
        fi
        SHOESTRING_DIR=$(ask_user "新しいShoestringノードのフォルダ名を指定してください" "$default_dir")
        if [ -z "$SHOESTRING_DIR" ]; then
            print_error "フォルダ名を指定してください。"
            continue
        fi
        # ディレクトリが存在しない場合、作成
        if [ ! -d "$SHOESTRING_DIR" ]; then
            print_info "フォルダ $SHOESTRING_DIR を作成中..."
            mkdir -p "$SHOESTRING_DIR" >> "$log_file" 2>&1 || {
                print_error "フォルダ $SHOESTRING_DIR の作成に失敗しました。書き込み権限を確認してください。"
                echo "詳細: $log_file"
                SHOESTRING_DIR=""
                continue
            }
        fi
        # 書き込み権限を確認
        if [ ! -w "$SHOESTRING_DIR" ]; then
            print_error "フォルダ $SHOESTRING_DIR に書き込み権限がありません。"
            SHOESTRING_DIR=""
            continue
        fi
        print_success "Shoestringフォルダ: $SHOESTRING_DIR"
    done

    # 仮想環境の作成
    if python3 -c "import venv" &> /dev/null; then
        if confirm "Python仮想環境を作成しますか？（推奨）"; then
            print_info "仮想環境を作成中..."
            
            # 仮想環境ディレクトリ
            local venv_dir="$SHOESTRING_DIR/shoestring-env"
            
            # 既存の仮想環境をクリア
            if [ -d "$venv_dir" ]; then
                print_info "既存の仮想環境を削除中..."
                rm -rf "$venv_dir"
            fi
            
            # 仮想環境作成
            python3 -m venv "$venv_dir" >> "$log_file" 2>&1 || {
                print_error "仮想環境の作成に失敗しました: $venv_dir"
                echo "詳細: $log_file"
                echo "ディスク容量や権限を確認してください。"
                exit 1
            }
            
            # 仮想環境の有効化
            source "$venv_dir/bin/activate"
            
            # 仮想環境内の pip をアップグレード
            python3 -m ensurepip --upgrade >> "$log_file" 2>&1
            $venv_dir/bin/pip install --upgrade pip >> "$log_file" 2>&1 || {
                print_error "仮想環境内の pip アップグレードに失敗しました。"
                echo "手動で以下を試してください："
                echo "source $venv_dir/bin/activate"
                echo "pip install --upgrade pip"
                echo "詳細: $log_file"
                deactivate
                exit 1
            }
            
            print_success "仮想環境を作成しました: $venv_dir"
            print_info "今後のコマンド実行時は以下を実行してください:"
            echo "source $venv_dir/bin/activate"
            
            # 環境変数を設定
            export VIRTUAL_ENV="$venv_dir"
            export PATH="$venv_dir/bin:$PATH"
        fi
    fi

    # Shoestringのインストール
    print_info "Shoestringをチェック中..."
    if ! python3 -m shoestring --help &> /dev/null; then
        print_warning "Shoestringがインストールされていません。"
        if confirm "Shoestringをインストールしますか？"; then
            print_info "Shoestringをインストール中..."
            $venv_dir/bin/pip install symbol-shoestring >> "$log_file" 2>&1 || {
                print_error "Shoestringのインストールに失敗しました。"
                echo "手動で以下を試してください："
                echo "source $venv_dir/bin/activate"
                echo "pip install symbol-shoestring"
                echo "詳細: $log_file"
                exit 1
            }
            print_success "Shoestringが正常にインストールされました"
        else
            print_error "Shoestringが必要です。手動でインストールしてください："
            echo "source $venv_dir/bin/activate"
            echo "pip install symbol-shoestring"
            exit 1
        fi
    else
        print_success "Shoestringが見つかりました"
        local shoestring_version
        shoestring_version=$(python3 -c "import pkg_resources; print(pkg_resources.get_distribution('symbol-shoestring').version)" 2>/dev/null || echo "不明")
        print_info "Shoestringバージョン: $shoestring_version"
    fi

    # 必要なライブラリの確認（仮想環境内でチェック）
    print_info "必要なライブラリをチェック中..."
    local missing_libs=()
    for lib in "aiohttp" "cryptography" "docker" "pyyaml" "html5lib"; do
        if ! "$venv_dir/bin/python" -c "import $lib" &> /dev/null; then
            missing_libs+=("$lib")
        fi
    done
    if [ ${#missing_libs[@]} -gt 0 ]; then
        print_warning "不足しているライブラリ: ${missing_libs[*]}"
        print_info "自動的にインストールします..."
        $venv_dir/bin/pip install "${missing_libs[@]}" >> "$log_file" 2>&1 || {
            print_error "ライブラリのインストールに失敗しました: ${missing_libs[*]}"
            echo "詳細: $log_file"
            exit 1
        }
        print_success "必要なライブラリをインストールしました"
    else
        print_success "必要なライブラリが揃っています"
    fi
}

# 前提条件チェック
check_prerequisites() {
    print_header "その他の前提条件をチェックしています..."
    
    # Dockerの確認
    if ! command -v docker &> /dev/null; then
        print_error "Dockerがインストールされていません。"
        echo "インストールするには: sudo apt install docker.io"
        exit 1
    fi
    print_success "Dockerが見つかりました"
    
    # Dockerサービスの確認
    if ! docker info &> /dev/null; then
        print_error "Dockerサービスが起動していません。"
        echo "以下のコマンドでDockerを起動してください:"
        echo "sudo systemctl start docker"
        echo "sudo systemctl enable docker"
        exit 1
    fi
    print_success "Dockerサービスが起動しています"
    
    # Docker Composeの確認
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Composeがインストールされていません。"
        echo "インストールするには: sudo apt install docker-compose"
        exit 1
    fi
    print_success "Docker Composeが見つかりました"
    
    # Docker権限の確認
    if ! docker ps &> /dev/null; then
        print_error "Dockerを実行する権限がありません。"
        echo "以下のコマンドでユーザーをdockerグループに追加してください:"
        echo "sudo usermod -aG docker $USER"
        echo "その後、ログアウト・ログインしてください。"
        exit 1
    fi
    print_success "Docker権限が正常です"
    
    # rootユーザーチェック
    if [ "$EUID" -eq 0 ]; then
        print_error "このスクリプトはrootユーザーでは実行できません。"
        print_info "一般ユーザーで実行してください。"
        exit 1
    fi
    print_success "一般ユーザーで実行されています"
    
    # ディスク容量チェック
    local available_space=$(df -h . | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ "$available_space" =~ ^[0-9]+$ ]] && [ "$available_space" -lt 10 ]; then
        print_warning "使用可能ディスク容量が少ない可能性があります: ${available_space}GB"
        print_info "Symbolノードには最低20GB以上の空き容量を推奨します"
        if ! confirm "続行しますか？"; then
            exit 1
        fi
    else
        print_success "十分なディスク容量があります"
    fi
}

# ユーザー情報の収集
collect_user_info() {
    print_header "移行に必要な情報を収集しています..."
    
    echo "移行を開始する前に、いくつかの情報が必要です。"
    echo ""
    
    # Bootstrapディレクトリの確認
    while true; do
        echo -e "${BLUE}ℹ️ Bootstrapのtargetフォルダを指定してください。${NC}"
        echo -e "${BLUE}このフォルダには、既存のBootstrapノードのデータ（例：nodes/node）が含まれています。${NC}"
        BOOTSTRAP_DIR=$(ask_user "Bootstrapのtargetフォルダのパスを入力してください" "$HOME/bootstrap/target")
        
        if [ -z "$BOOTSTRAP_DIR" ]; then
            print_error "フォルダを指定してください。"
            continue
        fi
        
        if [ -d "$BOOTSTRAP_DIR" ]; then
            if [ -d "$BOOTSTRAP_DIR/nodes/node" ]; then
                print_success "Bootstrapフォルダが見つかりました: $BOOTSTRAP_DIR"
                break
            else
                print_error "正しいBootstrapのtargetフォルダではありません。"
                print_info "例: $HOME/bootstrap/target"
            fi
        else
            print_error "フォルダが存在しません: $BOOTSTRAP_DIR"
        fi
    done
    
    # 新しいShoestringディレクトリ
    while true; do
        echo -e "${BLUE}ℹ️ 新しいShoestringノードのフォルダ名を指定してください。${NC}"
        echo -e "${BLUE}このフォルダは現在の場所（$(pwd)）に作られます。${NC}"
        echo -e "${BLUE}例: shoestring（事前に作ったフォルダ名を入力してください）${NC}"
        local default_dir="shoestring"
        if [[ "$(basename "$(pwd)")" != "shoestring" ]]; then
            default_dir="shoestring-node"
        fi
        SHOESTRING_DIR=$(ask_user "新しいShoestringノードのフォルダ名を指定してください" "$default_dir")
        if [ -z "$SHOESTRING_DIR" ]; then
            print_error "フォルダ名を指定してください。"
            continue
        fi
        # ディレクトリが存在しない場合、作成
        if [ ! -d "$SHOESTRING_DIR" ]; then
            print_info "フォルダ $SHOESTRING_DIR を作成中..."
            mkdir -p "$SHOESTRING_DIR" || {
                print_error "フォルダ $SHOESTRING_DIR の作成に失敗しました。書き込み権限を確認してください。"
                continue
            }
        fi
        # 書き込み権限を確認
        if [ ! -w "$SHOESTRING_DIR" ]; then
            print_error "フォルダ $SHOESTRING_DIR に書き込み権限がありません。"
            continue
        fi
        print_success "Shoestringフォルダ: $SHOESTRING_DIR"
        break
    done
    
    # ネットワークタイプの確認
    echo ""
    echo "ネットワークタイプを選択してください:"
    echo "1) mainnet (メインネット - 本番環境)"
    echo "2) sai (テストネット - テスト環境)"
    
    while true; do
        network_choice=$(ask_user "選択してください (1 または 2)" "1")
        case $network_choice in
            1) NETWORK="mainnet"; break;;
            2) NETWORK="sai"; break;;
            *) echo "1 または 2 を選択してください。";;
        esac
    done
    
    print_success "ネットワーク: $NETWORK"
    
    # バックアップディレクトリ
    while true; do
        echo -e "${BLUE}ℹ️ バックアップフォルダを指定してください。${NC}"
        echo -e "${BLUE}Bootstrapデータのバックアップがこのフォルダに保存されます。${NC}"
        BACKUP_DIR=$(ask_user "バックアップフォルダを指定してください" "$HOME/symbol-bootstrap-backup-$(date +%Y%m%d_%H%M%S)")
        if [ -z "$BACKUP_DIR" ]; then
            print_error "フォルダを指定してください。"
            continue
        fi
        # ディレクトリが存在しない場合、作成
        if [ ! -d "$BACKUP_DIR" ]; then
            print_info "フォルダ $BACKUP_DIR を作成中..."
            mkdir -p "$BACKUP_DIR" || {
                print_error "フォルダ $BACKUP_DIR の作成に失敗しました。書き込み権限を確認してください。"
                continue
            }
        fi
        # 書き込み権限を確認
        if [ ! -w "$BACKUP_DIR" ]; then
            print_error "フォルダ $BACKUP_DIR に書き込み権限がありません。"
            continue
        fi
        print_success "バックアップフォルダ: $BACKUP_DIR"
        break
    done
    
    echo ""
    print_info "設定確認:"
    echo "  Bootstrap: $BOOTSTRAP_DIR"
    echo "  Shoestring: $SHOESTRING_DIR"
    echo "  ネットワーク: $NETWORK"
    echo "  バックアップ: $BACKUP_DIR"
    echo ""
    
    if ! confirm "この設定で移行を開始しますか？"; then
        print_info "移行をキャンセルしました。"
        exit 0
    fi
}

# Bootstrapノードの停止
stop_bootstrap() {
    print_header "Bootstrapノードを停止しています..."
    
    local bootstrap_root=$(dirname "$BOOTSTRAP_DIR")
    
    if [ -f "$bootstrap_root/docker-compose.yml" ] || [ -f "$bootstrap_root/docker-compose.yaml" ]; then
        print_info "Bootstrapノードを停止中..."
        cd "$bootstrap_root"
        docker-compose down || true
        print_success "Bootstrapノードを停止しました"
    else
        print_warning "docker-compose.ymlが見つかりません。手動で停止してください。"
    fi
    
    # Symbol関連コンテナのクリーンアップ
    print_info "Symbol関連のDockerコンテナをクリーンアップ中..."
    docker ps -a | grep -E "(symbol|catapult)" | awk '{print $1}' | xargs -r docker rm -f || true
    print_success "Dockerコンテナをクリーンアップしました"
}

# バックアップ作成
create_backup() {
    print_header "重要なデータをバックアップしています..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Bootstrap全体をバックアップ
    print_info "Bootstrapフォルダ全体をバックアップ中..."
    cp -r "$BOOTSTRAP_DIR" "$BACKUP_DIR/original-bootstrap-target/"
    
    # 重要なファイルを個別にバックアップ
    print_info "重要なファイルをバックアップ中..."
    
    if [ -f "$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-harvesting.properties" ]; then
        cp "$BOOTSTRAP_DIR/nodes/node/server-config/resources/config-harvesting.properties" "$BACKUP_DIR/"
        print_success "ハーベスティング設定をバックアップしました"
    fi
    
    if [ -d "$BOOTSTRAP_DIR/nodes/node/votingkeys" ]; then
        cp -r "$BOOTSTRAP_DIR/nodes/node/votingkeys" "$BACKUP_DIR/"
        print_success "投票鍵をバックアップしました"
    fi
    
    if [ -f "$BOOTSTRAP_DIR/nodes/node/cert/node.key.pem" ]; then
        cp "$BOOTSTRAP_DIR/nodes/node/cert/node.key.pem" "$BACKUP_DIR/"
        print_success "ノード鍵をバックアップしました"
    fi
    
    if [ -f "$BOOTSTRAP_DIR/nodes/node/data/harvesters.dat" ]; then
        cp "$BOOTSTRAP_DIR/nodes/node/data/harvesters.dat" "$BACKUP_DIR/"
        print_success "ハーベスターデータをバックアップしました"
    fi
    
    print_success "バックアップが完了しました: $BACKUP_DIR"
}

# CA秘密鍵の生成
create_ca_key() {
    print_header "CA秘密鍵を生成しています..."
    
    cd "$SHOESTRING_DIR"
    
    echo "CA秘密鍵を生成します。この鍵はノードのセキュリティにとって重要です。"
    print_warning "強力なパスワードを設定することを推奨します！"
    echo ""
    
    if confirm "パスワード付きのCA鍵を生成しますか？（推奨）"; then
        python3 -m shoestring pemtool --output ca.key.pem --ask-pass
    else
        print_warning "パスワードなしのCA鍵を生成します（セキュリティリスクあり）"
        python3 -m shoestring pemtool --output ca.key.pem
    fi
    
    print_success "CA秘密鍵を生成しました: ca.key.pem"
    print_warning "この鍵ファイルは安全な場所にバックアップしてください！"
}

# Shoestring設定の初期化
initialize_shoestring() {
    print_header "Shoestring設定を初期化しています..."
    
    cd "$SHOESTRING_DIR"
    
    print_info "基本設定ファイルの生成中..."
    python3 -m shoestring init --platform "$NETWORK" shoestring.ini
    
    print_success "設定ファイルを生成しました: shoestring.ini"
}

# Bootstrapからのデータインポート
import_bootstrap_data() {
    print_header "Bootstrapからデータをインポートしています..."
    
    cd "$SHOESTRING_DIR"
    
    print_info "Bootstrap設定をインポート中..."
    python3 -m shoestring import-bootstrap \
        --config shoestring.ini \
        --bootstrap "$BOOTSTRAP_DIR" \
        --include-node-key
    
    print_success "Bootstrapデータのインポートが完了しました"
    
    echo ""
    print_info "インポートされた設定:"
    if [ -d "bootstrap-import" ]; then
        ls -la bootstrap-import/
    fi
}

# Shoestringノードのセットアップ
setup_shoestring_node() {
    print_header "Shoestringノードをセットアップしています..."
    
    cd "$SHOESTRING_DIR"
    
    local security_mode="default"
    if [ "$NETWORK" = "sai" ]; then
        security_mode="insecure"
    fi
    
    print_info "ノードセットアップを実行中..."
    python3 -m shoestring setup \
        --config shoestring.ini \
        --platform "$NETWORK" \
        --directory . \
        --ca-key-path ca.key.pem \
        --security "$security_mode"
    
    print_success "Shoestringノードのセットアップが完了しました"
}

# ノードの起動と確認
start_and_verify_node() {
    print_header "ノードを起動して動作を確認しています..."
    
    cd "$SHOESTRING_DIR"
    
    print_info "Dockerコンテナを起動中..."
    docker compose up -d
    
    print_success "ノードを起動しました"
    
    print_info "ノードの初期化を待機中..."
    sleep 30
    
    print_info "ノードの健康状態をチェック中..."
    if python3 -m shoestring health --config shoestring.ini --directory .; then
        print_success "ノードは正常に動作しています！"
    else
        print_warning "ヘルスチェックで問題が検出されました"
        print_info "ログを確認してください: docker compose logs"
    fi
}

# 移行後のガイダンス
show_post_migration_guide() {
    print_header "移行完了！次に行うこと"
    
    echo ""
    print_success "🎉 Bootstrap → Shoestring 移行が完了しました！"
    echo ""
    
    print_info "重要なファイルの場所:"
    echo "  📗 新しいノード: $SHOESTRING_DIR"
    echo "  🔑 CA秘密鍵: $SHOESTRING_DIR/ca.key.pem"
    echo "  ⚙️  設定ファイル: $SHOESTRING_DIR/shoestring.ini"
    echo "  💾 バックアップ: $BACKUP_DIR"
    echo ""
    
    print_info "よく使うコマンド:"
    echo "  🏃 ノード起動: cd $SHOESTRING_DIR && docker compose up -d"
    echo "  🛑 ノード停止: cd $SHOESTRING_DIR && docker compose down"
    echo "  💊 ヘルスチェック: cd $SHOESTRING_DIR && python3 -m shoestring health --config shoestring.ini --directory ."
    echo "  📊 ログ確認: cd $SHOESTRING_DIR && docker compose logs -f"
    echo ""
    
    print_warning "重要な注意事項:"
    echo "  🔐 ca.key.pemは安全な場所にバックアップしてください"
    echo "  💾 $BACKUP_DIR は削除しないでください"
    echo "  📈 ノードの同期には時間がかかります（数時間〜数日）"
    echo "  🔄 定期的にヘルスチェックを実行してください"
    echo ""
    
    print_info "問題が発生した場合:"
    echo "  1. ログを確認: $SHOESTRING_DIR/setup.log"
    echo "  2. ヘルスチェック: cd $SHOESTRING_DIR && python3 -m shoestring health --config shoestring.ini --directory ."
    echo "  3. mikunに質問: https://x.com/mikunNEM"
    echo "  4. バックアップから復旧可能"
    echo ""
    
    if confirm "ノードのログを表示しますか？"; then
        cd "$SHOESTRING_DIR"
        docker compose logs --tail 50
    fi
}

# エラー処理
handle_error() {
    print_error "エラーが発生しました！"
    print_info "ご安心ください、以下の手順で解決できます："
    echo ""
    echo "  1. エラーの詳細を確認: $SHOESTRING_DIR/setup.log"
    echo "  2. インターネット接続を確認"
    echo "  3. ディスク容量を確認: df -h $SHOESTRING_DIR"
    echo "  4. 権限を確認: ls -ld $SHOESTRING_DIR"
    echo "  5. スクリプトを再実行: ./bootstrap_to_shoestring.sh"
    echo ""
    print_info "解決しない場合、mikunに質問してください: https://x.com/mikunNEM"
    
    # 仮想環境がアクティブな場合、非アクティブ化
    if [ -n "$VIRTUAL_ENV" ]; then
        deactivate
    fi
    
    exit 1
}

# メイン実行
main() {
    # エラー時のハンドラ
    trap handle_error ERR
    
    print_header "🚀 Bootstrap → Shoestring 簡単移行スクリプト（完全版）"
    echo ""
    print_info "このスクリプトは、Symbol BootstrapからShoestringへの移行を自動化します。"
    print_info "初心者でも安心！ステップごとにガイドします。"
    echo ""
    print_warning "注意: 移行中はBootstrapノードが停止されます。"
    echo ""
    
    if ! confirm "移行を開始しますか？"; then
        print_info "移行をキャンセルしました。"
        exit 0
    fi
    
    # システム環境のチェック
    check_system_environment
    
    check_prerequisites
    collect_user_info
    
    print_info "作業フォルダを作成中: $SHOESTRING_DIR"
    mkdir -p "$SHOESTRING_DIR"
    
    setup_shoestring_environment
    stop_bootstrap
    create_backup
    create_ca_key
    initialize_shoestring
    import_bootstrap_data
    setup_shoestring_node
    start_and_verify_node
    show_post_migration_guide
    
    print_success "🎉 移行が正常に完了しました！"
}

# スクリプト実行
main "$@"
