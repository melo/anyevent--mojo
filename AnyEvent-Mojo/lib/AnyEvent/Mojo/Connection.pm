package AnyEvent::Mojo::Connection;

use strict;
use warnings;
use base 'Mojo::Base';
use AnyEvent::Handle;

our $VERSION = '0.1';

__PACKAGE__->attr('server',    chained => 1, weak => 1);
__PACKAGE__->attr('sock',      chained => 1);
__PACKAGE__->attr('peer_host', chained => 1);
__PACKAGE__->attr('peer_port', chained => 1);
__PACKAGE__->attr('timeout',   chained => 1, default => 5);

__PACKAGE__->attr('tx',        chained => 1);
__PACKAGE__->attr('handle',    chained => 1);


sub run {
  my $self = shift;
  my $srv  = $self->server;
  
  # Create the initial transaction
  my $tx = $srv->build_tx_cb->($srv)->state('read');
  $self->tx($tx);
  
  # Keep it simple, no keep-alive for now
  $tx->res->headers->connection('close');

  # Create out magic handler_cb
  my $handle = AnyEvent::Handle->new(
    fh         => $self->sock,
    timeout    => $self->timeout,
    on_eof     => sub { $self->close('eof')     },
    on_error   => sub { $self->close('error')   },
    on_timeout => sub { $self->close('timeout') },
  );
  $self->handle($handle);

  $handle->push_read(sub { $self->_read(@_) });
  
  return;
}

sub close {
  my ($self) = @_;
  
  $self->tx(undef)->handle(undef);
  close($self->sock);
}



##############
# Read request

sub _read {
  my ($self, $handle) = @_;
  my $srv = $self->server;
  my $tx  = $self->tx;
  my $req = $tx->request;
  
  return unless defined $handle->{rbuf};
  
  $req->parse(delete $handle->{rbuf});

  my $done = $req->is_state(qw/done error/);
  if ($done) {
    $tx->state('write');
    $srv->handler_cb->($srv, $tx);
    
    $self->_write;
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
    # No keep-alives
    $self->close;
    return;
  }
  
  $handle->push_write($self->_get_next_chunk);
}


sub _tx_state_machine_adv {
  my ($self) = @_;
  my $tx   = $self->tx;
  my $done = 0;
  
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



=head1 AUTHOR

Pedro Melo, C<< <melo at evolui.com> >>



=head1 COPYRIGHT & LICENSE

Copyright 2008 EVOLUI.COM.