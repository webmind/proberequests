#!/usr/bin/perl

use warnings;
use strict;

use POE qw(Component::Server::TCP Filter::HTTPD);
use HTTP::Response;
use JSON;
use Redis;
use Getopt::Long;

my %h;
$h{DEBUG} = 0;
$h{help} = 0;
$h{redis} = '127.0.0.1:6379';
$h{redisname} = 'probereqdb';
$h{redisdb} = 0;
$h{listenport} = 8088;
GetOptions (\%h, 'redis=s', 'redisname=s', 'redisdb=i', 'listenport=i', 'DEBUG', 'help');

if($h{help}) {
    print "Usage: $0 <--listenport=tcp-port> <--redis=hostname:port> <--redisname=dbname> <--redisdb=dbnumber>\n\n";
    exit 1;
}


# Spawn a web server on port 8088 

POE::Component::Server::TCP->new(
  Alias        => "web_server",
  Port         => $h{listenport},
  ClientFilter => 'POE::Filter::HTTPD',

  # The ClientInput function is called to deal with client input.
  # Because this server uses POE::Filter::HTTPD to parse input,
  # ClientInput will receive HTTP requests.

  ClientInput => sub {
    my ($kernel, $heap, $request) = @_[KERNEL, HEAP, ARG0];

    # Filter::HTTPD sometimes generates HTTP::Response objects.
    # They indicate (and contain the response for) errors that occur
    # while parsing the client's HTTP request.  It's easiest to send
    # the responses as they are and finish up.

    if ($request->isa("HTTP::Response")) {
      $heap->{client}->put($request);
      $kernel->yield("shutdown");
      return;
    }

    # The request is real and fully formed.  Build content based on
    # it.  Insert your favorite template module here, or write your
    # own. :)

    my $request_fields = '';
    $request->headers()->scan(
      sub {
        my ($header, $value) = @_;
        $request_fields .= "<tr><td>$header</td><td>$value</td></tr>";
      }
    );

    my $response = HTTP::Response->new(200);
    $response->push_header('Content-type', 'application/json');
    $response->push_header('Access-Control-Allow-Origin', '*');

    my $redis = Redis->new(server => $h{redis},
                           name   => $h{redisname});

    $redis->select($h{redisdb}) if($h{redisdb});    

    my @keys = $redis->keys('*');
        
    my %db;
    my @jvalues = $redis->mget(@keys);
    
    # Convert all json blobs to hashref structures
    my @values = map { JSON->new->allow_nonref->decode($_); } @jvalues;

    # Merge into the %db hash
    @db{@keys} = @values;

    my $json = JSON->new->allow_nonref->pretty->encode(\%db);

    $response->content($json);

    # Once the content has been built, send it back to the client
    # and schedule a shutdown.

    $heap->{client}->put($response);
    $kernel->yield("shutdown");
  }
);

# Start POE.  This will run the server until it exits.

$poe_kernel->run();
exit 0;
