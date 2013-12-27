package App::Uc::TwitterIrcGateway::Plugin::Irc::Privmsg;
use 5.014;
use parent 'Uc::IrcGateway::Plugin::Irc::Privmsg';
use Uc::IrcGateway::Common;

{
    no strict 'refs';
    my $parent = ${__PACKAGE__.'::ISA'}[0];
    *{__PACKAGE__.'::super_action'} = *{$parent.'::action'};
}

sub event :IrcEvent('PRIVMSG') {
    my $self = shift;
    $self->run_hook('irc.privmsg.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.privmsg.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_ngword($handle, $msg->{params}[1]);

    super_action($self, @_);
}

sub hook :Hook('irc.privmsg.finish') {
    my ($hook, $self, $args) = @_;
    my ($handle, $msg, $plugin) = @$args;

    my ($msgtarget, $text) = @{$msg->{params}};
    my ($plain_text, $ctcp) = @{$msg}{qw/plain_text ctcp/};
    my @target_list = map { $_->{target} } @{$msg->{success}};

    my $ctcp_text = '';
    if ($text =~ /^\s/) {
        $plain_text =~ s/^\s+//;
        my $action = ['ACTION', $plain_text];
        push @$ctcp, $action;
        $self->handle_ctcp_msg( $handle, join(' ', @$action), target => $_ ) for @target_list;
        $plain_text = '';
    }
    $text = $plain_text;

    if ($text && scalar @target_list && $self->twitter_agent($handle)) {
        for my $target (@target_list) {
            $self->api($handle, 'statuses/update', params => { status => $text }, cb => sub {
                my ($header, $res, $reason) = @_;
                if (!$res) { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|send error: "$text": $reason| ); }
            } );
        }
    }
}

1;
