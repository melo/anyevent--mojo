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
  my ($class, $port) = @_;
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
          "http://127.0.0.1:$port/0.1",
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
  $server->keep_alive_timeout(30);
  $server->port($port)->handler_cb(sub {
    my ($srv, $tx) = @_;
    my $conn = $tx->connection;
    my $res  = $tx->res;
    my $url  = $tx->req->url;
    my ($delay) = $url =~ m{/([\d.]+)};
    
    $res->code(200);
    $res->headers->content_type('text/plain');
    
    if ($delay) {
      my $body = "Slept for $delay";
      $res->body($body);

      my $resume_cb = $conn->pause;
      my $t; $t = AnyEvent->timer( after => $delay, cb => sub {
        # Resume the transaction
        $resume_cb->();

        # Timer no longer needed
        undef $t;
      });
    }
    else {
      $res->body('Hi!');
    }
        
    return;
  });
  
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