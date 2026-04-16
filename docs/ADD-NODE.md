# Add Node Runbook

## Prerequisites

- A fresh Ubuntu 22.04+ VM with public IP and 1 Gbit/s channel
- Control-plane already running (see [HA-SETUP.md](HA-SETUP.md))
- SSH access to the new node as root

## Step 1: Create node in panel

1. Open the admin panel: `https://panel.example.com`
2. Navigate to **Ноды** (Nodes)
3. Click **Add Node**
4. Enter hostname (e.g. `wgfi3`) and private IP (the IP nginx will route to)
5. Click **Create**

The panel generates an enrollment token and shows two commands.

## Step 2: Run AntiZapret setup on the new node (if fresh)

SSH to the node and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup.sh)
```

This installs the full AntiZapret stack: WireGuard, knot-resolver, iptables rules, doall.sh.

## Step 3: Install sync-agent

Copy the one-liner from the panel (Step 2 of the modal) and run it on the node:

```bash
CORPWEB_CP_URL=https://panel.example.com CORPWEB_TOKEN=<token> bash <(curl -fsSL https://panel.example.com/agent/install.sh)
```

The agent:
1. Registers with the control-plane
2. Receives the shared WireGuard keypair
3. Reconciles all 12 managed files
4. Starts the SSE stream for real-time updates

## Step 4: Wait for health=ok

The panel polls the node every 3 seconds. When the agent sends its first heartbeat with `health=ok`, the panel advances to Step 3 (done).

You can also verify on the node:

```bash
bash /opt/corpweb-agent/check.sh
```

## Step 5: Add to nginx upstream

Edit `control-plane/nginx.conf` on the control-plane:

```nginx
upstream wg_antizapret {
    least_conn;
    server EXISTING_NODE_IP:51443 max_fails=3 fail_timeout=10s;
    server NEW_NODE_IP:51443 max_fails=3 fail_timeout=10s;   # <-- add
}
# Repeat for wg_vpn, awg_antizapret, awg_vpn
```

Then reload:

```bash
nginx -s reload
```

## Verification

```bash
# Check node appears healthy in panel
curl -sH "Authorization: Bearer $TOKEN" https://panel.example.com/api/v1/nodes

# Check WG peers synced to the new node
ssh root@new-node 'wg show antizapret | grep -c peer'

# Check nginx is proxying to both nodes
# (look at stream access log or active connections)
```

## Troubleshooting

**Agent not connecting:**
```bash
journalctl -u corpweb-sync-agent -n 50
```

**Files not syncing:**
```bash
bash /opt/corpweb-agent/check.sh
# Compare SHAs with control-plane
```

**WG peers not matching:**
```bash
wg show antizapret latest-handshakes | wc -l
# Should match the number of peers in the panel
```
