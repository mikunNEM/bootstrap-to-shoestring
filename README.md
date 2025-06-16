# 無題

# Symbol Bootstrap から Shoestring への移行マニュアル

ようこそ！このマニュアルは、**Symbol ノード**を **Symbol Bootstrap** から **Shoestring** に簡単に移行するためのガイドです。スクリプトは初心者でも使いやすく、依存ツールの自動インストールやエラーログを提供します。

## **このスクリプトでできること**

- Symbol Bootstrap のノードデータを **Shoestring** に移行（データベースとチェーンデータを移動）。
- 既存のブロックデータを移動して、同期時間を短縮。
- 必要なツール（Docker、Python 3.10、Node.jsなど）を自動インストール。
- 重要なデータ（秘密鍵、設定ファイル、投票鍵）をバックアップ。
- ディレクトリを自動検出し、ポート競合をチェック。
- **beneficiaryAddress** をBootstrapから自動設定
- 初心者向けの対話型プロンプトと詳細なエラーガイド。

## **こんな人にオススメ**

- Symbol Bootstrap ノードを Shoestring に移行したい。
- コマンド操作を最小限に抑えたい。
- データの安全性を確保しつつ、スムーズに移行したい。

## **前提条件**

スクリプトを実行する前に、以下の準備を確認してください：

1. **サーバーへの SSH ログイン**：
    - サーバーにログイン済み（例：`ssh mikun@vmi845243`）。
    - ツール：PuTTY、Termius、またはターミナル。
2. **必要なコマンド**：
    - `bash`, `curl`（または `wget`）, `chmod` が使える。
    - 確認：
        
        ```bash
        bash --version
        curl --version
        chmod --version
        
        ```
        
3. **サーバー環境**：
    - Ubuntu 22.04 以上（20.04 はアップグレード必須）。
    - ディスク：120GB 以上（データ用）＋1GB（仮想環境用）。
    - メモリ：4GB 以上。
    - 確認：
        
        ```bash
        lsb_release -a
        df -h /home
        free -m
        
        ```
        
4. **Bootstrap ノード**：
    - Symbol Bootstrap が稼働中（例：`/home/mikun/work/symbol-bootstrap/target/`）。
    - データ（`databases/db`, `nodes/node/data`）が存在。
    - 確認：
        
        ```bash
        ls -l /home/mikun/work/symbol-bootstrap/target/
        # databases/db, nodes/node/data がある？
        
        ```
        
5. **移行先フォルダ**：
    - Shoestring 用フォルダを用意（例：`/home/mikun/shoestring/`）。
    - Bootstrap とは別の場所に。
    - 作成：
        
        ```bash
        mkdir -p ~/shoestring
        cd ~/shoestring
        pwd
        # /home/mikun/shoestring なら OK
        
        ```
        
6. **addresses.yml の平文必須**（⚠️ **超重要！**）：
    - `addresses.yml`（例：`/home/mikun/work/symbol-bootstrap/target/addresses.yml`）は **必ず平文** にしてください。
    - 暗号化された `addresses.yml` は使用不可（`crypto-js` のバージョン不一致で復元失敗の可能性）。
    - 平文変換は「準備」手順で説明します。

## **必要なもの**

- **インターネット接続**：スクリプトやツールをダウンロード。
- **管理者権限**：`sudo` でパッケージインストールや権限変更。
- **10〜30分**：データサイズ（例：4GB データベース＋24GB チェーンデータ）やサーバー性能による。

## **準備：addresses.yml を平文に変換**

⚠️ **スクリプト実行前に、`addresses.yml` を必ず平文にしてください！** 暗号化されたままでは復元に失敗する可能性があります。

1. **暗号化確認**：
    
    ```bash
    head -n 5 /home/mikun/work/symbol-bootstrap/target/addresses.yml
    
    ```
    
    - **暗号化**例：
        
        ```
        encrypted: eyJjaXBoZXIiOiAiQUVTLTEyOC1HQ00iLCAiY2lwaGVydGV4dCI6IC...
        
        ```
        
    - **平文**例：
        
        ```
        main:
          privateKey: ABCDEF...
        
        ```
        
    - 平文なら「ステップ 1」へ！
2. **平文に変換**：
    - 暗号化パスワードを準備（忘れた場合は「エラー対処」参照）。
    - **コマンド**：
        
        ```bash
        cd /home/mikun/work/symbol-bootstrap/target
        symbol-bootstrap decrypt --source addresses.yml --destination d_addresses.yml
        
        ```
        
    - **パスワード入力**：
        - `Enter password:` で手打ち入力。
        
    - 成功確認：
        
        ```bash
        head -n 5 d_addresses.yml
        # main: ... なら OK
        
        ```
        
3. **元のファイルを置き換え**：
    - バックアップ：
        
        ```bash
        cp addresses.yml addresses.yml.encrypted-backup
        
        ```
        
    - 置き換え：
        
        ```bash
        mv d_addresses.yml addresses.yml
        
        ```
        
4. **権限設定**（セキュリティ）：
    
    ```bash
    chmod 600 addresses.yml
    ls -l addresses.yml
    # -rw------- なら OK
    
    ```
    

**注意**：

- 平文の `addresses.yml` には秘密鍵が含まれるため、**公開しない**。
- バックアップ（`addresses.yml.encrypted-backup`）を安全な場所に保存。

## **手順**

### **ステップ 1: スクリプトのダウンロード**

Shoestring フォルダを作成 / 移動し、スクリプトをダウンロードします。

1. **フォルダに移動**：
    
    ```bash
    mkdir ~/shoestring
    cd ~/shoestring
    
    ```
    
2. **スクリプトをダウンロード**：
    - `bootstrap_to_shoestring.sh`（本体）：
        
        ```bash
        curl -O https://raw.githubusercontent.com/mikunNEM/bootstrap-to-shoestring/main/bootstrap_to_shoestring.sh
        
        ```
        
    - `utils.sh`（ユーティリティ）：
        
        ```bash
        curl -O https://raw.githubusercontent.com/mikunNEM/bootstrap-to-shoestring/main/utils.sh
        
        ```
        
    - **代替**（`curl` がない場合）：
        
        ```bash
        wget https://raw.githubusercontent.com/mikunNEM/bootstrap-to-shoestring/main/bootstrap_to_shoestring.sh
        wget https://raw.githubusercontent.com/mikunNEM/bootstrap-to-shoestring/main/utils.sh
        
        ```
        
3. **確認**：
    
    ```bash
    ls -l
    # bootstrap_to_shoestring.sh, utils.sh がある？
    
    ```
    

### **ステップ 2: 実行権限の設定**

スクリプトに実行権限を付与します。

```bash
chmod +x bootstrap_to_shoestring.sh utils.sh

```

- **確認**：
    
    ```bash
    ls -l
    # -rwxr-xr-x で x（実行権限）が付いてる？
    
    ```
    

### **ステップ 3: スクリプトの実行**

スクリプトを実行して移行を行います。

1. **スクリプト実行**：
    
    ```bash
    ./bootstrap_to_shoestring.sh
    
    ```
    
2. **質問への回答**：
    - **Shoestring フォルダ**：
        - デフォルト：`/home/mikun/shoestring`
        - Enter で OK
    - **Bootstrap フォルダ**：
        - 例：`/home/mikun/work/symbol-bootstrap/target`
        - 自動検出されたパスを確認
        - Enterで Ok。
    - **バックアップフォルダ**：
        - デフォルト：`/home/mikun/symbol-bootstrap-backup-YYYYMMDD_HHMMSS`
        - Enter で OK。
    - **addresses.yml の暗号化**：
        - 平文に変換済みなら「n」を入力。
        - ⚠️ 暗号化のままは不可！準備手順で平文に変換。
    - **設定ファイル確認**：
        - `shoestring.ini`, `overrides.ini` が表示。
        - 編集が必要なら別のターミナルで `nano` を使って編集。
        - 「n」で更新を確認、「y」で進む。

## **重要なポイント**

- **データ安全性**：
    - ブロックデータは Shoestring に移動され、Bootstrap の元データは削除されます。
    - Shoestring の安定稼働を確認後、バックアップを整理。
    - 重要ファイル（`addresses.yml`, `node.key.pem`, `ca.key.pem`, `config-harvesting.properties`, `votingkeys`）は `$BACKUP_DIR` にバックアップ。
    - 平文 `addresses.yml` は権限（`chmod 600`）で保護。
- **ログ**：
    - `$SHOESTRING_DIR/log/` に整理（`setup.log`, `data_copy.log`, `docker_compose.log`, `import_bootstrap.log`）。
- **beneficiaryAddress**：
    - `config-harvesting.properties`  から自動設定。
    - `overrides.ini` に反映。
- **ポート競合**：
    - ポート3000の使用状況をチェック。競合があればエラーで停止。
- **仮想環境**：
    - 既存の仮想環境は削除され、Python 3.10 で再作成。
- **ノードロール**：
    - `config-harvesting.properties` や `votingkeys` の有無に応じて、HARVESTER や VOTER ロールを自動設定。

## **エラー対処**

エラーが発生した場合、以下のログを確認してください：

- 全体ログ：`cat $SHOESTRING_DIR/log/setup.log`
- データ移動：`cat $SHOESTRING_DIR/log/data_copy.log`
- Docker 起動：`cat $SHOESTRING_DIR/log/docker_compose.log`
- インポート：`cat $SHOESTRING_DIR/log/import_bootstrap.log`
- ディスク容量：`df -h`
- 権限：`ls -ld $SHOESTRING_DIR`
- ネットワーク：`ping -c 4 github.com; curl -v https://github.com`
- サポート：[https://x.com/mikunNEM](https://x.com/mikunNEM)

## **移行後の確認**

1. **ノード状態**：
    
    ```bash
    cd $SHOESTRING_DIR/shoestring
    docker ps
    docker-compose logs -f
    
    ```
    
2. **REST API**：
    
    ```bash
    curl http://localhost:3000
    
    ```
    
3. **設定編集**（必要に応じて）：
    
    ```bash
    nano $SHOESTRING_DIR/shoestring/shoestring.ini
    nano $SHOESTRING_DIR/shoestring/overrides.ini
    
    ```
    

## **バックアップの管理**

- バックアップ場所：`$BACKUP_DIR`
- 内容：`addresses.yml`, `node.key.pem`, `config-harvesting.properties`, `votingkeys`
- 安全な場所に保存し、Shoestring ノードの安定稼働後に整理。

## **スクリプト情報**

- バージョン：2025-06-16-v38
- 作成者：mikun (@mikunNEM)
- リポジトリ：[https://github.com/mikunNEM/bootstrap-to-shoestring](https://github.com/mikunNEM/bootstrap-to-shoestring)