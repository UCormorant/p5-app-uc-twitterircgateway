requires 'perl', '5.014';

# not on CPAN
requires 'Uc::IrcGateway';
requires 'Uc::Model::Twitter';

# Twitter
requires 'Net::Twitter::Lite';
requires 'AnyEvent::Twitter';
requires 'AnyEvent::Twitter::Stream';

requires 'Clone';
requires 'Config::Pit';
requires 'Path::Class';
requires 'HTML::Entities';
requires 'DateTime::Format::DateParse';

requires 'namespace::clean';

# for utig.pl
requires 'Data::Lock';
requires 'Smart::Options';
requires 'Term::ReadKey';

on 'test' => sub {
    requires 'Test::More', '0.98';
};
