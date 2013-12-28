#!/usr/bin/env perl

use 5.014;
use warnings;
use utf8;

use App::Uc::TwitterIrcGateway;

use Data::Lock qw(dlock);
dlock my $CHARSET = ($^O eq 'MSWin32' ? 'cp932' : 'utf8');
binmode STDIN  => ":encoding($CHARSET)";
binmode STDOUT => ":encoding($CHARSET)";

use opts;
use Config::Pit qw(pit_get pit_set);
my $conf = pit_get( 'utig.pl', require => {
    consumer_key    => 'your twitter consumer_key',
    consumer_secret => 'your twitter consumer_secret',
});

local $| = 1;

opts my $host  => { isa => 'Str',  default => '127.0.0.1' },
     my $port  => { isa => 'Int',  default => '16668' },
     my $debug => { isa => 'Bool', default => 0 },
     my $help  => { isa => 'Bool', default => 0 };

warn <<"_HELP_" and exit if $help;
Usage: $0 --host=127.0.0.1 --port=16668 --debug
_HELP_

my $cv = AnyEvent->condvar;
my $ircd = App::Uc::TwitterIrcGateway->new(
    host => $host,
    port => $port,
    servername => 'utig.pl',
    welcome => 'Welcome to the utig server',
    motd_text => do { local $/; <DATA> },
    time_zone => 'Asia/Tokyo',
    app_dir_to_home => 1,
    debug => $debug,

    consumer_key    => $conf->{consumer_key},
    consumer_secret => $conf->{consumer_secret},
);

$ircd->run();
$cv->recv();

exit;

__DATA__
Version 1.0.0

古いプロジェクトから大体移植完了
    tid & actionコマンド復旧
    #activityにJOINしたら返信取得

    残りは MySQL にツイート&お気に入り保存する機能

fix:
    チャンネルのユーザが発言してもアイドル時間が伸び続ける不具合修正
    リツイートの文末が省略表示されないように修正


Version 0.1.0

App::Uc::TwitterIrcGateway として分割
    ログインしてstream,activity,listsにjoin,streamの取得,発言まで
    OAuth認証機能がうまく行ってないの修正
    listのメンバー取るのに時間かかってjoinまで相当待たされるの改善した
    自分を含むリストに自分の発言が流れない不具合修正

Uc::IrcGateway 作りこみ計画
    ゲートウェイサーバ基底クラスとしての完成度上げたい
        プロクシ
        ctcp-action拡張
        外部サービスとの連携機能(簡単にapi叩けるようにする設定のしくみ)
        タイマーイベント
        テスト
    各種コマンド完成
        残: pass, mode, names, privmsg, who, whois
    各コマンドのマスク機能(そのうち)
    設定を gatewaybot と対話で出来るようにしてはどうか
    memo: プラガブルにしてロガーつけてデータベース使いだしたらメモリ消費7MB増

TODO:
    on_event と MySQL の連携
    Twitterアカウントのデータ更新
    process_event の復旧
    PODの内容検討
    いい感じに継承する方法の検討
