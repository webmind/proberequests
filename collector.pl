#!/usr/bin/perl -w
use strict;
use JSON;
use Getopt::Long;
use Redis;
use Protocol::OSC;
use IO::Socket::INET;


my %h;
$h{DEBUG} = 0;
$h{tsharkPath} = '/usr/bin/tshark';
$h{redis} = '127.0.0.1:6379';
$h{redisname} = 'probereqdb';
$h{OSCPort} = 5555;
$h{OSCPeer} = '';
GetOptions (\%h, 'device=s', 'redis=s', 'tsharkPath=s', 'OSCPort=i', 'OSCPeer=s', 'DEBUG');

if((!defined $h{device})) {
    print STDERR "Usage: $0 --device=<wireless device> <--redis=hostname:port> <--redisname=dbname> <--tsharkPath=/path/to/tshark> <--DEBUG>\n\n";
    exit 1;
}

## If we have an OSCPeer host, we start using OSC.
my $udp;
my $osc;
if($h{OSCPeer}) {
    $udp = IO::Socket::INET->new( PeerAddr => $h{OSCPeer}, PeerPort => $h{OSCPort}, Proto => 'udp', Type => SOCK_DGRAM) || die "Cannot connect via UDP on $h{OSCPeer}:$h{OSCPort} ($!)\n";
    $osc = Protocol::OSC->new;
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
            if(!defined($struct->{lastSeen}) or 
               !defined($struct->{macs}->{$macAddress}) or 
               ($struct->{lastSeen} - time) >= 1) {
                print "Spotted $SSID from $macAddress\n" if($h{DEBUG});

                ## Send OSC first if needed
                if($udp && $osc) {
                    ## Send SSID
                    my @ssidblob = map({ord} split(//, $SSID));
                    my $ssidblobtypes = join('', map({'i'} split(//, $SSID)));
                    $udp->send($osc->message('/network', $ssidblobtypes, @ssidblob));
                    print "Send network over OSC($h{OSCPeer}:$h{OSCPort}): $SSID\n"
                        if($h{DEBUG});
                    
                    ## Send mac
                    my @macblob = map({hex} split(/:/, $macAddress));
                    my $macblobtypes = join('', map({'i'} split(/:/, $macAddress)));
                    $udp->send($osc->message('/mac', $macblobtypes, @macblob));
                    print "Send mac over OSC($h{OSCPeer}:$h{OSCPort}): $macAddress\n"
                        if($h{DEBUG});
                }

                $struct->{firstSeen} = time if(!defined($struct->{lastseen}));
                $struct->{macs}->{$macAddress}++;
                $struct->{name} = $SSID;
                $struct->{count}++;
                $struct->{lastSeen} = time;
                writeredis($redis, $SSID, $struct);
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
