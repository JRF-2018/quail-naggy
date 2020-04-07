

    quail-naggy.el: 単漢字変換 Input Method for Emacs.

    (Created: 2015-10-16 +0900, Time-stamp: <2020-01-24T03:02:10Z>)


■ About the "quail-naggy.el"

Windows 用単漢字変換日本語 IME 『風』の実用性とアイデアを受け、将来的に
非 Windows 環境や IME 非対応の Windows 用 Emacs でも『風』のようなイン
プット・メソッドが使えるようにしておこうとして開発されたのが本ソフトで
ある。

quail-naggy.el 本体は、仮想鍵盤の表示がメインで、変換時の辞書引きなどに
は、同梱の naggy-backend.pl という Perl プログラムをバックエンドとして
使っている。

quail-naggy.el 自体は、Emacs に付属している quail/japanese.el と
kkc.el を大いに参考にして作った。また、随分前に私自身が作ってほぼ身内
でのみ配布した vkegg.el も参考にしている。

バックエンドを使うこともあり、インストールが複雑なのが本ソフトの弱点で
ある。また、Emacs のバージョンの違いによる表示の差も設定を難しくする要
因となる。

本ドキュメントでは、その難しいインストール作業をまず説明し、次いで操作
方法を説明する。


■ インストール方法

インストール方法の大枠は次の通りである。

  * naggy-backend.pl で使用する Perl モジュールのインストール。

  * Emacs-Lisp ディレクトリ上へのファイルの展開。

  * SKK-JISYO.L や tankanji.txt などの変換用辞書の入手＆インデックス・
    データベースファイルの作成。

  * naggy-backend.pl の設定。

  * .emacs の設定。


順に説明していこう。


  * naggy-backend.pl で使用する Perl モジュールのインストール。

naggy-backend.pl ではデフォルトでインストールされていない Perl モジュー
ルはほとんど使っていないが、日本語関連の一つとデバッグ用の一つの計二つ
のモジュールだけは別途インストールする必要があるだろう。

その二つは Unicode::Japanese と autovivification である。

なお、バージョン 0.04 までは Encode::JIS2K も必要だった。

問題があった Encode::JIS2K は、コンパイルがうまくいかない環境があるよう
だ。Windows の標準的な Perl である ActivePerl がその例である。
2015-10-16 現在、ActivePerl で "ppm install Encode::JIS2K" としてもエラー
が返るだけである。

実は Encode::JIS2K と似た機能のモジュールとして Encode::JISX0213 モジュー
ルがあり、代わりに利用できるはずである。ただし、これも ActivePerl にお
いて "ppm install Encode-JISX0213" が成功するのに、うまく使えなかった。
そのため、そちらに対応するコードは書かなかった。が、それがうまく入る環
境では、各種 .pl ファイル内の "require Encode::JIS2K" 
を "require Encode::JISX0213"に変えるだけでうまく機能するはずである。

バージョン 0.05 からは Encode::JIS2K が多くの環境で必要なくなった。
Encode モジュールはバージョン 1.64 から、デフォルトで euc-jp を指定する
と euc-jisx0213 の内容をデコードできるため、euc-jisx0213 を使っていると
ころを euc-jp に変えた。万一、euc-jp でなく euc-jisx0213 が必要な環境の
場合は、make_skk_dic_db.pl make_tankanji_dic_sdb.pl naggy-backend.plの
起動時に --jisx0213 オプションを付ければ euc-jisx0213 を使って従来どお
りの動作をする。(ただし、このオプションは obsolete。)

著者は Cygwin の Perl 5.10.1 で動作確認をしている。


  * Emacs-Lisp ディレクトリ上へのファイルの展開。

Unix 環境であれば /usr/share/emacs/site-lisp にこのアーカイブを展開し
た quail-naggy/ ディレクトリを置けばいい。ドキュメントなどもそのままコ
ピーしておいたほうがいいだろう。


  * SKK-JISYO.L や tankanji.txt などの変換用辞書の入手＆インデックス・
    データベースファイルの作成。

単漢字変換辞書は、例えば↓から持って来れる。が、『風』の所有者にできれ
ば限定しておきたい。

   《まさか!の単漢字入力。IME『風』 [ JRF の勝手に PR ]》
   http://jrf.cocolog-nifty.com/pr/2012/04/post-4.html

   《jrf_tankanji-20120505.zip》
   https://www.sugarsync.com/pf/D252372_79_7170323252

『風』の所有者ならば、もしかすると、『風』の辞書をテキストに変換して使っ
てよいと考えるかもしれない。一応 dic2txt.pl というそのためのスクリプト
を用意したが、詳しくはそのソースを読んで欲しい。

単漢字変換辞書の形式は、行が #YOMI:ナニカ で始まるところから次の #YOMI
までが一単位で、そこに半角スペース２つか "!-" で区切られた単漢字が 10文
字分が四行で、40字分を一ページとして数ページ分が含まれるのが続くファイ
ルである。行頭が #YOMI 以外の # で始まる行は無視される。

quail-naggy.el では、変換時の候補のしぼりこみに SKK 用の単語辞書を使う。
また、単に単漢字変換だけでなく指定すれば SKK 辞書を使った単語変換もで
きるので、SKK 辞書を手に入れたほうがよい。↓から SKK-JISYO.L をダウン
ロードする。ダウンロードしたものは gzip がかけられていると思うので
gunzip しておく。

  《SKK辞書 - SKK辞書Wiki》
  http://openlab.ring.gr.jp/skk/wiki/wiki.cgi?page=SKK%BC%AD%BD%F1

手に入れた tankanji.txt と SKK-JISYO.L を先にファイルをインストールし
た quiail-naggy/ に置く。ここで、辞書のロードに時間をくわないように、
インデックス・データベースファイルを作っておく必要がある。

<source>
# perl make_skk_dic_db.pl -e SKK-JISYO.L
# perl make_tankanji_dic_db.pl -e tankanji.txt
</source>

…とする。オプションの -e は euc-jisx0213 を使うという意味で、
tankanji.txt が sjis の場合は -s を指定すれば良い。-u とすれば、utf8に
なる。

tankanji.txt が sjis の場合は -s を指定すれば良い。

これで、SKK-JISYO.L.sdb.pag , SKK-JISYO.L.sdb.dir ,
tankanji.txt.sdb.pag , tankanji.txt.sdb.dir ができるはずである。

ファイルをインストールしたときに付いてきた bushu-skk-dic.txt も SKK 辞
書で部首変換に使う。「＠き」などとして木へんの部首の単漢字が引ける。こ
れもインデックス・データベースファイルを作る必要がある。

<source>
# perl make_skk_dic_db.pl -e bushu-skk-dic.txt
</source>

これで、bushu-skk-dic.txt.sdb.pag , bushu-skk-dic.txt.sdb.dir ができる
はずである。


  * naggy-backend.pl の設定。

naggy-backend.pl はそれが起動したディレクトリからデータを読む設定になっ
ている。最初に site-init.nginit というファイルを読む。これを記述する必
要がある。これまでのファイル名で辞書を作ったら、次のようなファイルにす
ればいい。

<source>
load-init-file default-init.nginit

set-tankanji-dic tankanji.txt -e
add-skk-dic SKK-JISYO.L -e
add-skk-dic bushu-skk-dic.txt -e
</source>

ここでも -e は文字コードに euc-jisx0213 を指定するためのオプションで、
この二番目の引き数の位置になければならない。tankanji.txt が sjis であ
れば、-s を指定する。

naggy-backend.pl では、付属の alpha-hwkana.trl と simple_hebrew.trl を
読み込んで使用する。それらは特に設定の必要はない。


  * .emacs の設定。

やっと、.emacs の設定である。.emacs には quail-naggy/ を置いたディレク
トリについて、次のように書く。

<source>
;;
;; Naggy
;;
 (setq load-path
       (append load-path (list "/usr/share/emacs/site-lisp/quail-naggy")))
(require 'quail-naggy)
(setq naggy-backend-program "/usr/bin/perl")
(setq naggy-backend-options
      '("/usr/share/emacs/site-lisp/quail-naggy/naggy-backend.pl"))
(setq default-input-method "japanese-naggy")
(if (>= (string-to-number emacs-version) 24.5)
    (progn 
      (setq naggy-vk-split-window-length 7)
      (setq naggy-vk-frame-length 7)))
</source>

最後の naggy-vk-split-window-length と naggy-vk-frame-length の設定は、
Emacs のウィンドウに候補を表示するとき作るウィンドウの高さを指定する。
経験によると、ftp.gnu.org の /gnu/emacs/windows/ から取ってきた Emacs
24.5 はこの設定ないと候補が 4行表示されるべきところで 3行しか表示され
なかった。一方、gnupack の Emacs 23.3 では必要なかった。

これで C-\ を置せば quail-naggy が起動するはずである。


■ 操作方法

何かを(ローマ字で)入力したあとに、それを平仮名としてまたは片仮名として
または漢字として確定するかをキーで指定するというのが変換の流れになる。

そのため、入力中は、他の Input Method のようにひらがなが表示されるので
はなく、半角英字のローマ字読みが表示される。

そのまま英字として確定するときは return を押せば良い。ひらがなで確定す
るときは「無変換」キーを押し、カタカナで確定するときは「変換」キーを押
す。半角カタカナで確定するときは Shift + 「変換」キーを押す。全角英数
字を出したいときは tab を押す。だいたいそのようにキー設定してある。

ただし、109キーボードではなく 101キーボードにも使えるよう M-tab または
S-return でひらがな確定、S-tab でカタカナ確定をできるようにしてあるが、
それは標準的なキー操作ではないという認識が作者にはある。

なお、Emacs はこれまで「無変換」キーや「変換」キーの Elisp 用キーシンボ
ルをたびたび変えてきた。一応、私が知ってる範囲でそれらのシンボルにもキー
割り当てをしているが、将来的にまた変えられたら、quail-naggy.el の該当部
分をいじって対応して欲しい。どのようなキーシンボルが割り当てられている
かは、M-x describe-key をして調べれば良い。


単漢字変換はローマ字の文字列入力後にスペースキーを押すことで行う。候補
ウィンドウが表示され、そこに 40 個の候補が並ぶ。それらはキーボード上の
一つのキーにマッピングされる。さらにスペースを押すとページをめくって次
の候補群を表示する。

単漢字変換モードに入ってからも、「無変換」キーでひらがな確定、「変換」
キーでカタカナ確定ができることに変わりはない。ただ、半角英数で確定する
ためには C-g で一端キャンセルしてから return する必要がある。


単漢字のしぼり込み検索ということができる。具体的には aka:kou と入力して
変換すると、「あか」という読みを持つ漢字のうち「こう」という読みも持つ
漢字が highlight して表示される。なお、aka:akeru と入力すると、
SKK-JISYO.L で「あk」の読みを持つ「明ける」があるため、「明」が
highlight して表示される。

Akka:bakeru といったように大文字ではじめた場合、または、:akka:bakeru と
いったように最初を : ではじめた場合は、単語変換になり、「あっか」という
読みの候補が「ばける」という読みでしぼり込み検索されて、表示される。1文
字以上の長さのため、後ろのほうがわからない候補は meta キー+ その候補の
キーを押すことで候補を一時的に選択できて、後ろがなんであるかがわかる。

この辺りは『風』の機能よりも拡張されている部分になる。


■ 方式指定変換 (新機能: 2017-04-29)

操作方法の続き。

スペースを押して変換する際に Abraam#greek などと # のあとに方式を指定し
た変換ができる。この場合、スペースを押すと仮想鍵盤も表示されることなく
Αβρααμ と変換される。上で単語変換を :akka:bakeru なとしたが同様の
ことが akka:bakeru#j でできる。

指定できる方式には、今のところ 16進数 Unicode 変換の #u、ギリシャ語の
#greek、ヘブライ語の #hebrew、アラビア語の #arabic、Latin-1 の #latin、
ロシア語の #russian を一応用意している。各言語の知識を私はそれほど持っ
ていないので、暫定的なものと考えていただきたい。詳しい変換テーブルは、
酷な要求かもしれないが、trl ディレクトリに入っているファイルを読んで欲
しい。

あと、方式には、いちおう単漢字変換の #J、単語変換の #j、ひらがなの #h、
カタカナの #k、半角カタカナの #hwkata、英文字全角の #fw もある。(hw は
half-width、fw は full-width の略。)

なお、直前に指定した方式で、次も変換したいときは "\e " (meta キー + ス
ペース)を使えばよい。


■ 単漢字変換を使わず常に単語変換をしたい場合 (新機能: 2020-01-23)

単漢字変換を使わず常に単語変換をしたい場合は、site-init.nginit で 
add-tankanji-dic をコメントアウトすればいい。または以下の source タグで
囲まれた内容の ~/.naggy-backend を作ればよい。

<source>
load-init-file site-init.nginit

.if defined FRONT_END
  .if ${FRONT_END} == quail-naggy
    set DEFAULT_CONVERT skk
  .endif
.endif
</source>


■ わかっている不具合

『風』は、入力が終ったあととかは、制御キーでバックスペースなどが自由に
できる。しかし、quail-naggy.el では、元の quail モードの制限らしく、そ
れができないことがある。確定後に制御キーが使える場合もあり、動作が一定
しない。原因は掴めていないが、quail モードの制限と思うので、詳しく調査
していない。がまんして使っていただきたい。(注: 2017-04-29 に一部のバグ
を取ったので改善しているかもしれない。)

ただ、制御キーの前に C-g を押すと、次の制御キーは効くようになるような
ので、私はだいたい気にせず使っている。


また、gnupack の Emacs で、Windows の日本語 IME を『風』ではなく、
Windows 標準の Microsoft IME を使っていると、「変換」キーでカタカナ変換
をしたあと、変換モードに入ってしまう。これを避けるには、私が標準的でな
いと思っている、S-tab でカタカナ変換しないといけない。

Windows 7 でこれを避けるもう一つの方法は、IME のツールバーを右クリック
で出てくる設定において、追加として日本語キーボードに(Microsoft IME でな
く)単なる「日本語」と書かれたものも選択しておき、shift+control などで選
んで、その Microsoft IME でない、日本語キーボードを使うというものであ
る。

Windows 10 でこれを避けるもう一つの方法は、DIFE.exe (Disable IME for
Emacs) を使うというものである。X Window でも同様にインプット・メソッド
を Emacs で使わないように ~/.Xresources に Emacs.useXIM: off の一文を
足さねばならないかもしれない。詳しくは↓に書いた。

  《Windows 10 (…の…) Emacs で quail-naggy.el を使うには、DIFE.exe が
  ほぼ必須のようだ。 - JRF のひとこと》
  http://jrf.cocolog-nifty.com/statuses/2017/05/windo.html


さらに、ときどき、Emacs から perl の起動がうまくいかないことがあった。
Emacs を起動した直後のひらがな確定や単漢字変換のとき、変換すべきローマ
字列が消えてしまい、その次に何度か同じように変換したりしてると、変換が
できるようになるという現象が、何度かあった。naggy-backend.pl のプロセス
用バッファである" *naggy-backend*" を見ると、exit code 5 で異常終了して
いた。再現性がなくて、原因不明である。


あと、不具合ではないが、naggy モード中は、shift + space で全角スペース
が出るように global-set-key してしまっている。それがおいやな方は、
quail-naggy.el の該当部分を消す必要がある。ごめんなさい。


■ 最後に

最初に書きましたが、このソフトは多くを他の人のアイデアやコードに依って
います。その作者の方々に感謝します。

インストールが大変難しいものになってしまいました。それをクリアした上で
使ってくださる利用者の方がいれば、その方々にも感謝します。

インストールが難しかったり、まだできたてで動作が安定していなかったり、
やろうと思ってできなかった部分が多くあったりしますが、もしかすると遠く
の誰かが必要とするかもしれないと思い、公開することにしました。いろいろ
致らない部分があるとは思いますが、お許しください。


■ 作者

JRF (http://jrf.cocolog-nifty.com/software/)


■ License

The author is a Japanese.

I intended this program to be public-domain, but you can treat
this program under the (new) BSD-License or under the Artistic
License, if it is convenient for you.

Within three months after the release of this program, I
especially admit responsibility of efforts for rational requests
of correction to this program.

I often have bouts of schizophrenia, but I believe that my
intention is legitimately fulfilled.


■ 更新ログ

  2020-01-24 -- 更新。バージョン 0.16。
  2020-01-23 -- 更新。バージョン 0.15。
  2017-11-13 -- 更新。バージョン 0.10。
  2017-07-13 -- 更新。バージョン 0.09。
  2017-06-08 -- 更新。バージョン 0.08。
  2017-04-29 -- 更新。バージョン 0.07。
  2016-02-09 -- 更新。バージョン 0.05。
  2015-11-15 -- 更新。バージョン 0.04。
  2015-11-13 -- 更新。バージョン 0.03。
  2015-10-23 -- 更新。バージョン 0.02。
  2015-10-16 -- 初公開。バージョン 0.01。


(This file was written in Japanese/UTF8.)
