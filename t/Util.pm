package t::Util;

use 5.014;
use warnings;
use utf8;

use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir);
use lib catdir(dirname(__FILE__), '..', 'extlib', 'p5-uc-ircgateway', 'lib');
use lib catdir(dirname(__FILE__), '..', 'extlib', 'p5-uc-model-twitter', 'lib');
use lib catdir(dirname(__FILE__), '..', 'extlib', 'p5-text-inflatedsprintf', 'lib');
use lib catdir(dirname(__FILE__), '..', 'extlib', 'p5-teng-plugin-dbic-resultset', 'lib');
use lib catdir(dirname(__FILE__), '..', 'extlib', 'sharl-AnyEvent-Twitter-Stream', 'lib');
use lib catdir(dirname(__FILE__), '..', 'lib');

use autodie;
use DBI;
use JSON::PP qw();
use Storable qw(dclone);

my $MYSQLD;
my $JSON = JSON::PP->new->utf8->allow_bignum;

sub import {
    strict->import;
    warnings->import;
    utf8->import;
}

sub clone { shift; dclone(shift); }

sub setup_sqlite_dbh {
    shift;
    my $file = shift || ':memory:';
    DBI->connect('dbi:SQLite:'.$file,undef,undef,{RaiseError => 1, PrintError => 0, AutoCommit => 1});
}

sub open_json_file {
    shift;
    $JSON->decode(do { local $/; open my $fh, '<:utf8', shift; $fh->getline; });
}

1;
