# quail-naggy

<!-- Time-stamp: "2026-05-24T15:26:04Z" -->

単漢字変換 Input Method for Emacs。

詳しくは↓をご覧ください(`Dockerfile` の使い方以外)。

《quail-naggy.el: 単漢字変換 Input Method for Emacs. - JRF のソフトウェア Tips》  
http://jrf.cocolog-nifty.com/software/2015/10/post.html


## `Dockerfile` の使い方

まず使ってみたいという方のために、Dockerfile をご用意しました。

Linux (私は WSL2 を使っています)で docker がインストールされてるとします。

```sh
git clone https://github.com/JRF-2018/quail-naggy
cd quail-naggy
docker build -t jrf/quail-naggy-emacs .
```

…を実行したあと、もしIME「風」の権利をお持ちなどその辞書を使いたい場合は…、

```sh
docker run -it --rm \
    -e MODE=kaze \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v "${PWD}:/app/work" \
    jrf/quail-naggy-emacs
```

そうでない場合は…

```sh
docker run -it --rm \
    -e MODE=default \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v "${PWD}:/app/work" \
    jrf/quail-naggy-emacs
```

…とすれば Emacs が起動するはずです。最初の画面で `q` を押して文字を入力できるようにしてください。

ここで `C-\` で変換文字列入力モードに入り、aka:myoujou などと入力してスペースを押すと変換がはじまり候補ウィンドウが表示されます。「明」は単漢字 aka の読みを持ち、単語 myoujou の一部と重なるため、ハイライトが付いて表示されます。キーボードのその位置を押すと確定です。無変換キーでひらがな変換、変換キーでカタカナ変換、TABキーで全角変換です。

フォント等は詰めてませんし、元の開発が Windows なのですが、それと同じ動きにはできてません。あくまで参考程度の動作とご了承ください。


## GitHub 登録までの略歴

2015-10-16、初公開。2020-01-24、バージョン 0.16。2020-04-07、GitHub にバージョン 0.16 を初登録。


## License

The author is a Japanese.

I intended this program to be public-domain, but you can treat this
program under the (new) BSD-License or under the Artistic License, if
it is convenient for you.

Within three months after the release of this program, I especially
admit responsibility of efforts for rational requests of correction to
this program.

I often have bouts of schizophrenia, but I believe that my intention
is legitimately fulfilled.

----
(This document is mainly written in Japanese/UTF8.)
