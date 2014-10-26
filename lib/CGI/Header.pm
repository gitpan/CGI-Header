package CGI::Header;
use 5.008_009;
use strict;
use warnings;
use Carp qw/carp croak/;
use List::Util qw/first/;
use Scalar::Util qw/blessed/;

our $VERSION = '0.42';

our $MODIFY = 'Modification of a read-only value attempted';

my %Property_Alias = (
    'cookies'       => 'cookie',
    'content-type'  => 'type',
    'set-cookie'    => 'cookie',
    'uri'           => 'location',
    'url'           => 'location',
    'window-target' => 'target',
);

sub normalize_property_name {
    my $class = shift;
    my $prop = lc shift;
    $prop =~ s/^-//;
    $prop =~ tr/_/-/;
    $Property_Alias{$prop} || $prop;
}

sub normalize_field_name {
    my $class = shift;
    my $field = lc shift;
    $field =~ s/^-//;
    $field =~ tr/_/-/;
    $field;
}

sub time2str {
    require CGI::Util;
    CGI::Util::expires( $_[1], 'http' );
}

sub new {
    my $self = bless { handler => 'header' }, shift;
    my @args = @_;

    if ( ref $args[0] eq 'HASH' ) {
        @{ $self }{qw/header query/} = splice @args, 0, 2;
    }
    elsif ( @args % 2 == 0 ) {
        my $header = $self->{header} = {};
        while ( my ($key, $value) = splice @args, 0, 2 ) {
            my $prop = $self->normalize_property_name( $key );
            $header->{ $prop } = $value; # force overwrite
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

sub header {
    $_[0]->{header};
}

sub handler {
    my $self = shift;
    return $self->{handler} unless @_;
    $self->{handler} = shift;
    $self;
}

sub query {
    my $self = shift;
    $self->{query} ||= $self->_build_query;
}

sub _build_query {
    require CGI;
    CGI::self_or_default();
}

sub rehash {
    my $self   = shift;
    my $header = $self->{header};

    for my $key ( keys %{$header} ) {
        my $prop = lc $key;
           $prop =~ s/^-//;
           $prop =~ tr/_/-/;
           $prop = $Property_Alias{$prop} || $prop;

        next if $key eq $prop; # $key is normalized

        croak "Property '$prop' already exists" if exists $header->{$prop};

        $header->{$prop} = delete $header->{$key}; # rename $key to $prop
    }

    $self;
}

sub get {
    my $self = shift;
    my $field = lc shift;
    $self->{header}->{$field};
}

my %SET = (
    DEFAULT => sub {
        my ( $self, $prop, $value ) = @_;
        $self->{header}->{$prop} = $value;
    },
    'content-disposition' => sub {
        my ( $self, $prop, $value ) = @_;
        delete $self->{header}->{attachment};
        $self->{header}->{$prop} = $value;
    },
    'content-type' => sub {
        my ( $self, $prop, $value ) = @_;
        if ( defined $value and $value ne q{} ) {
            @{ $self->{header} }{qw/charset type/} = ( q{}, $value );
            return $value;
        }
        else {
            carp "Can set '-content_type' to neither undef nor an empty string";
        }
    },
    date => sub {
        my ( $self, $prop, $value ) = @_;
        croak $MODIFY if $self->_has_date;
        $self->{header}->{$prop} = $value;
    },
    expires => sub {
        carp "Can't assign to '-expires' directly, use expires() instead";
    },
    p3p => sub {
        carp "Can't assign to '-p3p' directly, use p3p() instead";
    },
    pragma => sub {
        my ( $self, $prop, $value ) = @_;
        croak $MODIFY if $self->query->cache;
        $self->{header}->{$prop} = $value;
    },
    server => sub {
        my ( $self, $prop, $value ) = @_;
        croak $MODIFY if $self->nph;
        $self->{header}->{$prop} = $value;
    },
    'set-cookie' => sub {
        my ( $self, $prop, $value ) = @_;
        delete $self->{header}->{date} if $value;
        $self->{header}->{cookie} = $value;
    },
    'window-target' => sub {
        my ( $self, $prop, $value ) = @_;
        $self->{header}->{target} = $value;
    },
);

sub set { # unstable
    my $self = shift;
    my $field = $self->normalize_field_name( shift );
    my $set = $SET{$field} || $SET{DEFAULT};
    $self->$set( $field, @_ );
}

sub exists {
    my $self = shift;
    my $field = lc shift;
    exists $self->{header}->{$field};
}

my %DELETE = (
    'content-disposition' => sub {
        my ( $self, $prop ) = @_;
        delete @{ $self->{header} }{ $prop, 'attachment' };
    },
    'content-type' => sub {
        my ( $self, $prop ) = @_;
        delete $self->{header}->{charset};
        $self->{header}->{type} = q{};
    },
    date => sub {
        my ( $self, $prop ) = @_;
        croak $MODIFY if $self->_has_date;
        delete $self->{header}->{$prop};
    },
    expires => '_delete',
    p3p => '_delete',
    pragma => sub {
        my ( $self, $prop ) = @_;
        croak $MODIFY if $self->query->cache;
        delete $self->{header}->{$prop};
    },
    server => sub {
        my ( $self, $prop ) = @_;
        croak $MODIFY if $self->nph;
        delete $self->{header}->{$prop};
    },
    'set-cookie' => sub {
        my ( $self, $prop ) = @_;
        delete $self->{header}->{cookie};
    },
    status => '_delete',
    'window-target' => sub {
        my ( $self, $prop ) = @_;
        delete $self->{header}->{target};
    },
);

sub delete {
    my $self  = shift;
    my $field = $self->normalize_field_name( shift );

    if ( my $delete = $DELETE{$field} ) {
        my $value = defined wantarray && $self->get( $field );
        $self->$delete( $field );
        return $value;
    }

    delete $self->{header}->{$field};
}

sub _delete {
    my ( $self, $prop ) = @_;
    delete $self->{header}->{$prop};
}

sub clear {
    my $self = shift;
    %{ $self->{header} } = ( type => q{} );
    $self->query->cache( 0 );
    $self;
}

sub clone {
    my $self = shift;
    my %copy = %{ $self->{header} };
    ref( $self )->new( \%copy, $self->{query} );
}

BEGIN {
    my @props = qw(
        attachment
        charset
        expires
        location
        nph
        status
        target
        type
    );

    for my $prop ( @props ) {
        my $code = sub {
            my $self = shift;
            return $self->{header}->{$prop} unless @_;
            $self->{header}->{$prop} = shift;
            $self;
        };

        no strict 'refs';
        *{$prop} = $code;
    }
}

sub cookie {
    my $self = shift;

    if ( @_ ) {
        $self->{header}->{cookie} = @_ > 1 ? [ @_ ] : shift;
    }
    elsif ( my $cookie = $self->{header}->{cookie} ) {
        my @cookies = ref $cookie eq 'ARRAY' ? @{$cookie} : $cookie;
        return @cookies;
    }
    else {
        return;
    }

    $self;
}

sub push_cookie {
    my $self = shift;
    push @{ $self->{header}->{cookie} }, @_;
}

sub p3p {
    my $self   = shift;
    my $header = $self->{header};

    if ( @_ ) {
        $header->{p3p} = @_ > 1 ? [ @_ ] : shift;
    }
    elsif ( my $p3p = $header->{p3p} ) {
        my @tags = ref $p3p eq 'ARRAY' ? @{$p3p} : $p3p;
        return map { split ' ', $_ } @tags;
    }
    else {
        return;
    }

    $self;
}

sub as_hashref {
    +{ $_[0]->flatten(0) };
}

sub flatten {
    my $self  = shift;
    my $level = defined $_[0] ? int shift : 1;
    my $query = $self->query;
    my %copy  = %{ $self->{header} };

    if ( $self->{handler} eq 'redirect' ) {
        $copy{location} = $query->self_url if !$copy{location};
        $copy{status} = '302 Found' if !defined $copy{status};
        $copy{type} = q{} if !exists $copy{type};
    }

    my @headers;

    my ( $charset, $cookie, $expires, $nph, $status, $target, $type )
        = delete @copy{qw/charset cookie expires nph status target type/};

    push @headers, 'Server', $query->server_software if $nph or $query->nph;
    push @headers, 'Status', $status        if $status;
    push @headers, 'Window-Target', $target if $target;

    if ( my $p3p = delete $copy{p3p} ) {
        my $tags = ref $p3p eq 'ARRAY' ? join ' ', @{$p3p} : $p3p;
        push @headers, 'P3P', qq{policyref="/w3c/p3p.xml", CP="$tags"};
    }

    my @cookies = ref $cookie eq 'ARRAY' ? @{$cookie} : $cookie;
       @cookies = map { $self->_bake_cookie($_) || () } @cookies;

    if ( @cookies ) {
        if ( $level == 0 ) {
            push @headers, 'Set-Cookie', \@cookies;
        }
        else {
            push @headers, map { ('Set-Cookie', $_) } @cookies;
        }
    }

    push @headers, 'Expires', $self->time2str($expires) if $expires;
    push @headers, 'Date', $self->time2str if $expires or $cookie or $nph;
    push @headers, 'Pragma', 'no-cache' if $query->cache;

    if ( my $attachment = delete $copy{attachment} ) {
        my $value = qq{attachment; filename="$attachment"};
        push @headers, 'Content-Disposition', $value;
    }

    push @headers, map { ucfirst $_, $copy{$_} } keys %copy;

    if ( !defined $type or $type ne q{} ) {
        $charset = $query->charset unless defined $charset;
        my $ct = $type || 'text/html';
        $ct .= "; charset=$charset" if $charset && $ct !~ /\bcharset\b/;
        push @headers, 'Content-Type', $ct;
    }

    @headers;
}

sub _bake_cookie {
    my ( $self, $cookie ) = @_;
    ref $cookie eq 'CGI::Cookie' ? $cookie->as_string : $cookie;
}

sub as_string {
    my $self    = shift;
    my $handler = $self->{handler};
    my $query   = $self->query;

    if ( $handler eq 'header' or $handler eq 'redirect' ) {
        if ( my $method = $query->can($handler) ) {
            return $query->$method( $self->{header} );
        }
        else {
            croak ref($query) . " is missing '$handler' method";
        }
    }
    elsif ( $handler eq 'none' ) {
        return q{};
    }
    else {
        croak "Invalid handler '$handler'";
    }

    return;
}

BEGIN { # TODO: These methods can't be overridden
    *TIEHASH = \&new;    *FETCH  = \&get;    *STORE = \&set;
    *EXISTS  = \&exists; *DELETE = \&delete; *CLEAR = \&clear;    
}

sub FIRSTKEY {
    my $self = shift;
    my @fields = keys %{ $self->as_hashref };
    ( $self->{iterator} = sub { shift @fields } )->();
}

sub NEXTKEY { $_[0]->{iterator}->() }

sub _has_date {
    my $self = shift;
    $self->{header}->{cookie} or $self->expires or $self->nph;
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
      attachment => 'foo.gif',
      charset    => 'utf-7',
      cookie     => [ $cookie1, $cookie2 ], # CGI::Cookie objects
      expires    => '+3d',
      nph        => 1,
      p3p        => [qw/CAO DSP LAW CURa/],
      target     => 'ResultsWindow',
      type       => 'image/gif'
  };

  # create a CGI::Header object
  my $h = CGI::Header->new( $header, $query );

  # update $header
  $h->set( 'Content-Length' => 3002 );
  $h->delete( 'Content-Disposition' );
  $h->clear;

  $h->header; # same reference as $header

=head1 VERSION

This document refers to CGI::Header version 0.40.

=head1 DEPENDENCIES

This module is compatible with CGI.pm 3.51 or higher.

=head1 DESCRIPTION

This module is a utility class to manipulate a hash reference
received by the C<header()> function of CGI.pm.
This class is, so to speak, a subclass of Hash,
while Perl5 doesn't provide a built-in class called Hash.

This module isn't the replacement of the C<CGI::header()> function.
If you're allowed to replace the function with other modules
like L<HTTP::Headers>, you should do so.

This module can be used in the following situation:

=over 4

=item 1. $header is a hash reference which represents CGI response headers

For example, L<CGI::Application> implements C<header_add()> method
which can be used to add CGI.pm-compatible HTTP header properties.
Instances of CGI applications often hold those properties.

  my $header = { type => 'text/plain' };

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
  #     'type' => 'text/plain',
  #     'content-length' => '3002',
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

=head2 CLASS METHODS

=over 4

=item $header = CGI::Header->new( { type => 'text/plain', ... }[, $query] )

Given a header hash reference, returns a CGI::Header object
which holds a reference to the original given argument:

  my $header = { type => 'text/plain' };
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

=item $header = CGI::Header->new( type => 'text/plain', ... )

It's roughly equivalent to:

  my $h = CGI::Header->new({ type => 'text/plain', ... })->rehash;

Unlike C<rehash()>, if a property name is duplicated,
that property will be overwritten silently:

  my $h = CGI::Header->new(
      -Type        => 'text/plain',
      Content_Type => 'text/html'
  );

  $h->header->{type}; # => "text/html"

In addition to CGI.pm-compatible HTTP header properties,
you can specify '-query' property which represents your query object:

  my $query = CGI->new;

  my $h = CGI::Header->new(
      type  => 'text/plain',
      query => $query,
  );

  $h->header; # => { type => 'text/plain' }
  $h->query;  # => $query

=item $header = CGI::Header->new( $media_type )

A shortcut for:

  my $header = CGI::Header->new({ type => $media_type });

=back

=head2 INSTANCE METHODS

=over 4

=item $query = $header->query

Returns your current query object. C<query()> defaults to the Singleton
instance of CGI.pm (C<$CGI::Q>).

=item $self = $header->handler('redirect')

Works like C<CGI::Application>'s C<header_type> method.
This method can be used to declare that you are setting a redirection
header. This attribute defaults to C<header>.

  $header->handler('redirect')->as_string; # invokes $header->query->redirect

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
  #     'type'           => 'text/plain',
  #     'cookie'         => 'ID=123456; path=/',
  #     'expires'        => '+3d',
  #     'target'         => 'ResultsWindow',
  #     'content-length' => '3002'
  # }

Normalized property names are:

=over 4

=item 1. lowercased

  'Content-Length' -> 'content-length'

=item 2. use dashes instead of underscores in property name

  'content_length' -> 'content-length'

=back

C<CGI::header()> also accepts aliases of parameter names.
This module converts them as follows:

 'content-type'  -> 'type'
 'cookies'       -> 'cookie'
 'set-cookie'    -> 'cookie'
 'uri'           -> 'location'
 'url'           -> 'location'
 'window-target' -> 'target'

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

=item $clone = $header->clone

Returns a copy of this CGI::Header object.
It's identical to:

  my %copy = %{ $header->header }; # shallow copy
  my $clone = CGI::Header->new( \%copy, $header->query );

=item @headers = $header->flatten

Returns pairs of fields and values. 

  # $cookie1 and $cookie2 are CGI::Cookie objects
  my $header = CGI::Header->new( cookie => [$cookie1, $cookie2] );

  $header->flatten;
  # => (
  #     "Set-Cookie" => "$cookie1",
  #     "Set-Cookie" => "$cookie2",
  #     ...
  # )

=item $header->as_hashref

=item $header->as_string

If C<< $header->handler >> is set to C<header>, it's identical to:

  $header->query->header( $header->header );

If C<< $header->handler >> is set to C<redirect>, it's identical to:

  $header->query->redirect( $header->header );

If C<< $header->handler >> is set to C<none>, returns an empty string.

=back

=head2 PROPERTIES

The following methods were named after propertyn ames recognized by
CGI.pm's C<header> method. Most of these methods can both be used to
read and to set the value of a property.

If you pass an argument to the method, the property value will be set,
and also the current object itself will be returned; therefore you can
chain methods as follows:

  $header->type('text/html')->charset('utf-8');

If no argument is supplied, the property value will returned.
If the given property doesn't exist, C<undef> will be returned.

=over 4

=item $self = $header->attachment( $filename )

=item $filename = $header->attachment

Get or set the C<attachment> property.
Can be used to turn the page into an attachment.
Represents suggested name for the saved file.

  $header->attachment( 'genome.jpg' );
  my $filename = $header->attachment; # => "genome.jpg"

In this case, the outgoing header will be formatted as:

  Content-Disposition: attachment; filename="genome.jpg"

=item $self = $header->charset( $character_set )

=item $character_set = $header->charset

Get or set the C<charset> property. Represents the character set sent to
the browser.

=item $self = $header->cookie( @cookies )

=item @cookies = $header->cookie

Get or set the C<cookie> property.
The parameter can be a list of L<CGI::Cookie> objects.

=item $header->push_cookie( @cookie )

Given a list of L<CGI::Cookie> objects, appends them to the C<cookie>
property.

=item $self = $header->expires

=item $header->expires( $format )

Get or set the C<expires> property.
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

=item $self = $header->location( $url )

=item $url = $header->location

Get or set the Location header.

  $header->location('http://somewhere.else/in/movie/land');

=item $self = $header->nph( $bool )

=item $bool = $header->nph

Get or set the C<nph> property.
If set to a true value, will issue the correct headers to work
with a NPH (no-parse-header) script.

  $header->nph(1);

=item @tags = $header->p3p

=item $self = $header->p3p( @tags )

Get or set the C<p3p> property.
The parameter can be an array or a space-delimited
string. Returns a list of P3P tags. (In scalar context,
returns the number of P3P tags.)

  $header->p3p(qw/CAO DSP LAW CURa/);
  # or
  $header->p3p( 'CAO DSP LAW CURa' );

  my @tags = $header->p3p; # => ("CAO", "DSP", "LAW", "CURa")
  my $size = $header->p3p; # => 4

In this case, the outgoing header will be formatted as:

  P3P: policyref="/w3c/p3p.xml", CP="CAO DSP LAW CURa"

=item $self = $header->status( $status )

=item $status = $header->status

Get or set the Status header.

  $header->status('304 Not Modified');

=item $self = $header->target( $window_target )

=item $window_target = $header->target

Get or set the Window-Target header.

  $header->target('ResultsWindow');

=item $self = $header->type( $media_type )

=item $media_type = $header->type

Get or set the C<type> property. Represents the media type of the message
content.

  $header->type('text/html');

=back

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
      my $h = CGI::Header->new( $blosxom::header )->rehash;
      $h->set( 'Content-Length' => length $blosxom::output );
  }

  1;

Since L<Blosxom|http://blosxom.sourceforge.net/> depends on the procedural
interface of CGI.pm, you don't have to pass C<$query> to C<new()>
in this case.

=head2 CONVERTING TO HTTP::Headers OBJECTS

  use CGI::Header;
  use HTTP::Headers;

  my @header_props = ( type => 'text/plain', ... );
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
You're allowed to set P3P tags using C<p3p()>.

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
      # => $header->query->server_software

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
