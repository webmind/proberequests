#!/usr/bin/perl -w
use strict;
use JSON;
use Redis;
use Getopt::Long;
use Dancer2;
$|++;
set port => 80;
set server => '12';

my %h;
$h{DEBUG} = 0;
$h{help} = 0;
$h{redis} = '127.0.0.1:6379';
$h{redisname} = 'probereqdb';
$h{redisdb} = 0;
$h{listenport} = 8088;
$h{listenhost} = '0.0.0.0';
GetOptions (\%h, 'redis=s', 'redisname=s', 'redisdb=i', 'listenport=i', 'listenhost=s', 'DEBUG', 'help');

if($h{help}) {
    print "Usage: $0 <--listenport=tcp-port> <--redis=hostname:port> <--redisname=dbname> <--redisdb=dbnumber>\n\n";
    exit 1;
}

set port    => $h{listenport};
set server  => $h{listenhost};
 
get '/all' => sub {
    print "Giving All\n" if($h{DEBUG});
    my $db = redis2hash('*');
    set content_type => 'application/json';
    set header 'Access-Control-Allow-Origin' => '*';
    return JSON->new->allow_nonref->pretty->encode($db);
};

get '/match/:blob' => sub { 
    my $blob = route_parameters->get('blob');
    print "Giving keys matching: $blob\n" if($h{DEBUG});
    my $db = redis2hash($blob);
    set content_type => 'application/json';
    set header 'Access-Control-Allow-Origin' => '*';
    return JSON->new->allow_nonref->pretty->encode($db);
};

get '/exclude/**' => sub {
    my ($splat) = splat;
    my @blacklist = @{$splat};
    print "blacklist: ", join(',', @blacklist), "\n" if($h{DEBUG});
    my %db = redis2hash('*');
    for my $key (keys %db) {
        if(grep { $_ eq $key } @blacklist) {
            delete($db{$key}); 
            print "deleted $key\n";
            
        }
    }

    set content_type => 'application/json';
    set header 'Access-Control-Allow-Origin' => '*';
    return JSON->new->allow_nonref->pretty->encode(\%db);

};


#get '' => sub { }
 
start;



=item redis2hash($key)

    Requests all keys matching $key (blob) from redis database

=cut

sub redis2hash {
    my ($keys) = @_;
    my $redis = Redis->new(server => $h{redis},
                           name   => $h{redisname});

    $redis->select($h{redisdb}) if($h{redisdb});

    my @keys = $redis->keys($keys);

    my %db;
    my @jvalues = $redis->mget(@keys); # FIXME: what to do when there are no keys 

    # Convert all json blobs to hashref structures
    my @values = map { JSON->new->allow_nonref->decode($_); } @jvalues;

    # Merge into the %db hash
    @db{@keys} = @values;
    return %db if wantarray;
    return \%db;
}
