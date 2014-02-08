package App::Uc::TwitterIrcGateway::Plugin::Log::Tweet2DB;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;
use Uc::Model::Twitter;
use AnyEvent;
use Config::Pit qw(pit_get);

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;

    my $mysql = pit_get('utig.pl.mysql', require => {
        user => 'your mysql account',
        pass => 'your mysql password',
    });
    $config->{connect_info}[1] = $mysql->{user};
    $config->{connect_info}[2] = $mysql->{pass};

    $plugin->{queue}  = +[];
    $plugin->{schema} = Uc::Model::Twitter->new( connect_info => $config->{connect_info} );
    $plugin->{guard}  = AnyEvent->timer(after => 10, interval => 10, cb => sub {
        $class->log(undef, debug => sprintf "Log::Tweet2DB commit.");
        $plugin->commit;
    });

    $class->logger->on_destroy(sub { $plugin->commit; });

    $plugin->{schema}->create_table(if_not_exists => 1);

    my $w; $w = AnyEvent->timer(after => 1, cb => sub {
        $class->log(undef, info => sprintf "load plugin: %s", ref $plugin);
        undef $w;
    });
}

sub tweet2db :LogLevel('tweet2db') {
    my $logger = shift;
    my $level = shift;
    my $message = shift;
    my $plugin = pop;
    my $handle = pop;
    my @args = @_;

    if ($handle && $handle->self->isa('Uc::IrcGateway::User')) {
        my $queue = +{
            tweet => $message,
            user  => $handle->self,
        };
        push @{$plugin->{queue}}, $queue if ref $queue->{tweet} && ref $queue->{user};
    }

    ();
}

sub remark2db :LogLevel('remark2db') {
    my $logger = shift;
    my $level = shift;
    my $message = shift;
    my $plugin = pop;
    my $handle = pop;
    my @args = @_;

    if ($handle && $handle->self->isa('Uc::IrcGateway::User')) {
        my $attr = $message;

        my $id  = delete $attr->{id}  if exists $attr->{id};
        my $tid = delete $attr->{tid} if exists $attr->{tid};
        $id = $handle->{tmap}->get($tid) if $tid;
        my $tweet = $handle->ircd->get_tweet($handle, $id);

        my $columns = {
            id => $id,
            user_id => $handle->self->login,
            status_user_id => $tweet->{login},
        };
        for my $col (qw/favorited retweeted/) {
            $columns->{$col} = delete $attr->{$col} if exists $attr->{$col};
        }

        $plugin->commit;
        $plugin->{schema}->update_or_create_remark( $columns );
    }

    ();
}

sub commit {
    my $plugin = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;

    return unless scalar @{$plugin->{queue}};

    eval {
        my $txn = $plugin->{schema}->txn_scope;
        while (my $q = shift @{$plugin->{queue}}) {
            $plugin->{schema}->find_or_create_status(
                $q->{tweet},
                { user_id => $q->{user}->login, ignore_unmarking => 1 },
            );
        }
        $txn->commit;
    };

    if ($@ && exists $args{handle}) {
        my $self = $args{handle}->ircd;
        $self->log($args{handle}, emerg => $@);
        $args{handle}->push_shutdown; # close connection
    }
}

1;
