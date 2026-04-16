# HA Setup Guide

## Architecture

```
Control-plane (RU, wide channel)
  nginx stream{} UDP → least_conn → nodes
  nginx http{} 443 → corpweb-backend :8000
  PostgreSQL

Data-plane nodes (FI)
  Full AntiZapret stack + sync-agent
```

All nodes share a single WireGuard keypair. Client configs point to the control-plane IP. nginx distributes UDP sessions across nodes.

## Prerequisites

- Control-plane VM: Ubuntu 22.04+, public IP, sufficient bandwidth for all VPN traffic
- Node VMs: Ubuntu 22.04+, 1 Gbit/s, public or control-plane-routable IPs

## Step 1: Install control-plane

```bash
ssh root@control-plane

git clone <repo> /opt/corpweb
cd /opt/corpweb/control-plane
bash install.sh
```

The installer asks for mode (Native/Docker) and domain. It:
- Installs PostgreSQL, nginx, Python, certbot
- Runs `alembic upgrade head` (creates tables + NOTIFY trigger)
- Runs `python3 -m app.bootstrap` (generates server keypairs)

## Step 2: Import from existing wgfi2

Copy configs from the running node:

```bash
scp root@wgfi2:/etc/wireguard/antizapret.conf .
scp root@wgfi2:/etc/wireguard/vpn.conf .
scp root@wgfi2:/etc/wireguard/key .
scp -r root@wgfi2:/root/antizapret/config .
```

Upload via the admin panel: **Admin > Import WG Files**. Upload:
- `antizapret.conf`
- `vpn.conf`
- `key` (WireGuard private key)

The backend stores confs in `wg_file_state`, derives the public key, and stores the keypair in `wg_server_keys` for both interfaces.

## Step 3: Register wgfi2 as first node

1. Panel > **Ноды** > **Add Node**
2. Enter hostname `wgfi2` and its IP
3. On wgfi2, run the one-liner from Step 2 of the modal
4. Wait for health=ok in the panel
5. The sync-agent reconciles — since sha256 matches, nothing is overwritten

## Step 4: Add a new node

See [ADD-NODE.md](ADD-NODE.md).

## Step 5: Switch DNS

Point `vpn.example.com` to the control-plane public IP.

All client configs already use this hostname. New UDP connections go through nginx to data nodes.

## Step 6: Update nginx.conf

Edit `/etc/nginx/nginx.conf` (or `control-plane/nginx.conf`):
- Add both node IPs to all 4 upstream blocks
- `nginx -s reload`

## Rollback

DNS back to wgfi2's direct IP. Clients reconnect to the original node without any config changes.

## Verification

```bash
# On control-plane
nginx -t
curl -s https://panel.example.com/api/health

# Node status
curl -s -H "Authorization: Bearer <admin-token>" https://panel.example.com/api/v1/nodes

# WG active peers on a node
ssh root@node 'wg show antizapret latest-handshakes | wc -l'
```
