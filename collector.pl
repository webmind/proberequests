#!/usr/bin/perl -w
use strict;
use JSON;
use Getopt::Long;
use Redis;
use IO::Socket::INET;


my %h;
$h{DEBUG} = 0;
$h{tsharkPath} = 'tshark';
$h{redis} = '127.0.0.1:6379';
$h{redisname} = 'probereqdb';
$h{redisdb} = 0;
$h{monitor} = 0;
$h{OSCPort} = 5555;
$h{OSCPeer} = '';
GetOptions (\%h, 'device=s', 'redis=s', 'redisname=s', 'redisdb=i', 'tsharkPath=s', 'OSCPort=i', 'OSCPeer=s', 'monitor', 'DEBUG');

if((!defined $h{device})) {
    print STDERR "Usage: $0 --device=<wireless device> <--redis=hostname:port> <--redisname=dbname> <--redisdb=dbnumber> <--tsharkPath=/path/to/tshark> <--monitor> <--DEBUG>\n\n";
    print STDERR 
"       --device        wireless device for monitoring
        --redis         redis host:port to connect to (default: 127.0.0.1:6379)
        --redisname     name of redisconnection (default: probereqdb)
        --redisdb       database number to use to store data in (default: 0)
        --tsharkPath    path to tshark binary (default: tshark)
        --OSCPort       port to sent OSC packets to (default: 5555)
        --OSCPeer       hostname to sent OSC packets to (default: off)
        --monitor       tell tshark to set device in monitor mode
        --DEBUG         provide debugging output
";
    exit 1;
}

## If we have an OSCPeer host, we start using OSC.
my $udp;
my $osc;
if($h{OSCPeer}) {
    require Protocol::OSC;
    $udp = IO::Socket::INET->new( PeerAddr => $h{OSCPeer}, PeerPort => $h{OSCPort}, Proto => 'udp', Type => SOCK_DGRAM ) || die "Cannot connect via UDP on $h{OSCPeer}:$h{OSCPort} ($!)\n";
    $osc = Protocol::OSC->new;
}

my $monitor_mode = '';
if(defined $h{monitor}) {
    $monitor_mode = '-I'
}

my $redis = Redis->new(server => $h{redis},
                       name   => $h{redisname});

$redis->select($h{redisdb});
print STDERR "Set Redis DB to: $h{redisdb}\n" if($h{DEBUG});

my $ssid;


open(my $tshark, "$h{tsharkPath} $monitor_mode -i $h{device} -n -l subtype probereq |") || die "Cannot spawn tshark process!\n";
while (my $line = <$tshark>) {
    chomp $line;
    #if($line = m/\d+\.\d+ ([a-zA-Z0-9:_]+).+SSID=([a-zA-ZÀ-ÿ0-9"\s\!\@\$\%\^\&\*\(\)\_\-\+\=\[\]\{\}\,\.\?\>\<]+)/) {
    #if($line =~ m/\d+\.\d+ ([a-zA-Z0-9:_]+).+SSID=(.+)$/) {
    if($line =~ m/\d+\.\d+ ([a-zA-Z0-9:_]+).+SN=([0-9]+),.+SSID=(.+)$/) {
        if($3 ne "Broadcast") { # Ignore broadcasts
            my $macAddress = $1;
            my $SN = $2;
            my $SSID = $3;
            my $struct = readredis($redis, $SSID);
            if(!defined($struct->{lastSeen}) or 
               !defined($struct->{macs}->{$macAddress}) or 
               (time - $struct->{lastSeen}) >= 1) {
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

                    ## Send SN
                    $udp->send($osc->message('/sn', 'i', $SN));
                    print "Send SN over OSC($h{OSCPeer}:$h{OSCPort}): $SN\n"
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
