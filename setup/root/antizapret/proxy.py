#!/usr/bin/env -S python3 -u
# -*- coding: utf-8 -*-

from __future__ import print_function
import socket,struct,subprocess,sys,time,argparse,threading
from collections import deque
from ipaddress import IPv4Network
from dnslib import DNSRecord,RCODE,QTYPE,A
from dnslib.server import DNSServer,DNSHandler,BaseResolver,DNSLogger

class ProxyResolver(BaseResolver):
    """
        Proxy resolver - passes all requests to upstream DNS server and
        returns response

        Note that the request/response will be each be decoded/re-encoded
        twice:

        a) Request packet received by DNSHandler and parsed into DNSRecord
        b) DNSRecord passed to ProxyResolver, serialised back into packet
           and sent to upstream DNS server
        c) Upstream DNS server returns response packet which is parsed into
           DNSRecord
        d) ProxyResolver returns DNSRecord to DNSHandler which re-serialises
           this into packet and returns to client

        In practice this is actually fairly useful for testing but for a
        'real' transparent proxy option the DNSHandler logic needs to be
        modified (see PassthroughDNSHandler)
    """
    def __init__(self,address,port,timeout,ip_range,cleanup_interval,cleanup_expiry):
        self.ip_pool = deque([str(x) for x in IPv4Network(ip_range).hosts()])
        self.ip_map = {}
        # Loading existing mappings
        rule = "iptables -w -t nat -S ANTIZAPRET-MAPPING | awk '{if (NR<2) {next}; print substr($4, 1, length($4)-3), $8}'"
        mappings = subprocess.run(rule,shell=True,check=True,capture_output=True,text=True).stdout.splitlines()
        current_time = time.time()
        for mapping in mappings:
            fake_ip,real_ip = mapping.split(" ")
            if not self.mapping_ip(real_ip,fake_ip,current_time):
                rule = "iptables -w -t nat -F ANTIZAPRET-MAPPING"
                subprocess.run(rule,shell=True,check=True)
                sys.exit(1)
        print(f"Loaded: {len(mappings)} fake IPs")
        self.address = address
        self.port = port
        self.timeout = timeout
        self.cleanup_interval = cleanup_interval
        self.cleanup_expiry = cleanup_expiry
        self.lock = threading.Lock()
        # Start thread for cleanup fake IPs
        threading.Thread(target=self.cleanup_fake_ips_worker,daemon=True).start()

    def get_fake_ip(self,real_ip):
        with self.lock:
            entry = self.ip_map.get(real_ip)
            if entry:
                entry["last_access"] = time.time()
                return entry["fake_ip"]
            else:
                try:
                    fake_ip = self.ip_pool.popleft()
                except IndexError:
                    print("ERROR: No fake IP left")
                    return None
                self.ip_map[real_ip] = {"fake_ip": fake_ip,"last_access": time.time()}
                rule = f"iptables -w -t nat -A ANTIZAPRET-MAPPING -d {fake_ip} -j DNAT --to {real_ip}"
                subprocess.run(rule,shell=True,check=True)
                #print(f"Mapping: {fake_ip} to {real_ip}")
                return fake_ip

    def mapping_ip(self,real_ip,fake_ip,last_access):
        if self.ip_map.get(real_ip):
            print(f"ERROR: Real IP {real_ip} is already mapped")
            return False
        try:
            self.ip_pool.remove(fake_ip)
            self.ip_map[real_ip] = {"fake_ip": fake_ip,"last_access": last_access}
            #print(f"Mapping: {fake_ip} to {real_ip}")
        except ValueError:
            print(f"ERROR: Fake IP {fake_ip} not in fake IP pool")
            return False
        return True

    def cleanup_fake_ips_worker(self):
        while True:
            time.sleep(self.cleanup_interval)
            self.cleanup_fake_ips()

    def cleanup_fake_ips(self):
        with self.lock:
            current_time = time.time()
            cleanup_ips = []
            rules = ["*nat"]
            for key,entry in self.ip_map.items():
                if current_time - entry["last_access"] > self.cleanup_expiry:
                    cleanup_ips.append((key,entry["fake_ip"]))
            for real_ip,fake_ip in cleanup_ips:
                self.ip_pool.appendleft(fake_ip)
                del self.ip_map[real_ip]
                rules.append(f"-D ANTIZAPRET-MAPPING -d {fake_ip} -j DNAT --to {real_ip}")
                #print(f"Unmapping: {fake_ip} to {real_ip}")
            rules.append("COMMIT")
            subprocess.run(["iptables-restore","-w","-n"],input="\n".join(rules).encode(),check=True)
            print(f"Cleaned: {len(cleanup_ips)} expired fake IPs")

    def resolve(self,request,handler):
        try:
            if handler.protocol == "udp":
                proxy_r = request.send(self.address,self.port,timeout=self.timeout)
            else:
                proxy_r = request.send(self.address,self.port,tcp=True,timeout=self.timeout)
            reply = DNSRecord.parse(proxy_r)
            if request.q.qtype == QTYPE.A:
                #print("GOT A")
                newrr = []
                for record in reply.rr:
                    if record.rtype != QTYPE.A:
                        continue
                    newrr.append(record)
                reply.rr = newrr
                for record in reply.rr:
                    #print(dir(record))
                    #print(type(record.rdata))
                    real_ip = str(record.rdata)
                    fake_ip = self.get_fake_ip(real_ip)
                    if not fake_ip:
                        reply = request.reply()
                        reply.header.rcode = getattr(RCODE,"SERVFAIL")
                        return reply
                    record.rdata = A(fake_ip)
                    record.rname = request.q.qname
                    record.ttl = 300
                    #print(a.rdata)
                return reply
            #print(reply)
        except socket.timeout:
            reply = request.reply()
            reply.header.rcode = getattr(RCODE,"SERVFAIL")
        return reply

class PassthroughDNSHandler(DNSHandler):
    """
        Modify DNSHandler logic (get_reply method) to send directly to
        upstream DNS server rather then decoding/encoding packet and
        passing to Resolver (The request/response packets are still
        parsed and logged but this is not inline)
    """
    def get_reply(self,data):
        host,port = self.server.resolver.address,self.server.resolver.port
        request = DNSRecord.parse(data)
        #self.log_request(request)
        if self.protocol == "tcp":
            data = struct.pack("!H",len(data)) + data
            response = send_tcp(data,host,port)
            response = response[2:]
        else:
            response = send_udp(data,host,port)
        reply = DNSRecord.parse(response)
        #self.log_reply(reply)
        return response

def send_tcp(data,host,port):
    """
        Helper function to send/receive DNS TCP request
        (in/out packets will have prepended TCP length header)
    """
    sock = socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    sock.connect((host,port))
    sock.sendall(data)
    response = sock.recv(8192)
    length = struct.unpack("!H",bytes(response[:2]))[0]
    while len(response) - 2 < length:
        response += sock.recv(8192)
    sock.close()
    return response

def send_udp(data,host,port):
    """
        Helper function to send/receive DNS UDP request
    """
    sock = socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    sock.sendto(data,(host,port))
    response,server = sock.recvfrom(8192)
    sock.close()
    return response

if __name__ == "__main__":
    p = argparse.ArgumentParser(description="DNS Proxy")
    p.add_argument("--port","-p",type=int,default=53,
                    metavar="<port>",
                    help="Local proxy port (default:53)")
    p.add_argument("--address","-a",default="127.0.0.2",
                    metavar="<address>",
                    help="Local proxy listen address (default:all)")
    p.add_argument("--upstream","-u",default="127.0.0.1:53",
                    metavar="<dns server:port>",
                    help="Upstream DNS server:port (default:127.0.0.1:53)")
    p.add_argument("--tcp",action="store_true",default=False,
                    help="TCP proxy (default: UDP only)")
    p.add_argument("--timeout","-o",type=float,default=5,
                    metavar="<timeout>",
                    help="Upstream timeout (default: 5s)")
    p.add_argument("--passthrough",action="store_true",default=False,
                    help="Dont decode/re-encode request/response (default: off)")
    p.add_argument("--log",default="truncated,error",
                    help="Log hooks to enable (default: +truncated,+error,-request,-reply,-recv,-send,-data)")
    p.add_argument("--log-prefix",action="store_true",default=False,
                    help="Log prefix (timestamp/handler/resolver) (default: False)")
    p.add_argument("--ip-range",default="10.30.0.0/15",
                    metavar="<ip/mask>",
                    help="Fake IP range (default:10.30.0.0/15)")
    p.add_argument("--cleanup-interval","-c",type=int,default=3600,
                    metavar="<seconds>",
                    help="Seconds between fake IP cleanup runs (default: 3600)")
    p.add_argument("--cleanup-expiry","-e",type=int,default=7200,
                    metavar="<seconds>",
                    help="Seconds of inactivity before fake IP is removed (default: 7200)")
    args = p.parse_args()
    args.dns,_,args.dns_port = args.upstream.partition(":")
    args.dns_port = int(args.dns_port or 53)
    print("Starting Proxy Resolver (%s:%d -> %s:%d) [%s]" % (
                        args.address or "*",args.port,
                        args.dns,args.dns_port,
                        "UDP/TCP" if args.tcp else "UDP"))
    resolver = ProxyResolver(args.dns,args.dns_port,args.timeout,args.ip_range,args.cleanup_interval,args.cleanup_expiry)
    handler = PassthroughDNSHandler if args.passthrough else DNSHandler
    logger = DNSLogger(args.log,args.log_prefix)
    udp_server = DNSServer(resolver,
                           port=args.port,
                           address=args.address,
                           logger=logger,
                           handler=handler)
    udp_server.start_thread()
    if args.tcp:
        tcp_server = DNSServer(resolver,
                               port=args.port,
                               address=args.address,
                               tcp=True,
                               logger=logger,
                               handler=handler)
        tcp_server.start_thread()
    while udp_server.isAlive():
        time.sleep(1)