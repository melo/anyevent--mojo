package AnyEvent::Mojo::Connection;

use strict;
use warnings;
use base 'Mojo::Base';
use AnyEvent::Handle;
use Carp;

our $VERSION = '0.1';

__PACKAGE__->attr('server',    chained => 1, weak => 1);
__PACKAGE__->attr('sock',      chained => 1);
__PACKAGE__->attr('peer_host', chained => 1);
__PACKAGE__->attr('peer_port', chained => 1);
__PACKAGE__->attr('timeout',   chained => 1, default => 5);

__PACKAGE__->attr('request_count', chained => 1, default => 0);

__PACKAGE__->attr('tx',        chained => 1);
__PACKAGE__->attr('handle',    chained => 1);


sub run {
  my $self = shift;
  my $srv  = $self->server;
  
  # Create out magic handler_cb
  my $handle = AnyEvent::Handle->new(
    fh         => $self->sock,
    timeout    => $self->timeout,
    on_eof     => sub { $self->close('eof')     },
    on_error   => sub { $self->close('error')   },
    on_timeout => sub { $self->close('timeout') },
  );
  $self->handle($handle);

  $self->_ready_for_transaction;
  
  return;
}

sub close {
  my ($self) = @_;
  
  $self->tx(undef)->handle(undef);
  close($self->sock);
}


##########################################
# Pause/restart processing of transactions

sub pause {
  my ($self) = @_;
  my $tx = $self->tx;
  
  croak("pause() only works on tx's in the 'write' state")
    unless $tx && $tx->is_state('write');
  
  $self->tx->state('paused');
  
  return sub { $self->resume };
}

sub resume {
  my ($self) = @_;
  my $tx = $self->tx;

  croak("resume() only works on tx's in the 'paused' state")
    unless $tx && $tx->is_state('paused');
  
  $self->tx->state('write');
  $self->_write;
  
  return;
}


######################
# Transaction handling

sub _ready_for_transaction {
  my $self = shift;
  
  $self->handle->push_read(sub { $self->_read(@_) });
  
  return;
}

sub _current_transaction {
  my $self = shift;
  my $tx   = $self->tx;
  
  # Initial request, prepare transaction
  if (!$tx) {
    my $srv  = $self->server;
    $tx = $srv->build_tx_cb->($srv)->state('read');
    $self->tx($tx);
    $tx->connection($self);
  }
  
  return $tx;
}

sub _last_transaction {
  my $self = shift;
  
  $self->tx->res->headers->connection('Close');
  
  return;
}

sub _end_transaction {
  my ($self) = @_;
  my $handle = $self->handle;
  my $tx     = $self->tx;
  my $ka     = $tx->keep_alive;  

  # Destroy current tx
  $self->tx(undef);

  if ($ka) {
    $self->_ready_for_transaction;
  }
  else {
    $self->close;
  }
  
  return;
}


##############
# Read request

sub _read {
  my ($self, $handle) = @_;

  return unless defined $handle->{rbuf};

  my $tx  = $self->_current_transaction;
  my $req = $tx->request;
  $req->parse(delete $handle->{rbuf});

  my $done = $req->is_state(qw/done error/);
  # FIXME: we should take care of error differently
  if ($done) {
    my $srv = $self->server;

    # Check to see if this is our last request
    $srv->request_count(($srv->request_count || 0) + 1);
    my $max_keep_alive_requests = $srv->max_keep_alive_requests;
    my $count = ($self->request_count || 0) + 1;
    $self->request_count($count);

    if ($max_keep_alive_requests && $count >= $max_keep_alive_requests) {
      $self->_last_transaction('max-keep-alive');
    }
    
    $tx->state('write');
    $srv->handler_cb->($srv, $tx);
    
    $self->_write if $tx->is_state('write');
  }
  
  return $done;
};


################
# Write response

sub _write {
  my ($self) = @_;

  $self->handle->on_drain(sub {
    $self->_write_more;
  });
}

sub _write_more {
  my ($self) = @_;
  my $handle = $self->handle;

  if (my $done = $self->_tx_state_machine_adv) {
    $handle->on_drain(undef);
    $self->_end_transaction;

    return;
  }
  
  $handle->push_write($self->_get_next_chunk);
}


sub _tx_state_machine_adv {
  my ($self) = @_;
  my $tx   = $self->tx;
  my $res  = $tx->res;
  my $done = 0;
  
  # Advance Mojo state machine
  if ($tx->is_state('write')) {
    $tx->state('write_start_line');
    $tx->{_to_write} = $res->start_line_length;
  }

  # Response start line
  if ($tx->is_state('write_start_line') && $tx->{_to_write} <= 0) {
    $tx->state('write_headers');

    # Connection header
    unless ($res->headers->connection) {
      if ($tx->keep_alive) {
        $res->headers->connection('Keep-Alive');
      }
      else {
        $res->headers->connection('Close');
      }
    }
    
    $tx->{_offset} = 0;
    $tx->{_to_write} = $res->header_length;
  }

  # Response headers
  if ($tx->is_state('write_headers') && $tx->{_to_write} <= 0) {
    $tx->state('write_body');
    $tx->{_offset} = 0;
    $tx->{_to_write} = $res->body_length;
  }

  # Response body
  if ($tx->is_state('write_body') && $tx->{_to_write} <= 0) {
    $done = 1;
  }
  
  return $done;
}

sub _get_next_chunk {
  my ($self) = @_;
  my $tx  = $self->tx;
  my $res = $tx->res;
  my $chunk;
  
  # Write the next chunk
  my $offset = $tx->{_offset}   || 0;
  my $tw     = $tx->{_to_write} || 0;
  
  # Body?
  $chunk = $res->get_body_chunk($offset)
    if $tx->is_state('write_body');
  
  # Headers?
  $chunk = $res->get_header_chunk($offset)
    if $tx->is_state('write_headers');
  
  # Start line?
  $chunk = $res->get_start_line_chunk($offset)
    if $tx->is_state('write_start_line');
  
  # The chunk is no longer the responsability of the Tx object
  my $written = length($chunk);
  $tx->{_to_write} -= $written;
  $tx->{_offset}   += $written;
  
  return $chunk;
}


42; # End of AnyEvent::Mojo::Connection

__END__

=encoding utf8

=head1 NAME

AnyEvent::Mojo::Connection - An active TCP connection to AnyEvent::Mojo



=head1 VERSION

Version 0.1



=head1 SYNOPSIS

    use AnyEvent::Mojo::Connection;

    ...


=head1 DESCRIPTION

Foreach connection to a L< AnyEvent::Mojo > server,
a C< AnyEvent::Mojo::Connection > object is created.

This object keeps track of the current L< Mojo::Transaction >.

If an error or EOF condition is detected while reading or writting to the
client socket, or in case of a timeout, the socket is disconnected.


=head1 METHODS

=head2 new

The constructor accepts the following parameters:


=over 4

=item sock

The client socket.


=item peer_host

The IP of the client.


=item peer_port

The TCP port number of the client.


=item server

The L< AnyEvent::Mojo > server to whom this connection belongs to.


=item timeout

Number of seconds the connection will wait for data while reading.

If no data is sent, the connection is closed.


=back


It returns the C< AnyEvent::Mojo::Connection > object.



=head2 run

The C< run() > method starts all the L< AnyEvent::Handle > processing to read
the next request, process it and write the response.

It returns nothing.



=head2 close

The C< close() > method clears the current transaction, destroys the 
L< AnyEvent::Handle > associated with this connection and closes the
client socket.


=head2 request_count

Returns the total request count for the connection. In case of keep-alive
requests, the request count grows beyond 1. 


=head2 peer_host

Returns the IP address of the peer host.


=head2 peer_port

Returns the TCP port number of the peer host.


=head1 ASYNCHRONOUS PROCESSING

While in the middle of a request, an application can pause the current
transaction, do something else (including dealing with other requests)
and then resume the processing.

To do that, you application must call the C<$tx->connection->pause()> method.

When you are ready to send back the response, call
C<$tx->connection->resume()>.

For example:

    # inside your response handler of you Mojo::App
    $tx->connection->pause();
    
    # Call webservice and deal with result
    http_get 'http://my.webservice.endpoint/api', sub {
      my ($data) = @_;
      
      $tx->response->body("Webservice returned this: '$data'");
      $tx->connection->resume();
    };

To make it easier to resume later, the C<pause()> method returns a coderef
that will resume the transaction when called. So the code above could be
written like this:

    # inside your response handler of you Mojo::App
    my $resume_cb = $tx->connection->pause();
    
    # Call webservice and deal with result
    http_get 'http://my.webservice.endpoint/api', sub {
      my ($data) = @_;
      
      $tx->response->body("Webservice returned this: '$data'");
      $resume_cb->();
    };



=head2 pause()

Pauses the current transaction.

The transaction state must be C<write>, that is, before sending any status
or header responses.

Returns a coderef that, when called, will resume the transaction.


=head2 resume()

Resumes a paused transaction.

The response must be complete and we will immediatly start sending the data
to the client.

Returns nothing.


=head1 AUTHOR

Pedro Melo, C<< <melo at cpan.org> >>



=head1 COPYRIGHT & LICENSE

Copyright 2008 Pedro Melo.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

