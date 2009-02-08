package AnyEvent::Mojo::Client::Connection;

use strict;
use warnings;
use base 'Mojo::Base';
use AnyEvent::Handle;
use AnyEvent::Socket;
use Carp;

our $VERSION = '0.1';

__PACKAGE__->attr([qw/sock handle/]);
__PACKAGE__->attr([qw/sockaddr sockport peeraddr peerport/]);
__PACKAGE__->attr([qw/client tx/], weak => 1);
__PACKAGE__->attr([qw/timeout/], default => 5);
__PACKAGE__->attr([qw/reuse/], default => 1);

#####################################
# Expected interface for Mojo::Client

sub connect {
  my ($self) = @_;
  
  tcp_connect(
    # connect to...
    $self->sockaddr, $self->sockport,
    
    # Success/failure callback
    sub {
      my ($sock, $peeraddr, $peerport) = @_;
      my $tx = $self->tx;
      
      if (!defined $sock) {
        $tx->error("Connect failed: $!");
      }
      else {
        # we got a live one
        $self->sock($sock);
        $self->peeraddr($peeraddr);
        $self->peerport($peerport);
        
        my $handle = AnyEvent::Handle->new(
          fh => $sock,
          on_eof   => sub { $self->_on_error(undef)     },
          on_error => sub { $self->_on_error($_[0], $!) },
          on_read  => sub { $self->_on_read(@_)         },
        );
        $self->handle($handle);
      }
      
      $self->client->spin($tx);
      return
    },
    
    # Sock setup callback
    sub {
      return $self->timeout
    },
  );
  
  return;
}

sub connected { return $_[0]->{sock} }

sub start_write {
  my ($self) = @_;
  my $handle = $self->handle;
  
  return if $handle->on_drain;
  $self->handle->on_drain(sub { $self->_on_write(@_) });
  
  return;
}


##################
# Deal with events

sub _on_read {
  my ($self, $handle) = @_;
  my $client = $self->client;
  my $tx     = $self->tx;

  my $chunk = delete $handle->{rbuf};
  print STDERR "[READ] chunk sized ".length($chunk || '')."\n";
  return unless $chunk;
  
  # No more writes
  $handle->on_drain(undef);
  
  $client->_parse_read_chunk($tx, length($chunk), $chunk);
  print STDERR "[READ] parsed, is finished? ",($tx->is_finished? 'yes' : 'no'),"\n";
  $client->spin($tx) if $tx->is_finished;
  
  return;
}

sub _on_write {
  my ($self, $handle) = @_;
  my $client = $self->client;
  my $tx     = $self->tx;
  
  # check the tx status
  print STDERR "[WRITE] Pre  spin, tx state is ",$tx->state,"\n";
  $client->spin($tx);
  print STDERR "[WRITE] Post spin, tx state is ",$tx->state,"\n";
  
  # try and get something to send
  my $chunk = $client->_get_next_chunk($tx);
  print STDERR "[WRITE] got chunk sized ".length($chunk || '').", to write is $tx->{_to_write}/$tx->{_offset}\n";
  print STDERR "CHUNK:\n$chunk\n---\n";
  return unless defined $chunk;

  # update tx status
  # FIXME: this should really be done by tx
  my $written = length($chunk);
  $tx->{_to_write} -= $written;
  $tx->{_offset} += $written;
  print STDERR "[WRITE] still to write $tx->{_to_write}\n";
  
  $handle->push_write($chunk);
  
  return;
}

sub _on_error {
  my ($self, $handle, $error) = @_;
  my $tx = $self->tx;
  
  $self->reuse(0);
  $handle->on_drain(undef);
  
  if (defined($error)) {
    $tx->error("Can't read from socket: $error");
  }
  else {
    $self->client->_parse_read_chunk($tx, 0, '');
  }
  
  $self->client->spin($tx);
  
  return;
}

1;