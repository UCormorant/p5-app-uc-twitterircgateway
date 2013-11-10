package App::Uc::TwitterIrcGateway::Plugin::Irc::Nick;
use 5.014;
use parent 'Uc::IrcGateway::Plugin::Irc::Nick';
use Uc::IrcGateway::Common;

sub hook :Hook('irc.nick.finish') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;

    $self->twitter_configure($handle) if $msg->{registered};
}

1;
