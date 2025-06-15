# Symbol Bootstrap から Shoestring への移行マニュアル

ようこそ！このマニュアルは、**Symbol ノード**を **Symbol Bootstrap** から **Shoestring** に簡単に移行するためのガイドです。

## **このスクリプトでできること**
- Symbol Bootstrap のノードデータを **Shoestring** に移行。
- 既存のブロックデータをコピーして、同期時間を短縮。
- 必要なツール（Docker、Pythonなど）を自動インストール。
- 重要なデータ（秘密鍵、設定ファイル）を安全にバックアップ。
- **初心者向け**のわかりやすいメッセージとエラー対処ガイド。

## **こんな人にオススメ**
- Symbol ノードを動かしてるけど、Shoestring に移行したい！
- サーバーの操作で、極力コマンドを打ちたくない。
- データの安全性を守りつつ、簡単に移行したい。

## **前提条件**
スクリプトを実行する前に、以下の準備を確認してください：

1. **サーバーへの SSH ログイン**：
   - サーバーにログイン済み（例：`ssh mikun@vmi845243`）。
   - ツール：PuTTY、Termius、またはターミナルなど。
2. **必要なコマンド**：
   - `bash`, `curl`（または `wget`）, `chmod` が使える。
   - 確認：
     ```bash
     bash --version
     curl --version
     chmod --version
     ```
3. **サーバー環境**：
   - Ubuntu（22.04 以上推奨）
   - ディスク：120GB 以上（データコピー用）
   - メモリ：4GB 以上。
   - 確認：
     ```bash
     lsb_release -a
     df -h /home
     free -m
     ```
4. **Bootstrap ノード**：
   - Symbol Bootstrap が動いてる（例：`/home/mikun/work/symbol-bootstrap/target/`）。
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
   - **暗号化された `addresses.yml` は NG！** Symbol Bootstrap の暗号化方式（`crypto-js`）のバージョン変更により、復元に失敗する可能性があります。
   - 平文変換は「準備」手順で説明します。

## **必要なもの**
- **インターネット接続**：スクリプトやツールをダウンロード。
- **管理者権限**：`sudo` でパッケージインストールや権限変更。
- **10〜30分**：データサイズ（例：4GB + 24GB）やサーバー性能による。

## **準備：addresses.yml を平文に変換**
⚠️ **スクリプト実行前に、`addresses.yml` を必ず平文にしてください！** 暗号化されたままでは、**`crypto-js` のバージョン不一致**で復元に失敗する可能性があります。以下の手順で変換してね！

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
     mainAccount:
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
     - 実行後、`Enter password:` と表示されるので、**手打ちでパスワードを入力**。
     - **⚠️ コマンドラインにパスワードを書かないで！** セキュリティ上危険です。
   - 成功確認：
     ```bash
     head -n 5 d_addresses.yml
     # mainAccount: ... なら OK
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
- 平文の `addresses.yml` には秘密鍵が含まれる。**他の人に公開しない**！
- バックアップ（`addresses.yml.encrypted-backup`）を安全な場所に。

## **手順**

### **ステップ 1: スクリプトのダウンロード**
Shoestring フォルダに移動し、必要なファイル（スクリプト本体とユーティリティ）をダウンロードします。

1. **フォルダに移動**：
   ```bash
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
ダウンロードしたスクリプトに「実行可能」な権限を付けます。

```bash
chmod +x bootstrap_to_shoestring.sh utils.sh
```

- **確認**：
  ```bash
  ls -l
  # -rwxr-xr-x で x（実行権限）が付いてる？
  ```

### **ステップ 3: スクリプトの実行**
スクリプトを実行して、Bootstrap から Shoestring に移行します。

1. **スクリプト実行**：
   ```bash
   ./bootstrap_to_shoestring.sh
   ```
   - **高速モード**（確認スキップ、上級者向け）：
     ```bash
     ./bootstrap_to_shoestring.sh -y
     ```
2. **質問への回答**：
   - **Shoestring フォルダ**：
     - デフォルト：`/home/mikun/shoestring`
     - Enter で OK。
   - **Bootstrap フォルダ**：
     - 例：`/home/mikun/work/symbol-bootstrap/target`
     - 入力（`ls /home/mikun/work/symbol-bootstrap/target/` で確認）。
   - **バックアップフォルダ**：
     - デフォルト：`/home/mikun/symbol-bootstrap-backup-YYYYMMDD_HHMMSS`
     - Enter で OK。
   - **addresses.yml の暗号化**：
     - 平文に変換済みなら「n」を入力。
     - **暗号化のままは NG！** 準備手順で平文にしてください。
   - **設定ファイル確認**：
     - `shoestring.ini`, `overrides.ini` が表示。
     -  編集をするなら 別のターミナルを開いて `nano` で編集
     - 「n」で更新を確認
     - 「y」で進む
3. **進捗**：
   - データコピー（テストネット 例：4GB データベース、24GB チェーンデータ）の進捗バー：
     ```
     ℹ️ チェーンデータ 23.6GiB をコピーします
     12.4GiB [=====>     ] 52% ETA 0:02:30 78.7MiB/s
     ```
   - 所要時間：5〜30分。

## **重要なポイント**
- **データ安全性**：
  - ブロックデータは Shoestring にコピーされ、Bootstrap 元データは残る。
  - Shoestring の安定稼働を確認後、Bootstrapのブロックデータは削除可
  - 重要ファイル（`addresses.yml`, `node.key.pem`, `config-harvesting.properties`, `votingkeys`）はバックアップ。
  - 平文 `addresses.yml` は権限（`chmod 600`）で保護。

- **ログ**：
  - `/home/mikun/shoestring/log/` に整理（`data_copy.log`, `docker_compose.log`）。
