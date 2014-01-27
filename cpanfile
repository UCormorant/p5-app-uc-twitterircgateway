requires 'perl', '5.014';

# not on CPAN
#requires 'Uc::IrcGateway';
#requires 'Uc::Model::Twitter';

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

# dependencies of extlib
requires 'AnyEvent', '7.04';
requires 'AnyEvent::IRC', '0.6';
requires 'Class::Accessor::Lite';
requires 'Class::Component', '0.17';
requires 'DBD::mysql';
requires 'DBD::SQLite', '1.027';
requires 'DateTime::Format::HTTP';
requires 'DateTime::Format::MySQL';
requires 'JSON';
requires 'Log::Dispatch', '2.36';
requires 'Path::Class', '0.29';
requires 'Teng', '0.17';
requires 'YAML';

on 'test' => sub {
    requires 'Test::More', '0.98';
};
