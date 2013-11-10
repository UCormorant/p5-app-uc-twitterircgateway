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
    time_zone => 'Asia/Tokyo',
    debug => $debug,

    consumer_key    => $conf->{consumer_key},
    consumer_secret => $conf->{consumer_secret},
);

$ircd->run();
$cv->recv();

1;
