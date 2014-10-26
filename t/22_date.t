use strict;
use warnings;
use Test::MockTime qw/set_fixed_time/;
use CGI::Header;
use Test::More tests => 14;
use Test::Exception;

set_fixed_time( 1341637509 );
my $now = 'Sat, 07 Jul 2012 05:05:09 GMT';

my $header = CGI::Header->new;

%{ $header->header } = ();
is $header->as_hashref->{Date}, undef;
ok !exists $header->as_hashref->{Date};
#is delete $header{Date}, undef;
#is_deeply $header->header, {};

%{ $header->header } = ( date => q{} );
is $header->as_hashref->{Date}, q{};
ok exists $header->as_hashref->{Date};
#is delete $header->as_hashref->{Date}, q{};
#is_deeply $header->header, {};

%{ $header->header } = ( date => 'Sat, 07 Jul 2012 05:05:10 GMT' );
is $header->as_hashref->{Date}, 'Sat, 07 Jul 2012 05:05:10 GMT';
ok exists $header->as_hashref->{Date};
#is delete $header{Date}, 'Sat, 07 Jul 2012 05:05:10 GMT';
#is_deeply $header->header, {};

#my $expected = qr{^Modification of a read-only value attempted};

%{ $header->header } = ( nph => 1 );
is $header->as_hashref->{Date}, $now;
ok exists $header->as_hashref->{Date};
#throws_ok { $header{Date} = 'Sat, 07 Jul 2012 05:05:09 GMT' } $expected;
#throws_ok { delete $header{Date} } $expected;

%{ $header->header } = ( cookie => 'ID=123456; path=/' );
is $header->as_hashref->{Date}, $now;
ok exists $header->as_hashref->{Date};
#throws_ok { $header{Date} = 'Sat, 07 Jul 2012 05:05:09 GMT' } $expected;
#throws_ok { delete $header{Date} } $expected;

%{ $header->header } = ();
my $value = 'Sat, 07 Jul 2012 05:05:09 GMT';
is $header->set( Date => $value ), $value;
is_deeply $header->header, { date => 'Sat, 07 Jul 2012 05:05:09 GMT' };

%{ $header->header } = ( expires => '+3d' );
is $header->as_hashref->{Date}, $now;
ok exists $header->as_hashref->{Date};
#throws_ok { $header{Date} = 'Sat, 07 Jul 2012 05:05:09 GMT' } $expected;
#throws_ok { delete $header{Date} } $expected;
