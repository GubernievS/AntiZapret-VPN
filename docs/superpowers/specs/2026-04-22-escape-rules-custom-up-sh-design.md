# Escape-rules via `custom-up.sh` hook — Design

**Date:** 2026-04-22
**Bead:** `CorpAdmin-AZ-6za` (P1, bug), under epic `CorpAdmin-AZ-te3`
**Supersedes:** `CorpAdmin-AZ-yjq` (closed) — agent-side recovery subsumed here.
**Related:** `CorpAdmin-AZ-t2r` (P3, future) — CP dashboard drift visibility.

## Goal

Make both escape tunnels (`az_escape`, `vpn_escape`) functional end-to-end on data-plane nodes. Today tunnels handshake and peers get IPs (10.27.8.x / 10.26.8.x), but no traffic flows — upstream `/root/antizapret/up.sh` scopes its NAT / forwarding rules to the baseline subnets only (10.28 for vpn, 10.29 for antizapret). 10.26 and 10.27 are not covered, so egress is silently dropped.

## Non-goals

- IPv6 escape (matches current state).
- CLIENT_ISOLATION parity for 10.26/10.27 (security gap — separate issue if ever requested).
- `ALTERNATIVE_CLIENT_IP` / custom `CLIENT_IP` schemes (172.x etc.) — not deployed, agent asserts against it.
- Rewriting upstream to use `nftables` or ipsets.
- Auto-managing any upstream hook other than `custom-up.sh` / `custom-down.sh`.

## Top-level architecture

Upstream already ships an extension point we can own:

```
/root/antizapret/up.sh       (upstream, not touched)
  …all upstream rules…
  └─ ./custom-up.sh           ← empty in upstream, CorpAdmin writes here

/root/antizapret/down.sh     (upstream, not touched)
  …all upstream -D rules…
  └─ ./custom-down.sh         ← empty in upstream, CorpAdmin writes here
```

CorpAdmin-sync-agent is the sole owner of content between marker comments
inside these two files. Upstream `setup.sh` upgrades replace `up.sh` /
`down.sh` but leave `custom-*.sh` alone (they are user-data, not code).
Even if upstream one day overwrites them, the agent re-syncs on its
heartbeat loop and restarts `antizapret.service` to re-apply.

## Decisions

### D1. Extension-point, not patching
Use the upstream-provided `custom-up.sh` / `custom-down.sh` hook. Do **not** modify upstream `up.sh`. This removes the entire class of "upstream ate our patch" failures by construction.

### D2. Marker-bracketed managed block
Agent writes only between:
```
# === BEGIN CorpAdmin escape rules (managed by corpweb-sync-agent) ===
…
# === END CorpAdmin escape rules ===
```
Content outside markers (hypothetical operator additions) is preserved byte-for-byte. If markers are absent, agent appends a fresh block at the end of the file. If only one marker is present, agent refuses to touch the file and reports an error.

### D3. Rule set — mirror upstream semantics per iface

**`az_escape` (10.27.0.0/16) mirrors `antizapret` (10.29.0.0/16):**

- `nat PREROUTING -s 10.27.0.0/16 -p udp --dport 53 -j DNAT --to-destination 127.0.0.1`
- `nat PREROUTING -s 10.27.0.0/16 -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1`
- `nat PREROUTING -s 10.27.0.0/16 -d $FAKE_IP.0.0/15 -j ANTIZAPRET-MAPPING` (re-uses upstream's chain)
- If `RESTRICT_FORWARD=y`:
  - `nat PREROUTING -s 10.27.0.0/16 ! -d $FAKE_IP.0.0/15 -j CONNMARK --set-mark 0x1`
  - `filter -I FORWARD 2 -s 10.27.0.0/16 -m connmark --mark 0x1 -m set ! --match-set antizapret-forward dst -j DROP`
- `nat POSTROUTING -s 10.27.0.0/16 -o $ANTIZAPRET_OUT_INTERFACE -j MASQUERADE` (or `SNAT --to-source $ANTIZAPRET_OUT_IP` if non-empty)

**`vpn_escape` (10.26.0.0/16) mirrors `vpn` (10.28.0.0/16):**

- If `VPN_DNS=1`:
  - `nat PREROUTING -s 10.26.0.0/16 -p udp --dport 53 -j DNAT --to-destination 127.0.0.2`
  - `nat PREROUTING -s 10.26.0.0/16 -p tcp --dport 53 -j DNAT --to-destination 127.0.0.2`
- `nat POSTROUTING -s 10.26.0.0/16 -o $VPN_OUT_INTERFACE -j MASQUERADE` (or `SNAT --to-source $VPN_OUT_IP` if non-empty)

`custom-down.sh` is the symmetric counterpart — same conditionals, `-D` instead of `-A`/`-I`.

### D4. WARP inheritance — automatic
If `ANTIZAPRET_WARP=y`, upstream `up.sh` reassigns `$ANTIZAPRET_OUT_INTERFACE = warp`. Our rules read that variable, so they transparently egress through WARP. No special code.

### D5. Unconditional deploy (no `ESCAPE_ENABLED` gate)
`ESCAPE_ENABLED` is a CP-side toggle controlling balancer DNAT for ports 500/53443. On data-plane nodes, escape ifaces are always up (backend `bootstrap()` creates all 4 keypairs + `/register` endpoint returns them unconditionally; agent brings ifaces up on every registration). Therefore our custom-up.sh rules are safe to apply always — they are inert when no traffic arrives. Simpler code path, no CP→agent toggle propagation.

### D6. `ALTERNATIVE_CLIENT_IP` — assertion, not support
Escape subnets are hardcoded to `10.26.0.0/16` / `10.27.0.0/16`, matching `vpn_manager_new._IFACE_CONFIG`. If `setup` contains `ALTERNATIVE_CLIENT_IP=y`, agent refuses to write `custom-up.sh` and reports an error via heartbeat. This fails loudly instead of silently breaking.

### D7. Agent lifecycle — sync on startup + heartbeat
- On agent startup, after `register_if_needed()` and `_apply_wg_config()`:
  1. Validate `/root/antizapret/setup` exists and passes ALTERNATIVE_CLIENT_IP check.
  2. Render expected content for `custom-up.sh` and `custom-down.sh`.
  3. For each file: if current content (between markers) != expected → rewrite.
  4. If either file changed → `systemctl restart antizapret.service` once.
- On each heartbeat cycle: repeat steps 2–4. On drift detection, bump `escape_drift_applied_count` in heartbeat payload and set `escape_drift_detected=true`.

### D8. Re-apply via `systemctl restart antizapret.service`
- Does not touch `wg-quick@*.service` — WG tunnels stay up.
- Only iptables rulesets flap (2–3 s window during `down.sh` → `up.sh`).
- Stable, well-tested upstream lifecycle path. No direct manual invocation of `./up.sh`.

## Data model

None. Fully agent-local.

## Backend changes

None.

## Frontend changes

None.

## Agent changes

`agent/corpweb_sync_agent.py`:
- New pure function `render_custom_up_sh(flags: dict) -> str`.
- New pure function `render_custom_down_sh(flags: dict) -> str`.
- New pure function `validate_setup_env(setup_text: str) -> None` (raises on ALTERNATIVE_CLIENT_IP=y).
- New helper `sync_custom_script(path: str, expected: str) -> bool` (marker-aware idempotent write; returns True on change).
- New orchestrator `sync_escape_rules() -> dict` — parses `/root/antizapret/setup`, renders both scripts, syncs both files, triggers `systemctl restart antizapret.service` if either changed; returns heartbeat-shaped metrics.
- Hook points:
  - `register_if_needed()` — call `sync_escape_rules()` at the tail, after `_apply_wg_config`.
  - Heartbeat loop — call `sync_escape_rules()` each cycle; merge returned metrics into heartbeat payload.

`agent/tests/`:
- **New:** `test_escape_rules.py` — L1 unit tests for render/validate pure functions.
- `test_sync_agent.py` — L2/L3 tests: `sync_custom_script` idempotency / marker preservation / subprocess interactions.

## Node-side effects

No manual node-side setup. The agent owns:
- `/root/antizapret/custom-up.sh` (between markers)
- `/root/antizapret/custom-down.sh` (between markers)

Applied via standard `antizapret.service` restart cycle.

## CP install-script changes

None.

## Testing strategy (TDD)

**L1 — pure function unit tests** (`test_escape_rules.py`):
- `render_custom_up_sh` contains both markers.
- Always emits DNS DNAT for 10.27/53 → 127.0.0.1 (both udp + tcp).
- Always emits ANTIZAPRET-MAPPING chain jump for 10.27 fake-IP range.
- Emits CONNMARK + FORWARD DROP for 10.27 iff `RESTRICT_FORWARD=y`.
- Emits DNS DNAT for 10.26/53 → 127.0.0.2 iff `VPN_DNS=1`.
- POSTROUTING branch: MASQUERADE when `OUT_IP` empty, else SNAT.
- `render_custom_down_sh` symmetry: for each `-A`/`-I` rule in up, a matching `-D` appears in down under the same conditional.
- Idempotency: two calls with identical flags return identical string.
- `validate_setup_env`: raises on `ALTERNATIVE_CLIENT_IP=y`, accepts n/missing/empty.

**L2 — sync-layer unit tests** (`test_sync_agent.py`, `tmp_path`):
- Empty file → full managed block written, returns True.
- File with managed block + stale content → block replaced, returns True.
- File with managed block + user content outside markers → user content preserved.
- File without markers but with user content → markers appended at tail, user content preserved.
- File already in expected state → no-op, returns False.
- File with only BEGIN marker (no END) → raises.

**L3 — integration tests** (`test_sync_agent.py`, mock subprocess.run):
- On drift detection, exactly one `systemctl restart antizapret.service` call per sync cycle.
- Heartbeat payload carries `escape_drift_detected` + `escape_drift_applied_count`.

**L4 — manual smoke** (deploy checklist, documented in plan):
- On CP: `ESCAPE_ENABLED=true`.
- On node: `cat /root/antizapret/custom-up.sh` shows managed block.
- `iptables -t nat -nvL POSTROUTING | grep -E '10\.2[67]'` shows 2 rules.
- `iptables -t nat -nvL PREROUTING | grep -E '10\.27.*53'` shows DNAT rules.
- Android client (az_escape variant) opens any blocked site end-to-end.
- Android client (vpn_escape variant) reaches arbitrary public IP.

**L5 — drift-recovery smoke**:
- On node: `: > /root/antizapret/custom-up.sh` (truncate).
- Wait one heartbeat interval.
- File re-populated; `iptables -t nat -nvL` again shows escape rules.
- Heartbeat on CP reports `escape_drift_applied_count` incremented.

## Migration / rollout

1. No DB migrations (alembic head stays 0007).
2. No backend changes.
3. Deploy new agent via existing flow: `scp corpweb_sync_agent.py → /tmp`, `install -m 0755 -o root -g root`, `systemctl restart corpweb-sync-agent`.
4. Order: wgfi3 (secondary) first → smoke → wgfi2 (primary).
5. **Rollback:** revert agent binary; optionally `rm` managed block from custom-up.sh manually. Stale rules are inert without tunnel traffic — no hurry.
6. No user-visible downtime. `antizapret.service` restart flaps iptables for 2–3 s; WG tunnels are unaffected (separate `wg-quick@*.service`).

## Error handling

| Scenario | Behaviour |
|---|---|
| `/root/antizapret/setup` missing | Agent skips sync, logs warning, does not fail startup. |
| `ALTERNATIVE_CLIENT_IP=y` detected | Agent skips sync, sends `error: "escape requires IP=10 scheme"` in heartbeat. |
| Malformed markers (BEGIN without END) | Agent refuses to write, reports error in heartbeat. |
| `systemctl restart` fails | Captured in logs; next heartbeat retries. |
| Upstream overwrites custom-up.sh | Heartbeat loop detects on next cycle, re-applies, increments drift counter. |
| Duplicate rules (custom-up re-run without down) | Upstream `up.sh` always calls `./down.sh` first (line 7), so chains are clean. Agent's own re-apply uses `systemctl restart` which follows the same lifecycle. |

## Files touched

| File | Change |
|---|---|
| `agent/corpweb_sync_agent.py` | +render_custom_up_sh / render_custom_down_sh / validate_setup_env / sync_custom_script / sync_escape_rules; hook into register + heartbeat. |
| `agent/tests/test_escape_rules.py` | **New** — L1 unit tests. |
| `agent/tests/test_sync_agent.py` | +L2 (sync layer) +L3 (subprocess / heartbeat payload) tests. |

Backend, frontend, alembic, install scripts: untouched.

## Future work

- `CorpAdmin-AZ-t2r` (P3) — CP dashboard surfaces `escape_drift_applied_count` per node (kept parked until real drift observed).
- `CorpAdmin-AZ-adj` (P2) — dashboard escape-peers visibility (independent, not blocked by this).
- Potential future: CLIENT_ISOLATION parity for 10.26/10.27 (only if security review requests).
