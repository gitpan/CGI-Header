package CGI::Header;
use 5.008_009;
use strict;
use warnings;
use Carp qw/croak/;

our $VERSION = '0.46';

my %Property_Alias = (
    'cookies'       => 'cookie',
    'content-type'  => 'type',
    'set-cookie'    => 'cookie',
    'uri'           => 'location',
    'url'           => 'location',
    'window-target' => 'target',
);

sub new {
    my $class = shift;

    bless {
        handler => 'header',
        header => {},
        @_
    }, $class;
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
           $prop = $Property_Alias{$prop} if exists $Property_Alias{$prop};

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

sub set {
    my $self = shift;
    my $field = lc shift;
    $self->{header}->{$field} = shift;
}

sub exists {
    my $self = shift;
    my $field = lc shift;
    exists $self->{header}->{$field};
}

sub delete {
    my $self = shift;
    my $field = lc shift;
    delete $self->{header}->{$field};
}

sub clear {
    my $self = shift;
    %{ $self->{header} } = ();
    $self;
}

BEGIN {
    my @props = qw(
        attachment
        charset
        cookie
        expires
        location
        nph
        p3p
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

sub push_cookie {
    my $self   = shift;
    my $cookie = $self->query->cookie( @_ );
    my $header = $self->{header};

    if ( ref $header->{cookie} eq 'ARRAY' ) {
        push @{ $header->{cookie} }, $cookie;
    }
    elsif ( exists $header->{cookie} ) {
        $header->{cookie} = [ $header->{cookie}, $cookie ];
    }
    else {
        $header->{cookie} = $cookie;
    }

    $self;
}

sub as_string {
    my $self    = shift;
    my $handler = $self->{handler};

    if ( $handler eq 'header' or $handler eq 'redirect' ) {
        return $self->query->$handler( $self->{header} );
    }
    elsif ( $handler eq 'none' ) {
        return q{};
    }
    else {
        croak "Invalid handler '$handler'";
    }

    return;
}

1;

__END__

=head1 NAME

CGI::Header - Handle CGI.pm-compatible HTTP header properties

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
  my $h = CGI::Header->new(
      header => $header,
      query  => $query
  );

  # update $header
  $h->set( 'Content-Length' => 3002 ); # overwrite
  $h->delete('Content-Disposition'); # => 3002
  $h->clear; # => $self

  $h->header; # same reference as $header

=head1 VERSION

This document refers to CGI::Header version 0.46.

=head1 DEPENDENCIES

This module is compatible with CGI.pm 3.51 or higher.

=head1 DESCRIPTION

This module is a utility class to manipulate a hash reference
received by CGI.pm's C<header()> method.

This module isn't the replacement of the C<header()> method, but complements
CGI.pm.

This module can be used in the following situation:

=over 4

=item 1. $header is a hash reference which represents CGI response headers

For example, L<CGI::Application> implements C<header_add()> method
which can be used to add CGI.pm-compatible HTTP header properties.
Instances of CGI.pm-based applications often hold those properties.

  my $header = { type => 'text/plain' };

=item 2. Manipulates $header using CGI::Header

Since property names are case-insensitive,
application developers have to normalize them manually
when they specify header properties.
CGI::Header normalizes them automatically.

  use CGI::Header;

  my $h = CGI::Header->new( header => $header );
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
This module can be used to generate L<PSGI>-compatible response header
array references. See L<CGI::Header::PSGI>.

=back

=head2 ATTRIBUTES

=over 4

=item $query = $header->query

Returns your current query object. This attribute defaults to the Singleton
instance of CGI.pm (C<$CGI::Q>) which is shared by functions exported by the module.

=item $self = $header->handler('redirect')

Works like C<CGI::Application>'s C<header_type> method.
This method can be used to declare that you are setting a redirection
header. This attribute defaults to C<header>.

  $header->handler('redirect')->as_string; # invokes $header->query->redirect

=item $hashref = $header->header

Returns the header hash reference associated with this CGI::Header object.
This attribute defaults to a reference to an empty hash.
You can always pass the header hash to C<CGI::header()> function
to generate CGI response headers:

  print CGI::header( $header->header );

=back

=head2 METHODS

=over 4

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
  $header->get('Content-Length');
  $header->get('content-length');

The C<$value> argument must be a plain string:

  $header->set( 'Content-Length' => 3002 );
  my $length = $header->get('Content-Length'); # => 3002

=item $bool = $header->exists( $field )

Returns a Boolean value telling whether the specified field exists.

  if ( $header->exists('ETag') ) {
      ...
  }

=item $value = $header->delete( $field )

Deletes the specified field form CGI response headers.
Returns the value of the deleted field.

  my $value = $header->delete('Content-Disposition'); # => 'inline'

=item $self = $header->clear

This will remove all header properties.

=item $header->as_string

If C<< $header->handler >> is set to C<header>, it's identical to:

  $header->query->header( $header->header );

If C<< $header->handler >> is set to C<redirect>, it's identical to:

  $header->query->redirect( $header->header );

=back

=head2 PROPERTIES

The following methods were named after property names recognized by
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

  $header->attachment('genome.jpg');

In this case, the outgoing header will be formatted as:

  Content-Disposition: attachment; filename="genome.jpg"

=item $self = $header->charset( $character_set )

=item $character_set = $header->charset

Get or set the C<charset> property. Represents the character set sent to
the browser.

=item $self = $header->cookie( $cookie )

=item $cookie = $header->cookie

Get or set the C<cookie> property.

=item $header->push_cookie({ name => $name, value => $value, ... })

The given argument will be passed to C<< $header->query->cookie >> method
to create L<CGI::Cookie> object. The object will be added to the C<cookie>
property.

  $header->push_cookie( riddle_name => "The Sphynx's Question" );

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

=item $tags = $header->p3p

=item $self = $header->p3p( $tags )

Get or set the C<p3p> property.
The parameter can be an arrayref or a space-delimited
string.

  $header->p3p([qw/CAO DSP LAW CURa/]);
  # or
  $header->p3p('CAO DSP LAW CURa');

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
      my $h = CGI::Header->new( header => $blosxom::header )->rehash;
      $h->set( 'Content-Length' => length $blosxom::output );
  }

  1;

Since L<Blosxom|http://blosxom.sourceforge.net/> depends on the procedural
interface of CGI.pm, you don't have to pass C<$query> to C<new()>
in this case.

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

Set C<type> property to an empty string:

  $header->type(q{});

=item Date

If one of the following conditions is met, the Date header will be set
automatically, and also the header field will become read-only:

  if ( $header->nph or $header->cookie or $header->expires ) {
      $header->set( 'Date' => 'Thu, 25 Apr 1999 00:40:33 GMT' ); # wrong
      $header->delete('Date'); # wrong
  }

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
      $header->set( 'Pragma' => 'no-cache' ); # wrong
      $header->delete('Pragma'); # wrong
  }

=item Server

If the following condition is met, the Server header will be set
automatically, and also the header field will become read-only: 

  if ( $header->nph ) {
      $header->set( 'Server' => 'Apache/1.3.27 (Unix)' ); # wrong
      $header->delete('Server'); # wrong
  }


=back

=head1 SEE ALSO

L<CGI>, L<HTTP::Headers>

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
