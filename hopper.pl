#!/usr/bin/perl -w
use strict;
use Getopt::Long;
## Wifi channel hopper

my %h = ();

$h{iwPath} = '/sbin/iw';
$h{iwlistPath} = '/sbin/iwlist';
$h{DEBUG} = 1;
GetOptions (\%h, 'device=s@');

if(!defined $h{device}) {
    print "Usage: $0 --device=<wireless device>\n\n";
    exit 1;
}



for(@{$h{device}}) {
    print "Channel hopping with $_...\n";
}

my %device;

for my $dev (@{$h{device}}) {
    print "Collecting channel list for $dev\n";
    for my $line (`$h{iwlistPath} $dev frequency`) {
        if($line =~ /Channel\s+([0-9]+)\s+:\s+([0-9.]+)\s+([^\s]+)/i) {
            my ($chan, $freq, $unit) = ($1, $2, $3);
#            $device{$dev}->{channel}->{$chan} = $freq;
            push(@{$device{$dev}->{channels}}, $chan);
            if($h{DEBUG}) {
                print "DEBUG: $chan = $freq\n";
            }
        }
    }
    print "Found ". @{$device{$dev}->{channels}} . " channels...\n";
}

my %channels;

while(1) {
    for my $dev (keys %device) {
        print "Hopping on $dev\n" if($h{DEBUG});
        !defined($device{$dev}->{cur_channel}) ? 
            $device{$dev}->{cur_channel} = 0 : 
            $device{$dev}->{cur_channel}++;

        if($device{$dev}->{cur_channel} > $#{ $device{$dev}->{channels} }) {
            $device{$dev}->{cur_channel} = 0;
            print "Full circle on $dev, going back to 0\n" if($h{DEBUG});
        }

        for my $chan (grep { $channels{$_} =~ /^$dev$/ } keys(%{channels})) {
            print "  Unlocking $chan from $dev\n" if($h{DEBUG});
            delete $channels{$chan};
        }

        while(defined $channels{ $device{$dev}->{channels}->[ $device{$dev}->{cur_channel} ] }){
            if($h{DEBUG}) {
                print "  $device{$dev}->{channels}->[ $device{$dev}->{cur_channel} ] in use by $channels{ $device{$dev}->{channels}->[ $device{$dev}->{cur_channel} ] }\n";
            }
            $device{$dev}->{cur_channel}++;
            if($device{$dev}->{cur_channel} > $#{ $device{$dev}->{channels} }) {
                $device{$dev}->{cur_channel} = 0;
                print "Full circle on $dev, going back to 0\n" if($h{DEBUG});
            }
        }


        my $channel = $device{$dev}->{channels}->[ $device{$dev}->{cur_channel} ];
        $channels{$channel} = $dev;
        
        print "  Setting $dev to $channel\n" if($h{DEBUG});
        system("$h{iwPath} dev $dev set channel $channel");
        my $devInfo = `$h{iwPath} dev $dev info`;
        my ($seenChannel) = $devInfo =~ /channel\s+([0-9]+)/;
        if(!defined $seenChannel) {
            print STDERR "  ERROR: Cannot read channel: $devInfo\n";
            exit 1;
        } elsif($seenChannel != $channel) {
            print STDERR "  WARNING: channel setting might not have any effect (setting $channel, reading $seenChannel)\n";

        }
        if($h{DEBUG}) {
            print "  DEBUG: setting $channel, reading $seenChannel\n";
        }
    }
    sleep 1;
}
