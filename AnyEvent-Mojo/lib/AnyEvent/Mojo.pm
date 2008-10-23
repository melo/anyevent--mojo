package AnyEvent::Mojo;

use strict;
use warnings;
use 5.008;
use base 'Mojo::Server';
use Carp qw( croak );
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Mojo::Connection;

our $VERSION = '0.1';

__PACKAGE__->attr('port',         chained => 1, default => 3000);
__PACKAGE__->attr('run_guard',    chained => 1);
__PACKAGE__->attr('listen_guard', chained => 1);
__PACKAGE__->attr('connection_class',
   chained => 1,
   default => 'AnyEvent::Mojo::Connection'
);


sub listen {
  my $self = shift;
  
  # Already listening
  return if $self->listen_guard;
  
  my $guard = tcp_server(undef, $self->port,
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
      )->run;
    },
  );
  
  $self->listen_guard(sub { $guard = undef });
  $self->startup_banner;
  
  return;
}

sub run {
  my $self = shift;
  
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
  my ($self, $thishost, $thisport) = @_;
  
  print "Server available at http://$thishost:$thisport/\n";
}


42; # End of AnyEvent::Mojo

__END__

=encoding utf8

=head1 NAME

AnyEvent::Mojo - Run Mojo apps using AnyEvent framework



=head1 VERSION

Version 0.1



=head1 SYNOPSIS

    use strict;
    use warnings;
    use AnyEvent;
    use AnyEvent::Mojo;
    
    my $server = AnyEvent::Mojo->new;
    $server->port(3456);
    $server->handler_cb(sub {
      my ($self, $tx) = @_;
      
      # Do whatever you want here
      $you_mojo_app->handler($tx);
      
      return $tx;
    });
    
    # Start it up and keep it running
    $server->run
    
    # integrate with other AnyEvent stuff
    $server->listen
    
    # other AnyEvent stuff here
    
    # Run the loop
    AnyEvent->condvar->recv;



=head1 STATUS

This is a first B<alpha> release. The interface B<will> change, and there is
still missing funcionality, like keep alive support.

Basic HTTP/1.1 single request per connection works.



=head1 DESCRIPTION

This module allows you to integrate Mojo applications with the AnyEvent
framework. For example, you can run a web interface for a long-lived
AnyEvent daemon.

The AnyEvent::Mojo extends the Mojo::Server class.

To use you need to create a AnyEvent::Mojo object. You can set the port
with the C< port() > method.

Then set the request callback with the Mojo::Server method, 
C<handler_cb()>.

This callback will be called on every request. The first parameter is
the AnyEvent::Mojo server object itself, and the second parameter is a
Mojo::Transaction.

The code should build the response and return.

For now, the callback is synchronous, so the response must be completed
when the callback returns. Future versions will lift this restriction.



=head1 METHODS


=head2 new

The constructor. Takes no parameters, returns a server object.


=head2 port

Accessor to the port where the server will listen to. Defaults to 3000.


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
on your L< AnyEvent::Mojo > subclasses to setup other components.

The default C< startup_banner > prints the URL where the server
is listening to requests.

This method receives two parameters:


=over 4

=item $host

The hostname where the server is binded to. By default the server binds to all
addresses, and this value is C< 0.0.0.0 >.


=item $port

The port number.


=back



=head1 AUTHOR

Pedro Melo, C<< <melo at cpan.org> >>



=head1 COPYRIGHT & LICENSE

Copyright 2008 Pedro Melo.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
