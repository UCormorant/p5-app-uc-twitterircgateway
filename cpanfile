requires 'perl', '5.014';

requires 'Uc::IrcGateway';
requires 'Uc::Model::Twitter';

requires 'AnyEvent::Twitter';
requires 'AnyEvent::Twitter::Stream';
requires 'Net::Twitter::Lite';

requires 'opts';
requires 'YAML';
requires 'Clone';
requires 'Data::Lock';
requires 'Config::Pit';
requires 'Path::Class';
requires 'HTML::Entities';
requires 'DateTime::Format::DateParse';

on 'test' => sub {
    requires 'Test::More', '0.98';
};
