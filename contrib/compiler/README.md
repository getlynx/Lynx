# Lynx Data Storage Network (LDSN) Compiler

This directory contains `compile.sh` — a self-contained build script that compiles the
Lynx Core daemon, CLI, and transaction tool from source for any chain defined in the
repository, and packages each build as a dated `.zip` archive.

It is a **compile-only** tool. It produces archives; it does not install a daemon, write
a config, create a systemd service, or start anything. To actually *run* a chain, use the
[Spark installer](../installer/) instead, which downloads pre-built, fully tested release
binaries.

Documentation: https://docs.getlynx.io/

---

## ⚠️ Before you use this

**This script compiles the tip of the `main` branch.** That is cutting-edge code which may
not have completed the full suite of unit and functional tests, so a binary you build here
can carry bugs that never reach a tagged release. Compiling your own binary means accepting
that risk.

**For the most reliable binaries — the ones that have been through every test suite —
download an official build instead:**

### 👉 https://github.com/getlynx/Lynx/releases

The release archives use the same naming scheme this script produces, so a self-built
archive and a downloaded one are directly comparable. The script repeats this warning twice
during a run: once before you choose a chain, and again at the final confirmation right
before compiling begins.

---

## Quick start

Run it in one line. Nothing is downloaded to disk and nothing is left behind:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/getlynx/Lynx/main/contrib/compiler/compile.sh)
```

If `wget` is not installed but `curl` is:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/getlynx/Lynx/main/contrib/compiler/compile.sh)
```

Both forms are verified working. A few notes on why they look the way they do:

- **`bash <(...)` is required — do not pipe.** `wget ... | bash` sends the *script itself*
  down stdin, which means the interactive chain-selection prompts would try to read your
  answer out of the script's own source text. Process substitution hands bash the script as
  a file and leaves stdin attached to your keyboard. The script detects the piped case and
  refuses to run rather than misbehaving.
- **It must be `bash`, not `sh`.** Process substitution `<(...)` is a bash feature; under
  `sh`/`dash` you get `Syntax error: "(" unexpected`.
- **It runs from the directory you are standing in.** The finished `.zip` archives land in
  your current working directory, so `cd` somewhere sensible first.

You can also save the script and run it normally — in that case archives land next to the
saved script:

```bash
wget https://raw.githubusercontent.com/getlynx/Lynx/main/contrib/compiler/compile.sh
chmod +x compile.sh
./compile.sh
```

---

## Prerequisites

| Requirement | Detail |
| --- | --- |
| **Root** | Must run as `root` directly. `sudo` is not used. |
| **RAM** | At least 2 GB. Checked at startup and refused below that. |
| **Terminal** | An interactive TTY, because chain selection is a prompt. |
| **`wget` or `curl`** | Only to fetch the script. Everything else it installs itself. |
| **Disk** | A full build tree plus `depends` runs to several GB **per chain**. |

**Supported build targets:**

| Distro family | Architectures |
| --- | --- |
| Debian / Ubuntu | `x86_64-pc-linux-gnu`, `arm-linux-gnueabihf` (ARM 32-bit), `aarch64-linux-gnu` (ARM 64-bit) |
| RHEL family (RHEL, Rocky, Alma, CentOS, Fedora) | `x86_64-pc-linux-gnu` **only** |

RHEL-family repositories do not ship the ARM cross-toolchains the `depends` system needs,
so ARM targets require Debian or Ubuntu. The script fails fast on that combination.

A dedicated, disposable VPS is the intended environment. The script updates all system
packages and installs a full build toolchain.

---

## What the script does

1. **Checks the environment** — root, RAM, TTY, and a supported OS/architecture.
2. **Installs baseline packages** — `curl`, `git`, `zip`, and `htop` where available.
3. **Fetches the chain list** — downloads `src/kernel/chainparams.cpp` from `main` and
   extracts every chain defined in it (see [Where the chain list comes from](#where-the-chain-list-comes-from)).
4. **Prompts you to choose** one or more chains to build.
5. **Detaches** — everything after selection runs in the background, so you can close your
   SSH session.
6. **Prepares the system** — sets the `en_US.UTF-8` locale, applies all pending system
   updates, and installs the build toolchain for your architecture. This happens once per
   run regardless of how many chains you queued.
7. **Builds each chain in turn** — clone or update the source, build `depends`, run
   `autogen.sh` and `configure`, then `make`.
8. **Packages each chain** — stages the three binaries, strips them, zips them, and deletes
   the loose binaries so only the archive remains.
9. **Prints a summary** — per-chain success/failure plus a ready-to-paste `scp` command for
   pulling the archives to your local machine.

---

## Usage

### Selecting chains

The menu lists every buildable chain, each in its own color:

```
🧭 Select blockchain(s) (page 1 / 1):
    0) All Chains (11)
    1) Alioth
    2) Borrelly
    3) Cassiopeia
    ...
   11) Lynx
🙂 Enter number or comma-separated list (e.g. 3,7,12), 0=all, n=next, p=prev, q=quit:
```

| Input | Meaning |
| --- | --- |
| `7` | Queue a single chain. |
| `3,7,12` or `3 7 12` | Queue several at once. Commas and spaces both work. |
| `0` | Queue **every** chain. Asks for confirmation first. |
| `n` / `p` | Next / previous page (30 chains per page). |
| `q` | Quit without building. |

Duplicates are dropped automatically and the order you entered is preserved. A single
invalid entry rejects the whole line, so a typo can never silently build the wrong subset.

After each selection you are asked whether to add more:

```
➕ Add more? (y = keep selecting, Enter = start detached build):
```

Press `y` to keep browsing and queueing, or **Enter to start the build**.

Both prompts time out after **15 minutes** of no input and exit without building anything,
even if chains are already queued — starting a multi-hour batch is always a deliberate
keypress.

Chain colors are the same ones the Spark installer uses, so a chain looks identical here
and in Spark's `chain` selector.

### Building every chain

Entering `0` queues all chains and asks to confirm:

```
⚠️  That queues ALL 11 chains, one after another — expect this to run for hours.
❓ Build all 11 chains? (y = yes, anything else = go back):
```

Only `y` proceeds. Anything else — including a bare Enter — cancels and returns you to the
menu without changing your queue.

### Forcing a target architecture

By default the architecture is detected from `uname -m`. Pass one of the three supported
triplets to override it (useful for cross-compiling):

```bash
bash <(wget -qO- https://raw.githubusercontent.com/getlynx/Lynx/main/contrib/compiler/compile.sh) aarch64-linux-gnu
```

Accepted values: `x86_64-pc-linux-gnu`, `arm-linux-gnueabihf`, `aarch64-linux-gnu`.

---

## Monitoring a running build

Selection is the only interactive part. Once it finishes, the build detaches from your
terminal, ignores `SIGHUP`, and keeps running even if your SSH connection drops:

```
🛫 Build phase detached (PID 12345) — you can close this terminal now.
   🪵 Watch progress:  tail -f /var/log/chain-build-20260806-143022.log
   🔍 Still running?   ps -p $(cat /var/run/chain-build.pid) || echo done
   🛑 Cancel build:    chain-build-stop
   📦 Results land in /root (dated .zip archives).
```

| Path / command | Purpose |
| --- | --- |
| `/var/log/chain-build-<timestamp>.log` | Full build output. One file per run. |
| `/var/run/chain-build.pid` | PID of the detached build. |
| `chain-build-stop` | Cancels a running build. Installed to `/usr/local/bin`. |

`chain-build-stop` signals the entire process group, not just the recorded PID — `make`
spawns a tree of compiler children, and killing the parent alone would leave them running.
It escalates to `SIGKILL` if the build has not stopped within 10 seconds.

---

## Output

Each chain produces exactly one archive:

```
2026-08-06.Lynx.CLI.v27.1.1.Debian.12.AMD.zip
└─ date    └─ chain └─ version └─ distro └─ ver └─ arch
```

Architecture is labelled `AMD` for x86_64 and `ARM` for either ARM target. The version is
read from `configure.ac` in the cloned source.

Each archive contains three stripped binaries — for example, for Lynx:

- `lynxd` — the daemon
- `lynx-cli` — the RPC client
- `lynx-tx` — the transaction utility

**Archives land in the directory you ran the script from** (or next to the script, if you
saved it and ran it directly). The loose binaries are deleted once the archive is sealed,
so the `.zip` files are the only artifacts left behind.

> **Note:** nothing is installed onto your `PATH`. Unzip the archive to use the binaries.
> Only the `chain-build-stop` helper goes into `/usr/local/bin`.

When the batch finishes, a ready-to-paste download command is printed:

```bash
scp "root@203.0.113.10:/root/*.zip" ~/Desktop/
```

---

## Where the chain list comes from

The menu is built from `src/kernel/chainparams.cpp` on `main`, which defines every chain's
parameters as a block of `spec.<field>["<chain>"] = ...` assignments. The script downloads
that file and harvests the chain names from it directly.

This has two consequences worth understanding:

- **A chain becomes buildable the moment it is committed to `chainparams.cpp`.** No
  separate list to maintain — new chains appear in the menu automatically.
- **A chain that is not in `chainparams.cpp` cannot be built.** Its parameters would not
  exist in the compiled binary, so there is nothing to build.

The same branch feeds both the menu and the `git clone`, so the list you are offered and
the source you compile always agree.

---

## Rebuilds are fast

The first run for a chain does a fresh clone and a full build, including the `depends`
tree. That is the slow one — plan on hours.

After that:

- The existing clone is updated with `git fetch` plus a hard reset to the upstream tip, so
  **only files that actually changed get new timestamps**. `make` recompiles just those
  objects and reuses every cached object file.
- The `depends` tree is built once per architecture and reused on every later run.

Each chain gets its own working directory at `/root/<chain>` — for example `/root/lynx`.
These are left in place deliberately; deleting one forces a full rebuild of that chain.

---

## Troubleshooting

**Nothing happens at all — no output, no error.**
The download failed and `bash` executed an empty script. This is what a `404` looks like
with `wget -qO-`, which is silent by design. Check the URL is reachable:

```bash
curl -sI https://raw.githubusercontent.com/getlynx/Lynx/main/contrib/compiler/compile.sh | head -1
```

The `curl -fsSL` variant is more diagnostic here — it prints `curl: (22) ... 404` to stderr
rather than failing silently.

**`Syntax error: "(" unexpected`**
You ran it under `sh` or `dash`. Use `bash`.

**`Interactive selection requires a TTY.`**
You piped the script into bash instead of using `bash <(...)`, or ran it from a context
with no terminal (cron, CI, `< /dev/null`). Use the process-substitution form.

**`Must run as root on the target VPS (no sudo).`**
Switch to root first with `su -` or `sudo -i`, then run the one-liner.

**`Insufficient RAM: detected ~NNNMB; need at least 2048MB (2GB).`**
The build needs at least 2 GB. Add swap or move to a larger instance.

**`On RHEL-family distros (<distro>), only x86_64 builds are supported.`**
Expected — RHEL repos lack ARM cross-toolchains. Use Debian or Ubuntu for ARM targets.

**One chain failed but others succeeded.**
Each chain builds in its own subshell, so a failure is contained and the batch continues.
The summary lists each chain with ✅ or ❌; check the log for the failing chain's output.

---

## Files

| File | Description |
| --- | --- |
| `compile.sh` | The LDSN Compiler. Self-contained; no other files from this directory are needed at runtime. |
| `README.md` | This document. |
