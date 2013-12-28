package App::Uc::TwitterIrcGateway::Plugin::Irc::Join;
use 5.014;
use parent 'Uc::IrcGateway::Plugin::Irc::Join';
use Uc::IrcGateway::Common;

sub hook :Hook('irc.join.finish') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;

    my $stream_channel   = $handle->options->{stream};
    my $activity_channel = $handle->options->{activity};

    for my $res (@{$msg->{success}}) {
        if ($res->{channel} eq $stream_channel) {
            $self->streamer(
                handle          => $handle,
                consumer_key    => $handle->{conf_app}{consumer_key},
                consumer_secret => $handle->{conf_app}{consumer_secret},
                token           => $handle->{conf_user}{token},
                token_secret    => $handle->{conf_user}{token_secret},
            );

            $self->api($handle, 'users/show', params => { user_id => $handle->self->login }, cb => sub {
                my ($header, $res, $reason) = @_;
                if ($res) {
                    my $user = $res;
                    my $status = delete $user->{status};
                    $status->{user} = $user;

                    $self->process_tweet($handle, tweet => $status);
                }
                else {
                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $stream_channel, qq|topic fetching error: $reason| );
                }
            });
        }
        elsif ($res->{channel} eq $activity_channel) {
            $self->get_mentions($handle);
        }
    }
}

1;
