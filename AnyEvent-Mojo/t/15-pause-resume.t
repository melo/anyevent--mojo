#!perl -T

use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Deep;
use AnyEvent::Mojo::Server;

eval { require AnyEvent::HTTP; };
plan skip_all => 'Pause/Resume tests require the AnyEvent::HTTP module'
  if $@;

plan tests => 23;

my $port = 4000 + $$ % 10000;
my $pid = start_server($port);

ok($port, "Server is up at $port, pid $pid");

my $stop = AnyEvent->condvar;


# It's my server, I'm evil
my $conns = 10;
{
  no warnings;
  $AnyEvent::HTTP::MAX_PER_HOST = $conns;
}

my $now = time;
my $count;
my $active = 0;
while ($count++ < $conns) {
  my $sleep_for = 11 - $count;
  $active++;   
  AnyEvent::HTTP::http_get("http://127.0.0.1:$port/$sleep_for", sub {
    my ($data) = @_;
    
    is(
      $data, "Slept for $sleep_for",
      "Request sleep_for $sleep_for completed"
    );
    ok(time()-$now-1 <= $sleep_for, 'Timming ok');
    
    $stop->send if --$active == 0; 
  });
}

diag('Requests sent, waiting for replies');
$stop->recv;

stop_server($pid);


##########################################
# Start an child process to run the server

sub start_server {
  my $port = shift;
  
  my $pid = fork();
  die "Could not fork: $!" unless defined $pid;

  # Parent
  if ($pid) {
    diag("Waiting for server to start...");

    my $done = AnyEvent->condvar;
    my $checker; $checker = AnyEvent->timer(
      after => 1,
      interval => 2,
      cb => sub {
        AnyEvent::HTTP::http_get(
          "http://127.0.0.1:$port/0.1",
          timeout => 1,
          cb => sub {
            undef $checker;
            $done->send;
          },
        );
      },
    );
    
    $done->recv; # Wait for the server to start...
    
    return $pid;
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
  my $pid = shift;
  
  return unless $pid;
  
  is(kill(15, $pid), 1, "killed one"); # sigterm
  is(waitpid($pid, 0), $pid, "waipid ok");

  return;
}


1;