package AnyEvent::Mojo;

use strict;
use warnings;
use 5.008;
use base 'Mojo::Server';
use Carp qw( croak );
use AnyEvent;
use AnyEvent::Socket;

our $VERSION = '0.1';


__PACKAGE__->attr('port',  chained => 1, default => 3000);
__PACKAGE__->attr('alive', chained => 1);


sub listen {
  my $self = shift;
  
  tcp_server(undef, $self->port,
    # on connection
    sub {
      my ($fh) = @_;
      
      if (!$fh) {
        print STDERR "Connect failed: $!\n";
        return;
      }
      
      my $tx = $self->build_tx_cb->($self);
      $tx->state('read');
      # Keep it simple, no keep-alive for now
      $tx->res->headers->connection('close');
      
      # Create out magic handle
      my $handle; $handle = AnyEvent::Handle->new(
        fh       => $fh,
        timeout  =>  15,
        on_eof     => sub { undef $handle; undef $tx },
        on_error   => sub { undef $handle; undef $tx },
        on_timeout => sub { undef $handle; undef $tx },
      );
      
      $handle->push_read(sub { $self->_read($tx, @_) });      
    },
    
    # Startup phase
    sub {
      my ($fh, $thishost, $thisport) = @_;
      
      print "Server available at http://$thishost:$thisport/\n";
    }
  );
}

sub run {
  my $self = shift;
  
  $self->listen;
  
  my $cv = AnyEvent->condvar;
  $self->alive($cv);
  
  $cv->recv;
}


##############
# Read request

sub _read {
  my ($self, $tx, $handle) = @_;
  my $req = $tx->request;
  
  return unless defined $handle->{rbuf};
  
  $req->parse(delete $handle->{rbuf});

  my $done = $req->is_state(qw/done error/);
  if ($done) {
    $tx->state('write');
    $self->handler_cb->($self, $tx);
    
    $self->_write($tx, $handle);
  }
  
  return $done;
};


################
# Write response

sub _write {
  my ($self, $tx, $handle) = @_;

  $handle->on_drain(sub {
    $self->_write_more($tx, $handle);
  });
}

sub _write_more {
  my ($self, $tx, $handle) = @_;
  my $res = $tx->res;
  my $state = $tx->state;
  my $chunk;

  # Advance Mojo state machine
  if ($tx->is_state('write')) {
    $tx->state('write_start_line');
    $tx->{_to_write} = $tx->res->start_line_length;
  }

  # Response start line
  if ($tx->is_state('write_start_line') && $tx->{_to_write} <= 0) {
    $tx->state('write_headers');
    $tx->{_offset} = 0;
    $tx->{_to_write} = $tx->res->header_length;
  }

  # Response headers
  if ($tx->is_state('write_headers') && $tx->{_to_write} <= 0) {
    $tx->state('write_body');
    $tx->{_offset} = 0;
    $tx->{_to_write} = $tx->res->body_length;
  }

  # Response body
  if ($tx->is_state('write_body') && $tx->{_to_write} <= 0) {
    # FIXME: need AnyEvent::Mojo::Request to undo here
    $handle->on_drain(undef);
    close($handle->fh);
    return;
  }
  
  # Write the next chunk
  my $offset = $tx->{_offset} || 0;
  my $tw = $tx->{_to_write} || 0;
  
  # Body?
  $chunk = $res->get_body_chunk($offset)
    if $tx->is_state('write_body');
  
  # Headers?
  $chunk = $res->get_header_chunk($offset)
    if $tx->is_state('write_headers');
  
  # Start line?
  $chunk = $res->get_start_line_chunk($offset)
    if $tx->is_state('write_start_line');

  # Advance internal counters, the data is ours responsability now  
  my $written = length($chunk);
  $tw = $tx->{_to_write}   -= $written;
  $offset = $tx->{_offset} += $written;
  
  $handle->push_write($chunk);
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
AnyEvent runloop with a condvar.



=head1 AUTHOR

Pedro Melo, C<< <melo at cpan.org> >>



=head1 COPYRIGHT & LICENSE

Copyright 2008 Pedro Melo.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
