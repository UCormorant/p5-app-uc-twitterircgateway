package App::Uc::TwitterIrcGateway::Plugin::Irc::Pin;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;
use Config::Pit qw(pit_set);
use Scalar::Util qw(blessed);

use Uc::IrcGateway::Plugin::DefaultSet;
push @Uc::IrcGateway::Plugin::DefaultSet::IRC_COMMAND_LIST, qw(
    pin
);

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('PIN') {
    my $self = shift;
    $self->run_hook('irc.pin.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.pin.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.pin.start' => \@_);

    my $pin = $msg->{params}[0];
    my $nt = $self->twitter_agent($handle, $pin);
    if (blessed $nt) {
        my $conf = $self->servername.'.'.$handle->options->{account};
        pit_set( $conf, data => {
            %{$handle->{conf_user}},
        } ) if $nt->{config_updated};
    }

    $self->run_hook('irc.pin.finish' => \@_);
}

1;
