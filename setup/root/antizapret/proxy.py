#!/usr/bin/env -S python3 -u
# -*- coding: utf-8 -*-

import subprocess,time,argparse,threading,copy,os
from ipaddress import IPv4Network
from dnslib import DNSRecord,RCODE,QTYPE,A
from dnslib.server import DNSServer,DNSHandler,BaseResolver,DNSLogger,TCPServer

class ProxyResolver(BaseResolver):
    def __init__(self,address,port,timeout,ip_range,ttl):
        self._env=os.environ.copy()
        self.ip_pool={str(x) for x in IPv4Network(ip_range).hosts()}
        self.ip_map={}
        # Loading existing mappings
        result=subprocess.run(["/usr/sbin/iptables","-w","-t","nat","-S","ANTIZAPRET-MAPPING"],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,check=True,env=self._env)
        now=time.time()
        for line in result.stdout.splitlines():
            parts=line.split()
            if len(parts) < 8:
                continue
            fake_ip=parts[3].split("/")[0]
            real_ip=parts[7]
            if not self.mapping_ip(real_ip,fake_ip,now):
                print("Restarting: Invalid loaded fake IPs mappings")
                try:
                    subprocess.run(["/usr/sbin/iptables","-w","-t","nat","-F","ANTIZAPRET-MAPPING"],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
                finally:
                    os._exit(1)
        print(f"Loaded: {len(self.ip_map)} fake IPs")
        self.address=address
        self.port=port
        self.timeout=timeout
        self.ttl=ttl
        # Seconds of inactivity before fake IP is removed
        self.expire=ttl * 2
        self.lock=threading.Lock()
        # Start thread for cleanup fake IPs
        threading.Thread(target=self.cleanup_fake_ips_worker,daemon=True).start()

    def get_fake_ip(self,real_ip,now):
        with self.lock:
            entry=self.ip_map.get(real_ip)
            if entry:
                entry["used"]=now
                return entry["fake_ip"]
            if not self.ip_pool:
                print("Error: No fake IP left")
                return None
            fake_ip=self.ip_pool.pop()
            self.ip_map[real_ip]={"fake_ip": fake_ip,"used": now}
        try:
            subprocess.run(["/usr/sbin/iptables","-w","-t","nat","-A","ANTIZAPRET-MAPPING","-d",fake_ip,"-j","DNAT","--to-destination",real_ip],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
        except Exception as e:
            print(f"Error: {e} (real_ip={real_ip} fake_ip={fake_ip})")
            with self.lock:
                del self.ip_map[real_ip]
                self.ip_pool.add(fake_ip)
            return None
        #print(f"Mapping: {fake_ip} to {real_ip}")
        return fake_ip

    def mapping_ip(self,real_ip,fake_ip,now):
        if self.ip_map.get(real_ip):
            print(f"Error: Real IP {real_ip} is already mapped")
            return False
        if fake_ip not in self.ip_pool:
            print(f"Error: Fake IP {fake_ip} not in fake IP pool")
            return False
        self.ip_pool.discard(fake_ip)
        self.ip_map[real_ip]={"fake_ip": fake_ip,"used": now}
        #print(f"Mapping: {fake_ip} to {real_ip}")
        return True

    def cleanup_fake_ips_worker(self):
        while True:
            time.sleep(self.expire)
            try:
                self.cleanup_fake_ips()
            except Exception as e:
                print(f"Error: {e}")
                print(f"Restarting: Cleanup fake IPs failed")
                try:
                    subprocess.run(["/usr/sbin/iptables","-w","-t","nat","-F","ANTIZAPRET-MAPPING"],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
                finally:
                    os._exit(1)

    def cleanup_fake_ips(self):
        with self.lock:
            now=time.time()
            cleanup_ips=[]
            rules=["*nat"]
            for real_ip,entry in self.ip_map.items():
                if now - entry["used"] > self.expire:
                    cleanup_ips.append((real_ip,entry["fake_ip"]))
            for real_ip,fake_ip in cleanup_ips:
                self.ip_pool.add(fake_ip)
                del self.ip_map[real_ip]
                rules.append(f"-D ANTIZAPRET-MAPPING -d {fake_ip} -j DNAT --to-destination {real_ip}")
                #print(f"Unmapping: {fake_ip} to {real_ip}")
        if cleanup_ips:
            rules.append("COMMIT")
            subprocess.run(["/usr/sbin/iptables-restore","-w","-n"],input="\n".join(rules).encode(),stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
            print(f"Cleaned: {len(cleanup_ips)} expired fake IPs")

    def resolve(self,request,handler):
        try:
            if handler.protocol=="udp":
                data=request.send(self.address,self.port,timeout=self.timeout)
            else:
                data=request.send(self.address,self.port,tcp=True,timeout=self.timeout)
            reply=DNSRecord.parse(data)
            if request.q.qtype==QTYPE.A:
                now=time.time()
                for record in reply.rr:
                    record.ttl=self.ttl
                    if record.rtype!=QTYPE.A:
                        continue
                    real_ip=str(record.rdata)
                    fake_ip=self.get_fake_ip(real_ip,now)
                    if not fake_ip:
                        reply=request.reply()
                        reply.header.rcode=RCODE.SERVFAIL
                        return reply
                    record.rdata=A(fake_ip)
        except Exception as e:
            print(f"Error: {e} (qname={request.q.qname} qtype={QTYPE[request.q.qtype]} protocol={handler.protocol})")
            reply=request.reply()
            reply.header.rcode=RCODE.SERVFAIL
        return reply

if __name__=="__main__":
    p=argparse.ArgumentParser(description="DNS Proxy")
    p.add_argument("--port",type=int,default=53,
                    metavar="<port>",
                    help="Local proxy port (default:53)")
    p.add_argument("--address",default="127.3.3.3",
                    metavar="<address>",
                    help="Local proxy listen address (default:127.3.3.3)")
    p.add_argument("--upstream",default="127.2.2.2:53",
                    metavar="<dns server:port>",
                    help="Upstream DNS server:port (default:127.2.2.2:53)")
    p.add_argument("--timeout",type=float,default=5,
                    metavar="<timeout>",
                    help="Upstream timeout (default: 5s)")
    p.add_argument("--log",default="truncated,error",
                    help="Log hooks to enable (default: +truncated,+error,-request,-reply,-recv,-send,-data)")
    p.add_argument("--log-prefix",action="store_true",default=False,
                    help="Log prefix (timestamp/handler/resolver) (default: False)")
    p.add_argument("--ip-range",default="198.18.0.0/15",
                    metavar="<ip/mask>",
                    help="Fake IP range (default:198.18.0.0/15)")
    p.add_argument("--ttl",type=int,default=1800,
                    metavar="<seconds>",
                    help="TTL in seconds for all records (default: 1800)")
    args=p.parse_args()
    args.dns,_,args.dns_port=args.upstream.partition(":")
    args.dns_port=int(args.dns_port or 53)
    TCPServer.request_queue_size=128
    print("Starting Proxy Resolver...")
    resolver=ProxyResolver(args.dns,args.dns_port,args.timeout,args.ip_range,args.ttl)
    logger=DNSLogger(args.log,prefix=args.log_prefix)
    udp_server=DNSServer(resolver,
                           port=args.port,
                           address=args.address,
                           logger=logger,
                           handler=DNSHandler)
    udp_server.start_thread()
    tcp_server=DNSServer(resolver,
                           port=args.port,
                           address=args.address,
                           tcp=True,
                           logger=logger,
                           handler=DNSHandler)
    tcp_server.start_thread()
    print("Started Proxy Resolver: %s:%d -> %s:%d" % (args.address or "*",args.port,args.dns,args.dns_port))
    while udp_server.isAlive():
        time.sleep(1)