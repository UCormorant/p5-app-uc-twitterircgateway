use strict;
use Test::More;

use_ok $_ for qw(
    App::Uc::TwitterIrcGateway

    App::Uc::TwitterIrcGateway::Plugin::Irc::Nick
    App::Uc::TwitterIrcGateway::Plugin::Irc::Pin
    App::Uc::TwitterIrcGateway::Plugin::Irc::User
);

done_testing;
