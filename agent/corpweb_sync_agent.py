#!/usr/bin/env python3
"""
corpweb_sync_agent.py — data-plane sync daemon

Runs on each WireGuard node. Streams config updates from the control-plane
via SSE, applies them atomically, and sends periodic heartbeats.

Config: /etc/corpweb-sync-agent.env
  CONTROL_PLANE_URL=https://panel.example.com
  AGENT_TOKEN=<bearer>
  AGENT_HOSTNAME=<hostname>
"""

import hashlib
import json
import logging
import os
import subprocess
import tempfile
import threading
import time

import requests

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
log = logging.getLogger("corpweb-sync-agent")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

ENV_FILE = "/etc/corpweb-sync-agent.env"


def load_env(path: str = ENV_FILE) -> dict:
    """Parse a simple KEY=VALUE env file (no shell quoting)."""
    env: dict = {}
    try:
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                env[k.strip()] = v.strip()
    except FileNotFoundError:
        log.warning("Env file %s not found; falling back to OS environment", path)
    # OS env overrides file so systemd EnvironmentFile semantics hold
    for key in ("CONTROL_PLANE_URL", "AGENT_TOKEN", "AGENT_HOSTNAME"):
        if key in os.environ:
            env[key] = os.environ[key]
    return env


CFG = load_env()
CP_URL: str = CFG.get("CONTROL_PLANE_URL", "").rstrip("/")
TOKEN: str = CFG.get("AGENT_TOKEN", "")
HOSTNAME: str = CFG.get("AGENT_HOSTNAME", "") or os.uname().nodename

# ---------------------------------------------------------------------------
# Managed-file table
# ---------------------------------------------------------------------------

# Each entry: (path, hook_type)
# hook_type: None | "wg_antizapret" | "wg_vpn" | "wg_antizapret_escape"
#          | "wg_vpn_escape" | "doall" | "restart_antizapret"
MANAGED_FILES: list[tuple[str, str | None]] = [
    ("/etc/wireguard/antizapret.conf", "wg_antizapret"),
    ("/etc/wireguard/vpn.conf", "wg_vpn"),
    ("/etc/wireguard/antizapret_escape.conf", "wg_antizapret_escape"),
    ("/etc/wireguard/vpn_escape.conf", "wg_vpn_escape"),
    ("/root/antizapret/setup", "restart_antizapret"),
    ("/root/antizapret/config/include-hosts.txt", "doall"),
    ("/root/antizapret/config/exclude-hosts.txt", "doall"),
    ("/root/antizapret/config/include-ips.txt", "doall"),
    ("/root/antizapret/config/exclude-ips.txt", "doall"),
    ("/root/antizapret/config/allow-ips.txt", "doall"),
    ("/root/antizapret/config/forward-ips.txt", "doall"),
    ("/root/antizapret/config/include-adblock-hosts.txt", "doall"),
    ("/root/antizapret/config/exclude-adblock-hosts.txt", "doall"),
    ("/root/antizapret/config/remove-hosts.txt", "doall"),
]

MANAGED_PATHS: set[str] = {p for p, _ in MANAGED_FILES}

# ---------------------------------------------------------------------------
# Debounce helper for doall.sh
# ---------------------------------------------------------------------------

_doall_lock = threading.Lock()
_doall_timer: threading.Timer | None = None
DOALL_DEBOUNCE_SECS = 5.0


def _run_doall() -> None:
    log.info("Running /root/antizapret/doall.sh")
    try:
        subprocess.run(
            ["/root/antizapret/doall.sh"],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        log.error("doall.sh failed (rc=%d): %s", exc.returncode, exc.stderr.strip())
    except FileNotFoundError:
        log.error("/root/antizapret/doall.sh not found")


def schedule_doall() -> None:
    """Debounce: cancel any pending timer, start a fresh 5-second one."""
    global _doall_timer
    with _doall_lock:
        if _doall_timer is not None:
            _doall_timer.cancel()
        _doall_timer = threading.Timer(DOALL_DEBOUNCE_SECS, _run_doall)
        _doall_timer.daemon = True
        _doall_timer.start()


# ---------------------------------------------------------------------------
# Debounce helper for antizapret.service restart
# ---------------------------------------------------------------------------
# Settings in /root/antizapret/setup (WIREGUARD_BACKUP, SSH_PROTECTION,
# ATTACK_PROTECTION, ALTERNATIVE_CLIENT_IP, RESTRICT_FORWARD, CLIENT_ISOLATION,
# VPN_DNS, …) only take effect when up.sh re-runs — which happens at
# antizapret.service startup. Just writing the file is not enough.

_restart_antizapret_lock = threading.Lock()
_restart_antizapret_timer: threading.Timer | None = None
RESTART_ANTIZAPRET_DEBOUNCE_SECS = 5.0


def _run_restart_antizapret() -> None:
    log.info("Restarting antizapret.service")
    try:
        subprocess.run(
            ["systemctl", "restart", "antizapret.service"],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        log.error(
            "systemctl restart antizapret.service failed (rc=%d): %s",
            exc.returncode,
            exc.stderr.strip(),
        )
    except FileNotFoundError:
        log.error("systemctl not found")


def schedule_restart_antizapret() -> None:
    """Debounce: cancel any pending restart timer, start a fresh 5-second one."""
    global _restart_antizapret_timer
    with _restart_antizapret_lock:
        if _restart_antizapret_timer is not None:
            _restart_antizapret_timer.cancel()
        _restart_antizapret_timer = threading.Timer(
            RESTART_ANTIZAPRET_DEBOUNCE_SECS, _run_restart_antizapret
        )
        _restart_antizapret_timer.daemon = True
        _restart_antizapret_timer.start()


# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------

def sha256_of_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_of_file(path: str) -> str | None:
    """Return hex sha256 of existing file, or None if it doesn't exist."""
    try:
        with open(path, "rb") as fh:
            return sha256_of_bytes(fh.read())
    except FileNotFoundError:
        return None


def write_atomic(path: str, content: bytes) -> None:
    """Write content to path atomically via a temp file in the same directory."""
    dir_ = os.path.dirname(path) or "."
    os.makedirs(dir_, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=dir_, prefix=".tmp-corpweb-")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(content)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def apply_wg_syncconf(iface: str) -> None:
    cmd = f"wg syncconf {iface} <(wg-quick strip {iface})"
    log.info("Running: bash -c %r", cmd)
    try:
        subprocess.run(
            ["bash", "-c", cmd],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        log.error(
            "wg syncconf %s failed (rc=%d): %s",
            iface,
            exc.returncode,
            exc.stderr.strip(),
        )


def apply_path(path: str, content: bytes, hook: str | None) -> bool:
    """
    Write content to path if sha256 differs, then run the hook.
    Returns True if the file was actually updated.
    """
    new_sha = sha256_of_bytes(content)
    old_sha = sha256_of_file(path)
    if new_sha == old_sha:
        log.debug("No change for %s (sha=%s)", path, new_sha[:12])
        return False

    log.info("Updating %s (old=%s new=%s)", path, old_sha and old_sha[:12], new_sha[:12])
    write_atomic(path, content)

    if hook == "wg_antizapret":
        apply_wg_syncconf("antizapret")
    elif hook == "wg_vpn":
        apply_wg_syncconf("vpn")
    elif hook == "wg_antizapret_escape":
        apply_wg_syncconf("antizapret_escape")
    elif hook == "wg_vpn_escape":
        apply_wg_syncconf("vpn_escape")
    elif hook == "doall":
        schedule_doall()
    elif hook == "restart_antizapret":
        schedule_restart_antizapret()

    return True


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def auth_headers() -> dict:
    return {"Authorization": f"Bearer {TOKEN}"}


def api_get(path: str, stream: bool = False, timeout=30):
    url = f"{CP_URL}{path}"
    resp = requests.get(url, headers=auth_headers(), stream=stream, timeout=timeout)
    resp.raise_for_status()
    return resp


def api_post(path: str, payload: dict, timeout=30):
    url = f"{CP_URL}{path}"
    resp = requests.post(url, headers=auth_headers(), json=payload, timeout=timeout)
    resp.raise_for_status()
    return resp


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

WG_KEY_DIR = "/etc/wireguard"


def _key_path(iface: str) -> str:
    return os.path.join(WG_KEY_DIR, f"{iface}.key")


def _pub_path(iface: str) -> str:
    return os.path.join(WG_KEY_DIR, f"{iface}.key.pub")


def _local_ip() -> str:
    """Best-effort detection of the machine's outbound IP."""
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def register_if_needed() -> None:
    """
    POST /api/v1/agent/register with hostname + private_ip.
    The server returns wg_server_keys (private + public per iface).
    Writes key files and restarts wg-quick if keys changed.
    """
    log.info("Registering with control plane as %r", HOSTNAME)
    try:
        resp = api_post(
            "/api/v1/agent/register",
            {"hostname": HOSTNAME, "private_ip": _local_ip()},
        )
    except requests.HTTPError as exc:
        log.error("Registration HTTP error: %s", exc)
        return
    except requests.ConnectionError as exc:
        log.error("Registration connection error: %s", exc)
        return

    data = resp.json()
    keys: dict = data.get("wg_server_keys", {})

    for iface, key_data in keys.items():
        private_key: str = key_data.get("private_key", "")
        public_key: str = key_data.get("public_key", "")
        if not private_key:
            continue

        priv_content = (private_key.strip() + "\n").encode()
        pub_content = (public_key.strip() + "\n").encode()

        priv_path = _key_path(iface)
        pub_path = _pub_path(iface)

        # Write keys; if private key changed restart the interface
        os.makedirs(WG_KEY_DIR, exist_ok=True)
        key_changed = apply_path(priv_path, priv_content, hook=None)
        apply_path(pub_path, pub_content, hook=None)

        if key_changed:
            # Fix permissions on private key
            try:
                os.chmod(priv_path, 0o600)
            except OSError:
                pass
            log.info("Keys changed for %s — restarting wg-quick@%s", iface, iface)
            for action in ("stop", "start"):
                try:
                    subprocess.run(
                        ["systemctl", action, f"wg-quick@{iface}.service"],
                        check=True,
                        capture_output=True,
                    )
                except subprocess.CalledProcessError as exc:
                    log.error(
                        "systemctl %s wg-quick@%s failed: %s",
                        action,
                        iface,
                        exc.stderr,
                    )

    # Apply wg_config if provided (patch Interface section in WG confs)
    wg_config = data.get("wg_config")
    if wg_config:
        _apply_wg_config(wg_config)

    log.info("Registration complete")


def _apply_wg_config(cfg: dict) -> None:
    """Patch [Interface] section in WG conf files with CP-provided config."""
    iface_map = {
        "antizapret": {
            "conf": "/etc/wireguard/antizapret.conf",
            "address": cfg.get("antizapret_address"),
            "port": cfg.get("antizapret_listen_port"),
        },
        "vpn": {
            "conf": "/etc/wireguard/vpn.conf",
            "address": cfg.get("vpn_address"),
            "port": cfg.get("vpn_listen_port"),
        },
    }
    mtu = cfg.get("mtu")

    for iface, params in iface_map.items():
        conf_path = params["conf"]
        if not os.path.exists(conf_path):
            continue

        content = open(conf_path).read()
        changed = False

        if params["address"]:
            import re
            new_content = re.sub(
                r'^Address\s*=\s*.*$',
                f'Address = {params["address"]}',
                content, flags=re.MULTILINE,
            )
            if new_content != content:
                content = new_content
                changed = True

        if params["port"]:
            new_content = re.sub(
                r'^ListenPort\s*=\s*.*$',
                f'ListenPort = {params["port"]}',
                content, flags=re.MULTILINE,
            )
            if new_content != content:
                content = new_content
                changed = True

        if mtu:
            new_content = re.sub(
                r'^MTU\s*=\s*.*$',
                f'MTU = {mtu}',
                content, flags=re.MULTILINE,
            )
            if new_content != content:
                content = new_content
                changed = True

        if changed:
            write_atomic(conf_path, content.encode())
            log.info("Patched %s with wg_config from CP", conf_path)


# ---------------------------------------------------------------------------
# Startup reconcile
# ---------------------------------------------------------------------------

def startup_reconcile() -> None:
    """Fetch all 12 managed files from the control plane and apply if changed."""
    log.info("Running startup reconcile for %d files", len(MANAGED_FILES))
    import base64

    for path, hook in MANAGED_FILES:
        try:
            resp = api_get(f"/api/v1/agent/file?path={path}")
            data = resp.json()
            content = base64.b64decode(data["content"])
            apply_path(path, content, hook)
        except requests.HTTPError as exc:
            if exc.response is not None and exc.response.status_code == 404:
                log.debug("Control plane has no data for %s — skipping", path)
            else:
                log.warning("Failed to fetch %s: %s", path, exc)
        except (requests.ConnectionError, KeyError) as exc:
            log.warning("Failed to fetch %s: %s", path, exc)

    log.info("Startup reconcile done")


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------

def _active_peers(iface: str) -> int:
    """Count WireGuard peers with a handshake in the last 3 minutes."""
    try:
        result = subprocess.run(
            ["wg", "show", iface, "latest-handshakes"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return 0

    now = time.time()
    count = 0
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        try:
            ts = int(parts[1])
        except ValueError:
            continue
        if ts > 0 and (now - ts) < 180:
            count += 1
    return count


_prev_net: dict = {"rx": 0, "tx": 0, "ts": 0.0}


def collect_metrics() -> dict:
    global _prev_net
    metrics = {
        "active_peers_antizapret": _active_peers("antizapret"),
        "active_peers_vpn": _active_peers("vpn"),
    }
    try:
        with open("/proc/net/dev") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 10 and any(x in parts[0] for x in ("eth0", "ens")):
                    rx, tx = int(parts[1]), int(parts[9])
                    now = time.monotonic()
                    if _prev_net["ts"] > 0:
                        dt = max(now - _prev_net["ts"], 1)
                        metrics["rx_bytes_per_sec"] = int((rx - _prev_net["rx"]) / dt)
                        metrics["tx_bytes_per_sec"] = int((tx - _prev_net["tx"]) / dt)
                    _prev_net = {"rx": rx, "tx": tx, "ts": now}
                    break
    except Exception:
        pass
    return metrics


def collect_peers() -> list[dict]:
    """Collect full peer list from all WG interfaces via wg show dump."""
    peers = []
    for iface in ("antizapret", "vpn"):
        try:
            result = subprocess.run(
                ["wg", "show", iface, "dump"],
                capture_output=True, text=True, check=True,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
        for line in result.stdout.splitlines()[1:]:  # skip header
            parts = line.split("\t")
            if len(parts) < 8:
                continue
            peers.append({
                "interface": iface,
                "public_key": parts[0],
                "endpoint": parts[2] if parts[2] != "(none)" else None,
                "allowed_ips": parts[3],
                "latest_handshake": int(parts[4]) if parts[4] != "0" else 0,
                "rx_bytes": int(parts[5]),
                "tx_bytes": int(parts[6]),
            })
    return peers


# ---------------------------------------------------------------------------
# Heartbeat
# ---------------------------------------------------------------------------

HEARTBEAT_INTERVAL = 30  # seconds


def _applied_shas() -> dict:
    """Build the sha256 map for the heartbeat payload."""
    result: dict = {}
    for path, _ in MANAGED_FILES:
        sha = sha256_of_file(path)
        if sha is not None:
            result[path] = sha
    return result


def send_heartbeat() -> None:
    payload = {
        "applied_sha": _applied_shas(),
        "health": "ok",
        "metrics": collect_metrics(),
        "peers": collect_peers(),
    }
    try:
        api_post(
            "/api/v1/agent/heartbeat",
            payload,
            timeout=15,
        )
        log.debug("Heartbeat sent")
    except (requests.HTTPError, requests.ConnectionError, requests.Timeout) as exc:
        log.warning("Heartbeat failed: %s", exc)


# ---------------------------------------------------------------------------
# SSE streaming
# ---------------------------------------------------------------------------

SSE_RECONNECT_SLEEP = 5  # seconds


def _parse_sse_event(raw: str) -> dict | None:
    """
    Parse a single SSE message (multi-line block) into a dict with keys
    'event' and 'data'.  Returns None for comment/empty lines.
    """
    event_type = "message"
    data_lines: list[str] = []
    for line in raw.splitlines():
        if line.startswith("event:"):
            event_type = line[6:].strip()
        elif line.startswith("data:"):
            data_lines.append(line[5:].strip())
        # ignore id: and retry: fields for now
    if not data_lines:
        return None
    return {"event": event_type, "data": "\n".join(data_lines)}


def stream_events() -> None:
    """
    Open an SSE connection to the control plane and process events.
    Also fires a heartbeat every HEARTBEAT_INTERVAL seconds.
    Raises ConnectionError on stream loss so the caller can retry.
    """
    url = f"{CP_URL}/api/v1/agent/events"
    log.info("Connecting to SSE stream at %s", url)

    hook_map = {path: hook for path, hook in MANAGED_FILES}
    last_heartbeat = time.monotonic()

    try:
        resp = requests.get(
            url,
            headers={**auth_headers(), "Accept": "text/event-stream"},
            stream=True,
            timeout=(10, None),  # connect=10s, read=no timeout
        )
        resp.raise_for_status()
    except (requests.HTTPError, requests.ConnectionError, requests.Timeout) as exc:
        raise ConnectionError(f"SSE connect failed: {exc}") from exc

    raw_buf = ""
    try:
        for chunk in resp.iter_content(chunk_size=None, decode_unicode=True):
            # Heartbeat check
            now = time.monotonic()
            if now - last_heartbeat >= HEARTBEAT_INTERVAL:
                send_heartbeat()
                last_heartbeat = now

            raw_buf += chunk
            # SSE events are separated by double newlines
            while "\n\n" in raw_buf:
                block, raw_buf = raw_buf.split("\n\n", 1)
                evt = _parse_sse_event(block)
                if evt is None:
                    continue
                _handle_event(evt, hook_map)
    except (requests.exceptions.ChunkedEncodingError, requests.ConnectionError) as exc:
        raise ConnectionError(f"SSE stream lost: {exc}") from exc


def _handle_event(evt: dict, hook_map: dict) -> None:
    import base64

    data_str = evt.get("data", "")
    if not data_str:
        return

    try:
        payload: dict = json.loads(data_str)
    except json.JSONDecodeError:
        log.debug("Non-JSON SSE data: %r", data_str[:100])
        return

    # SSE sends {"path": "/etc/wireguard/antizapret.conf"} on file change
    path: str = payload.get("path", "")
    if not path or path not in MANAGED_PATHS:
        if path:
            log.debug("Received update for unmanaged path %r — ignoring", path)
        return

    # Fetch the updated file content
    log.info("SSE: file changed — %s", path)
    try:
        resp = api_get(f"/api/v1/agent/file?path={path}")
        data = resp.json()
        content = base64.b64decode(data["content"])
        changed = apply_path(path, content, hook_map.get(path))
        if changed:
            # Immediate heartbeat so CP knows we applied
            send_heartbeat()
    except Exception as exc:
        log.error("Failed to apply SSE update for %s: %s", path, exc)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def main() -> None:
    if not CP_URL:
        raise SystemExit("CONTROL_PLANE_URL is not set — check " + ENV_FILE)
    if not TOKEN:
        raise SystemExit("AGENT_TOKEN is not set — check " + ENV_FILE)

    log.info(
        "corpweb-sync-agent starting (hostname=%r, cp=%r)", HOSTNAME, CP_URL
    )

    register_if_needed()

    while True:
        try:
            startup_reconcile()
            stream_events()
        except ConnectionError as exc:
            log.warning("%s — reconnecting in %ds", exc, SSE_RECONNECT_SLEEP)
            time.sleep(SSE_RECONNECT_SLEEP)
        except KeyboardInterrupt:
            log.info("Interrupted — exiting")
            break
        except Exception as exc:  # pylint: disable=broad-except
            log.exception("Unexpected error: %s — reconnecting in %ds", exc, SSE_RECONNECT_SLEEP)
            time.sleep(SSE_RECONNECT_SLEEP)


if __name__ == "__main__":
    main()
