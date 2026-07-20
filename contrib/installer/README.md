# Lynx Installer Scripts

This directory contains the installer scripts for the Lynx Data Storage Network.

- **Spark** (`install.sh`) — A lightweight installer that runs one or more blockchain daemons on a single machine. Tuned for low-resource hosts (Raspberry Pis, small VPSs, low-RAM devices) where efficiency matters more than ergonomics.
- **[Beacon](https://github.com/getlynx/Beacon)** — A separate project. A multi-daemon manager with a TUI for driving several daemons from one console.

Both Spark and Beacon connect to the same Lynx Data Storage Network and both can run multiple daemons on one host. The difference is posture: Spark is shell-alias driven and optimized for resource-constrained deployments; Beacon is a richer, more convenient TUI experience for operators who have the headroom for it.

Documentation: https://docs.getlynx.io/

## Scripts

### install.sh (Spark)

The Spark installer. It automates the full lifecycle of one or more blockchain daemons on AMD and ARM-based systems — from initial setup to ongoing maintenance. Multiple chains can run in parallel on the same host; each chain gets its own daemon, systemd service, working directory, and RPC loopback address. Spark is deliberately tuned for low-resource hardware — it reacts to memory pressure during sync by restarting the daemon, uses `awk` instead of `jq` to keep dependencies minimal, and stays out of the way when idle.

The installer is versioned (`SPARK_INSTALLER_VERSION`) and the current version is displayed in the Spark console footer.

**What it does:**

- Installs system dependencies and configures the environment
- Downloads the correct pre-built daemon binary from GitHub releases (matched by OS, version, and architecture)
- Creates systemd services for the daemon and a wallet backup timer
- Configures firewall rules and SSH security (skipped with [`--shared-host`](#the---shared-host-parameter))
- Monitors blockchain sync status and restarts the daemon as needed (good for low RAM deployments)
- Adds shell aliases and the Spark console with daemon statistics and staking yield metrics
- Installs the `chain` / `c` selector for switching between multiple installed chains from a single shell — the menu shows each chain's wallet balance, current block height, and staking state at a glance
- Adds an `s` toggle that flips staking on or off for the active chain

**Prerequisites:**

- Root privileges
- `curl` must be installed (`apt install curl` or `dnf install curl`)

**Usage:**

Install or update a Spark (default Lynx chain)
```bash
bash <(curl -sL install.getlynx.io)
```

Install or update a Spark for a specific chain
```bash
bash <(curl -sL install.getlynx.io) --chain=mychain
```

Current chain options
```bash
bash <(curl -sL install.getlynx.io) --chain=alioth
```
```bash
bash <(curl -sL install.getlynx.io) --chain=borrelly
```
```bash
bash <(curl -sL install.getlynx.io) --chain=cassiopeia
```
```bash
bash <(curl -sL install.getlynx.io) --chain=delphinus
```
```bash
bash <(curl -sL install.getlynx.io) --chain=enceladus
```
```bash
bash <(curl -sL install.getlynx.io) --chain=fenrir
```
```bash
bash <(curl -sL install.getlynx.io) --chain=galatea
```
```bash
bash <(curl -sL install.getlynx.io) --chain=halley
```
```bash
bash <(curl -sL install.getlynx.io) --chain=indus
```
```bash
bash <(curl -sL install.getlynx.io) --chain=infiniloop
```

Explicitly update an existing Spark daemon
```bash
bash <(curl -sL install.getlynx.io) update
```

Rebuild services, timers, firewall rules, and aliases (leaves blockchain data and wallet untouched)
```bash
bash <(curl -sL install.getlynx.io) rebuild
```

If neither `update` nor `rebuild` is passed, the script auto-detects: when the chain's systemd service already exists it runs in update mode, otherwise it runs a full installation. The `upd` and `reb` aliases wrap these flows for the currently selected chain.

Install on a server that is already running other services — leaves the existing firewall and SSH configuration untouched (see [The --shared-host Parameter](#the---shared-host-parameter))
```bash
bash <(curl -sL install.getlynx.io) --chain=lynx --shared-host
```

> **Note:** If `curl` is not available, you can use `wget` as a fallback:
> ```bash
> wget -qO- install.getlynx.io | bash
> wget -qO- install.getlynx.io | bash -s -- --chain=mychain
> ```

**Supported platforms:**

| OS Family | Distributions | Architectures |
|-----------|--------------|---------------|
| Debian | Debian, Ubuntu | AMD x86_64, ARM (aarch64) |
| RedHat | Rocky, AlmaLinux, CentOS, Fedora | AMD x86_64, ARM (aarch64) |

**Operation modes:**

| Mode | Trigger | Description |
|------|---------|-------------|
| Initial Setup | First run (no existing service) | Full installation of all components |
| Update | `update` argument, or auto-detected when the service already exists | Updates system packages and downloads the latest binary |
| Maintenance | Systemd timer (every 12 minutes) | Checks sync status, restarts daemon if needed |
| Rebuild | `rebuild` argument (or the `reb` alias) | Updates services, timers, firewall rules, and aliases without touching blockchain data or wallet |

---

### iso-builder.sh

Creates a customized Raspberry Pi OS image with Spark pre-installed. The resulting `.img.xz` file can be flashed to an SD card for a plug-and-play Spark deployment.

**What it does:**

- Downloads the latest Raspberry Pi OS Lite 64-bit ARM image (or uses a provided URL)
- Mounts the image and injects an `rc.local` script
- On first boot, the Pi automatically downloads and runs `install.sh` to set up Spark
- Compresses the final image for distribution

**Usage:**

Build with default chain (lynx) and latest Raspberry Pi OS
```
./iso-builder.sh
```

Build with a specific chain
```
./iso-builder.sh --chain=mychain
```

Build with a specific base image
```
./iso-builder.sh "https://downloads.raspberrypi.org/raspios_lite_arm64/images/..."
```

Both options together
```
./iso-builder.sh --chain=mychain "https://downloads.raspberrypi.org/raspios_lite_arm64/images/..."
```

**Output:** `YYYY-MM-DD-<chain>-RPI-ISO.img.xz`

**Requirements:**

- Linux system (Debian/Ubuntu recommended)
- Root privileges
- At least 8GB free disk space
- Internet connection

---

## Differences Between the Scripts

| | install.sh (Spark) | iso-builder.sh |
|---|-----------|---------------|
| **Purpose** | Installs and maintains one or more daemons on a host | Builds a Raspberry Pi image that runs install.sh on first boot |
| **Runs on** | Any supported AMD or ARM system | Linux build machine (produces an image for Raspberry Pi) |
| **When to use** | Deploying a Spark on an existing server or device | Creating SD card images for Raspberry Pi distribution |
| **Chain default** | No default (matches all binaries if omitted) | Defaults to `lynx` |
| **Ongoing** | Yes — re-runs every 12 minutes via systemd timer | One-time build process |

## The --chain Parameter

Both scripts accept `--chain=<name>` to target a specific chain's binaries. The chain name is matched case-insensitively against binary filenames in the latest GitHub release.

- **install.sh**: If `--chain` is specified and no matching binary exists, the script exits gracefully with a message directing the user to the Lynx Discord server for assistance.
- **iso-builder.sh**: Defaults to `--chain=lynx` if not specified. The chain name is baked into the generated image so that `install.sh` receives it automatically on first boot.

If a binary for the specified chain has not been built and uploaded to the GitHub releases page, the installation will not proceed — no partial or broken state is left behind.

## The --shared-host Parameter

By default the installer takes ownership of the host's firewall and SSH configuration. That is the right posture for a dedicated node, but destructive on a server that is already doing other work. Passing `--shared-host` disables both, leaving the machine's existing network and SSH setup untouched.

```bash
bash <(curl -sL install.getlynx.io) --chain=lynx --shared-host
```

The flag is deliberately left out of the Spark console help (`h`) and the standard usage text — it is an advanced option for operators who are managing the host's security themselves.

### When to use it

Reach for `--shared-host` whenever the target machine is not a dedicated Spark node:

- **A VPS already serving web traffic** — nginx/Apache on ports 80/443, mail, or any other public listener
- **A host with an existing firewall policy** — `ufw`, `firewalld`, a managed/corporate ruleset, or fail2ban rules you need to keep
- **A host with established SSH or user configuration** — a customized `sshd_config`, non-root admin accounts, or centrally managed keys
- **A shared or multi-tenant box** where you are not the only stakeholder in the network configuration

On a dedicated, single-purpose node, omit the flag and let Spark manage the firewall.

### What it skips

| Default behaviour | With `--shared-host` |
|---|---|
| Creates a `SPARK` iptables chain, inserts it at the top of `INPUT`, and terminates it with a `DROP` — anything not explicitly allowed (including 80/443) is dropped | No iptables changes at all |
| Deletes every `INPUT` rule that is not the jump to `SPARK` (see `patch_firewall.sh`), removing pre-existing rules | `INPUT` is never touched |
| Reapplies the firewall on boot, every 6 hours, and on each 12-minute maintenance cycle | Firewall timers are never installed |
| On RHEL/Rocky/Alma: stops and disables `firewalld`, sets SELinux permissive and disables it in `/etc/selinux/config` | `firewalld` and SELinux are left alone |
| Edits `/etc/ssh/sshd_config` (`PubkeyAuthentication`, `AuthorizedKeysFile`), appends to `/root/.ssh/authorized_keys`, and restarts `sshd` | SSH configuration and `sshd` are never touched |

Everything else installs normally: the daemon and its systemd service, RPC configuration, wallet backups, swap, the chain registry, and the Spark console.

### The choice is persistent

The flag writes a marker file at `/etc/spark/shared-host`. This matters because the maintenance timer re-runs `install.sh` every 12 minutes *without* any arguments — the marker is what keeps the setting in force. Every subsequent run, including `upd` and `reb`, reads it and continues to skip the firewall and SSH steps. Without it, the firewall would be reapplied within minutes of the install.

The marker is host-wide rather than per-chain: once set, every chain installed on that machine honours it.

To hand firewall and SSH management back to Spark:

```bash
rm /etc/spark/shared-host
reb
```

### Console differences on a shared host

Commands that would modify the host's SSH or firewall are hidden from the console help and refuse to run while the marker is present:

| Command | Normal install | Shared host |
|---|---|---|
| `usp` — change SSH port (edits `sshd_config`, restarts `sshd`, reboots) | Listed in `h` | Hidden and disabled |
| `ipt` — list iptables rules (read-only) | Listed in `h` | Hidden |
| `fire` — edit and apply the firewall script | Hidden but available | Disabled |
| `shh` — edit `authorized_keys`, restart `sshd` | Hidden but available | Disabled |
| `pas` — toggle password authentication, restart `sshd` | Hidden but available | Disabled |

Every other console command — wallet, daemon, `chain`/`c`, `upd`, `reb`, logs — behaves normally, since each acts only on the chain's own daemon, wallet, and systemd service.

### What you take on

With `--shared-host`, Spark no longer manages the host's network rules, so:

- **Open the chain's P2P port yourself** if the host has its own firewall or a cloud security group in front of it. Without inbound access the daemon still syncs over outbound connections, but it will not accept incoming peers.
- **The RPC interface needs no action** — it binds to a per-chain loopback address (`127.0.0.x`) and is never exposed, regardless of firewall state.

## Spark vs Beacon

Both Spark and Beacon run multiple daemons per host. The difference is not *how many* daemons they manage but *how* they manage them — and which hardware they're aimed at.

- **Spark** is shell-alias driven. The `chain` / `c` selector switches the active chain in the current shell — and the menu itself doubles as a multi-chain dashboard, listing each installed chain's balance, block height, and staking state. Per-chain aliases (`lyr`, `gbi`, `lyl`, `s`, etc.) act on whichever chain is selected. It's deliberately lean: no TUI process sitting in memory, minimal dependencies, and sync-time daemon restarts that make it forgiving on low-RAM Raspberry Pis and small VPSs.
- **Beacon** is a TUI. It's more fun and more convenient — live dashboards, at-a-glance status for every daemon, keyboard-driven navigation — but it carries more runtime overhead and assumes the host has the resources to spare.

| | Spark | Beacon |
|---|-------|--------|
| **Interface** | Shell aliases + `chain` / `c` selector | TUI (terminal user interface) |
| **Resource footprint** | Minimal — no persistent UI process, `awk`-only JSON parsing, sync-time restarts tuned for low RAM | Higher — TUI process running continuously |
| **Ergonomics** | Functional; command-line driven | Richer and more convenient — live views and keyboard-driven navigation |
| **Wallet encryption** | Not provided — use `<chain>-cli encryptwallet` / `walletpassphrase` directly if needed | Built-in wallet encryption workflows |
| **ElectrumX** | Not included — install separately if you need it | Built-in ElectrumX installer |
| **Repo** | This repo (`getlynx/Lynx`) | [getlynx/Beacon](https://github.com/getlynx/Beacon) |
| **Install** | `bash <(curl -sL install.getlynx.io)` | `bash <(curl -sL beacon.getlynx.io)` |
| **Best for** | Low-RAM devices, Raspberry Pis, budget VPSs, headless deployments | Operators with the headroom who want a comfortable multi-daemon cockpit |

## Support

- Documentation: https://docs.getlynx.io/
- Discord: https://discord.gg/6jUaNeV2Uy
- Issues: https://github.com/getlynx/Lynx/issues
