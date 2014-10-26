use strict;
use warnings;
use Test::More tests => 1;

package CGI::Header::Extended;
use base 'CGI::Header';

sub cookie {
    $_[0]->{cookie} ||= {};
}

sub cookies {
    $_[0]->header->{cookies} ||= [];
}

sub as_string {
    my $self    = shift;
    my $query   = $self->query;
    my $cookies = $self->cookies;

    while ( my ($name, $value) = each %{$self->cookie} ) {
        push @{$cookies}, $query->cookie( $name => $value );
    }

    $self->SUPER::as_string;
}

package main;

my $header = CGI::Header::Extended->new;

$header->cookie->{ID} = 123456;

like $header->as_string, qr{Set-Cookie: ID=123456};
