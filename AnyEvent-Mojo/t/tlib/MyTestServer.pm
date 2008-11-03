package MyTestServer;

use strict;
use warnings;
use base 'AnyEvent::Mojo';

BEGIN {
  __PACKAGE__->attr('banner_called');
}

sub startup_banner {
  my $self = shift;
  
  $self->banner_called([$self->host, $self->port]);
  return $self->SUPER::startup_banner(@_);
}

1;