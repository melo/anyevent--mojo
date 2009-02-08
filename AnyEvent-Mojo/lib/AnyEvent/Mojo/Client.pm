package AnyEvent::Mojo::Client;

use strict;
use warnings;
use 5.008;
use base 'Mojo::Client';
use Carp qw( croak );
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Mojo::Client::Connection;

our $VERSION = '0.1';

__PACKAGE__->attr(
  'connection_class',
  default => 'AnyEvent::Mojo::Client::Connection',
);
__PACKAGE__->attr('txs', default => sub { {} });
__PACKAGE__->attr('run_guard');

#########
# Our API

*process_all = \&process;
sub process {
  my ($self, @transactions) = @_;
  my $cb = pop @transactions;

  # Record each transaction callback
  my $txs = $self->txs;
  foreach my $tx (@transactions) {
    $txs->{$tx} = [ $tx, $cb ];
  }
  
  # Start them up...
  $self->spin(@transactions);

  return;
}


########################
# Mojo::Client overrides

sub _connect {
  my ($self, $tx, $host, $port) = @_;

  print STDERR ">!>> NEW CONNECTION $host $port\n";  
  my $conn = $self->connection_class->new(
    client   => $self,
    tx       => $tx,
    sockaddr => $host,
    sockport => $port,
  );
  $conn->connect;
  
  return $conn;
}

sub _reuse_connection {
  my ($self, $tx, $conn) = @_;
  
  $conn->tx($tx);
}

sub test_connection {
  my ($self, $conn) = @_;
  
  return $conn->connected && $conn->reuse;
}

sub _start_writting {
  my ($self, $tx) = @_;
  
  $tx->connection->start_write;
}


#####################
# Our version of spin

sub spin {
  my ($self, @transactions) = @_;
  my $txs = $self->txs;
  my %transaction;
  
  $self->_prepare_transactions(\%transaction, @transactions);

  # FIXME: trigger _check_expired_continue_request() when needed
  
  foreach my $tx (@transactions) {
    next unless $tx->is_finished;
    
    # Callback call
    my $reg = delete $txs->{$tx};
    $reg->[1]->($reg->[0]);
  }
  
  return;
}


####################
# Start the run loop

sub run {
  my $self = shift;
  
  my $guard = AnyEvent->condvar;
  $self->run_guard(sub { $guard->send });
  
  $guard->recv;
  
  $self->run_guard(undef);
  
  return;
}

sub stop {
  my ($self) = @_;
  my $rg = $self->run_guard;
  
  return unless $rg;
  return $rg->();
}

1;
