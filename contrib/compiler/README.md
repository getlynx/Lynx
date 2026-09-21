# Lynx Data Storage Network (LDSN) Compiler

This directory contains `compile.sh` — a self-contained build script that compiles the
daemon, CLI, transaction tool, and Qt desktop wallet from source for **any coin on the Lynx
Data Storage Network**. Build a single chain, several at once, or every coin on the network
in one run; each one is packaged as two dated `.zip` archives, one for the command-line
binaries and one for the Qt wallet.

There is no fixed list of supported coins here. The compiler reads the available chains
straight out of the source at run time, so whatever the network supports on the day you
run it is what the menu offers.

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
| **Disk** | A full build tree plus `depends` runs to several GB **per chain** — and **double that** on a Debian 12 x86_64 host, which also builds Windows in its own tree. |

**Supported build targets:**

| Distro family | Architectures |
| --- | --- |
| Debian / Ubuntu | `x86_64-pc-linux-gnu`, `arm-linux-gnueabihf` (ARM 32-bit), `aarch64-linux-gnu` (ARM 64-bit) |
| RHEL family (RHEL, Rocky, Alma, CentOS, Fedora) | `x86_64-pc-linux-gnu` **only** |
| **Windows (cross-compiled)** | `x86_64-w64-mingw32` — **only from a Debian 12 x86_64 host** |

RHEL-family repositories do not ship the ARM cross-toolchains the `depends` system needs,
so ARM targets require Debian or Ubuntu. The script fails fast on that combination.

### Windows builds

On a **Debian 12 x86_64** host the script cross-compiles every selected chain to 64-bit
Windows automatically, in addition to the Linux build. There is no flag and no prompt. On
every other host the Windows target is silently skipped and never mentioned — no menu
entry, no summary row.

The Debian 12 restriction is deliberate, and not simple conservatism:

- A cross-compiled, statically linked Windows binary is **unaffected by the host distro**.
  The host only decides which toolchain compiles it, so "build on the newest distro" —
  the usual instinct for Linux builds — buys nothing here.
- Debian 12 ships mingw-w64 GCC **12.2**; Debian 13 ships GCC **14**. This tree pins Qt
  **5.15.5** and OpenSSL **1.1.1n**, both of which predate GCC 13/14. The `_GNU_SOURCE`
  workaround already in `compile.sh` exists because of exactly that mismatch on native
  GCC 14 builds.
- The project's own CI cross-compiles win64 on Ubuntu 22.04
  (`ci/test/00_setup_env_win64.sh`) — the same toolchain generation as Debian 12, and the
  configuration with actual test coverage.
- ARM hosts have no mingw-w64 cross-toolchain in Debian, and RHEL repositories ship none
  at all, so both are excluded.

The script installs `g++-mingw-w64-x86-64-posix` and `binutils-mingw-w64-x86-64`, then
verifies that `x86_64-w64-mingw32-g++-posix`, `-windres` and `-strip` all resolve. If any
is missing it disables the Windows target for that run rather than failing every chain
hours later. The `-posix` variant matters: `depends/hosts/mingw32.mk` auto-selects it when
present, which is what replaced the old `update-alternatives` step.

Windows builds use a **separate working directory** (`/root/<chain>-win64`) so each target
keeps its own `depends` tree and object cache. Sharing one checkout would make every run
reconfigure and rebuild both targets from scratch.

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
   updates, and installs the build toolchain for your architecture — plus the mingw-w64
   cross-toolchain on a Debian 12 x86_64 host. This happens once per run regardless of how
   many chains you queued.
7. **Builds each chain in turn** — clone or update the source, build `depends`, run
   `autogen.sh` and `configure`, then `make`. On a Debian 12 x86_64 host each chain is
   built twice: Linux first, then Windows in its own tree, so a Windows failure never
   costs you the Linux archives.
8. **Packages each build** — stages the four binaries, strips them, zips the command-line
   trio into a `CLI` archive and the Qt wallet into a `QT` archive, and deletes the loose
   binaries so only the archives remain.
9. **Prints a summary** — per-build success/failure (named `<Chain> (linux)` /
   `<Chain> (windows)` when both targets ran) plus a ready-to-paste `scp` command for
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

Each chain produces exactly two archives — or **four** on a Debian 12 x86_64 host, where
the Windows cross-build runs too:

```
2026-08-06.Lynx.CLI.v27.1.1.Debian.12.AMD.zip
2026-08-06.Lynx.QT.v27.1.1.Debian.12.AMD.zip
└─ date    └─ chain └─ version └─ distro └─ ver └─ arch

2026-08-06.Lynx.CLI.v27.1.1.Windows.AMD.zip
2026-08-06.Lynx.QT.v27.1.1.Windows.AMD.zip
└─ date    └─ chain └─ version └─ os      └─ arch
```

Architecture is labelled `AMD` for x86_64 and `ARM` for either ARM target, on **every**
platform — the arch token describes the CPU and is deliberately independent of the OS, so
a Windows x86_64 build is `AMD` just as a Debian x86_64 build is. The version is read from
`configure.ac` in the cloned source.

The Windows name has one segment fewer than the Linux name, and that is intentional: the
Linux archives carry a distro **and** a distro version because a binary built against
Debian 12's glibc is not portable to every other release, whereas one Windows `.exe`
covers Windows 7 through 11 — the Windows release is simply not a build axis.

> **Keep Linux distro names out of the Windows archive names.** The [Spark
> installer](../installer/) finds release assets by matching `.<chain>.CLI.`, which the
> Windows CLI archive also matches — it is excluded one step later by a `debian|ubuntu`
> filter on the filename. That filter, not the arch token, is what keeps `.exe` files away
> from headless Linux installs, so the `Windows` OS field has to stay recognisably
> non-Linux.

One knock-on effect worth knowing: `listAvailableBuilds()` in the Spark installer parses
asset names ending in `AMD`/`ARM`, so when a Linux user's own platform has no build, the
"available builds" notice will list `Windows (AMD)` alongside the Linux ones. It is
accurate, and Spark still refuses to install it, but it does appear in that list.

The `CLI` archive contains three stripped binaries — for example, for Lynx:

- `lynxd` — the daemon
- `lynx-cli` — the RPC client
- `lynx-tx` — the transaction utility

The `QT` archive contains one stripped binary, the desktop wallet — `lynx-qt` for Lynx. It
is a full node with a graphical wallet (send, receive, stake); it does not need `lynxd`
running alongside it. Qt itself is linked in statically, so the only things it needs from
the desktop are the X11 client libraries every Linux desktop already ships (`libxcb`,
`libxkbcommon`, `libfontconfig`, `libfreetype`). It is meant for desktops, not headless
servers; the [Spark installer](../installer/) ignores `QT` archives and only ever installs
from the `CLI` one.

The Windows archives hold the same four programs as `.exe` files (`lynxd.exe`,
`lynx-cli.exe`, `lynx-tx.exe`, `lynx-qt.exe`). They need **nothing** installed on the
target machine — Qt, OpenSSL and the mingw runtime are all linked in. Three things to know
before handing them to users:

- **One build covers Windows 10 and 11** (and back to Windows 7). Both are NT 10.0 x64 and
  load the identical PE image; the tree targets `_WIN32_WINNT=0x0601` and links with
  subsystem version 6.01.
- **64-bit only.** There is no 32-bit build. Windows 11 on ARM runs the x64 binary under
  emulation.
- **The `.exe` files are unsigned**, so Windows SmartScreen shows an "unrecognized app"
  warning on first run. Code signing is not part of this build.

Every chain's Windows `.exe` currently carries the stock Lynx icon — per-chain Windows
icons are not generated yet (see `share/branding/README.md`).

**Archives land in the directory you ran the script from** (or next to the script, if you
saved it and ran it directly). The loose binaries are deleted once the archives are sealed,
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
