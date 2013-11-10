package App::Uc::TwitterIrcGateway::Plugin::Irc::User;
use 5.014;
use parent 'Uc::IrcGateway::Plugin::Irc::User';
use Uc::IrcGateway::Common;

sub hook :Hook('irc.user.finish') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;

    $self->twitter_configure($handle) if $msg->{registered};
}

1;
