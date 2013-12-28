package App::Uc::TwitterIrcGateway::Plugin::Log::Tweet2DB;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

#sub todo_build_logger {
#    my $self = shift;
#    my $logger = Uc::IrcGateway::Logger->new(
#        gateway => $self,
#        log_debug => $self->debug,
#        logging => sub {
#            my ($self, $queue, %args) = @_;
#
#            if (ref $queue) {
#                push @{$self->{queue}}, $queue if ref $queue->{tweet} && ref $queue->{user};
#                return;
#            }
#
#            eval {
#                my $txn = $self->{schema}->txn_scope;
#                while (my $q = shift @{$self->{queue}}) {
#                    $self->{schema}->find_or_create_status_from_tweet(
#                        $q->{tweet},
#                        { user_id => $q->{user}->login, ignore_remark_disabling => 1 }
#                    );
#                }
#                $txn->commit;
#            };
#
#            if ($@ && exists $args{handle}) {
#                $self->debug($@, handle => $args{handle});
#                delete $self->gateway->handles->{refaddr $args{handle}};
##                if ($@ =~ /Rollback failed/) {
##                    undef $handle;
##                }
#            }
#        },
##        debugging => sub {},
#        remark => sub {
#            my ($self, $handle, $attr) = @_;
#
#            my $id  = delete $attr->{id}  if exists $attr->{id};
#            my $tid = delete $attr->{tid} if exists $attr->{tid};
#            $id = $handle->{tmap}->get($tid) if $tid;
#
#            my $columns = { id => $id, user_id => $handle->self->login };
#            for my $col (qw/favorited retweeted/) {
#                $columns->{$col} = delete $attr->{$col} if exists $attr->{$col};
#            }
#
#            $self->{schema}->update_or_create_remark_with_retweet( $columns );
#        },
#    );
#    my $mysql = pit_get('mysql', require => {
#        user => '',
#        pass => '',
#    });
#    $logger->{schema} = Uc::Model::Twitter->new( connect_info => ['dbi:mysql:twitter', $mysql->{user}, $mysql->{pass}, {
#        mysql_enable_utf8 => 1,
#        on_connect_do     => ['set names utf8mb4'],
#    }]);
#    $logger->{trigger} = AE::timer 10, 10, sub { $logger->log; };
#
#    $self->logger($logger);
#}

1;
