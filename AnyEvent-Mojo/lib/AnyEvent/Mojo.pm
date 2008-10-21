package AnyEvent::Mojo;

use strict;
use warnings;
use base 'Mojo::Server';
use Carp 'croak';
use AnyEvent;
use AnyEvent::Socket;

our $VERSION = '0.1';


__PACKAGE__->attr('port',  chained => 1, default => 3000);
__PACKAGE__->attr('alive', chained => 1);


sub listen {
  my $self = shift;
  
  tcp_server undef, $self->port, sub {
    my ($fh) = @_
        or die "Connect failed: $!";

    # ... deal with connection
  }, sub {
    my ($fh, $thishost, $thisport) = @_;
    
    print "Server available at http://$thishost:$thisport/\n";
  };
}

sub run {
  my $self = shift;
  
  $self->listen;
  
  my $cv = AnyEvent->condvar;
  $self->alive($cv);
  
  $cv->recv;
}


42; # End of AnyEvent::Mojo

__END__

=encoding utf8

=head1 NAME

AnyEvent::Mojo - Run Mojo apps using AnyEvent framework



=head1 VERSION

Version 0.1



=head1 SYNOPSIS

    use AnyEvent::Mojo;

    ...


=head1 DESCRIPTION



=head1 AUTHOR

Pedro Melo, C<< <melo at cpan.org> >>



=head1 COPYRIGHT & LICENSE

Copyright 2008 Pedro Melo.
