#!/usr/bin/env -S python3 -u
# -*- coding: utf-8 -*-

import subprocess,time,argparse,threading,os
from ipaddress import IPv4Network
from dnslib import DNSRecord,RCODE,QTYPE,A
from dnslib.server import DNSServer,DNSHandler,BaseResolver,DNSLogger,TCPServer

class ProxyResolver(BaseResolver):
    def __init__(self,dns,dns_port,dns_timeout,ip_range,ttl):
        self._env=os.environ.copy()
        self.ip_pool={str(x) for x in IPv4Network(ip_range).hosts()}
        self.ip_map={}
        # Loading existing fake IP mapping
        mapping=subprocess.run(["/usr/sbin/iptables","-w","-t","nat","-S","ANTIZAPRET-MAPPING"],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,env=self._env)
        if mapping.returncode:
            subprocess.run(["/usr/sbin/iptables","-w","-t","nat","-N","ANTIZAPRET-MAPPING"],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
        warp_ips=set()
        warp=subprocess.run(["/usr/sbin/iptables","-w","-t","mangle","-S","ANTIZAPRET-WARP"],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,env=self._env)
        if warp.returncode:
            subprocess.run(["/usr/sbin/iptables","-w","-t","mangle","-N","ANTIZAPRET-WARP"],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
        for line in warp.stdout.splitlines():
            parts=line.split()
            if len(parts) < 8:
                continue
            warp_ips.add(parts[3].split("/")[0])
        now=time.time()
        for line in mapping.stdout.splitlines():
            parts=line.split()
            if len(parts) < 8:
                continue
            fake_ip=parts[3].split("/")[0]
            real_ip=parts[7]
            if not self.mapping_ip(real_ip,fake_ip,now,fake_ip in warp_ips):
                print("Restarting: Invalid loaded fake IP mapping")
                try:
                    subprocess.run(["/usr/sbin/iptables","-w","-t","nat","-F","ANTIZAPRET-MAPPING"],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
                    subprocess.run(["/usr/sbin/iptables","-w","-t","mangle","-F","ANTIZAPRET-WARP"],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
                finally:
                    os._exit(1)
        print(f"Loaded: {len(self.ip_map)} fake IPs")
        self.dns=dns
        self.dns_port=dns_port
        self.dns_timeout=dns_timeout
        self.ttl=ttl
        # Seconds of inactivity before fake IP is removed
        self.expire=ttl * 2
        self.lock=threading.Lock()
        # Start thread for expire fake IP mapping
        threading.Thread(target=self.expire_mapping_worker,daemon=True).start()

    def get_fake_ip(self,real_ip,now,warp):
        with self.lock:
            entry=self.ip_map.get((real_ip,warp))
            if entry:
                entry["used"]=now
                return entry["fake_ip"]
            if not self.ip_pool:
                print("Error: No fake IP left in IP pool")
                return None
            fake_ip=self.ip_pool.pop()
            self.ip_map[(real_ip,warp)]={"fake_ip": fake_ip,"used": now}
        try:
            if warp:
                subprocess.run(["/usr/sbin/iptables","-w","-t","mangle","-A","ANTIZAPRET-WARP","-d",fake_ip,"-j","MARK","--set-mark","0x2"],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
            subprocess.run(["/usr/sbin/iptables","-w","-t","nat","-A","ANTIZAPRET-MAPPING","-d",fake_ip,"-j","DNAT","--to-destination",real_ip],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
        except Exception as e:
            print(f"Error: {e} (real_ip={real_ip} fake_ip={fake_ip} warp={warp})")
            with self.lock:
                del self.ip_map[(real_ip,warp)]
                self.ip_pool.add(fake_ip)
            if warp:
                subprocess.run(["/usr/sbin/iptables","-w","-t","mangle","-D","ANTIZAPRET-WARP","-d",fake_ip,"-j","MARK","--set-mark","0x2"],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=False,env=self._env)
            subprocess.run(["/usr/sbin/iptables","-w","-t","nat","-D","ANTIZAPRET-MAPPING","-d",fake_ip,"-j","DNAT","--to-destination",real_ip],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=False,env=self._env)
            return None
        #print(f"Mapping: {fake_ip} to {real_ip} warp={warp}")
        return fake_ip

    def mapping_ip(self,real_ip,fake_ip,now,warp):
        if self.ip_map.get((real_ip,warp)):
            print(f"Error: Real IP {real_ip} already mapped")
            return False
        if fake_ip not in self.ip_pool:
            print(f"Error: Fake IP {fake_ip} not in IP pool")
            return False
        self.ip_pool.discard(fake_ip)
        self.ip_map[(real_ip,warp)]={"fake_ip": fake_ip,"used": now}
        #print(f"Mapping: {fake_ip} to {real_ip} warp={warp}")
        return True

    def expire_mapping_worker(self):
        while True:
            time.sleep(self.expire)
            try:
                self.expire_mapping()
            except Exception as e:
                print(f"Error: {e}")
                print("Restarting: Expire fake IP mapping failed")
                try:
                    subprocess.run(["/usr/sbin/iptables","-w","-t","nat","-F","ANTIZAPRET-MAPPING"],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
                    subprocess.run(["/usr/sbin/iptables","-w","-t","mangle","-F","ANTIZAPRET-WARP"],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
                finally:
                    os._exit(2)

    def expire_mapping(self):
        with self.lock:
            now=time.time()
            mapping=[]
            mangle=["*mangle"]
            nat=["*nat"]
            for (real_ip,warp),entry in self.ip_map.items():
                if now - entry["used"] > self.expire:
                    mapping.append((real_ip,warp,entry["fake_ip"]))
            for real_ip,warp,fake_ip in mapping:
                self.ip_pool.add(fake_ip)
                del self.ip_map[(real_ip,warp)]
                if warp:
                    mangle.append(f"-D ANTIZAPRET-WARP -d {fake_ip} -j MARK --set-mark 0x2")
                nat.append(f"-D ANTIZAPRET-MAPPING -d {fake_ip} -j DNAT --to-destination {real_ip}")
                #print(f"Unmapping: {fake_ip} to {real_ip} warp={warp}")
        if mapping:
            rules=[]
            if len(mangle) > 1:
                rules.extend(mangle)
                rules.append("COMMIT")
            nat.append("COMMIT")
            rules.extend(nat)
            subprocess.run(["/usr/sbin/iptables-restore","-w","-n"],input="\n".join(rules).encode(),stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,env=self._env)
            print(f"Expired: {len(mapping)} fake IPs")

    def resolve(self,request,handler):
        warp=handler.server.warp
        try:
            if handler.protocol=="udp":
                data=request.send(self.dns,self.dns_port,timeout=self.dns_timeout)
            else:
                data=request.send(self.dns,self.dns_port,tcp=True,timeout=self.dns_timeout)
            reply=DNSRecord.parse(data)
            if request.q.qtype==QTYPE.A:
                now=time.time()
                for record in reply.rr:
                    record.ttl=self.ttl
                    if record.rtype!=QTYPE.A:
                        continue
                    real_ip=str(record.rdata)
                    fake_ip=self.get_fake_ip(real_ip,now,warp)
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
    p.add_argument("--dns",default="127.2.2.2:53",help="Upstream DNS server:port (default:127.2.2.2:53)")
    p.add_argument("--dns-timeout",type=float,default=5,help="Upstream DNS timeout (default: 5s)")
    p.add_argument("--ip-range",default="198.18.0.0/15",help="Fake IP range (default:198.18.0.0/15)")
    p.add_argument("--ttl",type=int,default=1800,help="TTL in seconds for A records (default: 1800)")
    p.add_argument("--proxy",default="127.3.3.3:53",help="Local Fake IP proxy listen address:port (default:127.3.3.3:53)")
    p.add_argument("--warp",default="127.4.4.4:53",help="Local WARP proxy listen address:port (default:127.4.4.4:53)")
    p.add_argument("--log",default="truncated,error",help="Log hooks to enable (default: +truncated,+error,-request,-reply,-recv,-send,-data)")
    p.add_argument("--log-prefix",action="store_true",default=False,help="Log prefix (timestamp/handler/resolver) (default: False)")
    args=p.parse_args()
    args.dns,_,args.dns_port=args.dns.partition(":")
    args.dns_port=int(args.dns_port or 53)
    args.proxy,_,args.proxy_port=args.proxy.partition(":")
    args.proxy_port=int(args.proxy_port or 53)
    args.warp,_,args.warp_port=args.warp.partition(":")
    args.warp_port=int(args.warp_port or 53)
    TCPServer.request_queue_size=128
    print("Starting...")
    resolver=ProxyResolver(args.dns,args.dns_port,args.dns_timeout,args.ip_range,args.ttl)
    logger=DNSLogger(args.log,prefix=args.log_prefix)
    def start_server(address,port,tcp=False):
        server=DNSServer(resolver,port=port,address=address,tcp=tcp,logger=logger,handler=DNSHandler)
        server.server.warp=address==args.warp
        server.start_thread()
        return server
    udp_server=start_server(args.proxy,args.proxy_port)
    tcp_server=start_server(args.proxy,args.proxy_port,tcp=True)
    print(f"Started proxy resolver {args.proxy}:{args.proxy_port} -> {args.dns}:{args.dns_port}")
    udp_warp=start_server(args.warp,args.warp_port)
    tcp_warp=start_server(args.warp,args.warp_port,tcp=True)
    print(f"Started WARP resolver {args.warp}:{args.warp_port} -> {args.dns}:{args.dns_port}")
    while all(s.thread.is_alive() for s in (udp_server,tcp_server,udp_warp,tcp_warp)):
        time.sleep(1)
    print("Restarting: A server thread died")
    os._exit(3)
