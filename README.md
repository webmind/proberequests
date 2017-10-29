# proberequests
Collect proberequests from wifi
the redis-server dependency here means a redis server needs to be available, it does not have to be on the same machine.

This data can then be visualised by https://github.com/liliakai/proberequests

## hopper.pl 
Channels hops wifi devices, takes multiple --device=<name> arguments
will insure no wifi device listens on the same channel, if there are more devices than channels, extra devices will not be set.
Example: ./hopper.pl --device=mon1 --device=mon2
Depends on:
* perl
* wireless-tools

## collector.pl
Collect probe-requests from a wifi device (needs monitoring mode)
Example: ./collector --device=mon1
Depends on:
* redis-server
* tshark
* perl
* libredis-perl (Redis)
* libjson-perl (JSON)
* (optional) libprotocol-osc-perl (Protocol::OSC)

## redis2json.pl
Dumps the redis database to json, either to STDOUT or a file
Example: ./redis2json.pl --output=dump.json
Depends on:
* redis-server
* perl
* libredis-perl (Redis)
* libjson-perl (JSON)

## redis-httpd.pl
Serves the redis database as JSON via a webserver
Example: ./redis-httpd.pl --listenport=8080
Depends on:
* redis-server
* perl
* libredis-perl (Redis)
* libjson-perl (JSON)
* libpoe-perl (POE:Component::Server::TCP, POE::Filter::HTTPD)
* libhttp-message-perl (HTTP::Response)

## redis-dancer-httpd.pl
Serves the redis database as JSON via a webserver
Example: ./redis-httpd.pl --listenport=8080
Depends on:
* redis-server
* perl
* libredis-perl (Redis)
* libjson-perl (JSON)
* libdancer2-perl (Dancer2)

Can handle webrequests such as:
/all                # all keys/ssids
/match/*foo*        # glob matched keys/ssids
/exclude/key1/key2/ # blacklisting keys/ssids

## Preparing wireless devices
* sudo /sbin/iw phy <phy-device-name> interface add <name-of-monitor-device> type monitor
* sudo /sbin/ip link set up dev <name-of-monitor-device>
