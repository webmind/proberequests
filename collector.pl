#!/usr/bin/perl -w
use strict;
use JSON;
use Getopt::Long;
use Redis;
use IO::Socket::INET;

use constant DEBUG  => 1;
use constant DEBUG2 => 2;
use constant DEBUG3 => 3;

my %h;
$h{DEBUG} = 1;
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
    log_message(DEBUG, "Prepared UDP for sending OSC messages to $h{OSCPeer}:$h{OSCPort}");
}

my $monitor_mode = '';
if(defined $h{monitor}) {
    $monitor_mode = '-I'
}

my $redis = Redis->new(server => $h{redis},
                       name   => $h{redisname});

$redis->select($h{redisdb});
log_message(DEBUG, "Set Redis DB to: $h{redisdb}");

my $ssid;

my $fields = '-e wlan.sa -e wlan.da -e wlan.ssid';
my $tshark_command = "$h{tsharkPath} $monitor_mode -q -i $h{device} -T ek $fields -n -l subtype probereq";

log_message(DEBUG2, "Running [$tshark_command]");
open(my $tshark, "$tshark_command |") or die "Cannot spawn tshark process($!): $tshark_command\n";
while (my $line = <$tshark>) {
    next if($line =~ /^\s*$/);
    chomp $line;
    log_message(DEBUG3, $line);
    my $blob = safe_json_decode($line);

    if(defined($blob->{layers}) and 
       defined($blob->{layers}->{wlan_sa}) and 
       defined($blob->{layers}->{wlan_da}) and
       defined($blob->{layers}->{wlan_ssid})) {
        my $macAddress = $blob->{layers}->{wlan_sa}->[0];
        my $SSID = $blob->{layers}->{wlan_ssid}->[0];
        if($SSID ne '') {

            my $struct = readredis($redis, $SSID);
            if(!defined($struct->{lastSeen}) or 
               !defined($struct->{macs}->{$macAddress}) or 
               (time - $struct->{lastSeen}) >= 1) {

                if($h{DEBUG} and !defined($struct->{lastSeen})) {
                    log_message(DEBUG, "Spotted new $SSID from $macAddress");
                } elsif($h{DEBUG} and !defined($struct->{macs}->{$macAddress})) {
                    log_message(DEBUG, "Spotted new $macAddress for $SSID");
                } elsif($h{DEBUG}) {
                    log_message(DEBUG, "Spotted $SSID from $macAddress");
                }

                ## Send OSC first if needed
                if($udp && $osc) {
                    ## Send SSID
                    my @ssidblob = map({ord} split(//, $SSID));
                    my $ssidblobtypes = join('', map({'i'} split(//, $SSID)));
                    $udp->send($osc->message('/network', $ssidblobtypes, @ssidblob));
                    log_message(DEBUG, "Send network over OSC($h{OSCPeer}:$h{OSCPort}): $SSID");

                    ## Send mac
                    my @macblob = map({hex} split(/:/, $macAddress));
                    my $macblobtypes = join('', map({'i'} split(/:/, $macAddress)));
                    $udp->send($osc->message('/mac', $macblobtypes, @macblob));
                    log_message(DEBUG, "Send mac over OSC($h{OSCPeer}:$h{OSCPort}): $macAddress");

                    ## Send SN
                    #$udp->send($osc->message('/sn', 'i', $SN));
                    #print "Send SN over OSC($h{OSCPeer}:$h{OSCPort}): $SN\n"
                    #    if($h{DEBUG});

                }

                $struct->{firstSeen} = time if(!defined($struct->{lastseen}));
                $struct->{macs}->{$macAddress}++;
                $struct->{name} = $SSID;
                $struct->{count}++;
                $struct->{lastSeen} = time;

                writeredis($redis, $SSID, $struct);
            } else {
                my $age = time - $struct->{lastSeen};
                log_message(DEBUG, "Double of $SSID? (lastseen: $struct->{lastSeen}, maccount: $struct->{macs}->{$macAddress},  age: $age)\n");
            }
        } else {
            log_message(DEBUG, "Broadcast request from $blob->{layers}->{wlan_sa}->[0]");
        }
    } elsif(defined($blob->{index})) {
        log_message(DEBUG3, "Irrelevant index data from tshark: [$line]");
    } else {
        log_message(DEBUG2, "Unknown packet: [$line]");
#        use Data::Dumper;
#        print Dumper $blob;
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

sub log_message {
    my ($level, @messages) = @_;
    if($level <= $h{DEBUG}) {
        for my $message (@messages) {
            print STDERR "($level:$h{DEBUG}) $message\n" if($level <= $h{DEBUG});
        }
        return @messages if wantarray;
        return $level;
    }
    return;
}

# standard json decode croaks on incorrect json, we want to continue
sub safe_json_decode {
    my ($json) = @_;
    my $decoded;
    eval {
        $decoded = decode_json($json);
    };
    if($@) {
        log_message(DEBUG, "JSON Decoding error: [$@]");
        log_message(DEBUG2, "Failed JSON data: [$json]");
    }
    return $decoded;
}
