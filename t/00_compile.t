use strict;
use Test::More tests => 8;

use_ok $_ for qw(
    App::Uc::TwitterIrcGateway

    App::Uc::TwitterIrcGateway::Component::Tweet

    App::Uc::TwitterIrcGateway::Plugin::Ctcp::Action

    App::Uc::TwitterIrcGateway::Plugin::Irc::Join
    App::Uc::TwitterIrcGateway::Plugin::Irc::Part
    App::Uc::TwitterIrcGateway::Plugin::Irc::Pin
    App::Uc::TwitterIrcGateway::Plugin::Irc::Privmsg

    App::Uc::TwitterIrcGateway::Plugin::Log::Tweet2DB
);

done_testing;
