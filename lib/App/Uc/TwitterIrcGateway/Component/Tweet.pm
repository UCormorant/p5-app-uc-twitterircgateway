package App::Uc::TwitterIrcGateway::Component::Tweet;
use 5.014;
use Uc::IrcGateway::Common;

use Carp qw(croak);
use DBI qw(:sql_types);
use DBD::SQLite 1.027;
use Path::Class qw(file);
use AnyEvent;

my %CREATE_TABLE_SQL = (
    tweet            => q{
CREATE TABLE 'tweet' (
  'id'    int  NOT NULL,
  'text'  text,
  'login' text,
  'nick'  text,

  PRIMARY KEY ('id')
)
    },
);

sub setup_dbh {
    my $handle = shift;
    my $db = file($handle->ircd->app_dir, sprintf "%s.tweet.sql", $handle->self->login);
    $handle->{tweet_dbh} = DBI->connect(
        'dbi:SQLite:'.$db,undef,undef,
        +{ RaiseError => 1, PrintError => 0, AutoCommit => 1, sqlite_unicode => 1 }
    );
    setup_database($handle, force_create_table => 1);

    # clean up
    $handle->{tweet_dbh}->do("VACUUM");

    # queue
    $handle->{tweet_db_queue} = +[];

    # transaction timer
    $handle->{tweet_db_guard_txn} = AnyEvent->timer(after => 30, interval => 30, cb => sub {
        commit_tweet_db(undef, $handle);
    });

    # VACUUM timer
    $handle->{tweet_db_guard_vacuum} = AnyEvent->timer(after => 6*3600, interval => 6*3600, cb => sub {
        return unless $handle->{tmap} and $handle->{timeline};
        vacuum_tweet_db(undef, $handle, $handle->{timeline});
    });
}

sub setup_database {
    my ($handle, %opt) = @_;
    my %sql = %CREATE_TABLE_SQL;
    my $dbh = $handle->{tweet_dbh};

    drop_table($handle) if $opt{force_create_table};

    for my $table (keys %sql) {
        my $sth = $dbh->prepare(q{
            SELECT count(*) FROM sqlite_master
                WHERE type='table' AND name=?;
        });
        $sth->execute($table);
        delete $sql{$table} if $sth->fetchrow_arrayref->[0];
    }

    for my $table (keys %sql) {
        $dbh->do($_) for split ";", $sql{$table};
    }
}

sub drop_table {
    my $handle = shift;
    my $dbh = $handle->{tweet_dbh};
    $dbh->do("DROP TABLE IF EXISTS $_") for scalar @_ ? @_ : keys %CREATE_TABLE_SQL;
}


use namespace::clean;

sub get_tweet {
    my ($self, $handle, $tweet_id) = @_;
    return unless defined $tweet_id;
    return unless $self->check_connection($handle);
    return unless $handle->self->isa('Uc::IrcGateway::User');

    setup_dbh($handle) unless defined $handle->{tweet_dbh};

    # commit queue before select
    $self->commit_tweet_db($handle);

    my $sth = $handle->{tweet_dbh}->prepare(q{
        SELECT * FROM tweet
            WHERE id=?;
    });
    $sth->execute($tweet_id);
    $sth->fetchrow_hashref;
}

sub set_tweet {
    my ($self, $handle, $tweet) = @_;
    return unless ref $tweet && exists $tweet->{id};
    return unless defined(my $tweet_id = $tweet->{id});
    return unless $self->check_connection($handle);
    return unless $handle->self->isa('Uc::IrcGateway::User');

    setup_dbh($handle) unless defined $handle->{tweet_dbh};

    my $sth = $handle->{tweet_dbh}->prepare(q{
        INSERT OR REPLACE
            INTO tweet (id, text, login, nick) VALUES (?, ?, ?, ?);
    });
    my @values = (
        $tweet->{id},
        $tweet->{text},
        $tweet->{user}{id},
        $tweet->{user}{screen_name},
    );
    $sth->execute(@values);
}

sub commit_tweet_db {
    shift;
    my ($handle) = @_;
    return unless defined $handle->{tweet_dbh};
    return unless scalar @{$handle->{tweet_db_queue}};

    my $dbh = $handle->{tweet_dbh};
    my $sth = $handle->{tweet_dbh}->prepare(q{
        INSERT OR REPLACE
            INTO tweet (id, text, login, nick) VALUES (?, ?, ?, ?);
    });

    $dbh->begin_work;
    while (my $q = shift @{$handle->{tweet_db_queue}}) {
        $sth->execute(@$q);
    }
    $dbh->commit;
}

sub vacuum_tweet_db {
    shift;
    my ($handle, $ids) = @_;
    return unless defined $handle->{tweet_dbh};
    return unless ref $ids eq 'ARRAY' and scalar @$ids;

    my $dbh = $handle->{tweet_dbh};
    $dbh->do(
        sprintf q{DELETE FROM tweet WHERE id NOT IN (%s)},
            join ",", map { sprintf "'%s'", s/'/\\'/gr; } @$ids
    );
    $dbh->do("VACUUM");
}

1;
