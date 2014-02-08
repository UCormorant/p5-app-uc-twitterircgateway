# NAME

App::Uc::TwitterIrcGateway - Twitter IRC Gateway of me by me for me

# SYNOPSIS

## Configure consumer key that utig.pl uses

    $ script/utig.pl configure

    input Twitter consumer key:
    input Twitter consumer secret:

## Start twitter irc gateway server

    $ script/utig.pl run --host 127.0.0.1 --port 16668

## Login utig.pl server

- IRCクライアントで起動したサーバに適当な名前でログインする
- 暫くするとサーバーから OAuth 認証用の URL を渡されるので、それを開いて認証する
- IRCクライアントで

        /pin <pin code>
- そのうちTwitterストリームの読み込みが始まる

# DESCRIPTION

utig.pl は userstream の監視プログラムに毛が生えた程度のTwitter IRCゲートウェイサーバです

# INSTALLATION

## GitHub Checkout

    $ git clone git@github.com:UCormorant/utig.pl.git
    $ cd utig.pl/
    $ git submodule update --init
    $ cpanm --installdeps .

    # and run utig.pl

    $ perl script/utig.pl run

## CPAN Minus

__\*it doesn't work yet!\*__

    $ cpanm git@github.com:UCormorant/utig.pl.git

    # and run utig.pl
    $ utig run

# FEATURES

- UserStream を使用して閲覧するので発言が即座に流れてくるぞ！
- あんまり API を叩かない仕様だから他の Twitter 関連サービスと併用しても安心！
- コマンドと自前で作った TypableMap が快適な Twitter Life をサポートするぞ！
- Lists 対応。ただしリストに入れていてもフォローしてない人の発言は流れてこないぞ！
しかも自分が作ったリストしか見れないぞ！
- MySQLにログたくさんとるぞ！(いまうごいてないです)
- Follow, unfollow, direct message, block, list, account の操作？そんなもんねぇ！
(いつか対応予定です)
- 設定は `$HOME/.utig` にみんな入ってる

## ACTION COMMANDS

CTCP-actionにいろんなコマンドを実装してあります。

    /me *command* *args*

上記のような感じで使います。

    /me mention (or me): fetch mentions.
    /me reply (or re) <tid> <text>: reply to a <tid> tweet.
    /me favorite (or f, fav) +<tid>: add <tid> tweets to favorites.
    /me unfavorite (or unf, unfav) +<tid>: remove <tid> tweets from favorites.
    /me retweet (or rt) +<tid>: retweet <tid> tweets.
    /me quotetweet (or qt, qw) <tid> <text>: quotetweet a <tid> tweet, like "<text> QT \@tid_user: tid_tweet".
    /me delete (or del, oops) *<tid>: delete your <tid> tweets. if unset <tid>, delete your last tweet.
    /me list (or li) <screen_name>: list <screen_name>'s recent 20 tweets.
    /me information (or in, info) +<tid>: show <tid> tweets information. e.g. retweet_count, has conversation, created_at.
    /me conversation (or co) <tid>: show <tid> tweets conversation.
    /me ratelimit (or rate, limit): show remaining api hit counts.

だいたいこんな感じ！

    [SPACE] f <tid>...

みたいに、先頭に空白入れると action として認識するのでいちいち `/me ` とか打たなくてもへいきです

# DEPENDENCIES

## App::Uc::TwitterIrcGateway

- [perl](https://metacpan.org/pod/perl) >= 5.14
- Uc::IrcGateway [https://github.com/UCormorant/p5-uc-ircgateway](https://github.com/UCormorant/p5-uc-ircgateway)
- Uc::Model::Twitter [https://github.com/UCormorant/p5-uc-model-twitter](https://github.com/UCormorant/p5-uc-model-twitter)
- [Net::Twitter::Lite](https://metacpan.org/pod/Net::Twitter::Lite)
- [AnyEvent::Twitter](https://metacpan.org/pod/AnyEvent::Twitter)
- [AnyEvent::Twitter::Stream](https://metacpan.org/pod/AnyEvent::Twitter::Stream)
- [Clone](https://metacpan.org/pod/Clone)
- [Config::Pit](https://metacpan.org/pod/Config::Pit)
- [DateTime::Format::DateParse](https://metacpan.org/pod/DateTime::Format::DateParse)
- [HTML::Entities](https://metacpan.org/pod/HTML::Entities)
- [namespace::clean](https://metacpan.org/pod/namespace::clean)

## utig.pl

- [Data::Lock](https://metacpan.org/pod/Data::Lock)
- [Smart::Options](https://metacpan.org/pod/Smart::Options)
- [Term::ReadKey](https://metacpan.org/pod/Term::ReadKey)

# BUGS AND LIMITATIONS

Please report any bugs or feature requests to
[https://github.com/UCormorant/p5-app-uc-twitterircgateway/issues](https://github.com/UCormorant/p5-app-uc-twitterircgateway/issues)

# AUTHOR

[https://twitter.com/c18t](https://twitter.com/c18t)

# LICENCE AND COPYRIGHT

Copyright (C) U=Cormorant.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See [perlartistic](https://metacpan.org/pod/perlartistic).
