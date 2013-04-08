use strict;
use warnings;
use CGI::Header;
use Test::More tests => 5;
use Test::Warn;

subtest 'default' => sub {
    my $header = CGI::Header->new;
    is $header->as_hashref->{P3P}, undef;
    ok !exists $header->as_hashref->{P3P};
    #is delete $header{P3P}, undef;
    #is_deeply $header->header, {};
};

subtest 'an empty string' => sub {
    my $header =CGI::Header->new( -p3p => q{} );
    is $header->as_hashref->{P3P}, undef;
    ok !exists $header->as_hashref->{P3P};
    #is delete $header{P3P}, undef;
    #is_deeply $header->header, {};
};

subtest 'an array' => sub {
    my $header = CGI::Header->new;
    $header->p3p( qw/CAO DSP LAW CURa/ );
    is_deeply $header->header, { p3p => [qw/CAO DSP LAW CURa/] };
    is $header->as_hashref->{P3P}, 'policyref="/w3c/p3p.xml", CP="CAO DSP LAW CURa"';
    ok exists $header->as_hashref->{P3P};
    is $header->p3p, 4;
    is_deeply [ $header->p3p ], [qw/CAO DSP LAW CURa/];
    #is delete $header{P3P}, 'policyref="/w3c/p3p.xml", CP="CAO DSP LAW CURa"';
    #is_deeply $header->header, {};
};

subtest 'a plain string' => sub {
    my $header = CGI::Header->new;
    $header->p3p( 'CAO DSP LAW CURa' );
    is_deeply $header->header, { p3p => 'CAO DSP LAW CURa' };
    ok exists $header->as_hashref->{P3P};
    is $header->p3p, 4;
    is_deeply [ $header->p3p ], [qw/CAO DSP LAW CURa/];
    #is delete $header{P3P}, 'policyref="/w3c/p3p.xml", CP="CAO DSP LAW CURa"';
    #is_deeply $header->header, {};
};

subtest 'exceptions' => sub {
    plan skip_all => 'obsolete';
    my $header = tie my %header, 'CGI::Header';
    warning_is { $header{P3P} = '/path/to/p3p.xml' }
        "Can't assign to '-p3p' directly, use p3p() instead";
};
