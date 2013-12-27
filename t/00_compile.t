use strict;
use Test::More tests => 6;

use_ok $_ for qw(
    App::Uc::TwitterIrcGateway

    App::Uc::TwitterIrcGateway::Plugin::Ctcp::Action

    App::Uc::TwitterIrcGateway::Plugin::Irc::Join
    App::Uc::TwitterIrcGateway::Plugin::Irc::Part
    App::Uc::TwitterIrcGateway::Plugin::Irc::Pin
    App::Uc::TwitterIrcGateway::Plugin::Irc::Privmsg
);

done_testing;
