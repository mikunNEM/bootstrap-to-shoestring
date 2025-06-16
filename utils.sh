#!/bin/bash

# utils.sh - bootstrap_to_shoestring.sh のための便利な関数
# ログ、環境チェック、YAML 解析、ユーザー対話を管理します。
#
# 作成者: mikun (@mikunNEM, 2025-06-05)
# バージョン: 2025-06-07-v5

set -e

# カラーコード
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ログを記録する関数
log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="${SHOESTRING_DIR:-$HOME/work/shoestring}/setup.log"
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
    # 特殊文字をエスケープ
    local escaped_message=$(printf '%s' "$message" | sed 's/["$`\\]/\\&/g')
    echo "[$timestamp] [$level] $escaped_message" >> "$log_file" 2>/dev/null
    echo "[$timestamp] [$level] $escaped_message" >&2
}

# エラーで終了する関数
error_exit() {
    local message="$1"
    local code="${2:-1}"
    echo -e "${RED}❌ エラー: $message${NC}" >&2
    log "$message" "ERROR"
    echo -e "${BLUE}💡 解決のヒント:${NC}" >&2
    echo "  - ログを確認: cat ${SHOESTRING_DIR:-$HOME/work/shoestring}/setup.log" >&2
    echo "  - ディスク容量: df -h" >&2
    echo "  - 権限: ls -ld ${SHOESTRING_DIR:-$HOME/work/shoestring}" >&2
    echo "  - YAML確認: head -n 20 ${ADDRESSES_YML:-/home/mikun/work/symbol-bootstrap/target/addresses.yml}" >&2
    echo "  - ネットワーク: ping -c 4 github.com; curl -v https://github.com" >&2
    echo "  - 翻訳エラー: cat ${SHOESTRING_DIR:-$HOME/work/shoestring}/shoestring-env/lib/python3.12/site-packages/shoestring/__main__.py | grep -A 5 'lang ='" >&2
    echo "  - スクリプト構文: bash -n utils.sh; grep -n \"'\" utils.sh" >&2
    echo "  - サポート: https://x.com/mikunNEM" >&2
    exit "$code"
}

# 成功メッセージ
print_success() {
    echo -e "${GREEN}✅ $1${NC}" >&2
    log "$1" "INFO"
}

# 警告メッセージ
print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}" >&2
    log "$1" "WARNING"
}

# 情報メッセージ
print_info() {
    local message="$1"
    echo -e "${BLUE}ℹ️ $message${NC}" >&2
    log "$message" "INFO"
}

# ユーザーに入力を求める
ask_user() {
    local question="$1"
    local default="$2"
    local is_path="${3:-}"
    local response

    echo -e "${BLUE}$question${NC}" >&2
    if [ -n "$default" ]; then
        echo -e "${BLUE}デフォルト（Enterで選択）: $default${NC}" >&2
    fi

    while true; do
        read -r response
        if [ -z "$response" ] && [ -n "$default" ]; then
            response="$default"
        fi
        if [ -z "$response" ]; then
            echo -e "${RED}❌ 入力してください！${NC}" >&2
            continue
        fi
        if [ "$is_path" = "path" ]; then
            response=$(expand_tilde "$response")
            if [[ ! "$response" =~ ^/ ]]; then
                response="$(pwd)/$response"
            fi
            response=$(echo "$response" | xargs)
            if [[ "$response" =~ \[.*\] || "$response" =~ \' || "$response" =~ \" ]]; then
                echo -e "${RED}❌ 無効なパスだよ！（特殊文字やログっぽいのはダメ）${NC}" >&2
                continue
            fi
        fi
        printf "%s" "$response"
        log "ユーザー入力: 質問='$question', 回答='$response'" "DEBUG"
        break
    done
}

# チルダ展開
expand_tilde() {
    local response="$1"
    if [[ -n "$response" ]]; then
        log "Tilde expansion before: $response" "DEBUG"
        response="${response/#~/$HOME}"
        log "Tilde expansion after: $response" "DEBUG"
    else
        log "Tilde expansion skipped: empty response" "DEBUG"
    fi
    echo "$response"
}

# 確認プロンプト
confirm() {
    local question="$1"
    local response

    while true; do
        echo -e "${YELLOW}$question（y/n）: ${NC}"
        read -r response
        if [ -z "$response" ]; then
            return 0
        fi
        case $response in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "y か n で答えてね！" >&2 ;;
        esac
    done
}

# コマンドの存在チェック
check_command() {
    if ! command -v "$1" &>/dev/null; then
        error_exit "$1 が必要です！インストールしてください。"
    fi
}

# YAML ファイルを解析（ネスト対応）
parse_yaml() {
    local file="$1"
    local key="$2"
    if [ ! -f "$file" ]; then
        error_exit "YAML ファイル $file が見つかりません。"
    fi
    log "parse_yaml: ファイル=$file, キー=$key" "DEBUG"
    
    if command -v yq &>/dev/null; then
        local result=$(yq eval ".nodes[0].${key}.privateKey" "$file" 2>> "${SHOESTRING_DIR:-$HOME/work/shoestring}/setup.log")
        if [[ "$result" != "null" && -n "$result" ]]; then
            log "yq 結果: $result" "DEBUG"
            echo "$result"
            return 0
        fi
        log "yq でキー $key が見つからない" "DEBUG"
    else
        log "yq 未インストール、grep にフォールバック" "DEBUG"
    fi
    
    local line=$(grep -A 10 "^[[:space:]]*${key}:" "$file" | grep privateKey | head -n 1 | sed -e 's/^[[:space:]]*privateKey:[[:space:]]*//' -e 's/[[:space:]]*$//')
    log "grep 結果: $line" "DEBUG"
    if [[ -n "$line" ]]; then
        echo "$line"
    else
        error_exit "${key} の privateKey が見つからないよ"
    fi
}

# ファイルの検証
validate_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        error_exit "ファイル $file が見つかりません。"
    fi
}

# ディレクトリの検証
validate_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        error_exit "ディレクトリ $dir が見つかりません。"
    fi
}

# ディスク容量のチェック（1GB 以上）
check_disk_space() {
    local dir="$1"
    local min_space_mb=1000
    local free_space=$(df -m "$dir" | tail -1 | awk '{print $4}')
    if [ "$free_space" -lt "$min_space_mb" ]; then
        error_exit "$dir のディスク容量が不足: ${free_space}MB（${min_space_mb}MB 必要）"
    fi
    print_info "$dir のディスク容量: ${free_space}MB"
    log "ディスク容量チェックOK: ${free_space}MB" "DEBUG"
}

# Python バージョンのチェック（3.10 以上）
check_python_version() {
    local min_version="3.10"
    local python_version=$(python3 --version | cut -d' ' -f2)
    if [ "$(echo -e "$python_version\n$min_version" | sort -V | head -n1)" != "$min_version" ]; then
        error_exit "Python $min_version 以上が必要（現在: $python_version）"
    fi
    print_info "Python バージョン: $python_version"
    log "Python バージョンチェックOK: $python_version" "DEBUG"
}

# 仮想環境のチェック（オプション）
check_venv_optional() {
    local venv_dir="$1"
    if [ ! -f "${venv_dir}/bin/activate" ]; then
        print_warning "仮想環境が見つかりません: ${venv_dir}。後で作成されます。"
        return 1
    fi
    
    # 仮想環境をアクティベートしてチェック
    set +e
    source "${venv_dir}/bin/activate"
    local activate_result=$?
    set -e
    
    if [ $activate_result -ne 0 ]; then
        print_warning "仮想環境の有効化に失敗しました。後で再作成されます。"
        return 1
    fi
    
    if ! pip show symbol-shoestring &>/dev/null; then
        print_warning "symbol-shoestring が未インストール。後でインストールされます。"
        deactivate
        return 1
    fi
    
    local package_version=$(pip show symbol-shoestring | grep Version | cut -d' ' -f2)
    print_success "仮想環境OK: symbol-shoestring v${package_version}"
    log "仮想環境チェックOK: symbol-shoestring v${package_version}" "DEBUG"
    deactivate
    return 0
}

# 書き込み権限のチェック
check_write_permission() {
    local dir="$1"
    if ! touch "${dir}/.write_test" 2>/dev/null; then
        error_exit "$dir に書き込み権限がありません。"
    fi
    rm -f "${dir}/.write_test"
    print_info "$dir の書き込み権限OK"
    log "$dir の書き込み権限チェックOK" "DEBUG"
}

# ログのローテーション
rotate_log() {
    local log_file="${SHOESTRING_DIR:-$HOME/work/shoestring}/setup.log"
    if [ -f "$log_file" ] && [ $(stat -c %s "$log_file" 2>/dev/null || stat -f %z "$log_file") -gt 10485760 ]; then
        mv "$log_file" "$log_file.$(date +%Y%m%d_%H%M%S)"
        print_info "ログをローテーション: $log_file"
        log "ログをローテーションしました"
    fi
}

export -f log error_exit print_success print_warning print_info ask_user expand_tilde confirm check_command parse_yaml validate_file validate_dir check_disk_space check_python_version check_venv_optional check_write_permission rotate_log
