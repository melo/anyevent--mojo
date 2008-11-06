package MyTestServer;

use strict;
use warnings;
use AnyEvent;
use base 'AnyEvent::Mojo::Server';
use AnyEvent::HTTP;
use Test::More;

BEGIN {
  __PACKAGE__->attr('banner_called');
}

sub startup_banner {
  my $self = shift;
  
  $self->banner_called([$self->host, $self->port]);
  return $self->SUPER::startup_banner(@_);
}


###################################
# Fork off a server for us, please?

sub start_server {
  my $class = shift;
  my $port = shift;
  my $cb = pop;
  my %args = @_;

  # Default port: random
  $port ||= 4000 + $$ % 10000;
    
  my $pid = fork();
  die "Could not fork: $!" unless defined $pid;

  # Parent
  if ($pid) {
    diag("Waiting for server to start...");
     
    my $count = 0;
    my $done = AnyEvent->condvar;
    my $checker; $checker = AnyEvent->timer(
      after => 1,
      interval => 2,
      cb => sub {
        AnyEvent::HTTP::http_get(
          "http://127.0.0.1:$port/",
          timeout => 1,
          cb => sub {
            if (!defined($_[0])) {
              $count++;
              die "Could not start test server!\n" if $count > 10;
              return;
            }
            undef $checker;
            $done->send;
          },
        );
      },
    );
    
    $done->recv; # Wait for the server to start...
    
    return wantarray? ($pid, $port) : $pid;
  }


  # Child
  my $server = AnyEvent::Mojo::Server->new;
  $server->keep_alive_timeout($args{keep_alive_timeout})
      if defined $args{keep_alive_timeout};
  $server->port($port)->handler_cb($cb);
  
  $server->run;
  exit(0);
}

sub stop_server {
  my ($class, $pid) = @_;
  
  return unless $pid;
  
  is(kill(15, $pid), 1, "killed one"); # sigterm
  is(waitpid($pid, 0), $pid, "waipid ok");

  return;
}

1;