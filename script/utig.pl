#!/usr/bin/env perl

use 5.014;
use warnings;
use utf8;

use File::Spec;
use File::Basename;
use lib File::Spec->catdir(dirname(__FILE__), '../extlib', 'p5-uc-ircgateway', 'lib');
use lib File::Spec->catdir(dirname(__FILE__), '../extlib', 'p5-uc-model-twitter', 'lib');
use lib File::Spec->catdir(dirname(__FILE__), '../extlib', 'p5-text-inflatedsprintf', 'lib');
use lib File::Spec->catdir(dirname(__FILE__), '../extlib', 'p5-teng-plugin-dbic-resultset', 'lib');
use lib File::Spec->catdir(dirname(__FILE__), '../lib');

use App::Uc::TwitterIrcGateway;

use Data::Lock qw(dlock);
dlock my $CHARSET = ($^O eq 'MSWin32' ? 'cp932' : 'utf8');
binmode STDIN  => ":encoding($CHARSET)";
binmode STDOUT => ":encoding($CHARSET)";

use Smart::Options;
use Term::ReadKey qw(ReadMode);
use Config::Pit qw(pit_get pit_set);
use Net::Twitter::Lite::WithAPIv1_1;

local $| = 1;

chomp(my $usage_configure = <<"_USAGE_CONFIGURE_");
Usage: $0 configure

this command configures Twitter consumer key and secret key.
these settings will be saved with Config::Pit.
_USAGE_CONFIGURE_

my $opt = Smart::Options->new->usage("Usage: $0 [configure or run]")
->subcmd( configure => Smart::Options->new->usage($usage_configure) )
->subcmd( run       => Smart::Options->new->usage("Usage: $0 run")->options(
    host      => { type => 'Str',  default => '127.0.0.1', describe => 'bind host' },
    port      => { type => 'Int',  default => '16668',     describe => 'listen port' },
    time_zone => { type => 'Str',  default => 'local',     describe => 'server time zone (ex. Asia/Tokyo)' },
    tweet2db  => { type => 'Bool', default => 0,           describe => 'load Tweet2DB plugin' },
    debug     => { type => 'Bool', default => 0,           describe => 'debug mode' },
) );
my $given = $opt->parse(@ARGV);

my $command = $given->{command} // '';
if    ($command eq 'configure') { configure($given->{cmd_option}); }
elsif ($command eq 'run')       { run($given->{cmd_option}); }
else                            { $opt->showHelp; }

exit;

sub configure {
    my ($consumer_key, $consumer_secret);

    CONSUMER_KEY:    $consumer_key = input_secret("input Twitter consumer key: ");
                     goto CONSUMER_KEY if $consumer_key eq '';
    CONSUMER_SECRET: $consumer_secret = input_secret("input Twitter consumer secret: ");
                     goto CONSUMER_SECRET if $consumer_secret eq '';

    my $config = +{
        consumer_key    => $consumer_key,
        consumer_secret => $consumer_secret,
    };

    print "verifying input keys ... ";
    eval { Net::Twitter::Lite::WithAPIv1_1->new( %$config )->get_authorization_url; };
    die "invalid key set is given. retry configure.\n" if $@;
    say "ok.\n";

    pit_set('utig.pl', data => $config);
    say "utig is configured. '$0 run' to start utig.pl";
}

sub run {
    my $option = shift;
    my $config = pit_get('utig.pl', require => {
        consumer_key    => 'your twitter consumer_key',
        consumer_secret => 'your twitter consumer_secret',
    });

    die "utig is not configured yet. '$0 configure' before run utig.pl\n"
        unless defined $config->{consumer_key} && defined $config->{consumer_secret};

    my $cv = AnyEvent->condvar;
    my $ircd = App::Uc::TwitterIrcGateway->new(
        host => $option->{host},
        port => $option->{port},
        servername => 'utig.pl',
        motd_text => do { local $/; <DATA> },
        time_zone => $option->{time_zone},
        app_dir_to_home => 1,
        debug => $option->{debug},

        consumer_key    => $config->{consumer_key},
        consumer_secret => $config->{consumer_secret},

        tweet2db => $option->{tweet2db},
    );

    $ircd->run();
    $cv->recv();
}

sub input_secret {
    ReadMode('noecho');
    print shift; chomp(my $input = <STDIN>);
    ReadMode('restore'); print "\n";
    return $input;
}

__DATA__
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

--------------------------------------------------------------------------------

Version 1.0.0

古いプロジェクトから大体移植完了
    tid & actionコマンド復旧
    #activityにJOINしたら返信取得

    残りは MySQL にツイート&お気に入り保存する機能

fix:
    チャンネルのユーザが発言してもアイドル時間が伸び続ける不具合修正
    リツイートの文末が省略表示されないように修正

--------------------------------------------------------------------------------

Version 1.0.1

pit_getあるけど簡単のためにutigコマンドにconsumer_keyを設定する
サブコマンド追加してインストールからログインまでの手順書いた

書いたところでgithubにしかないモジュール使ってるからインストール出来ないことに
気づいたのでこけるやつはextlibにsubmoduleとして追加した

--------------------------------------------------------------------------------

Version 1.1.0

MySQLにログ取りまくる機能復旧。

    $utig run --tweet2db

でローカルのMySQLのtwitterデータベースにログ取る。
事前に "CREATE DATABASE twitter;" しておく必要あり。
SQLite対応もできなくはないけどたぶんやらない。

タイマーイベントについても
勝手にhandleにオプション生やして適当にやれよと思い始めた

TODO:
    on_event と MySQL の連携
    Twitterアカウントのデータ更新
    process_event の復旧
    いい感じに継承する方法の検討
    リツイート情報が消えてない気がする
