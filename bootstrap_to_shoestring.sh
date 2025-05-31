#!/bin/bash

# =============================================================================
# Bootstrap → Shoestring 簡単移行スクリプト（改善版）
# 初心者でも安心してBootstrapからShoestringに移行できます
# Python バージョン要件: >=3.9.2, <4.0.0
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
    local is_path="$3"  # パス入力かどうか（"path" または空）
    local response
    
    if [ -n "$default" ]; then
        echo -e "${BLUE}$question${NC}" >&2
        echo -e "${BLUE}例: $default${NC}" >&2
        echo -e "${BLUE}デフォルト（Enterで選択）: $default${NC}" >&2
    else
        echo -e "${BLUE}$question${NC}" >&2
    fi
    
    while true; do
        read -r response
        if [ -z "$response" ] && [ -n "$default" ]; then
            response="$default"
        fi
        if [ -z "$response" ]; then
            echo -e "${RED}❌ 入力してください。${NC}" >&2
            continue
        fi
        # 空白文字のみの入力を拒否
        if [[ "$response" =~ ^[[:space:]]*$ ]]; then
            echo -e "${RED}❌ 空白のみの入力は無効です。${NC}" >&2
            continue
        fi
        # チルダ（~）を$HOMEに展開（パス入力の場合のみ）
        if [ "$is_path" = "path" ] && [[ "$response" =~ ^~(/|$| ) ]]; then
            response="${response/#\~/$HOME}"
        fi
        # 絶対パスでない場合、現在のディレクトリ基準に変換（パス入力の場合のみ）
        if [ "$is_path" = "path" ] && [[ ! "$response" =~ ^/ ]]; then
            response="$(pwd)/$response"
        fi
        # 空白をトリム
        response=$(echo "$response" | xargs)
        # 戻り値を正確に出力（改行や余計な空白を防ぐ）
        printf "%s" "$response"
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
    local v1=$1  # 例: 3.10.12
    local v2=$2  # 例: 3.9.2
    # バージョンを . で分割
    IFS='.' read -r -a v1_parts <<< "$v1"
    IFS='.' read -r -a v2_parts <<< "$v2"
    
    # 各部分を数値として扱う（0埋め）
    local v1_major=${v1_parts[0]:-0}
    local v1_minor=${v1_parts[1]:-0}
    local v1_patch=${v1_parts[2]:-0}
    local v2_major=${v2_parts[0]:-0}
    local v2_minor=${v2_parts[1]:-0}
    local v2_patch=${v2_parts[2]:-0}
    
    # メジャーバージョン比較
    if [ "$v1_major" -lt "$v2_major" ]; then
        return 1
    elif [ "$v1_major" -gt "$v2_major" ]; then
        return 0
    fi
    
    # マイナーバージョン比較
    if [ "$v1_minor" -lt "$v2_minor" ]; then
        return 1
    elif [ "$v1_minor" -gt "$v2_minor" ]; then
        return 0
    fi
    
    # パッチバージョン比較
    if [ "$v1_patch" -lt "$v2_patch" ]; then
        return 1
    fi
    
    return 0
}

# システム環境のチェック
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
            print_error "Python 3.9.2 以上（4.0.0 未満）をインストールしてください。例: sudo apt install python3.10"
            exit 1
        fi
    else
        # バージョン比較（>=3.9.2）
        if version_compare "$python_version" "3.9.2"; then
            # さらに <4.0.0 をチェック
            if version_compare "$python_version" "4.0.0"; then
                print_error "Python 4.0.0 以上はサポートされていません。現在のバージョン: $python_version"
                if confirm "Python 3.10 をインストールしますか？"; then
                    install_python
                else
                    print_error "Python 3.9.2 以上（4.0.0 未満）をインストールしてください。例: sudo apt install python3.10"
                    exit 1
                fi
            else
                print_success "Python 3.9.2 以上（4.0.0 未満）が利用可能です: $python_version"
            fi
        else
            print_error "Python 3.9.2 以上が必要です。現在のバージョン: $python_version"
            if confirm "Python 3.10 をインストールしますか？"; then
                install_python
            else
                print_error "Python 3.9.2 以上（4.0.0 未満）をインストールしてください。例: sudo apt install python3.10"
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
}

# Pythonインストール関数
install_python() {
    # ログファイルの設定（関数内で使用）
    local log_file="$HOME/setup.log"
    print_info "システムを検出中..."
    if [[ -f /etc/debian_version ]]; then
        print_info "Ubuntu/Debianを検出しました"
        print_info "パッケージのインストールにsudo権限が必要です。パスワードを入力してください。"
        sudo apt update 2>&1 | tee -a "$log_file" || {
            print_error "apt update に失敗しました。インターネット接続を確認してください。"
            echo "詳細: $log_file"
            exit 1
        }
        sudo apt install -y python3.10 python3.10-venv python3-pip 2>&1 | tee -a "$log_file" || {
            print_error "Python 3.10 のインストールに失敗しました。"
            echo "手動で以下を試してください："
            echo "sudo apt install python3.10 python3.10-venv python3-pip"
            echo "詳細: $log_file"
            exit 1
        }
        sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 2>&1 | tee -a "$log_file"
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
        else
            print_info "カレントディレクトリが 'shoestring' です。カレントディレクトリをそのまま使いますか？"
            if confirm "カレントディレクトリ（$(pwd)）をそのまま使いますか？（推奨）"; then
                SHOESTRING_DIR="."
            fi
        fi
        if [ -z "$SHOESTRING_DIR" ]; then
            SHOESTRING_DIR=$(ask_user "新しいShoestringノードのフォルダ名を指定してください" "$default_dir" "path")
        fi
        # 空白をトリム
        SHOESTRING_DIR=$(echo "$SHOESTRING_DIR" | xargs)
        if [ -z "$SHOESTRING_DIR" ]; then
            print_error "フォルダ名を指定してください。"
            continue
        fi
        # カレントディレクトリ指定の場合
        if [ "$SHOESTRING_DIR" = "." ]; then
            SHOESTRING_DIR="$(pwd)"
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
        # ensurepip のチェック
        if python3 -c "import ensurepip" &> /dev/null; then
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
        else
            print_warning "ensurepip が見つかりません。python3.10-venv パッケージをインストールします。"
            print_info "パッケージのインストールにsudo権限が必要です。パスワードを入力してください。"
            sudo apt update 2>&1 | tee -a "$log_file" || {
                print_error "apt update に失敗しました。インターネット接続を確認してください。"
                echo "詳細: $log_file"
                exit 1
            }
            sudo apt install python3.10-venv -y 2>&1 | tee -a "$log_file" || {
                print_error "python3.10-venv のインストールに失敗しました。"
                echo "手動で以下を試してください："
                echo "sudo apt install python3.10-venv"
                echo "詳細: $log_file"
                exit 1
            }
            print_success "python3.10-venv をインストールしました"
            # 再帰的に再試行
            setup_shoestring_environment
        fi
    else
        print_warning "python3-venv がありません。インストールします。"
        print_info "パッケージのインストールにsudo権限が必要です。パスワードを入力してください。"
        sudo apt update 2>&1 | tee -a "$log_file" || {
            print_error "apt update に失敗しました。インターネット接続を確認してください。"
            echo "詳細: $log_file"
            exit 1
        }
        sudo apt install python3-venv -y 2>&1 | tee -a "$log_file" || {
            print_error "python3-venv のインストールに失敗しました。以下を試してください："
            echo "sudo apt install python3-venv"
            echo "詳細: $log_file"
            exit 1
        }
        print_success "python3-venv をインストールしました"
        # 再帰的に再試行
        setup_shoestring_environment
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
            # インストールしたShoestringのバージョンを表示
            local shoestring_version
            shoestring_version=$($venv_dir/bin/python -c "import pkg_resources; print(pkg_resources.get_distribution('symbol-shoestring').version)" 2>/dev/null || echo "不明")
            print_info "インストールしたShoestringバージョン: $shoestring_version"
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
    
    # Bootstrapディレクトリの確認
    while true; do
        echo -e "${BLUE}ℹ️ Bootstrapの「target」フォルダのパスを入力してください（例：/home/mikun/symbol-bootstrap/target）。${NC}"
        BOOTSTRAP_DIR=$(ask_user "Bootstrapのtargetフォルダのパスを入力してください" "" "path")
        
        # 空白をトリム
        BOOTSTRAP_DIR=$(echo "$BOOTSTRAP_DIR" | xargs)
        
        # デバッグ用に値を出力
        print_info "入力されたパス: '$BOOTSTRAP_DIR'"
        
        if [ -z "$BOOTSTRAP_DIR" ]; then
            print_error "フォルダを指定してください。"
            continue
        fi
        
        if [ -d "$BOOTSTRAP_DIR" ]; then
            if [ -d "$BOOTSTRAP_DIR/nodes/node" ]; then
                print_success "Bootstrapフォルダが見つかりました: $BOOTSTRAP_DIR"
                break
            else
                print_error "正しいBootstrapのtargetフォルダではありません（「nodes/node」ディレクトリが見つかりません）。"
                print_info "例: /home/mikun/symbol-bootstrap/target"
            fi
        else
            print_error "フォルダが存在しません: $BOOTSTRAP_DIR"
            print_info "ヒント: 以下のコマンドでtargetフォルダを検索できます。"
            echo "find ~ -type d -name \"target\" 2>/dev/null"
            print_info "見つかったパスを入力してください（例：/home/mikun/symbol-bootstrap/target）。"
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
        else
            print_info "カレントディレクトリが 'shoestring' です。カレントディレクトリをそのまま使いますか？"
            if confirm "カレントディレクトリ（$(pwd)）をそのまま使いますか？（推奨）"; then
                SHOESTRING_DIR="."
            fi
        fi
        if [ -z "$SHOESTRING_DIR" ]; then
            SHOESTRING_DIR=$(ask_user "新しいShoestringノードのフォルダ名を指定してください" "$default_dir" "path")
        fi
        # 空白をトリム
        SHOESTRING_DIR=$(echo "$SHOESTRING_DIR" | xargs)
        if [ -z "$SHOESTRING_DIR" ]; then
            print_error "フォルダ名を指定してください。"
            continue
        fi
        # カレントディレクトリ指定の場合
        if [ "$SHOESTRING_DIR" = "." ]; then
            SHOESTRING_DIR="$(pwd)"
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
        # 空白をトリム
        network_choice=$(echo "$network_choice" | xargs)
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
        echo -e "${BLUE}Bootstrapの重要な設定ファイル（投票鍵、ノード鍵など）がこのフォルダに保存されます。${NC}"
        # タイムゾーンをAsia/Tokyoに設定してdateコマンドを実行
        local default_backup_dir="$HOME/symbol-bootstrap-backup-$(TZ=Asia/Tokyo date +%Y%m%d_%H%M%S)"
        BACKUP_DIR=$(ask_user "" "$default_backup_dir" "path")
        # 空白をトリム
        BACKUP_DIR=$(echo "$BACKUP_DIR" | xargs)
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
    echo "  バックアップ（重要なファイル）: $BACKUP_DIR"
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
    
    # symbol-bootstrap stop を使用してノードを停止
    if command -v symbol-bootstrap &> /dev/null; then
        print_info "symbol-bootstrap stop を実行中..."
        cd "$bootstrap_root"
        symbol-bootstrap stop || {
            print_warning "symbol-bootstrap stop の実行に失敗しました。Dockerコンテナを直接確認します。"
        }
        print_success "Bootstrapノードを停止しました"
    else
        print_warning "symbol-bootstrap コマンドが見つかりません。Dockerコンテナを直接確認します。"
    fi
    
    # Symbol関連コンテナのクリーンアップ
    print_info "Symbol関連のDockerコンテナをクリーンアップ中..."
    # 実行中のコンテナを停止
    docker ps -q --filter "ancestor=symbol" --filter "ancestor=catapult" | xargs -r docker stop || true
    # すべての関連コンテナを削除
    docker ps -a -q --filter "ancestor=symbol" --filter "ancestor=catapult" | xargs -r docker rm -f || true
    print_success "Dockerコンテナをクリーンアップしました"
    
    # プロセスが残っている可能性があるため、さらに確認
    print_info "Symbol関連プロセスをチェック中..."
    if ps aux | grep -i "[c]atapult" > /dev/null; then
        print_warning "Symbol関連プロセスがまだ実行中です。プロセスを終了します。"
        ps aux | grep -i "[c]atapult" | awk '{print $2}' | xargs -r sudo kill -9 || true
        sleep 2
        if ps aux | grep -i "[c]atapult" > /dev/null; then
            print_error "Symbol関連プロセスを停止できませんでした。手動でプロセスを終了してください。"
            echo "プロセスを確認: ps aux | grep -i catapult"
            echo "プロセスを終了: sudo kill -9 <PID>"
            exit 1
        else
            print_success "Symbol関連プロセスを停止しました"
        fi
    else
        print_success "Symbol関連プロセスは実行されていません"
    fi
}

# 重要なデータのバックアップ（ブロックデータは除く）
create_backup() {
    print_header "重要なデータをバックアップしています..."
    
    mkdir -p "$BACKUP_DIR"
    
    # 重要なファイルのみをバックアップ
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
        print_info "新しいCA秘密鍵を生成中..."
        openssl genrsa -aes256 -out ca.key.pem 2048
        # パスワードを設定した場合、フラグを設定
        CA_PASSWORD_SET="true"
    else
        print_warning "パスワードなしのCA鍵を生成します（セキュリティリスクあり）"
        print_info "新しいCA秘密鍵を生成中..."
        openssl genrsa -out ca.key.pem 2048
        CA_PASSWORD_SET="false"
    fi
    
    print_success "CA秘密鍵を生成しました: ca.key.pem"
    print_warning "この鍵ファイルは安全な場所にバックアップしてください！"
}

# Shoestring設定の初期化
initialize_shoestring() {
    print_header "Shoestring設定を初期化しています..."
    
    cd "$SHOESTRING_DIR"
    
    # shoestring.ini がすでに存在するか確認
    if [ -f "shoestring.ini" ]; then
        print_info "既存の設定ファイル（shoestring.ini）が見つかりました。"
        print_info "このファイルをそのまま使用します。"
    else
        print_info "基本設定ファイルの生成中..."
        python3 -m shoestring init --package "$NETWORK" shoestring.ini
        print_success "設定ファイルを生成しました: shoestring.ini"
    fi
    
    print_warning "⚠️  この設定ファイルは、各ノードに合わせて編集する必要があります。"
    print_info "次のステップで、編集を行います。"
}

# shoestring.ini の編集
edit_shoestring_ini() {
    print_header "shoestring.ini を編集します..."
    
    cd "$SHOESTRING_DIR"
    
    # shoestring.ini の存在確認
    if [ ! -f "shoestring.ini" ]; then
        print_error "設定ファイル（shoestring.ini）が見つかりません。"
        print_info "前のステップで生成されているはずです。スクリプトを再実行してください。"
        exit 1
    fi
    
    # バックアップファイルのコピー
    print_info "バックアップされたファイルをShoestringフォルダにコピー中..."
    mkdir -p "$SHOESTRING_DIR/resources"
    
    local import_files=("config-harvesting.properties" "votingkeys" "node.key.pem")
    for file in "${import_files[@]}"; do
        if [ -e "$BACKUP_DIR/$file" ]; then
            cp -r "$BACKUP_DIR/$file" "$SHOESTRING_DIR/resources/"
            print_success "$file をコピーしました: $SHOESTRING_DIR/resources/$file"
        else
            print_warning "$file がバックアップフォルダに見つかりません: $BACKUP_DIR/$file"
        fi
    done
    
    print_info "設定ファイル（shoestring.ini）を表示します:"
    cat shoestring.ini
    echo ""
    
    print_warning "以下の項目は必須です。必ず値を設定してください:"
    echo "  - [node] caCommonName: CAの共通名（例: MyNodeCA）"
    echo "  - [node] nodeCommonName: ノードの共通名（例: MyNode）"
    print_info "必要に応じて以下の項目を編集してください:"
    echo "  - [imports] harvester: ハーベスティング設定ファイル（例: resources/config-harvesting.properties）"
    echo "  - [imports] voter: 投票鍵ディレクトリ（例: resources/votingkeys）"
    echo "  - [imports] nodeKey: ノード鍵ファイル（例: resources/node.key.pem）"
    echo "  - [node] features: ノードの機能（例: API | HARVESTER | VOTER）"
    if [ "$CA_PASSWORD_SET" = "true" ]; then
        echo "  - [node] caPassword: CA秘密鍵のパスワード（必須: CA鍵生成時に設定したパスワード）"
    else
        echo "  - [node] caPassword: CAパスワード（セキュリティのため設定推奨）"
    fi
    echo ""
    
    print_info "現在のターミナルはそのまま開いた状態で、別のターミナルで shoestring.ini ファイルを編集してください。"
    print_info "編集方法（例: nano エディタを使用する場合）:"
    echo "  1. 別のターミナルを開く"
    echo "  2. 以下のコマンドで編集を開始: nano $SHOESTRING_DIR/shoestring.ini"
    echo "  3. 必要な項目を編集"
    echo "  4. 保存して終了: Ctrl+O → Enter → Ctrl+X"
    echo ""
    print_info "編集が完了したら、このターミナルに戻り、Enter を押して続行してください。"
    read -p "（Enter を押してください）"
    
    print_success "設定ファイルの編集が完了しました。"
}

# shoestring.ini の内容確認
verify_shoestring_ini() {
    print_header "shoestring.ini の設定を確認しています..."
    
    cd "$SHOESTRING_DIR"
    
    # shoestring.ini の存在確認
    if [ ! -f "shoestring.ini" ]; then
        print_error "設定ファイル（shoestring.ini）が見つかりません。"
        exit 1
    fi
    
    # 必須項目の検証
    local ca_common_name
    local node_common_name
    local ca_password
    
    ca_common_name=$(grep -A 10 "\[node\]" shoestring.ini | grep "^caCommonName" | cut -d'=' -f2 | xargs)
    node_common_name=$(grep -A 10 "\[node\]" shoestring.ini | grep "^nodeCommonName" | cut -d'=' -f2 | xargs)
    ca_password=$(grep -A 10 "\[node\]" shoestring.ini | grep "^caPassword" | cut -d'=' -f2 | xargs)
    
    local missing_fields=()
    if [ -z "$ca_common_name" ]; then
        missing_fields+=("caCommonName")
    fi
    if [ -z "$node_common_name" ]; then
        missing_fields+=("nodeCommonName")
    fi
    if [ "$CA_PASSWORD_SET" = "true" ] && [ -z "$ca_password" ]; then
        missing_fields+=("caPassword")
    fi
    
    if [ ${#missing_fields[@]} -gt 0 ]; then
        print_error "以下の必須項目が設定されていません: ${missing_fields[*]}"
        print_info "再度編集を行います。"
        edit_shoestring_ini
        # 再帰的に検証
        verify_shoestring_ini
        return
    fi
    
    # [imports] セクションのファイル存在確認（任意項目）
    local harvester
    local voter
    local node_key
    
    harvester=$(grep -A 10 "\[imports\]" shoestring.ini | grep "^harvester" | cut -d'=' -f2 | xargs)
    voter=$(grep -A 10 "\[imports\]" shoestring.ini | grep "^voter" | cut -d'=' -f2 | xargs)
    node_key=$(grep -A 10 "\[imports\]" shoestring.ini | grep "^nodeKey" | cut -d'=' -f2 | xargs)
    
    local missing_files=()
    if [ -n "$harvester" ] && [ ! -f "$SHOESTRING_DIR/$harvester" ]; then
        missing_files+=("harvester: $harvester")
    fi
    if [ -n "$voter" ] && [ ! -d "$SHOESTRING_DIR/$voter" ]; then
        missing_files+=("voter: $voter")
    fi
    if [ -n "$node_key" ] && [ ! -f "$SHOESTRING_DIR/$node_key" ]; then
        missing_files+=("nodeKey: $node_key")
    fi
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_error "以下のファイルが見つかりません: ${missing_files[*]}"
        print_info "再度編集を行います。"
        edit_shoestring_ini
        # 再帰的に検証
        verify_shoestring_ini
        return
    fi
    
    # shoestring.ini の内容を表示
    print_info "設定ファイル（shoestring.ini）の内容:"
    cat shoestring.ini
    echo ""
    
    # ユーザーに確認
    if ! confirm "設定内容に問題がなければ、次に進みます。続行しますか？"; then
        print_info "再度編集を行います。"
        edit_shoestring_ini
        # 再帰的に検証
        verify_shoestring_ini
    fi
}

# overrides.ini の作成
create_overrides_ini() {
    print_header "overrides.ini を作成します..."
    
    cd "$SHOESTRING_DIR"
    
    # overrides.ini がすでに存在するか確認
    if [ -f "overrides.ini" ]; then
        print_info "既存の設定ファイル（overrides.ini）が見つかりました。"
        print_info "このファイルをそのまま使用します。"
    else
        print_info "新しい設定ファイル（overrides.ini）を生成中..."
        cat << EOF > overrides.ini
[user.account]
enableDelegatedHarvestersAutoDetection = true

[harvesting.harvesting]
maxUnlockedAccounts = 5
beneficiaryAddress = 

[node.node]
minFeeMultiplier = 100

[node.localnode]
host = 
friendlyName = 
EOF
        print_success "設定ファイルを生成しました: overrides.ini"
    fi
    
    print_warning "⚠️  この設定ファイルは、各ノードに合わせて編集する必要があります。"
    print_info "次のステップで、編集を行います。"
}

# overrides.ini の編集
edit_overrides_ini() {
    print_header "overrides.ini を編集します..."
    
    cd "$SHOESTRING_DIR"
    
    # overrides.ini の存在確認
    if [ ! -f "overrides.ini" ]; then
        print_error "設定ファイル（overrides.ini）が見つかりません。"
        print_info "前のステップで生成されているはずです。スクリプトを再実行してください。"
        exit 1
    fi
    
    print_info "設定ファイル（overrides.ini）を表示します:"
    cat overrides.ini
    echo ""
    
    print_warning "以下の項目は必須です。必ず値を設定してください:"
    echo "  - [harvesting.harvesting] beneficiaryAddress: 受益者アドレス（例: TBXUTAXCDE2FGHIJ）"
    echo "  - [node.localnode] host: ノードのホスト名（例: localhost または your.domain.com）"
    echo "  - [node.localnode] friendlyName: ノードのフレンドリーネーム（例: MyNode）"
    print_info "必要に応じて以下の項目も編集してください:"
    echo "  - [harvesting.harvesting] maxUnlockedAccounts: 最大アンロックアカウント数（例: 5）"
    echo "  - [node.node] minFeeMultiplier: 最小手数料乗数（例: 100）"
    echo ""
    
    print_info "現在のターミナルはそのまま開いた状態で、別のターミナルで overrides.ini ファイルを編集してください。"
    print_info "編集方法（例: nano エディタを使用する場合）:"
    echo "  1. 別のターミナルを開く"
    echo "  2. 以下のコマンドで編集を開始: nano $SHOESTRING_DIR/overrides.ini"
    echo "  3. 必要な項目を編集"
    echo "  4. 保存して終了: Ctrl+O → Enter → Ctrl+X"
    echo ""
    print_info "編集が完了したら、このターミナルに戻り、Enter を押して続行してください。"
    read -p "（Enter を押してください）"
    
    print_success "設定ファイルの編集が完了しました。"
}

# overrides.ini の内容確認
verify_overrides_ini() {
    print_header "overrides.ini の設定を確認しています..."
    
    cd "$SHOESTRING_DIR"
    
    # overrides.ini の存在確認
    if [ ! -f "overrides.ini" ]; then
        print_error "設定ファイル（overrides.ini）が見つかりません。"
        exit 1
    fi
    
    # 必須項目の検証
    local beneficiary_address
    local host
    local friendly_name
    
    beneficiary_address=$(grep -A 10 "\[harvesting.harvesting\]" overrides.ini | grep "^beneficiaryAddress" | cut -d'=' -f2 | xargs)
    host=$(grep -A 10 "\[node.localnode\]" overrides.ini | grep "^host" | cut -d'=' -f2 | xargs)
    friendly_name=$(grep -A 10 "\[node.localnode\]" overrides.ini | grep "^friendlyName" | cut -d'=' -f2 | xargs)
    
    local missing_fields=()
    if [ -z "$beneficiary_address" ]; then
        missing_fields+=("beneficiaryAddress")
    fi
    if [ -z "$host" ]; then
        missing_fields+=("host")
    fi
    if [ -z "$friendly_name" ]; then
        missing_fields+=("friendlyName")
    fi
    
    if [ ${#missing_fields[@]} -gt 0 ]; then
        print_error "以下の必須項目が設定されていません: ${missing_fields[*]}"
        print_info "再度編集を行います。"
        edit_overrides_ini
        # 再帰的に検証
        verify_overrides_ini
        return
    fi
    
    # overrides.ini の内容を表示
    print_info "設定ファイル（overrides.ini）の内容:"
    cat overrides.ini
    echo ""
    
    # ユーザーに確認
    if ! confirm "設定内容に問題がなければ、Shoestringノードのセットアップを続行します。続行しますか？"; then
        print_info "再度編集を行います。"
        edit_overrides_ini
        # 再帰的に検証
        verify_overrides_ini
    fi
}

# Shoestringノードのセットアップ
setup_shoestring_node() {
    print_header "Shoestringノードをセットアップしています..."
    
    cd "$SHOESTRING_DIR"
    
    # caPassword を読み込み、必要に応じて pass: を付加
    local ca_password
    ca_password=$(grep -A 10 "\[node\]" shoestring.ini | grep "^caPassword" | cut -d'=' -f2 | xargs)
    
    if [ -n "$ca_password" ]; then
        # pass: プレフィックスがなければ付加
        if [[ ! "$ca_password" =~ ^pass: ]]; then
            ca_password="pass:$ca_password"
        fi
        # 一時的な shoestring.ini を作成
        cp shoestring.ini shoestring.ini.tmp
        sed -i "/^\[node\]/,/^\[/ s/^caPassword[[:space:]]*=.*$/caPassword = $ca_password/" shoestring.ini.tmp
    else
        # caPassword が空の場合、CA_PASSWORD_SET と一致するか確認
        if [ "$CA_PASSWORD_SET" = "true" ]; then
            print_error "caPassword が設定されていません。CA鍵にパスワードが設定されています。"
            print_info "shoestring.ini を編集して caPassword を設定してください。"
            edit_shoestring_ini
            verify_shoestring_ini
            # 再帰的に再試行
            setup_shoestring_node
            return
        fi
        cp shoestring.ini shoestring.ini.tmp
    fi
    
    local security_mode="default"
    if [ "$NETWORK" = "sai" ]; then
        security_mode="insecure"
    fi
    
    print_info "ノードセットアップを実行中..."
    python3 -m shoestring setup \
        --ca-key-path ca.key.pem \
        --config shoestring.ini.tmp \
        --overrides overrides.ini \
        --directory "$(pwd)" \
        --package "$NETWORK" \
        --security "$security_mode" || {
            print_error "Shoestringノードのセットアップに失敗しました。"
            print_info "ログを確認してください: $SHOESTRING_DIR/setup.log"
            rm -f shoestring.ini.tmp
            exit 1
        }
    
    # 一時ファイルを削除
    rm -f shoestring.ini.tmp
    
    print_success "Shoestringノードのセットアップが完了しました"
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
    
    # ブロックデータの移行
    echo ""
    print_info "ブロックデータの移行について:"
    print_info "Bootstrapノードのブロックデータを移行すると、同期を最新ブロックから再開できます。"
    print_info "ブロックデータは $SHOESTRING_DIR/data にコピーされます。"
    
    local bootstrap_data_dir="$BOOTSTRAP_DIR/nodes/node/data"
    local shoestring_data_dir="$SHOESTRING_DIR/data"
    
    if [ -d "$bootstrap_data_dir" ]; then
        # ブロックデータのサイズを取得
        local data_size=$(du -sh "$bootstrap_data_dir" 2>/dev/null | awk '{print $1}')
        print_warning "注意: ブロックデータのサイズは $data_size です。"
        
        # 移行先のディスク空き容量を確認
        local available_space=$(df -h "$SHOESTRING_DIR" | awk 'NR==2 {print $4}')
        print_info "移行先のディスク空き容量: $available_space"
        
        # サイズ比較（簡易的なチェック）
        local data_size_bytes=$(du -s "$bootstrap_data_dir" 2>/dev/null | awk '{print $1}')
        local available_space_bytes=$(df "$SHOESTRING_DIR" | awk 'NR==2 {print $4}')
        if [ -n "$data_size_bytes" ] && [ -n "$available_space_bytes" ] && [ "$available_space_bytes" -lt "$data_size_bytes" ]; then
            print_error "ディスク空き容量が不足しています！"
            print_info "ブロックデータ: $data_size"
            print_info "空き容量: $available_space"
            print_info "ディスク容量を増やすか、ブロックデータの移行をスキップしてください。"
            if ! confirm "それでもブロックデータを移行しますか？"; then
                print_info "ブロックデータの移行をスキップしました。"
                print_info "Shoestringノードは1ブロック目から同期を開始します。"
            fi
        fi
    else
        print_warning "Bootstrapノードのブロックデータが見つかりません: $bootstrap_data_dir"
    fi
    
    if [ -d "$bootstrap_data_dir" ] && confirm "ブロックデータを移行しますか？（推奨）"; then
        # rsync がインストールされているか確認
        if ! command -v rsync &> /dev/null; then
            print_warning "rsync が見つかりません。インストールします。"
            print_info "パッケージのインストールにsudo権限が必要です。パスワードを入力してください。"
            sudo apt update 2>&1 | tee -a "$SHOESTRING_DIR/setup.log" || {
                print_error "apt update に失敗しました。インターネット接続を確認してください。"
                echo "詳細: $SHOESTRING_DIR/setup.log"
                exit 1
            }
            sudo apt install rsync -y 2>&1 | tee -a "$SHOESTRING_DIR/setup.log" || {
                print_error "rsync のインストールに失敗しました。"
                echo "手動でインストールしてください: sudo apt install rsync"
                echo "詳細: $SHOESTRING_DIR/setup.log"
                exit 1
            }
            print_success "rsync をインストールしました"
        fi
        
        # 既存のデータディレクトリの内容をクリアするか確認
        if [ -d "$shoestring_data_dir" ] && [ -n "$(ls -A "$shoestring_data_dir")" ]; then
            print_warning "データディレクトリ（$shoestring_data_dir）に既存のデータがあります。"
            if confirm "既存のデータを削除して新しいブロックデータをコピーしますか？（推奨）"; then
                print_info "既存のデータを削除中..."
                rm -rf "$shoestring_data_dir"/*
            else
                print_info "既存のデータを保持して上書きコピーします。"
            fi
        fi
        
        print_info "ブロックデータをコピー中..."
        mkdir -p "$shoestring_data_dir"
        
        # 全体のサイズを取得（バイト単位）
        local total_size_bytes=$(du -sb "$bootstrap_data_dir" 2>/dev/null | awk '{print $1}')
        if [ -z "$total_size_bytes" ] || [ "$total_size_bytes" -eq 0 ]; then
            print_error "ブロックデータのサイズを取得できませんでした: $bootstrap_data_dir"
            exit 1
        fi
        
        # サイズをGBに変換（小数点以下2桁）
        local total_size_gb=$(echo "scale=2; $total_size_bytes / 1024 / 1024 / 1024" | bc)
        
        # rsync をバックグラウンドで実行
        rsync -a "$bootstrap_data_dir/" "$shoestring_data_dir/" &
        local rsync_pid=$!
        
        # 進捗表示
        local copied_size_bytes=0
        local percent=0
        local copied_size_gb=0
        while kill -0 $rsync_pid 2>/dev/null; do
            # コピー済みのサイズを取得（バイト単位）
            copied_size_bytes=$(du -sb "$shoestring_data_dir" 2>/dev/null | awk '{print $1}')
            if [ -z "$copied_size_bytes" ]; then
                copied_size_bytes=0
            fi
            
            # 進捗（%）を計算
            percent=$(( $copied_size_bytes * 100 / $total_size_bytes ))
            if [ $percent -gt 100 ]; then
                percent=100
            fi
            
            # コピー済みのサイズをGBに変換
            copied_size_gb=$(echo "scale=2; $copied_size_bytes / 1024 / 1024 / 1024" | bc)
            
            # 進捗表示（同じ行を上書き）
            echo -ne "\r進捗: $percent%  転送済み: $copied_size_gb GB / $total_size_gb GB"
            
            # 1秒待機
            sleep 1
        done
        
        # コピーが完了したら最終的な進捗を表示
        echo -ne "\r進捗: 100%  転送済み: $total_size_gb GB / $total_size_gb GB"
        echo ""  # 改行
        
        # rsync の終了ステータスを確認
        wait $rsync_pid || {
            print_error "ブロックデータのコピーに失敗しました。"
            print_info "ディスク容量や権限を確認してください。"
            print_info "手動でコピーすることもできます："
            echo "rsync -a $bootstrap_data_dir/ $shoestring_data_dir/"
            exit 1
        }
        
        print_success "ブロックデータを移行しました: $shoestring_data_dir"
        print_info "Shoestringノードは、Bootstrapノードの最新ブロックから同期を再開します。"
    else
        print_info "ブロックデータの移行をスキップしました。"
        print_info "Shoestringノードは1ブロック目から同期を開始します。"
    fi
    
    # 委任者情報（harvesters.dat）の引き継ぎ
    echo ""
    print_info "委任者情報の引き継ぎについて:"
    print_info "Bootstrapノードの委任者情報（harvesters.dat）を引き継ぐことができます。"
    print_info "ファイルは $SHOESTRING_DIR/data に配置されます。"
    
    if [ -f "$BACKUP_DIR/harvesters.dat" ]; then
        if confirm "委任者情報（harvesters.dat）を引き継ぎますか？（推奨）"; then
            print_info "委任者情報をコピー中..."
            cp "$BACKUP_DIR/harvesters.dat" "$shoestring_data_dir/"
            print_success "委任者情報を引き継ぎました: $shoestring_data_dir/harvesters.dat"
        else
            print_info "委任者情報の引き継ぎをスキップしました。"
        fi
    else
        print_warning "委任者情報（harvesters.dat）が見つかりません: $BACKUP_DIR/harvesters.dat"
    fi
}

# 設定内容の確認
verify_configuration() {
    print_header "Shoestringノードの設定を確認しています..."
    
    cd "$SHOESTRING_DIR"
    
    # shoestring.ini の内容を表示
    if [ -f "shoestring.ini" ]; then
        print_info "設定ファイル（shoestring.ini）の内容:"
        cat shoestring.ini
        echo ""
    else
        print_error "設定ファイル（shoestring.ini）が見つかりません。"
        exit 1
    fi
    
    # overrides.ini の内容を表示
    if [ -f "overrides.ini" ]; then
        print_info "設定ファイル（overrides.ini）の内容:"
        cat overrides.ini
        echo ""
    else
        print_error "設定ファイル（overrides.ini）が見つかりません。"
        exit 1
    fi
    
    # docker-compose.yml の内容を表示
    if [ -f "docker-compose.yml" ]; then
        print_info "Docker Compose設定（docker-compose.yml）の内容:"
        cat docker-compose.yml
        echo ""
    else
        print_error "Docker Compose設定（docker-compose.yml）が見つかりません。"
        exit 1
    fi
    
    # ディレクトリ構造を確認
    print_info "ディレクトリ構造:"
    ls -la .
    echo ""
    
    # 重要なディレクトリが存在するか確認
    local required_dirs=("data" "logs")
    for dir in "${required_dirs[@]}"; do
        if [ -d "$dir" ]; then
            print_success "$dir ディレクトリが存在します"
        else
            print_error "$dir ディレクトリが見つかりません。"
            exit 1
        fi
    done
    
    # ユーザーに確認
    if ! confirm "設定内容に問題がなければ、ノードを起動します。続行しますか？"; then
        print_info "ノードの起動をキャンセルしました。"
        print_info "必要に応じて設定ファイルを編集してください:"
        echo "  - $SHOESTRING_DIR/shoestring.ini"
        echo "  - $SHOESTRING_DIR/overrides.ini"
        echo "  - $SHOESTRING_DIR/docker-compose.yml"
        print_info "編集後、スクリプトを再実行するか、以下のコマンドでノードを起動してください:"
        echo "  cd $SHOESTRING_DIR && docker compose up -d"
        exit 0
    fi
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
    
    print_info "ノードの状態をチェック中..."
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
    echo "  ⚙️  追加設定: $SHOESTRING_DIR/overrides.ini"
    echo "  📂 ブロックデータ: $SHOESTRING_DIR/data"
    echo "  💾 バックアップ（重要なファイル）: $BACKUP_DIR"
    echo ""
    
    print_info "よく使うコマンド:"
    echo "  🏃 ノード起動: cd $SHOESTRING_DIR && docker compose up -d"
    echo "  🛑 ノード停止: cd $SHOESTRING_DIR && docker compose down"
    echo "  💊 ヘルスチェック: cd $SHOESTRING_DIR && python3 -m shoestring health --config shoestring.ini --directory ."
    echo "  📊 ログ確認: cd $SHOESTRING_DIR && docker compose logs -f"
    echo ""
    
    print_warning "重要な注意事項:"
    echo "  🔐 ca.key.pemは安全な場所にバックアップしてください"
    echo "  📈 ノードの同期には時間がかかります（数時間〜数日）"
    echo "  🔄 定期的にヘルスチェックを実行してください"
    echo "  🗑️  Bootstrapディレクトリ（$BOOTSTRAP_DIR）は自動では削除されません。"
    echo "      移行に問題がないことを確認後、手動で削除してディスク容量を節約できます。"
    echo "      削除コマンド: rm -rf $BOOTSTRAP_DIR"
    echo "      注意: 削除前に重要なファイルが $BACKUP_DIR にバックアップされていることを確認してください。"
    echo ""
    
    print_info "問題が発生した場合:"
    echo "  1. ログを確認: $SHOESTRING_DIR/setup.log"
    echo "  2. ヘルスチェック: cd $SHOESTRING_DIR && python3 -m shoestring health --config shoestring.ini --directory ."
    echo "  3. mikunに質問: https://x.com/mikunNEM"
    echo "  4. バックアップから重要なファイルを復旧可能"
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
    
    print_header "🚀 Bootstrap → Shoestring 簡単移行スクリプト（改善版）"
    echo ""
    print_info "このスクリプトは、Symbol BootstrapからShoestringへの移行を自動化します。"
    print_info "初心者でも安心！ステップごとにガイドします。"
    echo ""
    print_warning "注意: 移行中はBootstrapノードが停止されます。"
    print_info "必要に応じてパッケージを自動インストールするため、sudo権限が必要です。"
    print_info "sudoのパスワードを求められた場合、その都度入力をしてください。"
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
    edit_shoestring_ini
    verify_shoestring_ini
    create_overrides_ini
    edit_overrides_ini
    verify_overrides_ini
    setup_shoestring_node
    import_bootstrap_data
    verify_configuration
    start_and_verify_node
    show_post_migration_guide
    
    print_success "🎉 移行が正常に完了しました！"
}

# スクリプト実行
main "$@"
