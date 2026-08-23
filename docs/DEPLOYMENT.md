# Deploying the AirGap DevKit

Author: Nima Shafie

Two supported ways to run the whole suite (the devkit-ui web manager, the tools,
and the [`conan-airgap`](../conan-airgap/README.md) offline-Conan kit):

| | **Mode 1 — Shared team server** | **Mode 2 — Per-user local** |
|---|---|---|
| Who runs it | Admin / IT / DevSecOps | Any user, **no admin rights** |
| Where it runs | One shared host, exposed on the LAN | Each user's own machine |
| Where tools install | On the server (shared) | Each user's user-prefix |
| Entry point | [`scripts/serve.sh`](../scripts/serve.sh) | [`scripts/launch.sh`](../scripts/launch.sh) |
| Access | Team opens a token URL in a browser | `localhost` UI or CLI |
| Best for | Central build host / thin clients | Laptops, workstations, quick spins |

Both modes are fully offline. Pick one — or run Mode 1 for a shared cache/mirror
and let users also run Mode 2 locally against it.

---

## Prerequisites (both modes)

The repo carries two submodules (`tools/`, `prebuilt/`). On a connected staging
box:

```bash
git clone <repo-url> airgap-cpp-devkit
cd airgap-cpp-devkit
git submodule update --init --recursive
```

For a **truly air-gapped** target, transfer the whole checkout (including
submodules) as an archive via approved media rather than cloning. Bash is
required (Git Bash/MINGW64 on Windows, system bash on RHEL). No Python or Node
runtime is needed for the server.

---

## Mode 1 — Shared team server (admin / IT / DevSecOps)

One host runs the manager; the team drives it from their browsers. **Tools
installed through the UI land on this host**, so this is the model for a shared
build server / dev box / terminal server that everyone uses (via the UI, SSH, or
RDP).

### 1. Place the repo on the server

Put the checkout somewhere stable, e.g. `/opt/airgap-cpp-devkit` (Linux) or
`C:\airgap-cpp-devkit` (Windows).

### 2. Configure `devkit.config.json`

```jsonc
{
  "team_name": "Platform C++ Team",
  "devkit_name": "AirGap DevKit",
  "hostname": "0.0.0.0",          // bind all interfaces (or a specific NIC)
  "port": 9090,
  "default_profile": "cpp-dev",   // from profiles.defaults.json
  "team_config_repo": "",         // optional: git URL of a shared team-config.json
  "allow_egress": false,          // keep false on air-gapped hosts
  "setup_complete": true
}
```

Installing tools **system-wide** (so all users on the host share them) requires
running the server as an admin/root account; the install prefix is then
`/opt/airgap-cpp-devkit/<tool>` or `C:\Program Files\airgap-cpp-devkit\<tool>`.
Non-privileged server accounts install to the running user's prefix instead.

### 3. Start the server

```bash
bash scripts/serve.sh --tls                       # HTTPS on 0.0.0.0 (self-signed)
bash scripts/serve.sh --port 9090 --tls           # HTTPS on a custom port
bash scripts/serve.sh --advertise devbox.corp.local --tls   # nicer URL for the team
bash scripts/serve.sh --insecure                  # plaintext HTTP (trusted LAN only)
```

Binding to a network interface without `--tls` is refused unless you pass
`--insecure`, so the access token is never sent in the clear by default.

`serve.sh` creates a stable auth token (`.devkit-token`) and prints the
one-click access URL, e.g.:

```
https://devbox.corp.local:9090/auth/bootstrap?devkit_token=<token>&next=/
```

When `serve.sh` runs non-interactively (e.g. under systemd, where stdout goes to
the journal) it does **not** print the token. It writes the access URL to the
owner-only file `.devkit-access-url` instead; reveal it with `cat
.devkit-access-url`.

### 4. Team access

Share that URL. Opening it sets an auth cookie and lands on the dashboard — team
members browse profiles, install tools, and watch live output. `/health` is open
for load-balancer checks; everything else requires the token.

### 5. Run it as a service (survives reboots)

**Linux (systemd)** — `/etc/systemd/system/devkit.service`:

```ini
[Unit]
Description=AirGap DevKit Manager
After=network.target

[Service]
Type=simple
User=devkit
WorkingDirectory=/opt/airgap-cpp-devkit
ExecStart=/bin/bash /opt/airgap-cpp-devkit/scripts/serve.sh --port 9090 --tls
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now devkit.service
```

**Windows** — register the launch command to run at startup with **Task
Scheduler** ("At startup", highest privileges), running:
`"C:\Program Files\Git\bin\bash.exe" C:\airgap-cpp-devkit\scripts\serve.sh --port 9090 --tls`.
The devkit also ships **Servy** (a Windows service manager) which can wrap the
same command as a service.

### 6. Conan for the whole team

Two options, from most to least infrastructure:

- **Internal mirror (recommended for teams):** stand up a Conan repo in your
  Artifactory/Nexus, push a seeded cache to it once
  (`conan upload "*" -r internal --confirm` from a connected host), and have each
  client use the `internal-mirror` network profile. See
  [`conan-airgap/network/internal-mirror/`](../conan-airgap/network/internal-mirror/README.md).
- **Shared cache on the build host:** on this shared server, run the kit's
  `import-airgap.sh --network offline` **once**; every user on the host then
  shares that populated `~/.conan2` (or a common `CONAN_HOME`).

### 7. Security checklist

- The token in `.devkit-token` grants full access — treat it as a secret; rotate
  by deleting the file and restarting. Prefer `--tls` on any shared network.
- Restrict the port with a host firewall to the team's subnet.
- Keep `allow_egress: false` on air-gapped hosts (blocks the update checker's
  outbound calls).
- For multi-user servers, add a per-user token roster (next section) so
  installs, uploads, and config changes are attributable and least-privileged
  instead of everyone sharing one all-powerful token.

### 8. Per-user tokens and roles (optional)

By default a single shared token (`.devkit-token`) grants full access — every
holder can install tools and upload packages, and actions are not attributable
to a person. For a shared team server, drop a `.devkit-users.json` next to the
repo root to issue **named tokens with roles**:

```json
{
  "users": [
    { "name": "alice", "token": "<64-hex>", "role": "admin" },
    { "name": "bob",   "token": "<64-hex>", "role": "operator" },
    { "name": "guest", "token": "<64-hex>", "role": "viewer" }
  ]
}
```

Generate each token with `openssl rand -hex 32`. The file holds live tokens, so
it is `git`-ignored and should be mode `600`.

| Role | Can do |
|---|---|
| `viewer` | read-only: dashboard, status, tool listings, install logs |
| `operator` | everything viewer can, plus install / uninstall / version + package operations |
| `admin` | everything operator can, plus package **uploads**, config changes, config import, and shutdown |

- When the roster is present the shared `.devkit-token` is **rejected** — access
  comes only from a named token. Remove the file to return to single-token mode.
- Every privileged (operator/admin) request is written to the server log as
  `audit: user=… role=… METHOD path`, giving per-user attribution.
- Package upload/install runs an executable `setup.sh`, so it is admin-only —
  keep the `admin` role to trusted operators.

### 9. Large package uploads

The **Packages → Upload Package** area accepts multi-GB `.zip` archives. Uploads
are sent in resumable chunks (tus protocol): a dropped connection or a page
reload continues from the last byte the server stored rather than restarting.

Relevant `devkit.config.json` keys (all optional; sane defaults applied):

| Key | Default | Purpose |
|---|---|---|
| `upload_max_bytes` | 8 GiB | largest archive accepted |
| `upload_chunk_size` | 16 MiB | bytes per chunk request |
| `zip_max_uncompressed` | 16 GiB | expansion guard |
| `zip_max_entry_bytes` | 8 GiB | per-file cap inside the archive |
| `upload_temp_dir` | `<repo>/.devkit-uploads` | chunk-assembly scratch space |
| `upload_session_ttl_hours` | 24 | abandoned uploads reaped after this |

- **Disk headroom:** `upload_temp_dir` needs room for the archive **plus** its
  extraction (~2× the largest package). Point it at a roomy volume on a shared
  server.
- **Reverse proxy:** because each request carries only one chunk, an nginx/Apache
  front end only needs `client_max_body_size` ≥ `upload_chunk_size` (not the full
  file). A too-small value returns `413` mid-upload.
- **Localhost shortcut:** on a per-user local install (Mode 2) set
  `allow_path_import: true` to reveal an **Import from path** field that installs
  a `.zip` directly off local disk — no transfer, no size ceiling beyond free
  disk. It is refused for non-loopback callers, so leave it off on a team server.

---

## Mode 2 — Per-user local (no admin rights)

Each user runs the devkit on their own machine and installs only what they need,
into their **user-prefix** — no administrator required.

Install prefixes (chosen automatically when not admin):

| | Windows | Linux |
|---|---|---|
| User install | `%LOCALAPPDATA%\airgap-cpp-devkit\<tool>` | `~/.local/share/airgap-cpp-devkit/<tool>` |

### Option A — Visual UI (localhost)

```bash
bash scripts/launch.sh              # opens http://127.0.0.1:9090 in the browser
bash scripts/launch.sh --no-browser # headless; open the printed URL yourself
```

Bound to `127.0.0.1` — only this user, nothing exposed. Pick a profile, install
tools; they go to the user-prefix automatically.

### Option B — Non-interactive CLI (headless / scripted)

```bash
bash scripts/internal/install-cli.sh --yes --profile cpp-dev
# custom location:
bash scripts/internal/install-cli.sh --yes --profile minimal --prefix "$HOME/devkit"
```

Profiles: `minimal`, `cpp-dev`, `devops`, `full` (defined once in
[`profiles.defaults.json`](../profiles.defaults.json)).

### Wire the installed tools onto your PATH

Each install writes an `env.sh` under the prefix and appends a source line to
`~/.bashrc`. Start a new shell, or:

```bash
source "$HOME/.local/share/airgap-cpp-devkit/env.sh"    # Linux user install
```

### Conan, per user (offline)

Install Conan (`conan` in any profile), then import a bundle you received into
your own cache:

```bash
bash tools/dev-tools/conan/setup.sh                      # Conan 2.30.0, user-prefix
bash conan-airgap/scripts/import-airgap.sh \
     --bundle conan-airgap-bundle-<stamp>.tar.gz --network offline \
     --verify-ref fmt/10.2.1
```

Then build with CMake or Eclipse straight from the cache — see
[`conan-airgap/templates/`](../conan-airgap/templates/README.md).

### Updates

Pull a newer repo checkout (or a delta) via approved transfer and re-run your
install/import. Conan delta bundles are additive:

```bash
bash conan-airgap/scripts/import-airgap.sh --bundle conan-airgap-update-<stamp>.tar.gz --network offline
```

---

## Which mode should I use?

- **Central control, thin clients, one place to patch** → Mode 1. Add an
  internal Conan mirror so clients pull updates through you.
- **No admin rights, air-gapped laptops, fast onboarding** → Mode 2. Ship the
  repo + a Conan bundle; users self-serve into their user-prefix.
- **Both** → host Mode 1 as the team's source of truth (config repo + Conan
  mirror), and let users run Mode 2 locally pointed at it.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Server binary not found` | `git submodule update --init --recursive prebuilt` |
| Team can't reach the UI | Server bound to `127.0.0.1` — use `serve.sh` (binds `0.0.0.0`) and open the port in the firewall |
| `Unauthorized` in browser | Open the full `/auth/bootstrap?devkit_token=…` URL from `serve.sh`, not the bare host |
| `conan` not found after install | Start a new shell or `source <prefix>/env.sh`; the latest Conan installs to `<prefix>/conan/bin` |
| Conan can't find a library offline | It wasn't seeded for that profile — re-seed on a matching host and import the delta |
