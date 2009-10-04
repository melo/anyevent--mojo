package AnyEvent::Mojo::Server::Connection;

use strict;
use warnings;
use parent 'Mojo::Base';
use Mojo::Transaction::Pipeline;
use Carp;

use Data::Dump qw(pp);

__PACKAGE__->attr([qw( server pipeline write_mode_cb close_sock_cb )]);
__PACKAGE__->attr([qw( remote_address remote_port local_address local_port )]);
__PACKAGE__->attr(request_count => 0);


##############################
# Close the current connection

sub close {
  my ($self, $type, $mesg) = @_;

  $self->pipeline(undef);
  $self->write_mode_cb(undef);
  $self->server(undef);

  ## Make sure the socket is closed
  my $cb = $self->close_sock_cb;
  $self->close_sock_cb(undef);
  $cb->();

  return;
}


##########################################
# Pause/restart processing of transactions

sub pause {
  my ($self) = @_;
  my $p = $self->pipeline;
  my $tx = $p && $p->server_tx;
  
  croak("pause() only works on tx's in the 'handle_request' state")
    unless $tx && $tx->is_state('handle_request');
  
  my ($tx_state, $tx_req_state) = ($tx->state, $tx->req->state);
  $tx->state('paused');
  $tx->req->state('paused');
  
  return sub { $self->_resume($tx_state, $tx_req_state) };
}

sub resume {
  Carp::croak('resume() not available, use the cb that pause() gave you, ')
}

sub _resume {
  my ($self, $tx_state, $tx_req_state) = @_;
  my $p = $self->pipeline;
  my $tx = $p && $p->server_tx;

  return unless $tx && $tx->is_state('paused');

  $tx->req->state($tx_state);
  $tx->state($tx_state);

  $p->server_handled;
  $p->server_spin;
  $self->_check_for_writters;
  
  return;
}


###############
# _on_ handlers

sub _on_read {
  my ($self, $buf) = @_;
  my $p = $self->pipeline;
  my $srv = $self->server;

  # Make sure we have a pipeline
  $p = $self->_mk_pipeline unless $p;

  my $tx = $p->server_tx;
  while ($buf) {
    # Need a new transaction?
    unless ($tx) {
      $tx = $srv->build_tx_cb->($srv);
      $p->server_accept($tx);
    }

    $p->server_read($buf);
    
    if ($p->is_state('handle_continue')) {
      $srv->continue_handler_cb->($srv, $p->server_tx);
      $p->server_handled;
    }

    if ($p->is_state('handle_request')) {
      my $tx = $p->server_tx;
      
      $srv->handler_cb->($srv, $tx);
      $p->server_handled unless $tx->state eq 'paused';
    }
    
    $p->server_spin;
    
    $buf = $p->server_leftovers;
    $tx = undef if $buf;
  }
  
  $self->_check_for_writters;
  $self->_cleanup;
}

sub _on_write {
  my ($self, $write_cb) = @_;

  return unless my $p = $self->pipeline;
  return unless my $chunk = $p->server_get_chunk;

  ## FIXME: The order of is wrong. We should call server_written with
  ## the output of $write_cb->(chunk)
  # but the problem is that the AnyEvent impl of AnyEvent::Handle
  # recursivelly calls us again when we call $write_cb. So we need to
  # move the state machine before we call it. Hence the call to
  # $p->server_spin.
  #
  # I don't have a better solution right now. One possibility would be
  # not to use AnyEvent::Handle, but that would mean to rewrite a lot of
  # tricky code. Another would be to use the autocork feature of
  # AnyEvent that delays the write until the next I/O loop iteraction.
  my $written = length($chunk);
  $p->server_written($written);
  $self->_cleanup;
  
  $write_cb->($chunk);
}

sub _on_error {
  my ($self, undef, $mesg) = @_;
  
  $self->close('on_error', $mesg)
}

sub _on_eof {
  my ($self) = @_;
  
  $self->close('on_error')
}

sub _on_timeout {
  my $self = shift;
  my $p = $self->pipeline;
  my $tx = $p && $p->server_tx;

  return $self->close('timeout') unless $tx && $tx->state eq 'paused';
  return;
}


##############
# Spin the web

sub _check_for_writters {
  my $self = shift;
  my $p = $self->pipeline;
  
  ## Start the writer if we are ready for it
  $self->write_mode_cb->($p->server_is_writing);
}

sub _cleanup {
  my $self = $_[0];
  my $p = $self->pipeline;
  return unless $p;
  
  $p->server_spin;

  if ($p->is_finished) {
    $self->pipeline(undef);
    $self->close('no-keep-alive') unless $p->keep_alive;
  }
}

sub _mk_pipeline {
  my ($self) = @_;
  
  my $srv = $self->server;
  my $p = Mojo::Transaction::Pipeline->new;
  $p->connection($self);
  $p->kept_alive(1) if $self->_inc_request_count > 1;

  # Store connection information
  $p->local_address($self->local_address);
  $p->local_port($self->local_port);
  $p->remote_address($self->remote_address);
  $p->remote_port($self->remote_port);
  
  $self->pipeline($p);
  
  return $p;
}


#######
# Stats

sub _inc_request_count {
  my $self = $_[0];
  $self->server->_inc_request_count;
  return ++$self->{request_count}
}

42; # End of AnyEvent::Mojo::Server::Connection

__END__

=encoding utf8

=head1 NAME

AnyEvent::Mojo::Server::Connection - An active TCP connection to AnyEvent::Mojo::Server



=head1 SYNOPSIS

    use AnyEvent::Mojo::Server::Connection;

    ...


=head1 DESCRIPTION

Foreach connection to a L< AnyEvent::Mojo::Server >,
a C< AnyEvent::Mojo::Server::Connection > object is created.

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

The L< AnyEvent::Mojo::Server > to whom this connection belongs to.


=item timeout

Seconds (can be fractional) that the connection can be idle (waiting
for a request or unable to write more data out).

If the connection is paused, the timeout is ignored.

If the timeout fires, the connection is closed.


=back


It returns the C< AnyEvent::Mojo::Server::Connection > object.



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

While the connection is paused, inactivity timeouts are ignored.

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

