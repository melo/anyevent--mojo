package AnyEvent::Mojo;

use strict;
use warnings;
use 5.008;
use AnyEvent::Mojo::Server;
use base qw( Exporter );

@AnyEvent::Mojo::EXPORT = qw( mojo_server );

our $VERSION = '0.6001';


#####################
# Start a Mojo server

sub mojo_server {
  my ($host, $port, $cb) = @_;
  
  croak('FATAL: the callback is required, ') unless ref($cb) eq 'CODE';
  
  my $server = AnyEvent::Mojo::Server->new;
  $server->host($host) if $host;
  $server->port($port) if $port;
  $server->handler_cb($cb);
  
  $server->listen;
  
  return $server;
}


42; # End of AnyEvent::Mojo

__END__

=encoding utf8

=head1 NAME

AnyEvent::Mojo - Start async Mojo servers easly



=head1 VERSION

Version 0.6



=head1 SYNOPSIS

    use strict;
    use warnings;
    use AnyEvent;
    use AnyEvent::Mojo;
    
    my $port = 7865;
    
    my $server = mojo_server undef, $port, sub {
      my ($self, $tx) = @_;
      
      # Handle the request here, see AnyEvent::Mojo::Server for details
    };
        
    # Run the loop
    $server->run
    
    # ... or ...
    AnyEvent->condvar->recv;


=head1 STATUS

This is a first B<beta> release. The interface B<should not> change
in a backwards incompatible way until version 1.0.



=head1 DESCRIPTION

This module allows you to integrate Mojo applications with the AnyEvent
framework. For example, you can run a web interface for a long-lived
AnyEvent daemon.


=head1 FUNCTIONS

The module exports the following functions:

=head2 mojo_server

Starts a server. Accepts three parameters:

=over 4

=item host

The hostname or IP address to which the server will bind to. Use C<undef> to
bind to all interfaces.


=item port

Port where the server will listen on. You can use C<undef> to choose the
default value of 3000.


=item cb

A coderef. This handler will be called for each request. The first parameter
is the server object, and the second is a C<Mojo::Transaction>.

=back

Returns a C<AnyEvent::Mojo::Server> object.



=head1 AUTHOR

Pedro Melo, C<< <melo at cpan.org> >>



=head1 COPYRIGHT & LICENSE

Copyright 2008 Pedro Melo.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
