package CGI::Header;
use 5.008_009;
use strict;
use warnings;
use overload q{""} => 'as_string', bool => 'SCALAR', fallback => 1;
use Carp qw/carp croak/;
use List::Util qw/first/;
use Scalar::Util qw/blessed/;

our $VERSION = '0.30';

my $MODIFY = 'Modification of a read-only value attempted';

sub new {
    my $self = bless {}, shift;
    my @args = @_;

    if ( ref $args[0] eq 'HASH' ) {
        @{ $self }{qw/header query/} = splice @args, 0, 2;
    }
    elsif ( @args % 2 == 0 ) {
        my $header = $self->{header} = {};
        while ( my ($key, $value) = splice @args, 0, 2 ) {
            $header->{ _lc($key) } = $value; # force overwrite
        }
        if ( blessed $header->{-query} ) {
            $self->{query} = delete $header->{-query};
        }
    }
    elsif ( @args == 1 ) {
        $self->{header}->{-type} = shift @args;
    }
    else {
        croak 'Odd number of elements in hash assignment';
    }

    $self;
}

sub header { $_[0]->{header} }

sub query { $_[0]->{query} ||= do { require CGI; CGI::self_or_default() } }

# This method is obsolete and will be removed in 0.31
sub env {
    my $self = shift;
    $self->{env} ||= $self->query->can('env') ? $self->{query}->env : \%ENV;
}

sub rehash {
    my $self   = shift;
    my $header = $self->{header};

    for my $key ( keys %{$header} ) {
        my $prop = _lc( $key );
        next if $key eq $prop; # $key is normalized
        croak "Property '$prop' already exists" if exists $header->{ $prop };
        $header->{ $prop } = delete $header->{ $key }; # rename $key to $prop
    }

    $self;
}

my $GET = sub { $_[1]->{$_[2]} };

my %GET = (
    -content_disposition => sub {
        my $filename = $_[1]->{-attachment};
        $filename ? qq{attachment; filename="$filename"} : $GET->( @_ );
    },
    -date => sub { _date_is_fixed( $_[1] ) ? _expires() : $GET->( @_ ) },
    -expires => sub { my $v = $GET->( @_ ); $v ? _expires( $v ) : undef },
    -p3p => sub {
        my $tags = $GET->( @_ );
        $tags = join ' ', @{ $tags } if ref $tags eq 'ARRAY';
        $tags ? qq{policyref="/w3c/p3p.xml", CP="$tags"} : undef;
    },
    -pragma => sub { $_[0]->query->cache ? 'no-cache' : $GET->( @_ ) },
    -server => sub {
        $_[1]->{-nph} ? $_[0]->query->server_software : $GET->( @_ );
    },
    -type => sub {
        my ( $type, $charset ) = @{ $_[1] }{qw/-type -charset/};
        return if defined $type and $type eq q{};
        $charset = $_[0]->query->charset unless defined $charset;
        $type ||= 'text/html';
        $type .= "; charset=$charset" if $charset && $type !~ /\bcharset\b/;
        $type;
    },
);

sub get {
    my $self = shift;
    my $key = _lc( shift );
    my $get = $GET{$key} || $GET;
    $self->$get( $self->{header}, $key );
}

my $set = sub { $_[1]->{$_[2]} = $_[3] };

my %set = (
    -content_disposition => sub { delete $_[1]->{-attachment}; $set->( @_ ) },
    -cookie => sub { $_[3] and delete $_[1]->{-date}; $set->( @_ ) },
    -date => sub { _date_is_fixed( $_[1] ) and croak $MODIFY; $set->( @_ ) },
    -expires => sub {
        carp "Can't assign to '-expires' directly, use expires() instead";
    },
    -p3p => sub {
        carp "Can't assign to '-p3p' directly, use p3p_tags() instead";
    },
    -pragma => sub { $_[0]->query->cache and croak $MODIFY; $set->( @_ ) },
    -server => sub { $_[1]->{-nph} and croak $MODIFY; $set->( @_ ) },
    -type => sub {
        my ( $self, $header, $norm, $value ) = @_;
        if ( defined $value and $value ne q{} ) {
            @{ $header }{qw/-charset -type/} = ( q{}, $value );
            return $value;
        }
        else {
            carp "Can set '-content_type' to neither undef nor an empty string";
        }
    },
);

sub set { # unstable
    my $self = shift;
    my $key = _lc( shift );
    my $header = $self->{header};
    $key && ( $set{$key} || $set )->( $self, $header, $key, @_ );
}

my $EXISTS = sub { exists $_[1]->{$_[2]} };

my %EXISTS = (
    -content_disposition => sub { $EXISTS->( @_ ) || $_[1]->{-attachment} },
    -date => sub { _date_is_fixed( $_[1] ) || $EXISTS->( @_ ) },
    -pragma => sub { $_[0]->query->cache || $EXISTS->( @_ ) },
    -server => sub { $_[1]->{-nph} || $EXISTS->( @_ ) },
    -type => sub { my $v = $_[1]->{-type}; !defined $v || $v ne q{} },
);

sub exists {
    my $self = shift;
    my $key = _lc( shift );
    my $exists = $EXISTS{$key} || $EXISTS;
    $self->$exists( $self->{header}, $key );
}

my $DELETE = sub { delete $_[1]->{$_[2]} };

my %DELETE = (
    -content_disposition => sub { delete @{$_[1]}{$_[2], '-attachment'} },
    -date => sub { _date_is_fixed($_[1]) and croak $MODIFY; $DELETE->( @_ ) },
    -expires => $DELETE,
    -p3p => $DELETE,
    -pragma => sub { $_[0]->query->cache and croak $MODIFY; $DELETE->( @_ ) },
    -server => sub { $_[1]->{-nph} and croak $MODIFY; $DELETE->( @_ ) },
    -type => sub { my $h = $_[1]; delete $h->{-charset}; $h->{-type} = q{} },
);

sub delete {
    my $self   = shift;
    my $key    = _lc( shift );
    my $header = $self->{header};

    if ( my $delete = $DELETE{$key} ) {
        my $value = defined wantarray && $self->get( $key );
        $self->$delete( $header, $key );
        return $value;
    }

    delete $header->{ $key };
}

sub is_empty { !$_[0]->SCALAR }

sub clear {
    my $self = shift;
    %{ $self->{header} } = ( -type => q{} );
    $self->query->cache( 0 );
    $self;
}

sub clone {
    my $self = shift;
    my %copy = %{ $self->{header} };
    ref( $self )->new( \%copy, $self->{query} );
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
            my $header = $self->{header};
    
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
    my $header = $self->{header};

    if ( @_ ) {
        $header->{-p3p} = @_ > 1 ? [ @_ ] : shift;
    }
    elsif ( my $tags = $header->{-p3p} ) {
        return ref $tags eq 'ARRAY' ? @{$tags} : split ' ', $tags;
    }

    return;
}

sub cache {
    my $self = shift;
    $self->query->cache(@_);
}

sub flatten {
    my $self  = shift;
    my $level = defined $_[0] ? int shift : 2;
    my $query = $self->query;
    my %copy  = %{ $self->{header} };

    my @headers;

    my ( $cookie, $expires, $nph, $status, $target )
        = delete @copy{qw/-cookie -expires -nph -status -target/};

    push @headers, 'Server', $query->server_software if $nph;
    push @headers, 'Status', $status        if $status;
    push @headers, 'Window-Target', $target if $target;

    if ( my $tags = delete $copy{-p3p} ) {
        $tags = join ' ', @{ $tags } if ref $tags eq 'ARRAY';
        push @headers, 'P3P', qq{policyref="/w3c/p3p.xml", CP="$tags"};
    }

    if ( $cookie ) {
        my @cookies = $level && ref $cookie eq 'ARRAY' ? @{$cookie} : $cookie;
           @cookies = map { "$_" } @cookies if $level > 1;
        push @headers, map { ('Set-Cookie', $_) } @cookies;
    }

    push @headers, 'Expires', _expires($expires) if $expires;
    push @headers, 'Date', _expires() if $expires or $cookie or $nph;
    push @headers, 'Pragma', 'no-cache' if $query->cache;

    if ( my $fn = delete $copy{-attachment} ) {
        push @headers, 'Content-Disposition', qq{attachment; filename="$fn"};
    }

    my ( $type, $charset ) = delete @copy{qw/-type -charset/};

    # not ordered
    while ( my ($field, $value) = CORE::each %copy ) {
        push @headers, _ucfirst($field), $value;
    }

    if ( !defined $type or $type ne q{} ) {
        $charset = $query->charset unless defined $charset;
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
    $self->query->header( $self->{header} );
}

BEGIN {
    *TIEHASH = \&new;    *FETCH  = \&get;    *STORE = \&set;
    *EXISTS  = \&exists; *DELETE = \&delete; *CLEAR = \&clear;    
}

sub SCALAR {
    my $self = shift;
    my $header = $self->{header};
    !defined $header->{-type}
        or first { $_ } values %{ $header }
        or $self->query->cache;
}

sub FIRSTKEY {
    my $self = shift;
    my @fields = $self->field_names;
    ( $self->{iterator} = sub { shift @fields } )->();
}

sub NEXTKEY { $_[0]->{iterator}->() }

BEGIN {
    require CGI::Util;
    *_expires = \&CGI::Util::expires;
}

sub _date_is_fixed {
    my $header = shift;
    $header->{-nph} || $header->{-cookie} || $header->{-expires};
}

sub _ucfirst {
    my $str = shift;
    $str =~ s/^-(\w)/\u$1/;
    $str =~ tr/_/-/;
    $str;
}

my %alias_of = (
    -content_type => '-type',   -window_target => '-target',
    -cookies      => '-cookie', -set_cookie    => '-cookie',
    -uri => '-location', -url => '-location', # for CGI::redirect()
);

sub _lc {
    my $str = lc shift;
    $str = "-$str" if $str !~ /^-/;
    substr( $str, 1 ) =~ tr/-/_/;
    $alias_of{ $str } || $str;
}

1;

__END__

=head1 NAME

CGI::Header - Adapter for CGI::header() function

=head1 SYNOPSIS

  use CGI;
  use CGI::Header;

  my $query = CGI->new;

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
  my $h = CGI::Header->new( $header, $query );

  # update $header
  $h->set( 'Content-Length' => 3002 );
  $h->delete( 'Content-Disposition' );
  $h->clear;

  $h->header; # same reference as $header

=head1 VERSION

This document refers to CGI::Header version 0.30.

=head1 DEPENDENCIES

This module is compatible with CGI.pm 3.51 or higher.

=head1 DESCRIPTION

This module is a utility class to manipulate a hash reference
received by the C<header()> function provided by CGI.pm.
This class is, so to speak, a subclass of Hash,
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
array references. See L<CGI::Header::PSGI>.

=back

=head2 CLASS METHOD

=over 4

=item $header = CGI::Header->new( { -type => 'text/plain', ... }[, $query] )

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

You can also pass your query object, preceded by the header hash ref.:

  my $query = CGI->new;
  my $h = CGI::Header->new( $header, $query );
  $h->query; # => $query

NOTE: In this case, C<new()> doesn't check whether property names of C<$header>
are normalized or not at all, and so you have to C<rehash()> the header hash
reference explicitly when you aren't sure that they are normalized.

=item $header = CGI::Header->new( -type => 'text/plain', ... )

It's roughly equivalent to:

  my $h = CGI::Header->new({ -type => 'text/plain', ... })->rehash;

Unlike C<rehash()>, if a property name is duplicated,
that property will be overwritten silently:

  my $h = CGI::Header->new(
      -Type        => 'text/plain',
      Content_Type => 'text/html'
  );

  $h->header->{-type}; # => "text/html"

In addition to CGI.pm-compatible HTTP header properties,
you can specify '-query' property which represents your query object:

  my $query = CGI->new;

  my $h = CGI::Header->new(
      -type  => 'text/plain',
      -query => $query,
  );

  $h->header; # => { -type => 'text/plain' }
  $h->query;  # => $query

=item $header = CGI::Header->new( $media_type )

A shortcut for:

  my $header = CGI::Header->new({ -type => $media_type });

=back

=head2 INSTANCE METHODS

=over 4

=item $query = $header->query

Returns your current query object. C<query()> defaults to the Singleton
instance of CGI.pm (C<$CGI::Q>).

=item $hashref = $header->env

This method is obsolete and will be removed in 0.31.

Returns the reference to the hash which contains your current environment.
C<env()> defaults to C<\%ENV>. This module depends on the following
elements of C<env()>:

  SERVER_PROTOCOL
  SERVER_SOFTWARE

=item $hashref = $header->header

Returns the header hash reference associated with this CGI::Header object.
You can always pass the header hash to C<CGI::header()> function
to generate CGI response headers:

  print CGI::header( $header->header );

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
 '-uri'           -> '-location'
 '-url'           -> '-location'

If a property name is duplicated, throws an exception:

  $header->header;
  # => {
  #     -Type        => 'text/plain',
  #     Content_Type => 'text/html',
  # }

  $header->rehash; # die "Property '-type' already exists"

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
  my $clone = CGI::Header->new( \%copy, $header->env );

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

Returns pairs of fields and values. 

  # $cookie1 and $cookie2 are CGI::Cookie objects
  my $header = CGI::Header->new( -cookie => [$cookie1, $cookie2] );

  $header->flatten;
  # => (
  #     "Set-Cookie" => "$cookie1",
  #     "Set-Cookie" => "$cookie2",
  #     ...
  # )

  $header->flatten(1);
  # => (
  #     "Set-Cookie" => $cookie1,
  #     "Set-Cookie" => $cookie2,
  #     ...
  # )

  $header->flatten(0);
  # => (
  #     "Set-Cookie" => [$cookie1, $cookie2],
  #     ...
  # )

=item $header->as_string

A shortcut for:

  $header->query->header( $header->header );

=back

=head2 TYING A HASH

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

=head2 OVERLOADED OPERATORS

The following operators are L<overload>ed:

 ""   -> as_string
 bool -> SCALAR

=head1 EXAMPLES

=head2 WRITING Blosxom PLUGINS

The following plugin just adds the Content-Length header
to CGI response headers sent by blosxom.cgi:

  package content_length;
  use CGI::Header;

  sub start {
      !$blosxom::static_entries;
  }

  sub last {
      my $h = CGI::Header->new( $blosxom::header );
      $h->set( 'Content-Length' => length $blosxom::output );
  }

  1;

L<Blosxom|http://blosxom.sourceforge.net/> depends on the procedural
interface of CGI.pm, and so you don't have to pass
C<$query> to C<new()> in this case.

=head2 CONVERTING TO HTTP::Headers OBJECTS

  use CGI::Header;
  use HTTP::Headers;

  my @header_props = ( -type => 'text/plain', ... );
  my $h = HTTP::Headers->new( CGI::Header->new(@header_props)->flatten );
  $h->header( 'Content-Type' ); # => "text/plain"

=head1 LIMITATIONS

Since the following strings conflict with property names,
you can't use them as field names (C<$field>):

  "Attachment"
  "Charset"
  "Cookie"
  "Cookies"
  "NPH"
  "Target"
  "Type"

=over 4

=item Content-Type

You can set the Content-Type header to neither undef nor an empty:

  # wrong
  $header->set( 'Content-Type' => undef );
  $header->set( 'Content-Type' => q{} );

Use delete() instead:

  $header->delete('Content-Type');

=item Date

If one of the following conditions is met, the Date header will be set
automatically, and also the header field will become read-only:

  if ( $header->nph or $header->get('Set-Cookie') or $header->expires ) {
      my $date = $header->get('Date'); # => HTTP-Date (current time)
      $header->set( 'Date' => 'Thu, 25 Apr 1999 00:40:33 GMT' ); # wrong
      $header->delete('Date'); # wrong
  }

=item Expires

You can't assign to the Expires header directly
because the following behavior will surprise us:

  # wrong
  $header->set( 'Expires' => '+3d' );

  my $value = $header->get('Expires');
  # => "Thu, 25 Apr 1999 00:40:33 GMT" (not "+3d")

Use expires() instead:

  $header->expires('+3d');

=item P3P

You can't assign to the P3P header directly:

  # wrong
  $header->set( 'P3P' => '/path/to/p3p.xml' );

C<CGI::header()> restricts where the policy-reference file is located,
and so you can't modify the location (C</w3c/p3p.xml>).
You're allowed to set P3P tags using C<p3p_tags()>.

=item Pragma

If the following condition is met, the Pragma header will be set
automatically, and also the header field will become read-only:

  if ( $header->query->cache ) {
      my $pragma = $header->get('Pragma'); # => 'no-cache'
      $header->set( 'Pragma' => 'no-cache' ); # wrong
      $header->delete('Pragma'); # wrong
  }

=item Server

If the following condition is met, the Server header will be set
automatically, and also the header field will become read-only: 

  if ( $header->nph ) {
      my $server = $header->get('Server');
      # => $header->env->{SERVER_SOFTWARE}

      $header->set( 'Server' => 'Apache/1.3.27 (Unix)' ); # wrong
      $header->delete( 'Server' ); # wrong
  }


=back

=head1 SEE ALSO

L<CGI>, L<Plack::Util>::headers(), L<HTTP::Headers>

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
