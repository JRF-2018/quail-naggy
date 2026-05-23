# ==============================================================================
# 最新の安定版 Debian 12 (bookworm) の軽量イメージをベースにする
# ==============================================================================
FROM debian:bookworm-slim

# ENV MODE=kaze
ENV DEBIAN_FRONTEND=noninteractive

# OSの環境変数を日本語（UTF-8）に設定
ENV LANG=ja_JP.UTF-8
ENV LANGUAGE=ja_JP:ja
ENV LC_ALL=ja_JP.UTF-8

# 必要なLinuxパッケージ（Emacs, Perl, LHA解凍ツール, curl, 文字コード変換器など）を一括インストール
RUN apt-get update && apt-get install -y \
    emacs \
    perl \
    make \
    build-essential \
    wget \
    curl \
    git \
    patch \
    lhasa \
    unzip \
    locales \
    fonts-noto-cjk \
    fonts-vlgothic \
    && rm -rf /var/lib/apt/lists/*

# 日本語ロケールの生成
RUN echo "ja_JP.UTF-8 UTF-8" > /etc/locale.gen && locale-gen

# CPANから指定のPerlモジュール2つをインストール
RUN cpan -i Unicode::Japanese autovivification

# コンテナ内の作業ディレクトリを設定
WORKDIR /app

# quail-naggy のパッケージ一式（ElispやPlファイル）をコンテナ内にコピー
COPY . /app/quail-naggy

# 後述する自動分岐起動スクリプトをコンテナ内に配置し、実行権限を付与
COPY ./entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# 起動時に自動的にこのスクリプトを走らせる
ENTRYPOINT ["/app/entrypoint.sh"]
