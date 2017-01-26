#!/usr/bin/env python
'''
This script uses the local system's DNS resolver and the ip-api to
find out information about a host or list of hosts. Output is to 
STDOUT in CSV format, so be sure to tee your output! Errors and other
log messages are written to STDERR.

Example usage:
  ./hostinfo.py -f list-of-hosts.txt 2>/err.log | tee results.csv
  ./hostinfo.py --host www.example.com 

References:
  http://ip-api.com/docs/
'''
import argparse
import re
import requests  # sudo pip install requests  # it will change your life
import socket
import sys


HEADER = 'Domain,IP,API Status,Country,Country Code,Region,Region Name,City,Zip,Lat,Lon,Timezone,ISP,Org,AS,api_query'


def check_host(host):
    r = requests.get('http://ip-api.com/json/'+host)
    return r.json()

def is_ip(ip):
    return re.match('^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$', ip) is not None

def get_all_hosts(host):
    ''' Build a list of all IP addresses that a domain resolves to, include CNAME records
    '''
    if is_ip(host):
        return [('', host)]

    to_do = [host]

    all_hosts = []  # (domain,ip)

    while to_do:
        for host in sorted(to_do):
            try:
                for (_, _, _, cname, server) in socket.getaddrinfo(host, 80):
                    if len(server) == 4:  # IPv6
                        server = server[:2]
                    if cname:
                        to_do.append(cname)
                    if (host, server[0]) not in all_hosts:
                        all_hosts.append((host, server[0]))
            except socket.gaierror:
                sys.stderr.write('Unknown host "{}"\n'.format(host))
            to_do.remove(host)


    return all_hosts

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default=None, help='A single host to check')
    parser.add_argument('-f', '--file', default=None, help='A newline-delimited file with a list of hosts to check')
    args = parser.parse_args()

    all_hosts = []

    # Get a list of IP's to query
    sys.stderr.write('[+] Building a list of hosts...\n')
    if args.host is not None:
        all_hosts = get_all_hosts(args.host)
    elif args.file is not None:
        with open(args.file) as f:
            for host in f.read().strip().split():
                all_hosts.extend(get_all_hosts(host))
    else:
        sys.stderr.write('[!] Include either a file or a single host to look up!\n')
        sys.exit(2)

    print HEADER
    for host,ip in all_hosts:
        r = requests.get('http://ip-api.com/csv/'+ip)
        record = '{},{},'.format(host, ip) + r.text

        try:
            print record
            sys.stdout.flush()
        except Exception as e:
            import base64
            sys.stderr.write('[!] Error printing record for {} ({}): {}\n'.format(host, ip, e))

    return

if __name__=='__main__':
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(1)

