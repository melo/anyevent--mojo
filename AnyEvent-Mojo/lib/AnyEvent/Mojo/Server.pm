package AnyEvent::Mojo::Server;

use strict;
use warnings;
use 5.008;
use base 'Mojo::Server';
use Carp qw( croak );
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Mojo::Server::Connection;
use IO::Socket qw( SOMAXCONN );

our $VERSION = '0.1';

__PACKAGE__->attr('port',         chained => 1, default => 3000);
__PACKAGE__->attr('host',         chained => 1);
__PACKAGE__->attr('listen_queue_size',
    chained => 1,
    default => sub { SOMAXCONN },
);
__PACKAGE__->attr('max_keep_alive_requests',
  chained => 1,
  default => 100,
);
__PACKAGE__->attr('keep_alive_timeout',
  chained => 1,
  default => 5,
);
__PACKAGE__->attr('request_count', chained => 1, default => 0);

__PACKAGE__->attr('run_guard',    chained => 1);
__PACKAGE__->attr('listen_guard', chained => 1);
__PACKAGE__->attr('connection_class',
    chained => 1,
    default => 'AnyEvent::Mojo::Server::Connection'
);


sub listen {
  my $self = shift;
  
  # Already listening
  return if $self->listen_guard;
  
  my $guard = tcp_server($self->host, $self->port,
    # on connection
    sub {
      my ($sock, $peer_host, $peer_port) = @_;
      
      if (!$sock) {
        $self->log("Connect failed: $!");
        return;
      }
      
      my $conn_class = $self->connection_class;
      $conn_class->new(
        sock      => $sock,
        peer_host => $peer_host,
        peer_port => $peer_port,
        server    => $self,
        timeout   => $self->keep_alive_timeout,
      )->run;
    },
    
    # Setup listen queue size, record our hostname and port
    sub {
      $self->host($_[1])->port($_[2]);
      
      return $self->listen_queue_size;
    }
  );
  
  $self->listen_guard(sub { $guard = undef });
  $self->startup_banner;
  
  return;
}

sub run {
  my $self = shift;
  
  $SIG{PIPE} = 'IGNORE';
  
  # Start the server socket
  $self->listen;
  
  # Create a run guard
  my $cv = AnyEvent->condvar;
  $self->run_guard(sub { $cv->send });

  $cv->recv;
  
  return;
}

sub stop {
  my ($self) = @_;
  
  # Clears the listening guard, closes the listening socket
  if (my $cb = $self->listen_guard) {
    $cb->();
    $self->listen_guard(undef);
  }
  
  # Clear the run() guard
  if (my $cb = $self->run_guard) {
    $cb->();
    $self->run_guard(undef);
  }
}

sub startup_banner {
  my $self = shift;
  my ($host, $port) = ($self->host, $self->port);
  
  print "Server available at http://$host:$port/\n";
}


42; # End of AnyEvent::Mojo::Server

__END__

=encoding utf8

=head1 NAME

AnyEvent::Mojo::Server - Run Mojo apps using AnyEvent framework



=head1 VERSION

Version 0.1



=head1 SYNOPSIS

    use strict;
    use warnings;
    use AnyEvent;
    use AnyEvent::Mojo::Server;
    
    my $server = AnyEvent::Mojo::Server->new;
    $server->port(3456)->listen_queue_size(10);
    $server->max_keep_alive_requests(100)->keep_alive_timeout(3);
    
    $server->handler_cb(sub {
      my ($self, $tx) = @_;
      
      # Do whatever you want here
      $you_mojo_app->handler($tx);

      # Cool stats
      $tx->res->headers(
        'X-AnyEvent-Mojo-Request-Count' =>  $server->request_count
      );
      
      return $tx;
    });
    
    # Start it up and keep it running
    $server->run
    
    # integrate with other AnyEvent stuff
    $server->listen
    
    # other AnyEvent stuff here
    
    # Run the loop
    AnyEvent->condvar->recv;
    
    # Advanced usage: use your own Connection class
    $server->connection_class('MyConnectionClass');


=head1 STATUS

This is a first B<beta> release. The interface B<should> not change in a
backwards incompatible way until version 1.0.

Basic HTTP/1.0 and HTTP/1.1 works, including keep-alives.

Support for 100-Continue is still missing.


=head1 DESCRIPTION

This module allows you to integrate Mojo applications with the AnyEvent
framework. For example, you can run a web interface for a long-lived
AnyEvent daemon.

The AnyEvent::Mojo::Server extends the Mojo::Server class.

To use you need to create a AnyEvent::Mojo::Server object. You can set the port
with the C< port() > method.

Then set the request callback with the Mojo::Server method, 
C<handler_cb()>.

This callback will be called on every request. The first parameter is
the L<AnyEvent::Mojo::Server> server object itself, and the second parameter is a
L<Mojo::Transaction>.

The code should build the response and return.

Optionally, you can pause the current request and resume it later. This
is useful if you need to request information from a remote service to
answer the current request. You pause the current Mojo request, ask the
information asyncronously, and resume when the answer arrives. In the
meantime, you can keep answering other requests.



=head1 METHODS


=head2 new

Creates a new L<AnyEvent::Server::Mojo> instance.

Returns a L<AnyEvent::Server::Mojo> object.


=head2 host

The hostname or IP address to which the server will bind to. By default it
will bind to all interfaces.


=head2 port

Port where the server will listen on. Defaults to 3000.


=head2 listen_queue_size

Defines the size of the listening queue. Defaults to C< SOMAXCONN >.

Use

    perl -MSocket -e 'print Socket::SOMAXCONN,"\n"'

to discover the default for your operating system.


=head2 max_keep_alive_requests

Number of requests that each connection will allow in keep-alive mode.

Use 0 for unlimited requests. Default is 100 requests.


=head2 keep_alive_timeout

Number of seconds (can be fractional) that the server lets open connections
stay idle.

Default is 5 seconds.


=head2 request_count

Returns the number of requests the server has answered since it started.


=head2 connection_class

Sets the class name that will be used to process each connection.

Defaults to L< AnyEvent::Mojo::Server::Connection >.


=head2 listen

Starts the listening socket.

Returns nothing.


=head2 run

Starts the listening socket and kickstarts the
L< AnyEvent > runloop.


=head2 stop

Closes the listening socket and stops the runloop initiated by a call to
C< run() >.


=head2 startup_banner

Called after the listening socket is started. You can override this method
on your L< AnyEvent::Mojo::Server > subclasses to setup other components.

The default C< startup_banner > prints the URL where the server
is listening to requests.



=head1 AUTHOR

Pedro Melo, C<< <melo at cpan.org> >>



=head1 COPYRIGHT & LICENSE

Copyright 2008 Pedro Melo.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
