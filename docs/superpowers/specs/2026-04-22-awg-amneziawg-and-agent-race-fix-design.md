# AmneziaWG on Nodes + Agent Race Fix — Design

**Date:** 2026-04-22
**Bead:** CorpAdmin-AZ-3qe (P1 bug)
**Parent epic:** CorpAdmin-AZ-roo (AWG escape obfuscation)
**Blocks:** CorpAdmin-AZ-cpk (Phase 7 deploy)

## Goal

Unblock Phase 7 deploy of the AWG escape feature. Phase 7 smoke test exposed
two problems not anticipated in the original spec:

1. Nodes run only the vanilla `wireguard` kernel module + `wireguard-tools`.
   `wg syncconf vpn_escape` fails with `Line unrecognized: 'Jc=3'` — vanilla
   parser doesn't understand AmneziaWG fields. For true obfuscation
   (`S1 > 0`, non-default `H1..H4`) the nodes need the `amneziawg` kernel
   module plus the `awg` / `awg-quick` userspace tools.
2. `register_if_needed()` in the agent starts `wg-quick@<iface>.service`
   immediately after writing keys, but the `.conf` file for escape ifaces
   arrives later via SSE. Result: `wg-quick up` fails because the conf
   does not exist yet. For `antizapret`/`vpn` this was never observed
   because upstream `setup.sh` creates those confs before the agent is
   ever installed; escape ifaces have no such pre-seeding.

## Non-goals

- Replacing vanilla `wireguard` for the existing `antizapret` / `vpn` ifaces.
  They continue to run on `wg` / `wg-quick`. AmneziaWG is added strictly
  for `*_escape` ifaces.
- Exotic amnezia-only features (DPI-fingerprint rotation, per-client S/H
  params, etc.) — still out of scope, as in the original spec.

## Decisions

### D1. Install `amneziawg` via `agent/install.sh` only

- `agent/install.sh` gets an idempotent block: if `awg` binary is missing,
  add the amnezia apt repo, install `amneziawg` + `amneziawg-tools`.
  DKMS builds the kernel module against the running kernel. Skip if
  already installed.
- Primary install path: amnezia's official apt repository (key + source
  list under `/etc/apt/keyrings/` + `/etc/apt/sources.list.d/`).
  Fallback, if the apt repo is unreachable: download the latest `.deb`
  artifacts from `github.com/amnezia-vpn/amneziawg-linux-kernel-module/releases`
  and `github.com/amnezia-vpn/amneziawg-tools/releases`, install via
  `dpkg -i` + `apt-get install -f`. Both paths are retried under a
  single `install_amneziawg()` shell function with clear error output
  if neither works — operator then installs by hand.
- `setup.sh` (upstream AntiZapret installer) is **not** touched.
  AmneziaWG is a CorpAdmin-AZ feature dependency, not an antizapret one.
- For the two existing nodes (wgfi2, wgfi3): one-shot manual install via
  SSH before rolling out the fixed agent. Scripted so later nodes get it
  automatically through `install.sh`.

### D2. Escape ifaces use `awg` / `awg-quick` and live in `/etc/amnezia/amneziawg/`

- `antizapret`, `vpn` continue using `wg`, `wg-quick`, `/etc/wireguard/`.
- `antizapret_escape`, `vpn_escape` use `awg`, `awg-quick`,
  `/etc/amnezia/amneziawg/`. This matches the amnezia convention; keeps
  the two tool chains clean; avoids nonstandard cross-wiring.
- systemd units: existing `wg-quick@<iface>.service` for base ifaces;
  `awg-quick@<iface>.service` (ships with `amneziawg-tools`) for escape.

### D3. Lazy iface-up: bring interfaces up in `apply_path`, not in `register_if_needed`

- `register_if_needed()` writes keys only — never calls `systemctl start`.
- `apply_path()` on receiving a managed wg/awg conf blob:
  - if iface is down → `systemctl start wg-quick@<iface>` (or `awg-quick@`);
  - if iface is up → `wg syncconf <iface>` (or `awg syncconf`) as today.
- The "is up" check is a thin wrapper (`ip link show <iface>` exit status).
- Benefit: same control path works for brand-new ifaces (escape) and
  for ones that already exist (antizapret/vpn). The agent becomes fully
  self-sufficient — it no longer depends on anything outside itself to
  seed the conf file.

### D4. `delete_peer` / `disable_peer` / `enable_peer` for escape ifaces

- Operations already work correctly for all four ifaces because:
  - `delete_peer` iterates over `_IFACE_CONFIG.items()` and re-renders
    with `awg_params` when rendering escape ifaces.
  - `_toggle_peer` uses `reverse_peer_keys`, a string-patch that reverses
    `PublicKey =` / `PresharedKey =` lines **only inside `[Peer]` blocks**.
    AWG fields (`Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `H1..H4`) live in the
    `[Interface]` section and are untouched.
- Add explicit regression tests covering escape ifaces so future changes
  cannot silently break them.

### D5. Data migration: relocate escape confs in `wg_file_state`

Alembic migration `0006_relocate_escape_confs.py`:
```sql
UPDATE wg_file_state
   SET path = '/etc/amnezia/amneziawg/antizapret_escape.conf'
 WHERE path = '/etc/wireguard/antizapret_escape.conf';
UPDATE wg_file_state
   SET path = '/etc/amnezia/amneziawg/vpn_escape.conf'
 WHERE path = '/etc/wireguard/vpn_escape.conf';
```

On CP this renames 2 rows. Agents pick up the new paths through
`MANAGED_FILES`; the startup reconcile re-fetches them into the new
directory and leaves the old (now-unmanaged) paths untouched in
`/etc/wireguard/` — harmless, but a cleanup step is noted below.

### D6. README + operator docs

After all fixes and a green end-to-end smoke, a final commit updates
`README.md` (the repository root) with:
- AmneziaWG requirement for nodes (what gets installed, by whom, why).
- Escape mode section: how admin enables it, user-facing toggle, port
  list (500 / 53443), and regeneration workflow.

## Affected components

| Component | Changes |
|---|---|
| `agent/install.sh` | Idempotent amneziawg install block (D1). |
| `agent/corpweb_sync_agent.py` | `MANAGED_FILES` paths + hooks (D2); new `apply_wg_or_up()` with up-or-sync branching; `register_if_needed` no longer starts units (D3). |
| `agent/tests/test_sync_agent.py` | Tests for new hook dispatch, up-vs-sync logic, register_if_needed no-start. |
| `corpweb/backend/app/services/vpn_manager_new.py` | `_IFACE_CONFIG` escape `conf_path` updated (D2). |
| `corpweb/backend/alembic/versions/0006_relocate_escape_confs.py` | UPDATE wg_file_state.path for 2 rows (D5). |
| `corpweb/backend/tests/test_vpn_manager_new.py` | Regression tests for `delete_peer`/`disable_peer`/`enable_peer` on escape ifaces (D4). |
| `README.md` | AmneziaWG + escape-mode documentation (D6). |

## Data flow after the fix

```
[admin toggles ESCAPE_ENABLED]
      ↓
PATCH /admin/settings {escape_enabled: true}
      ↓ balancer.apply_rules(..., escape_enabled=True)
CP iptables gets DNAT for 500 + 53443
      ↓
[agent apply_path receives /etc/amnezia/amneziawg/vpn_escape.conf blob via SSE]
      ↓
iface_is_up("vpn_escape")? → no
      ↓
systemctl start awg-quick@vpn_escape.service
      ↓
kernel amneziawg module loads iface on UDP 500 with S1/S2/H1..H4 from conf
      ↓
[client downloads bypass=true conf, connects]
      ↓
handshake reaches CP:500 → DNAT → NODE:500 → kernel awg iface → auth ok
```

## Testing strategy (TDD)

**Pure-function level:** none new — `reverse_peer_keys` tests already
assert no [Interface] changes, add explicit coverage for an input that
contains AWG fields.

**Agent level** (mock `subprocess.run`):
- `apply_path` with hook `awg_antizapret_escape` + iface down → `awg-quick@...` start.
- `apply_path` with same hook + iface up → `awg syncconf` only.
- `register_if_needed` never calls `systemctl start` — verify via mock.
- Unchanged-content path for escape ifaces (no-op).

**Backend regression:**
- `delete_peer` on an escape iface removes the peer and preserves the
  `[Interface]` AWG block byte-for-byte.
- `disable_peer` → `_toggle_peer` reverses `PublicKey`/`PresharedKey` in
  all four ifaces; `[Interface]` AWG fields unchanged in escape ifaces.
- `enable_peer` (second toggle) restores keys exactly (involution).

**Integration / smoke (Phase 7 continuation):**
- One-shot amneziawg install on wgfi2 and wgfi3.
- Deploy fixed agent; verify `awg show antizapret_escape` and
  `awg show vpn_escape` output non-empty on both nodes.
- Flip `ESCAPE_ENABLED` on CP → DNAT rules for 500/53443 appear.
- Download a bypass conf, plug into AmneziaWG client, handshake →
  traffic flows.
- Regenerate obfuscation params → old bypass conf stops working, new
  download works.

## Migration / rollout order

1. Manually install `amneziawg` on wgfi2 and wgfi3 (one-shot SSH).
2. Apply Alembic `0006` on CP (`alembic upgrade head`). `wg_file_state`
   path rename lands.
3. Push new agent to nodes; restart `corpweb-sync-agent`. Next SSE
   reconcile creates the escape confs under `/etc/amnezia/amneziawg/`,
   `apply_path` brings the two ifaces up via `awg-quick@*`.
4. Admin: flip `ESCAPE_ENABLED`. Smoke test end-to-end.
5. Cleanup: remove stale `/etc/wireguard/{antizapret,vpn}_escape.conf`
   that were written by the previous (failing) agent attempt, so there
   is no visual confusion later.
6. Merge `README.md` update.

## Out of scope / future work

- Automated amneziawg install on upgrade of existing nodes without
  re-running `install.sh`. Current plan: operator triggers the install
  once; future nodes handled at `install.sh` time.
- A CP-side healthcheck that surfaces "escape iface down" to the admin
  dashboard. Useful but not required for bypass to work.
- Prometheus / metrics for escape-iface byte counters.
