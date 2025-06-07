# bootstrap-to-shoestring
Script for migrating from symbol bootstrap to shoestring

# Shoestring 移行スクリプト利用手順

このマニュアルでは、サーバー上で **Symbol Bootstrap から Shoestring への移行スクリプト** を実行するための手順を説明します。

## 前提条件

- サーバーに SSH でログイン済みであること。  
- `bash`, `curl` (または `wget`), `chmod` コマンドが利用可能であること。  
- 移行先ディレクトリとして `~/work/shoestring/shoestring` フォルダを使用します。
  (任意で設定してください)

## 1. 必要ファイルのダウンロード

1. `shoestring` フォルダへ移動します。

    ```bash
    cd ~/work/shoestring/shoestring
    ```

2. GitHub リポジトリからスクリプト本体とユーティリティファイルを取得します。

    ```bash
    # bootstrap_to_shoestring.sh をダウンロード
    curl -O https://raw.githubusercontent.com/mikunNEM/bootstrap-to-shoestring/main/bootstrap_to_shoestring.sh

    # utils.sh をダウンロード
    curl -O https://raw.githubusercontent.com/mikunNEM/bootstrap-to-shoestring/main/utils.sh
    ```

    ※ `wget` を好む場合は `curl -O` の代わりに `wget` を使用しても構いません。

## 2. 実行権限の設定

ダウンロードしたスクリプトに実行権限を付与します。

```bash
chmod +x bootstrap_to_shoestring.sh utils.sh


## 3. スクリプトの実行

以下のコマンドで移行スクリプトを実行します。途中で確認プロンプトが表示されます。

```bash
./bootstrap_to_shoestring.sh

オプション -y を付けると、すべての確認をスキップして自動実行します（上級者向け）。

```bash
./bootstrap_to_shoestring.sh -y



