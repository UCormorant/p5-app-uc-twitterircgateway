#!/usr/bin/env perl

use 5.014;
use warnings;
use utf8;
use autodie;

use Benchmark qw(:all :hireswallclock);

use File::Spec;
use File::Basename;
use lib File::Spec->catdir(dirname(__FILE__), '../extlib', 'p5-uc-ircgateway', 'lib');
use lib File::Spec->catdir(dirname(__FILE__), '../lib');
use lib File::Spec->catdir(dirname(__FILE__));
use lib::Util;

use Uc::IrcGateway::Common qw(to_json from_json);
use Config::Pit qw(pit_get);

require File::Spec->catfile(dirname(__FILE__), 'lib', 'twitter_agent.pl');

my $conf_app  = pit_get('utig.pl', require =>{
    consumer_key    => 'your twitter consumer_key',
    consumer_secret => 'your twitter consumer_secret',
});
my $conf_user = +{};
twitter_agent($conf_app, $conf_user);

my $db = basename(__FILE__) =~ s/\.\w+$//r;
my $tweets = sample_stream({
    consumer_key    => $conf_app->{consumer_key},
    consumer_secret => $conf_app->{consumer_secret},
    token           => $conf_user->{token},
    token_secret    => $conf_user->{token_secret},
}, 20);

my $dir = dirname(__FILE__);
cmpthese(30 => +{
    store_all => store_all(File::Spec->catfile($dir, "store_all_$db.sqlite")),
    store_nes => store_nes(File::Spec->catfile($dir, "store_nes_$db.sqlite")),
    store_all_txn => store_all(File::Spec->catfile($dir, "store_all_$db.sqlite"), 'enable_txn'),
    store_nes_txn => store_nes(File::Spec->catfile($dir, "store_nes_$db.sqlite"), 'enable_txn'),
}, 'auto');

cmpthese(60 => +{
    fetch_all => fetch_all(File::Spec->catfile($dir, "store_all_$db.sqlite")),
    fetch_nes => fetch_nes(File::Spec->catfile($dir, "store_nes_$db.sqlite")),
}, 'auto');

exit;

sub store_all {
    my ($db, $enable_txn) = @_;
    my $dbh = setup_dbh('SQLite',$db) or die "dbh connect error";
    $dbh->do(q{DROP TABLE IF EXISTS tweet});
    $dbh->do(q{
        CREATE TABLE 'tweet' (
          'id'    int  NOT NULL,
          'tweet' text,

          PRIMARY KEY ('id')
        )
    });
    $dbh->do(q{VACUUM});
    my $insert = sub {
        my $item = shift;
        my $sth = $dbh->prepare(q{
            INSERT OR REPLACE
                INTO tweet (id, tweet) VALUES (?, ?);
        });
        $sth->execute(rand 2**16, to_json($item, pretty => 0));
    };
    return $enable_txn
    ? sub {
        $dbh->begin_work;
        $insert->($_) for @$tweets;
        $dbh->commit;
    }
    : sub {
#        $dbh->do(q{DELETE FROM tweet});
        $insert->($_) for @$tweets;
    };
}

sub store_nes {
    my ($db, $enable_txn) = @_;
    my $dbh = setup_dbh('SQLite',$db) or die "dbh connect error";
    $dbh->do(q{DROP TABLE IF EXISTS tweet});
    $dbh->do(q{
        CREATE TABLE 'tweet' (
          'id'    int  NOT NULL,
          'text'  text,
          'login' text,
          'nick'  text,

          PRIMARY KEY ('id')
        )
    });
    $dbh->do(q{VACUUM});
    my $insert = sub {
        my $item = shift;
        my $sth = $dbh->prepare(q{
            INSERT OR REPLACE
                INTO tweet (id, text, login, nick) VALUES (?, ?, ?, ?);
        });
        my @values = (
            rand 2**16,
            $item->{text},
            $item->{user}{id},
            $item->{user}{screen_name},
        );
        $sth->execute(@values);
    };

    return $enable_txn
    ? sub {
        $dbh->begin_work;
        $insert->($_) for @$tweets;
        $dbh->commit;
    }
    : sub {
#        $dbh->do(q{DELETE FROM tweet});
        $insert->($_) for @$tweets;
    };
}

sub fetch_all {
    my $dbh = setup_dbh('SQLite',+shift) or die "dbh connect error";
    my $sth = $dbh->prepare(q{SELECT id FROM tweet});
    $sth->execute();
    my $result = $sth->fetchall_arrayref;
    my $select = sub {
        my $item_id = shift;
        my $sth = $dbh->prepare(q{
            SELECT tweet FROM tweet
                WHERE id = ?
        });
        $sth->execute($item_id);
        my $result = $sth->fetchrow_arrayref;
        $result ? from_json($result->[0]) : undef;
    };
    return sub {
        $select->($_->[0]) for @$result;
    };
}

sub fetch_nes {
    my $dbh = setup_dbh('SQLite',+shift) or die "dbh connect error";
    my $sth = $dbh->prepare(q{SELECT id FROM tweet});
    $sth->execute();
    my $result = $sth->fetchall_arrayref;
    my $select = sub {
        my $item_id = shift;
        my $sth = $dbh->prepare(q{
            SELECT * FROM tweet
                WHERE id = ?
        });
        $sth->execute($item_id);
        $sth->fetchrow_hashref;
    };
    return sub {
        $select->($_->[0]) for @$result;
    };
}

__END__
streamer starts to read... connected.
collect 20 tweets... done.

Benchmark: timing 30 iterations of store_all, store_all_txn, store_nes, store_nes_txn...
 store_all: 103.75 wallclock secs ( 0.50 usr +  2.37 sys =  2.87 CPU) @ 10.45/s(n=30)
store_all_txn: 8.43446 wallclock secs ( 0.26 usr +  0.31 sys =  0.58 CPU) @ 51.99/s (n=30)
 store_nes: 92.277 wallclock secs ( 0.33 usr +  2.26 sys =  2.59 CPU) @ 11.58/s(n=30)
store_nes_txn: 6.27834 wallclock secs ( 0.06 usr +  0.22 sys =  0.28 CPU) @ 106.38/s (n=30)
            (warning: too few iterations for a reliable count)

                Rate     store_all     store_nes store_all_txn store_nes_txn
store_all     10.5/s            --          -10%          -80%          -90%
store_nes     11.6/s           11%            --          -78%          -89%
store_all_txn 52.0/s          397%          349%            --          -51%
store_nes_txn  106/s          918%          818%          105%            --

Benchmark: timing 60 iterations of fetch_all, fetch_nes...
 fetch_all: 53.8766 wallclock secs (31.87 usr + 20.45 sys = 52.32 CPU) @  1.15/s (n=60)
 fetch_nes: 41.9675 wallclock secs (22.20 usr + 18.63 sys = 40.83 CPU) @  1.47/s (n=60)

            Rate fetch_all fetch_nes
fetch_all 1.15/s        --      -22%
fetch_nes 1.47/s       28%        --
