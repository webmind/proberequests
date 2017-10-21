#!/usr/bin/perl -w
use strict;
use JSON;
use Redis;
use Getopt::Long;


my %h;
$h{DEBUG} = 0;
$h{help} = 0;
$h{redis} = '127.0.0.1:6379';
$h{redisname} = 'probereqdb';
$h{redisdb} = 0;
GetOptions (\%h, 'redis=s', 'redisname=s', 'redisdb=i', 'output=s', 'DEBUG', 'help');

if($h{help}) {
    print "Usage: $0 <--output=filename> <--redis=hostname:port> <--redisname=dbname> <--redisdb=dbnumber>\n\n";
    exit 1;
}

my $redis = Redis->new(server => $h{redis},
                       name   => $h{redisname});

$redis->select($h{redisdb});


my @keys = $redis->keys('*');

my %db;
my @jvalues = $redis->mget(@keys);

# Convert all json blobs to hashref structures
my @values = map { JSON->new->allow_nonref->decode($_); } @jvalues;

# Merge into the %db hash
@db{@keys} = @values;

my $json = JSON->new->allow_nonref->pretty->encode(\%db);

if(defined $h{output}) {
    open(my $fh, '>', $h{output}) or die "Cannot open $h{output} for writing: $!";
    print $fh $json;
    close($fh);
} else {
    print $json;
}

