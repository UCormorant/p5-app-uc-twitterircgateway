package App::Uc::TwitterIrcGateway::Plugin::Irc::Part;
use 5.014;
use parent 'Uc::IrcGateway::Plugin::Irc::Part';
use Uc::IrcGateway::Common;

sub hook :Hook('irc.part.finish') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;
    return unless scalar @{$msg->{success}};

    my $stream_channel   = $handle->options->{stream};
    my $activity_channel = $handle->options->{activity};

    for my $chan (@{$msg->{success}}) {
        delete $handle->{streamer} if $chan eq $handle->options->{stream};
    }
}

1;
