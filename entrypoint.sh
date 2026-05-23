#!/bin/bash
set -e
#set -x

cd /app/quail-naggy

if [ "$MODE" = "kaze" ]; then
    echo "=== VectorのWebページから最新のダウンロードURLを解析中... ==="
    # 1. 人間用のWebページ（HTML）を一時的にダウンロード
    HTML_URL="https://www.vector.co.jp/download/file/winnt/writing/fh548073.html"
    curl -s -o /tmp/page.html "$HTML_URL"

    # 2. HTMLの中から「ftp.vector.co.jp ... Wind230.exe」が含まれる行をあぶり出し、URLだけを抽出
    # (正規表現を使って、href="xxx" の中身をぶっこ抜きます)
    WIND_URL=$(grep -o -E 'https://ftp\.vector\.co\.jp/[^" ]+Wind230\.exe' /tmp/page.html | head -n 1)

    # 【デバッグ用】抽出されたURLを画面に表示して確認
    echo "解析結果。ターゲットURL: $WIND_URL"

    wget -q -O /tmp/Wind230.exe "$WIND_URL"
    
    # 2. LHAで解凍
    mkdir -p /tmp/wind_extracted
    pushd /tmp/wind_extracted > /dev/null
    lha x /tmp/Wind230.exe Wind2.rea Wind2.dic
    popd > /dev/null

    echo "=== 辞書データベース（SDBM）を作成中... ==="
    perl dic2txt.pl /tmp/wind_extracted/Wind2.rea /tmp/wind_extracted/Wind2.dic Wind2.txt
    perl make_tankanji_dic_db.pl -s Wind2.txt

    echo "=== site-init.nginit を編集... ==="
    cat << 'EOF' > site-init.nginit
load-init-file default-init.nginit
set-tankanji-dic Wind2.txt -s
#set-tankanji-dic tankanji.txt -e
#add-skk-dic SKK-JISYO.L -e
add-skk-dic SKK-JISYO.fixed.L -e
add-skk-dic bushu-skk-dic.txt -e
add-skk-dic emoji-skk-dic.txt -u
add-skk-dic SKK-JISYO.china_taiwan.fixed -e
EOF

else
    echo "=== デフォルトの単漢字辞書を構成中... ==="
    wget -q -O /tmp/jrf_tankanji-20120505.zip https://github.com/JRF-2018/quail-naggy/releases/download/jrf_tankanji-20120505/jrf_tankanji-20120505.zip
    unzip -qo -j /tmp/jrf_tankanji-20120505.zip tankanji.txt
    perl make_tankanji_dic_db.pl -e tankanji.txt

    echo "=== site-init.nginit を編集... ==="
    cat << 'EOF' > site-init.nginit
load-init-file default-init.nginit
#set-tankanji-dic Wind2.txt -s
set-tankanji-dic tankanji.txt -e
#add-skk-dic SKK-JISYO.L -e
add-skk-dic SKK-JISYO.fixed.L -e
add-skk-dic bushu-skk-dic.txt -e
add-skk-dic emoji-skk-dic.txt -u
add-skk-dic SKK-JISYO.china_taiwan.fixed -e
EOF
fi

echo "=== SKK-JISYO.L をダウンロード中... ==="
    wget -q -O SKK-JISYO.L.gz http://openlab.jp/skk/dic/SKK-JISYO.L.gz
    gunzip -f SKK-JISYO.L.gz
    perl fix_skk_jisyo_l.pl SKK-JISYO.L -o SKK-JISYO.fixed.L 2>/dev/null
    perl make_skk_dic_db.pl -e SKK-JISYO.fixed.L

echo "=== GitHubから絵文字SKK辞書をダウンロード中... ==="
    git clone --depth 1 https://github.com/JRF-2018/naggy-emoji-skk-dic.git /tmp/emoji-repo
    cp /tmp/emoji-repo/emoji-skk-dic.txt ./
    cp /tmp/emoji-repo/emoji-skk-dic.txt.sdb.dir ./
    cp /tmp/emoji-repo/emoji-skk-dic.txt.sdb.pag ./

echo "=== SKK-JISYO.china_taiwan をダウンロード中... ==="
    wget -q -O SKK-JISYO.china_taiwan.gz http://openlab.jp/skk/dic/SKK-JISYO.china_taiwan.gz
    gunzip -f SKK-JISYO.china_taiwan.gz
    cp SKK-JISYO.china_taiwan SKK-JISYO.china_taiwan.fixed
    patch -s SKK-JISYO.china_taiwan.fixed china_taiwan.patch
    perl make_skk_dic_db.pl -e SKK-JISYO.china_taiwan.fixed

# ==============================================================================
# 【着火】取扱説明書に書かれていた .emacs の設定を、その場で流し込んで Emacs 起動
# ==============================================================================
echo "=== Emacs を起動します... ==="

# コンテナ専用の一時的な .emacs 起動ファイルを動的に生成
cat << 'EOF' > /tmp/.emacs
;; ==============================================================================
;; Docker/Linux環境用：画面表示・フォントの固定設定
;; ==============================================================================

(defvar my/naggy-font "VL Gothic-12")
(defvar my/naggy-font-family "VL Gothic")
;(defvar my/naggy-font "Noto Sans Mono CJK JP-12")
;(defvar my/naggy-font-family "Noto Sans Mono CJK JP")

;; 新規フレームに最初から効かせる
(add-to-list 'default-frame-alist `(font . ,my/naggy-font))
;(add-to-list 'default-frame-alist '(tool-bar-lines . 0))
;(add-to-list 'default-frame-alist '(menu-bar-lines . 0))
;(add-to-list 'default-frame-alist '(vertical-scroll-bars . nil))
;(setq initial-frame-alist default-frame-alist)

(when (display-graphic-p)
  (tool-bar-mode -1)
;  (menu-bar-mode -1)
;  (scroll-bar-mode -1)

  ;; default face は family/height で指定した方が安定
  (set-face-attribute 'default nil
                      :family my/naggy-font-family
                      :height 120
                      :weight 'normal)

  ;; 日本語文字のフォントを明示
  (dolist (charset '(japanese-jisx0208 japanese-jisx0212 katakana-jisx0201))
    (set-fontset-font t charset (font-spec :family my/naggy-font-family)))

  (set-face-attribute
   'glyphless-char
   nil
   :height 30)

  ;; Unicode 全体のフォールバック
  (set-fontset-font t 'unicode (font-spec :family my/naggy-font-family))

  ;; 候補フレームが作られた瞬間に、そこへも強制適用
  (defun my/naggy-fix-frame-font (frame)
    (when (equal (frame-parameter frame 'name) "naggy_vk_candidates")
      (with-selected-frame frame
        (set-frame-font my/naggy-font t t)
        (set-face-attribute 'default frame
                            :family my/naggy-font-family
                            :height 120
                            :weight 'normal)
        (set-frame-parameter frame 'tool-bar-lines 0)
        (set-frame-parameter frame 'menu-bar-lines 0)
        (set-frame-parameter frame 'vertical-scroll-bars nil))))

  (add-hook 'after-make-frame-functions #'my/naggy-fix-frame-font))

(setq load-path (append load-path (list "/app/quail-naggy")))
(require 'quail-naggy)
(setq naggy-backend-program "/usr/bin/perl")
(setq naggy-backend-options '("/app/quail-naggy/naggy-backend.pl"))
(setq default-input-method "japanese-naggy")

;; 2015年当時の取扱説明書に記載されていた Emacs 24.5 以降用の画面判定
(if (>= (string-to-number emacs-version) 24.5)
    (progn 
      (setq naggy-vk-split-window-length 7)
      (setq naggy-vk-frame-length 7)))
EOF

# 生成した .emacs を読み込ませて、本物の Emacs を GUI（または端末）で起動！
exec emacs --display="$DISPLAY" -l /tmp/.emacs
