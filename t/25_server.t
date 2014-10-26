use strict;
use warnings;
use CGI::Header;
use Test::More tests => 12;
use Test::Exception;

#my %env;
my $header = tie my %header, 'CGI::Header', {};

%{ $header->header } = ();
is $header{Server}, undef;
ok !exists $header{Server};
my $value = 'Apache/1.3.27 (Unix)';
is $header->set( Server => $value ), $value;
is_deeply $header->header, { server => 'Apache/1.3.27 (Unix)' };

%{ $header->header } = ( server => 'Apache/1.3.27 (Unix)' );
is $header{Server}, 'Apache/1.3.27 (Unix)';
ok exists $header{Server};

%{ $header->header } = ( nph => 1 );

local %ENV;
is $header->as_hashref->{Server}, 'cmdline';
ok exists $header->as_hashref->{Server};

$ENV{SERVER_SOFTWARE} = 'Apache/1.3.27 (Unix)';
is $header->as_hashref->{Server}, 'Apache/1.3.27 (Unix)';
ok exists $header->as_hashref->{Server};

my $expected = qr{^Modification of a read-only value attempted};
throws_ok { $header{Server} = 'Apache/1.3.27 (Unix)' } $expected;
throws_ok { delete $header{Server} } $expected;
