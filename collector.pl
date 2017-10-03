#!/usr/bin/perl -w
use strict;
use JSON;
use Getopt::Long;
use Redis;

my %h;
$h{DEBUG} = 0;
$h{tsharkPath} = '/usr/bin/tshark';
$h{redis} = '127.0.0.1:6379';
$h{redisname} = 'probereqdb';
GetOptions (\%h, 'device=s', 'redis=s', 'tsharkPath=s', 'DEBUG');

if((!defined $h{device})) {
    print STDERR "Usage: $0 --device=<wireless device> <--redis=hostname:port> <--redisname=dbname> <--tsharkPath=/path/to/tshark> <--DEBUG>\n\n";
    exit 1;
}

my $redis = Redis->new(server => $h{redis},
                       name   => $h{redisname});

my $ssid;


open(my $tshark, "$h{tsharkPath} -i $h{device} -n -l subtype probereq |") || die "Cannot spawn tshark process!\n";
while (my $line = <$tshark>) {
    chomp $line;
    #if($line = m/\d+\.\d+ ([a-zA-Z0-9:_]+).+SSID=([a-zA-ZÀ-ÿ0-9"\s\!\@\$\%\^\&\*\(\)\_\-\+\=\[\]\{\}\,\.\?\>\<]+)/) {
    if($line =~ m/\d+\.\d+ ([a-zA-Z0-9:_]+).+SSID=(.+)$/) {
        if($2 ne "Broadcast") { # Ignore broadcasts
            my $macAddress = $1;
            my $SSID = $2;
            my $struct = readredis($redis, $SSID);
            if(!defined($struct->{lastseen}) or 
               !defined($struct->{macs}->{$macAddress}) or 
               ($struct->{lastseen} - time) >= 1) {

                $struct->{macs}->{$macAddress}++;
                $struct->{name} = $SSID;
                $struct->{count}++;
                $struct->{lastSeen} = time;
                writeredis($redis, $SSID, $struct);
                print "Spotted $SSID from $macAddress\n" if($h{DEBUG});
            } else {
                print "Double of $SSID?\n" if($h{DEBUG});
            }
        }
    } elsif($h{DEBUG}) {
        print STDERR "HUH?: $line\n";
    }

}
close($tshark);


sub writeredis {
    my ($robject, $key, $struct) = @_;
    my $json = JSON->new->allow_nonref->pretty->encode($struct);
    $robject->set($key => $json);
}

sub readredis {
    my ($robject, $key) = @_;
    my $json = $robject->get($key) or return {};
    my $struct = JSON->new->allow_nonref->decode($json) or warn "Incorrect data: [$json]";
    return $struct;
}
