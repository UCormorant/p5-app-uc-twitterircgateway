requires 'perl', '5.014';

# not on CPAN
#requires 'Uc::IrcGateway';
#requires 'Uc::Model::Twitter';

# Twitter
requires 'Net::OAuth', '0.26';
requires 'Net::Twitter::Lite', '0.12006';
requires 'AnyEvent::Twitter', '0.63';
requires 'AnyEvent::Twitter::Stream', '0.26';

requires 'Clone', '0.36';
requires 'Config::Pit';
requires 'DateTime::Format::DateParse';
requires 'Encode::Locale', '1.03';
requires 'HTML::Entities';
requires 'Path::Class', '0.29';

requires 'namespace::clean';

# for utig.pl
requires 'Smart::Options', '0.053';
requires 'Term::ReadKey', '2.31';

# dependencies of extlib
requires 'experimental', '0.006';
requires 'AnyEvent', '7.04';
requires 'AnyEvent::IRC', '0.6';
requires 'Class::Accessor::Lite';
requires 'Class::Component', '0.17';
requires 'DBD::mysql';
requires 'DBD::SQLite', '1.027';
requires 'DateTime::Format::HTTP';
requires 'DateTime::Format::MySQL';
requires 'File::HomeDir', '1.00';
requires 'JSON';
requires 'Log::Dispatch', '2.36';
requires 'Teng', '0.17';
requires 'TOML', '0.92';
requires 'YAML';

on 'test' => sub {
    requires 'Test::More', '0.98';
};
