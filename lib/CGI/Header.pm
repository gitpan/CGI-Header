package CGI::Header;
use 5.008_009;
use strict;
use warnings;
use CGI::Util qw//;
use Carp qw/carp croak/;
use Scalar::Util qw//;
use List::Util qw/first/;

our $VERSION = '0.14';

my $READONLY = 'Modification of a read-only value attempted';

# Why Inside-out?
# To avoid blessing a hash. This class behaves like a hash,
# and so the hash dereference operator of the derived class
# may be overloaded. Maybe not.

BEGIN { *id = \&Scalar::Util::refaddr }

my ( %header, %iterator ); # instance variables

sub new {
    my $self = bless \do { my $anon_scalar }, shift;
    $header{ id $self } = ref $_[0] eq 'HASH' ? shift : { @_ };
    $self;
}

sub header { $header{ id $_[0] } }

my %alias_of = (
    -content_type => '-type',   -window_target => '-target',
    -cookies      => '-cookie', -set_cookie    => '-cookie',
);

sub rehash {
    my $self   = shift;
    my $header = $header{ id $self };

    for my $key ( keys %{$header} ) {
        my $prop = _lc( $key );
           $prop = $alias_of{ $prop } || $prop;

        next if $key eq $prop;

        # overwrites existent property
        $header->{ $prop } = delete $header->{ $key };
    }

    $self;
}

my $get = sub { $_[0]->{$_[1]} };

my %get = (
    -content_disposition => sub {
        my $filename = $_[0]->{-attachment};
        $filename ? qq{attachment; filename="$filename"} : $get->( @_ );
    },
    -content_type => sub {
        my ( $type, $charset ) = @{ $_[0] }{qw/-type -charset/};
        return if defined $type and $type eq q{};
        $type ||= 'text/html';
        $type .= "; charset=$charset" if $charset && $type !~ /\bcharset\b/;
        $type;
    },
    -date => sub {
        my ( $h ) = @_;
        $h->{-nph} || $h->{-cookie} || $h->{-expires}
            ? CGI::Util::expires() : $get->( @_ );
    },
    -expires => sub {
        my $expires = $get->( @_ );
        $expires ? CGI::Util::expires( $expires ) : undef;
    },
    -p3p => sub {
        my $tags = $get->( @_ );
        $tags = join ' ', @{ $tags } if ref $tags eq 'ARRAY';
        $tags ? qq{policyref="/w3c/p3p.xml", CP="$tags"} : undef;
    },
    -server => sub {
        $_[0]->{-nph} ? $ENV{SERVER_SOFTWARE} || 'cmdline' : $get->( @_ );
    },
    -set_cookie => sub { $_[0]->{-cookie} },
    -window_target => sub { $_[0]->{-target} },
);

sub get {
    my $self = shift;
    my $field = _lc( shift );
    my $header = $header{ id $self };
    $field && ( $get{$field} || $get )->( $header, $field );
}

my $set = sub { $_[0]->{$_[1]} = $_[2] };

my %set = (
    -content_disposition => sub { $set->( @_ ); delete $_[0]->{-attachment} },
    -content_type => sub {
        my ( $header, $norm, $value ) = @_;
        if ( defined $value and $value ne q{} ) {
            @{ $header }{qw/-type -charset/} = ( $value, q{} );
        }
        else {
            carp "Can set '$norm' to neither undef nor an empty string";
        }
    },
    -date => sub {
        my ( $h ) = @_;
        croak $READONLY if $h->{-nph} or $h->{-cookie} or $h->{-expires};
        $set->( @_ );
    },
    -expires => sub {
        carp "Can't assign to '-expires' directly, use expires() instead";
    },
    -p3p => sub {
        carp "Can't assign to '-p3p' directly, use p3p_tags() instead";
    },
    -server => sub {
        my ( $h ) = @_;
        croak $READONLY if $h->{-nph};
        $set->( @_ );
    },
    -set_cookie => sub {
        my ( $header, $value ) = @_[0, 2];
        delete $header->{-date} if $value;
        $header->{-cookie} = $value;
    },
    -window_target => sub { $_[0]->{-target} = $_[2] },
);

sub set {
    my ( $self, $field, $value ) = @_;
    $field = _lc( $field );
    my $header = $header{ id $self };
    ( $set{$field} || $set )->( $header, $field, $value ) if $field;
    $value;
}

my $exists = sub { exists $_[0]->{$_[1]} };

my %exists = (
    -content_disposition => sub { $exists->( @_ ) || $_[0]->{-attachment} },
    -content_type => sub { !defined $_[0]->{-type} || $_[0]->{-type} ne q{} },
    -date => sub {
        my ( $h ) = @_;
        $h->{-nph} || $h->{-expires} || $h->{-cookie} || $exists->( @_ );
    },
    -server => sub { $_[0]->{-nph} || $exists->( @_ ) },
    -set_cookie => sub { exists $_[0]->{-cookie} },
    -window_target => sub { exists $_[0]->{-target} },
);

sub exists {
    my $self = shift;
    my $field = _lc( shift );
    my $header = $header{ id $self };
    $field && ( $exists{$field} || $exists )->( $header, $field );
}

my $delete = sub { delete $_[0]->{$_[1]} };

my %delete = (
    -content_disposition => sub { delete @{$_[0]}{$_[1], '-attachment'} },
    -content_type => sub { delete $_[0]->{-charset}; $_[0]->{-type} = q{} },
    -date => sub {
        my ( $h ) = @_;
        croak $READONLY if $h->{-nph} or $h->{-cookie} or $h->{-expires};
        $delete->( @_ );
    },
    -expires => $delete,
    -p3p => $delete,
    -server => sub { $_[0]->{-nph} and croak $READONLY; $delete->( @_ ) },
    -set_cookie => sub { delete $_[0]->{-cookie} },
    -window_target => sub { delete $_[0]->{-target} },
);

sub delete {
    my $self   = shift;
    my $field  = _lc( shift );
    my $header = $header{ id $self };

    if ( my $code = $delete{$field} ) {
        my $value = defined wantarray && $self->get( $field );
        $code->( $header, $field );
        return $value;
    }

    delete $header->{ $field };
}

sub is_empty { !$_[0]->SCALAR }

sub clear {
    my $self = shift;
    %{ $self->header } = ( -type => q{} );
    $self;
}

sub clone {
    my $self = shift;
    my $header = $header{ id $self };
    ref( $self )->new( %{$header} );
}

BEGIN {
    my @conflicts = (
        attachment => [ '-content_disposition' ],
        nph        => [ '-date', '-server' ],
        expires    => [ '-date' ],
    );

    while ( my ($method, $conflicts) = splice @conflicts, 0, 2 ) {
        my $prop = "-$method";
        my $code = sub {
            my $self   = shift;
            my $header = $header{ id $self };
    
            if ( @_ ) {
                my $value = shift;
                delete @{ $header }{ @$conflicts } if $value;
                $header->{ $prop } = $value;
            }

            $header->{ $prop };
        };

        no strict 'refs';
        *{ $method } = $code;
    }
}

sub p3p_tags {
    my $self   = shift;
    my $header = $header{ id $self };

    if ( @_ ) {
        $header->{-p3p} = @_ > 1 ? [ @_ ] : shift;
    }
    elsif ( my $tags = $header->{-p3p} ) {
        return ref $tags eq 'ARRAY' ? @{$tags} : split ' ', $tags;
    }

    return;
}

sub flatten {
    my $self  = shift;
    my $level = defined $_[0] ? int shift : 1;
    my %copy  = %{ $self->header };

    my @headers;

    my ( $cookie, $expires, $nph, $status, $target )
        = delete @copy{qw/-cookie -expires -nph -status -target/};

    push @headers, 'Server', $ENV{SERVER_SOFTWARE} || 'cmdline' if $nph;
    push @headers, 'Status',        $status if $status;
    push @headers, 'Window-Target', $target if $target;

    if ( my $tags = delete $copy{-p3p} ) {
        $tags = join ' ', @{ $tags } if ref $tags eq 'ARRAY';
        push @headers, 'P3P', qq{policyref="/w3c/p3p.xml", CP="$tags"};
    }

    if ( ref $cookie eq 'ARRAY' and $level ) {
        push @headers, map { ('Set-Cookie', $_) } @{ $cookie };
    }
    elsif ( $cookie ) {
        push @headers, 'Set-Cookie', $cookie;
    }

    push @headers, 'Expires', CGI::Util::expires($expires) if $expires;

    if ( $expires or $cookie or $nph ) {
        push @headers, 'Date', CGI::Util::expires();
    }

    if ( my $fn = delete $copy{-attachment} ) {
        push @headers, 'Content-Disposition', qq{attachment; filename="$fn"};
    }

    my ( $type, $charset ) = delete @copy{qw/-type -charset/};

    # not ordered
    while ( my ($key, $value) = each %copy ) {
        push @headers, _ucfirst( $key ), $value;
    }

    if ( !defined $type or $type ne q{} ) {
        my $ct = $type || 'text/html';
        $ct .= "; charset=$charset" if $charset && $ct !~ /\bcharset\b/;
        push @headers, 'Content-Type', $ct;
    }

    @headers;
}

sub each {
    my ( $self, $callback ) = @_;

    if ( ref $callback eq 'CODE' ) {
        my @headers = $self->flatten;
        while ( my ($field, $value) = splice @headers, 0, 2 ) {
            $callback->( $field, $value );
        }
    }
    else {
        croak 'Must provide a code reference to each()';
    }

    $self;
}

sub field_names { keys %{{ $_[0]->flatten(0) }} }

sub as_string {
    my $self = shift;
    my $eol  = defined $_[0] ? shift : "\015\012";

    my @lines;

    # add Status-Line
    if ( $self->nph ) {
        my $protocol = $ENV{SERVER_PROTOCOL} || 'HTTP/1.0';
        my $status   = $self->get('Status')  || '200 OK';
        push @lines, "$protocol $status";
    }

    # add response headers
    $self->each(sub {
        my ( $field, $value ) = @_;
        $value = $value->as_string if ref $value eq 'CGI::Cookie';
        $value =~ s/$eol(\s)/$1/g;
        $value =~ s/$eol|\015|\012//g;
        push @lines, "$field: $value";
    });

    join $eol, @lines, q{};
}

sub dump {
    my $self = shift;

    require Data::Dumper;

    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Terse  = 1;

    Data::Dumper::Dumper({
        __PACKAGE__, {
            header => $self->header,
        },
        @_,
    });
}

sub _lc {
    my $str = lc shift;
    $str = "-$str" if $str !~ /^-/;
    substr( $str, 1 ) =~ tr/-/_/;
    $str;
}

sub _ucfirst {
    my $str = shift;
    $str =~ s/^-(\w)/\u$1/;
    $str =~ tr/_/-/;
    $str;
}

BEGIN {
    *TIEHASH = \&new;    *FETCH  = \&get;    *STORE = \&set;
    *EXISTS  = \&exists; *DELETE = \&delete; *CLEAR = \&clear;    
}

sub SCALAR {
    my $self = shift;
    my $header = $header{ id $self };
    !defined $header->{-type} || first { $_ } values %{ $header };
}

sub FIRSTKEY {
    my $self = shift;
    my @fields = $self->field_names;
    ( $iterator{ id $self } = sub { shift @fields } )->();
}

sub NEXTKEY { $iterator{ id $_[0] }->() }

sub DESTROY {
    my $self = shift;
    delete $header{ id $self };
    delete $iterator{ id $self };
    return;
}

sub STORABLE_freeze {
    my ( $self, $cloning ) = @_;
    ( q{}, $header{ id $self } );
}

sub STORABLE_thaw {
    my ( $self, $serialized, $cloning, $header ) = @_;
    $header{ id $self } = $header;
    $self;
}

1;

__END__

=head1 NAME

CGI::Header - Adapter for CGI::header() function

=head1 SYNOPSIS

  use CGI::Header;

  # CGI.pm-compatible HTTP header properties
  my $header = {
      -attachment => 'foo.gif',
      -charset    => 'utf-7',
      -cookie     => [ $cookie1, $cookie2 ], # CGI::Cookie objects
      -expires    => '+3d',
      -nph        => 1,
      -p3p        => [qw/CAO DSP LAW CURa/],
      -target     => 'ResultsWindow',
      -type       => 'image/gif'
  };

  # create a CGI::Header object
  my $h = CGI::Header->new( $header );

  # update $header
  $h->set( 'Content-Length' => 3002 );
  $h->delete( 'Content-Disposition' );
  $h->clear;

  $h->header; # same reference as $header

=head1 DESCRIPTION

This module is a utility class to manipulate a hash reference
which L<CGI>'s C<header()> function receives.
This class is, so to speak, a subclass of Hash
because the function behaves like a hash,
while Perl5 doesn't provide a built-in class called Hash.

This module isn't the replacement of the function.
Although this class implements C<as_string()> method,
the function should stringify the reference in most cases.

This module can be used in the following situation:

=over 4

=item 1. $header is a hash reference which represents CGI response headers

For example, L<CGI::Application> implements C<header_add()> method
which can be used to add CGI.pm-compatible HTTP header properties.
Instances of CGI applications often hold those properties.

  my $header = { -type => 'text/plain' };

=item 2. Manipulates $header using CGI::Header

Since property names are case-insensitive,
application developers have to normalize them manually
when they specify header properties.
CGI::Header normalizes them automatically.

  use CGI::Header;

  my $h = CGI::Header->new( $header );
  $h->set( 'Content-Length' => 3002 ); # add Content-Length header

  $header;
  # => {
  #     -type => 'text/plain',
  #     -content_length => '3002',
  # }

=item 3. Passes $header to CGI::header() to stringify the variable

  use CGI;

  print CGI::header( $header );
  # Content-length: 3002
  # Content-Type: text/plain; charset=ISO-8859-1
  #

C<header()> function just stringifies given header properties.
This module can be used to generate L<PSGI>-compatible header
array references. See also C<flatten()>.

=back

=head2 CLASS METHOD

=over 4

=item $header = CGI::Header->new({ -type => 'text/plain', ... })

Given a header hash reference, returns a CGI::Header object
which holds a reference to the original given argument:

  my $header = { -type => 'text/plain' };
  my $h = CGI::Header->new( $header );
  $h->header; # same reference as $header

The object updates the reference when called write methods like C<set()>,
C<delete()> or C<clear()>:

  # updates $header
  $h->set( 'Content-Length' => 3002 );
  $h->delete( 'Content-Disposition' );
  $h->clear;

=item $header = CGI::Header->new( -type => 'text/plain', ... )

A shortcut for:

  my $header = CGI::Header->new({ -type => 'text/plain', ... });

=back

=head2 INSTANCE METHODS

=over 4

=item $header->header

Returns the header hash reference associated with this CGI::Header object.

=item $self = $header->rehash

Rebuilds the header hash to normalize parameter names
without changing the reference. Returns this object itself.
If parameter names aren't normalized, the methods listed below won't work
as you expect.

  my $h1 = $header->header;
  # => {
  #     '-content_type'   => 'text/plain',
  #     'Set-Cookie'      => 'ID=123456; path=/',
  #     'expires'         => '+3d',
  #     '-target'         => 'ResultsWindow',
  #     '-content-length' => '3002'
  # }

  $header->rehash;

  my $h2 = $header->header; # same reference as $h1
  # => {
  #     '-type'           => 'text/plain',
  #     '-cookie'         => 'ID=123456; path=/',
  #     '-expires'        => '+3d',
  #     '-target'         => 'ResultsWindow',
  #     '-content_length' => '3002'
  # }

Normalized parameter names are:

=over 4

=item 1. lowercased

  'Content-Length' -> 'content-length'

=item 2. start with a dash

  'content-length' -> '-content-length'

=item 3. use underscores instead of dashes except for the first character

  '-content-length' -> '-content_length'

=back

C<CGI::header()> also accepts aliases of parameter names.
This module converts them as follows:

 '-content_type'  -> '-type'
 '-set_cookie'    -> '-cookie'
 '-cookies'       -> '-cookie'
 '-window_target' -> '-target'

NOTE: C<new()> doesn't check whether parameter names are normalized
or not at all,
and so you have to C<rehash()> the header hash explicitly
when you aren't sure that they are normalized.

=item $value = $header->get( $field )

=item $value = $header->set( $field => $value )

Get or set the value of the header field.
The header field name (C<$field>) is not case sensitive.
You can use underscores as a replacement for dashes in header names.

  # field names are case-insensitive
  $header->get( 'Content-Length' );
  $header->get( 'content-length' );

The C<$value> argument may be a plain string or
a reference to an array of L<CGI::Cookie> objects for the Set-Cookie header.

  $header->set( 'Content-Length' => 3002 );
  my $length = $header->get( 'Content-Length' ); # => 3002

  # $cookie1 and $cookie2 are CGI::Cookie objects
  $header->set( 'Set-Cookie' => [$cookie1, $cookie2] );
  my $cookies = $header->get( 'Set-Cookie' ); # => [ $cookie1, $cookie2 ]

=item $bool = $header->exists( $field )

Returns a Boolean value telling whether the specified field exists.

  if ( $header->exists('ETag') ) {
      ...
  }

=item $value = $header->delete( $field )

Deletes the specified field form CGI response headers.
Returns the value of the deleted field.

  my $value = $header->delete( 'Content-Disposition' ); # => 'inline'

=item $self = $header->clear

This will remove all header fields.

=item $bool = $header->is_empty

Returns true if the header contains no key-value pairs.

  $header->clear;

  if ( $header->is_empty ) { # true
      ...
  }

=item $clone = $header->clone

Returns a copy of this CGI::Header object.
It's identical to:

  my %copy = %{ $header->header }; # shallow copy
  my $clone = CGI::Header->new( \%copy );

=item $filename = $header->attachment

=item $header->attachment( $filename )

Can be used to turn the page into an attachment.
Represents suggested name for the saved file.

  $header->attachment( 'genome.jpg' );
  my $filename = $header->attachment; # => "genome.jpg"

In this case, the outgoing header will be formatted as:

  Content-Disposition: attachment; filename="genome.jpg"

=item @tags = $header->p3p_tags

=item $header->p3p_tags( @tags )

Represents P3P tags. The parameter can be an array or a space-delimited
string. Returns a list of P3P tags. (In scalar context,
returns the number of P3P tags.)

  $header->p3p_tags(qw/CAO DSP LAW CURa/);
  # or
  $header->p3p_tags( 'CAO DSP LAW CURa' );

  my @tags = $header->p3p_tags; # => ("CAO", "DSP", "LAW", "CURa")
  my $size = $header->p3p_tags; # => 4

In this case, the outgoing header will be formatted as:

  P3P: policyref="/w3c/p3p.xml", CP="CAO DSP LAW CURa"

=item $format = $header->expires

=item $header->expires( $format )

The Expires header gives the date and time after which the entity
should be considered stale. You can specify an absolute or relative
expiration interval. The following forms are all valid for this field:

  $header->expires( '+30s' ); # 30 seconds from now
  $header->expires( '+10m' ); # ten minutes from now
  $header->expires( '+1h'  ); # one hour from now
  $header->expires( 'now'  ); # immediately
  $header->expires( '+3M'  ); # in three months
  $header->expires( '+10y' ); # in ten years time

  # at the indicated time & date
  $header->expires( 'Thu, 25 Apr 1999 00:40:33 GMT' );

=item $header->nph

If set to a true value, will issue the correct headers to work
with a NPH (no-parse-header) script.

  $header->nph( 1 );
  my $nph = $header->nph; # => 1

=item @fields = $header->field_names

Returns the list of distinct field names present in the header
in a random order.
The field names have case as returned by C<CGI::header()>.

  my @fields = $header->field_names;
  # => ( 'Set-Cookie', 'Content-length', 'Content-Type' )

=item $self = $header->each( \&callback )

Apply a subroutine to each header field in turn.
The callback routine is called with two parameters;
the name of the field and a value.
If the Set-Cookie header is multi-valued, then the routine is called
once for each value.
Any return values of the callback routine are ignored.

  my @lines;
  $header->each(sub {
      my ( $field, $value ) = @_;
      push @lines, "$field: $value";
  });

  print join @lines, "\n";
  # Content-length: 3002
  # Content-Type: text/plain

=item @headers = $header->flatten

=item @headers = $header->flatten( $is_recursive )

Returns pairs of fields and values. 
This method flattens the Set-Cookie headers recursively by default.
The optional C<$is_recursive> argument determines
whether to flatten them recursively.

  my $header = CGI::Header->new( -cookie => ['cookie1', 'cookie2'] );

  $header->flatten;
  # => (
  #     'Set-Cookie'   => 'cookie1',
  #     'Set-Cookie'   => 'cookie2',
  #     'Date'         => 'Thu, 25 Apr 1999 00:40:33 GMT',
  #     'Content-Type' => 'text/html'
  # )

  $header->flatten(0);
  # => (
  #     'Set-Cookie'   => ['cookie1', 'cookie2'],
  #     'Date'         => 'Thu, 25 Apr 1999 00:40:33 GMT',
  #     'Content-Type' => 'text/html'
  # )

This method can be used to generate L<PSGI>-compatible header array
references. For example,

  use parent 'CGI';
  use CGI::Header;

  sub psgi_header {
      my $self   = shift;
      my $header = CGI::Header->new(@_)->rehash;

      my $status = $header->delete('Status') || '200 OK';
      $status =~ s/\D*$//;

      $status, [ $header->flatten ];
  }

Strictly speaking, you have to check C<charset()> attribute of CGI.pm.
In addition, if C<< $header->nph >> is true,
C<< $header->flatten >> will return the Server header
which C<psgi_header()> shouldn't return.
Moreover, this method depends on a global variable C<%ENV>.

See also L<CGI::Emulate::PSGI>, L<CGI::PSGI>.

=item $header->as_string

=item $header->as_string( $eol )

Returns the header fields as a formatted MIME header.
The optional C<$eol> parameter specifies the line ending sequence to use.
The default is C<\015\012>.

When valid multi-line headers are included, this method will always output
them back as a single line, according to the folding rules of RFC 2616:
the newlines will be removed, while the white space remains.

Unlike CGI.pm, when invalid newlines are included,
this module removes them instead of throwing exceptions.

If C<< $header->nph >> is true, the Status-Line will be added to
the beginning of response headers automatically.

  $header->nph(1);

  $header->as_string;
  # HTTP/1.1 200 OK
  # Server: Apache/1.3.27 (Unix)
  # ...

=back

=head2 CREATING A CASE-INSENSITIVE HASH

  use CGI::Header;

  my $header = { -type => 'text/plain' };
  tie my %header => 'CGI::Header' => $header;

  # update $header
  $header{'Content-Length'} = 3002;
  delete $header{'Content-Disposition'};
  %header = ();

  tied( %header )->header; # same reference as $header

Above methods are aliased as follows:

  TIEHASH -> new
  FETCH   -> get
  STORE   -> set
  DELETE  -> delete
  CLEAR   -> clear
  EXISTS  -> exists
  SCALAR  -> !is_empty

You can also iterate through the tied hash:

  my @fields = keys %header;
  my @values = values %header;
  my ( $field, $value ) = each %header;

See also L<perltie>.

=head1 LIMITATIONS

=over 4

=item Content-Type

You can set the Content-Type header to neither undef nor an empty:

  # wrong
  $header->set( 'Content-Type' => undef );
  $header->set( 'Content-Type' => q{} );

Use delete() instead:

  $header->delete( 'Content-Type' );

=item Date

If one of the following conditions is met, the Date header will be set
automatically:

  if ( $header->nph or $header->get('Set-Cookie') or $header->expires ) {
      my $date = $header->get( 'Date' ); # => HTTP-Date (current time)
  }

and also the header field will become read-only: 

  # wrong
  $header->set( 'Date' => 'Thu, 25 Apr 1999 00:40:33 GMT' );
  $header->delete( 'Date' );

=item Expires

You can't assign to the Expires header directly:

  # wrong
  $header->set( 'Expires' => '+3d' );

Use expires() instead:

  $header->expires( '+3d' );

because the following behavior will surprise us:

  my $value = $header->get( 'Expires' );
  # => "Thu, 25 Apr 1999 00:40:33 GMT" (not "+3d")

=item P3P

You can't assign to the P3P header directly:

  # wrong
  $header->set( 'P3P' => '/path/to/p3p.xml' );

C<CGI::header()> restricts where the policy-reference file is located,
and so you can't modify the location (C</w3c/p3p.xml>).
You're allowed to set P3P tags using C<p3p_tags()>.

=item Server

If the following condition is met, the Server header will be set
automatically:

  if ( $header->nph ) {
      my $server = $header->get( 'Server' ); # => $ENV{SERVER_SOFTWARE}
  }

and also the header field will become read-only: 

  # wrong
  $header->set( 'Server' => 'Apache/1.3.27 (Unix)' );
  $header->delete( 'Server' );

=back

=head1 SEE ALSO

L<CGI>, L<Plack::Util>, L<HTTP::Headers>

=head1 BUGS

There are no known bugs in this module.
Please report problems to ANAZAWA (anazawa@cpan.org).
Patches are welcome.

=head1 AUTHOR

Ryo Anazawa (anazawa@cpan.org)

=head1 LICENSE

This module is free software; you can redistibute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut
