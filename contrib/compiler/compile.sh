#!/bin/bash

set -e

# Quick run (no args, stream + execute without saving):
#   bash <(wget -qO- https://raw.githubusercontent.com/getlynx/Lynx/main/contrib/compiler/compile.sh)
# NOTE: this URL is intentionally literal here so the line stays copy-pasteable; keep it
# in sync with BOOTSTRAP_URL below.

# Notes:
#   The list of buildable blockchains comes from the repo's own src/kernel/chainparams.cpp,
#   which hardcodes every chain's spec as spec.<field>["<chain>"] = ... . A chain becomes
#   buildable the moment it is committed there, and no chain outside that file can be built.
#   After selecting a blockchain, the latest source is fetched from git and only the
#   files that changed are recompiled — unchanged cached object files are reused, so
#   repeat builds are fast. A fresh clone + full build happens only on the first run.
#   Multiple blockchains can be selected at once as a comma-separated list of numbers
#   (e.g. "3,7,12"); they build sequentially and a summary prints at the end.
#   Once selection finishes, the build phase detaches from the terminal and logs to
#   /var/log/chain-build-<timestamp>.log, so the SSH session can be closed while
#   long batches run. Check progress later with tail -f on that log.
#   Each chain produces two dated .zip archives next to this script (or, when streamed, in
#   the directory it was launched from): a CLI archive (daemon, CLI, tx tool) and a QT
#   archive (the Qt desktop wallet). The loose binaries are deleted once zipped, so the
#   archives are the only artifacts left behind.
#   On a Debian 12 x86_64 host ONLY, each chain is additionally cross-compiled to 64-bit
#   Windows, producing a second pair of archives (...Windows.AMD.zip) holding .exe builds.
#   One .exe covers Windows 7 through 11; it is 64-bit only and unsigned, so SmartScreen
#   warns on first run. Every other host builds Linux alone and never mentions Windows.

echo "🚀 Starting the Lynx Data Storage Network (LDSN) Compiler..."

# Require root on the target VPS.
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "🔒 Must run as root on the target VPS (no sudo)."
    exit 1
fi

# Require at least 2GB RAM for building Qt/depends.
MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
MIN_KB=2097152  # 2GB
if [ "$MEM_KB" -lt "$MIN_KB" ]; then
    MEM_MB=$((MEM_KB / 1024))
    echo "🧠 Insufficient RAM: detected ~${MEM_MB}MB; need at least 2048MB (2GB)."
    exit 1
fi

# ── Global configuration defaults ───────────────────────────────────────────────
# Build targets: Debian/Ubuntu Linux on x86_64, ARM 32-bit (armhf), ARM 64-bit (aarch64).
BLOCKCHAINS=()                  # selected chain names (set later from chainparams.cpp)
ARCH_ARG=""                     # optional arch override passed on the command line
BIN_DIR="/usr/local/bin"        # PATH location for the chain-build-stop helper only

# Where the finished .zip archives land — next to this script, so they are waiting in the
# directory the operator was already standing in rather than somewhere they have to hunt
# for. The usual invocation streams the script (bash <(wget ...)), which makes $0 an
# ephemeral /dev/fd with no real directory; in that case fall back to the working directory
# the operator launched from. Resolved to an absolute path here, before any cd, because
# build_chain changes directories on its way through the build.
if [ -f "${BASH_SOURCE[0]}" ]; then
    OUTPUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    OUTPUT_DIR="$PWD"
fi
# The menu is derived from this file, read straight off the public repo. It is the same
# branch build_chain clones below, so the list offered and the source built always agree.
CHAINPARAMS_URL="https://raw.githubusercontent.com/getlynx/Lynx/main/src/kernel/chainparams.cpp"
# Where this script itself lives, quoted back to the operator when it has to be re-run.
# Served straight from the repo so a push is the only publishing step.
BOOTSTRAP_URL="https://raw.githubusercontent.com/getlynx/Lynx/main/contrib/compiler/compile.sh"

# Require interactive stdin so selection prompts work when streamed.
if [ ! -t 0 ]; then
    echo "Interactive selection requires a TTY. Re-run as: bash <(wget -qO- $BOOTSTRAP_URL)"
    exit 1
fi

# Parse arguments: optional arch arg.
POSITIONALS=()
while [ $# -gt 0 ]; do
    case "$1" in
        *)
            POSITIONALS+=("$1")
            shift
            ;;
    esac
done

INPUT1="${POSITIONALS[0]:-}"  # optional positional: arch override
case "$INPUT1" in
    x86_64-pc-linux-gnu|arm-linux-gnueabihf|aarch64-linux-gnu)
        ARCH_ARG="$INPUT1"
        ;;
    "" )
        ;;
    *)
        echo "Unrecognized argument '$INPUT1'. Expected arch."
        exit 1
        ;;
esac

# Detect and validate OS/arch; prefers explicit arch, otherwise infers.
# Also capture distro details (ID and VERSION_ID) when available.
detect_os_arch() {
    local input_arch="$1"
    local uname_s
    uname_s=$(uname -s)
    target_distro="unknown"
    target_distro_version="unknown"

    case "$uname_s" in
        Linux)
            target_os="linux"
            if [ -f /etc/os-release ]; then
                # shellcheck disable=SC1091
                . /etc/os-release
                target_distro="${ID:-unknown}"
                target_distro_version="${VERSION_ID:-unknown}"
            fi
            ;;
        *)
            echo "Error: Unsupported OS '$uname_s'. Supported OS: Linux (Debian/Ubuntu, or RHEL family x86_64)."
            exit 1
            ;;
    esac

    # Prefer explicit arch argument; otherwise detect from uname -m
    if [ -n "$input_arch" ]; then
        arch="$input_arch"
    else
        local uname_m
        uname_m=$(uname -m)
        case "$uname_m" in
            x86_64|amd64) arch="x86_64-pc-linux-gnu" ;;
            aarch64|arm64) arch="aarch64-linux-gnu" ;;
            armv7*|armv6*|armhf) arch="arm-linux-gnueabihf" ;;
            *)
                echo "Error: Unsupported machine architecture '$uname_m'."
                echo "Supported: x86_64, armhf (ARM 32-bit), arm64 (AArch64)."
                exit 1
                ;;
        esac
    fi

    # Final guard: only allow supported targets
    case "$arch" in
        x86_64-pc-linux-gnu|arm-linux-gnueabihf|aarch64-linux-gnu)
            ;;
        *)
            echo "Error: Unsupported target arch '$arch'."
            echo "Supported: x86_64-pc-linux-gnu, arm-linux-gnueabihf, aarch64-linux-gnu."
            exit 1
            ;;
    esac
}

# Install essential packages required by this script
init_packages() {
    echo "📦 Installing essential packages (curl, git, zip; htop if available)..."

    case "$DISTRO_FAMILY" in
        debian)
            apt-get update -qq >/dev/null 2>&1
            apt-get install -qq -y curl git zip >/dev/null 2>&1
            apt-get install -qq -y htop >/dev/null 2>&1 || true   # non-essential
            ;;
        rhel)
            # htop lives in EPEL; enable it best-effort so its absence isn't fatal.
            dnf install -y epel-release >/dev/null 2>&1 || true
            dnf install -y git zip >/dev/null 2>&1
            dnf install -y --allowerasing curl >/dev/null 2>&1 || true  # curl-minimal already provides curl
            dnf install -y htop >/dev/null 2>&1 || true
            ;;
        *)
            echo "⚠️  Unknown distro '$DETECTED_DISTRO'. Attempting apt-get..."
            apt-get update -qq >/dev/null 2>&1
            apt-get install -qq -y curl git zip >/dev/null 2>&1
            ;;
    esac

    echo "✅ Essential packages installed."
}

# Detect target OS/arch (optional override via ARCH_ARG)
detect_os_arch "$ARCH_ARG"
DETECTED_OS="$target_os"
DETECTED_DISTRO="$target_distro"
DETECTED_DISTRO_VERSION="$target_distro_version"
DETECTED_ARCH="$arch"
echo "🧭 Detected target OS: $target_os (${target_distro} ${target_distro_version})"
echo "🧭 Detected target architecture: $arch"

# Classify the package family so distro-specific steps (locale, system update, build
# deps) can branch consistently: "debian" = apt-based, "rhel" = dnf-based.
case "$DETECTED_DISTRO" in
    debian|ubuntu)                       DISTRO_FAMILY="debian" ;;
    rhel|centos|fedora|rocky|almalinux)  DISTRO_FAMILY="rhel" ;;
    *)                                   DISTRO_FAMILY="unknown" ;;
esac

# RHEL-family builds are x86_64-only: RHEL/Rocky/Alma repos don't ship the ARM
# cross-toolchains the depends system needs, so fail fast on any non-x86 target.
if [ "$DISTRO_FAMILY" = "rhel" ] && [ "$DETECTED_ARCH" != "x86_64-pc-linux-gnu" ]; then
    echo "❌ On RHEL-family distros (${DETECTED_DISTRO}), only x86_64 builds are supported."
    echo "   ARM targets require Debian/Ubuntu. Exiting."
    exit 1
fi

# ── Windows cross-build gate ────────────────────────────────────────────────────
# The Qt wallet is also cross-compiled to a 64-bit Windows .exe, but ONLY from a
# Debian 12 x86_64 host. That is not caution for its own sake:
#
#   * The Windows binary is fully cross-compiled and statically linked, so the host
#     distro has no bearing on which Windows releases it runs on. It only decides which
#     toolchain compiles it, which makes "newest host" a non-argument here.
#   * Debian 12 ships mingw-w64 GCC 12.2. Debian 13 ships GCC 14, which this tree's
#     Qt 5.15.5 and OpenSSL 1.1.1n predate — the same pairing the _GNU_SOURCE shim
#     further down already exists to work around on native GCC 14 builds.
#   * The project's own CI cross-compiles win64 on Ubuntu 22.04 (ci/test/00_setup_env_win64.sh),
#     the same toolchain generation as Debian 12. That is the configuration with coverage.
#   * ARM hosts have no mingw-w64 cross-toolchain in Debian at all, and RHEL repos ship
#     neither, so both are excluded by the architecture and family checks.
#
# When this is 0 the Windows target is never built and never mentioned — no prompt, no
# line in the queue header, no row in the final summary.
BUILD_WINDOWS=0
WIN_HOST="x86_64-w64-mingw32"
if [ "$DETECTED_DISTRO" = "debian" ] && [ "$DETECTED_DISTRO_VERSION" = "12" ] \
   && [ "$DETECTED_ARCH" = "x86_64-pc-linux-gnu" ]; then
    BUILD_WINDOWS=1
    echo "🪟 Windows cross-build enabled (${WIN_HOST}) — each chain also builds a 64-bit .exe set."
fi

# Initialize packages before using curl/git
init_packages

# Download chainparams.cpp, which is where the buildable blockchains are defined.
# Selection happens before any clone exists, so the file is fetched on its own rather
# than read off disk.
# curl --retry transparently retries transient HTTP errors (408/429/5xx) and timeouts
# — e.g. the occasional one-off 500 from the object store — so a single blip never
# surfaces as a failure. The surrounding MAX_RETRIES loop (exponential backoff via
# RETRY_DELAY) is the outer backstop for a sustained outage, shared by all network fetches.
CHAINPARAMS_FILE=$(mktemp /tmp/chainparams.XXXX.cpp)
MAX_RETRIES=10
RETRY_DELAY=5
for attempt in $(seq 1 "$MAX_RETRIES"); do
    if curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused "$CHAINPARAMS_URL" -o "$CHAINPARAMS_FILE"; then
        break
    fi
    if [ "$attempt" -eq "$MAX_RETRIES" ]; then
        echo "❌ Failed to download chainparams.cpp after $MAX_RETRIES attempts. Exiting."
        exit 1
    fi
    rm -f "$CHAINPARAMS_FILE"
    echo "⚠️  chainparams.cpp download failed (attempt $attempt/$MAX_RETRIES). Retrying in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
    RETRY_DELAY=$((RETRY_DELAY * 2))
done

# Harvest the chain names from the spec table in CMainParams(), where every chain is
# defined as a run of spec.<field>["<chain>"] = ... assignments. Matching ANY spec field
# (rather than one chosen key) keeps this working if a single field is ever renamed;
# the indexed forms — spec.pchMessageStart["alioth"][0] — match too, and
# spec.psztimestamp[CURRENT_CHAIN] has no quotes so it is correctly skipped.
# sort -u dedupes the many hits per chain and orders the menu alphabetically in one pass,
# so a new chain slots into place no matter where it was appended in the C++ file.
mapfile -t CHAIN_KEYS < <(grep -oP 'spec\.[A-Za-z_]\w*\["\K[^"]+(?="\])' "$CHAINPARAMS_FILE" | LC_ALL=C sort -u)
if [ "${#CHAIN_KEYS[@]}" -eq 0 ]; then
    echo "No blockchains found in chainparams.cpp."
    exit 1
fi
# Chain names are lowercase in the C++ source; capitalize for display. The lowercase form
# is recovered later via ${BLOCKCHAIN,,} for the binary names and the make NAME= label.
CHAINS=()
for chain_key in "${CHAIN_KEYS[@]}"; do
    CHAINS+=("${chain_key^}")
done

# ── Per-chain colors ────────────────────────────────────────────────────────────
# Ported from the Spark installer (contrib/installer/install.sh) so a chain wears the
# same color here as it does in Spark's chain selector: the same 100-entry xterm-256
# palette, the same djb2 hash mod 100, and the hash taken over the LOWERCASE name,
# which is the form Spark registers in /etc/spark/chains.conf.
#
# Spark additionally resolves palette collisions by walking to the next free slot, in
# each host's registry order. That machinery is deliberately not ported: it needs a
# registry and a /run/spark cache that do not exist on a build box, its result is
# host-specific, and none of the chains in chainparams.cpp collide — so the plain hash
# reproduces Spark's assignment exactly. It is also the fallback Spark itself uses for
# a chain missing from its cache. If a future chain ever does collide, it will share a
# color with an existing one here rather than being shifted.
#
# Keep this palette in sync with _SPARK_PALETTE in contrib/installer/install.sh.
_CHAIN_PALETTE=(
    20 21 26 27 32 33 38 39 44 45
    50 51 56 57 62 63 68 69 74 75
    80 81 86 87 92 93 98 99 104 105
    110 111 116 117 122 123 128 129 134 135
    140 141 146 147 152 153 158 159 164 165
    170 171 176 177 182 183 190 191 196 197
    202 203 208 209 214 215 220 221 226 227
    22 28 34 40 46 82 118 154
    124 130 136 142 148 160 166 172 178 184
    198 199 200 201 204 205 206 207 210 211 212 213
)
# djb2 hash, pure bash — no forks per chain.
_chain_hash_mod100() {
    local s="$1" i c h=5381
    for ((i=0; i<${#s}; i++)); do
        printf -v c '%d' "'${s:i:1}"
        h=$(( (h * 33 + c) & 0x7fffffff ))
    done
    printf '%d' $((h % 100))
}
# Wrap a display name (capitalized) in its color, hashing the lowercase form.
_colorize_chain() {
    local idx
    idx=$(_chain_hash_mod100 "${1,,}")
    printf '\033[1;38;5;%sm%s\033[0m' "${_CHAIN_PALETTE[$idx]}" "$1"
}
# This script always builds the tip of main, which sits ahead of the last tagged release
# and has not necessarily cleared the full unit and functional test suites. Printed twice:
# once before anything is queued, and again at the final confirmation — the second showing
# is what survives a long selection that scrolls the first one off screen, and it is the
# last thing on screen before the batch detaches and compiling actually begins.
print_risk_notice() {
    cat << 'RISKNOTICE'

⚠️  What you are about to build:
    This compiles the tip of the main branch. That is cutting-edge code which
    may not have completed the full suite of unit and functional tests, so a binary
    you build here can carry bugs that never reach a tagged release. Compiling your
    own binary means accepting that risk.

    For the most reliable binaries — the ones that have been through every test suite
    — download an official build instead:
    https://github.com/getlynx/Lynx/releases

RISKNOTICE
}

print_risk_notice
echo "🔗 Available blockchains:"

# Paged selection for long lists. A single number selects one chain; a comma-separated
# list (e.g. "3,7,12") queues several to build back-to-back. Numbers are global (1..N),
# so any number is valid from any page. Duplicates are dropped, order is preserved.
# After each selection an "add more?" prompt lets you browse other pages and keep
# queueing chains before the batch starts.
PAGE_SIZE=30
TOTAL=${#CHAINS[@]}
PAGE=0
BLOCKCHAINS=()
SELECTION_DONE=0

# Join chain names with ", " for readable queue/summary lines, each in its own color so
# the queue reads the same as the menu above it. The escapes are already literal bytes by
# the time they land in $out, so the callers' plain echo passes them through untouched.
join_chains() {
    local out="" c
    for c in "$@"; do
        [ -n "$out" ] && out+=", "
        out+="$(_colorize_chain "$c")"
    done
    printf '%s' "$out"
}

# One-line reminder of the detected build target, reshown while queueing coins.
TARGET_LINE="🧭 Building for: ${DETECTED_DISTRO^} ${DETECTED_DISTRO_VERSION} (${DETECTED_ARCH})"
# Only mentioned when the gate above opened; on every other host the operator sees the
# same single-target line the script has always printed.
[ "$BUILD_WINDOWS" -eq 1 ] && TARGET_LINE="${TARGET_LINE} + Windows (${WIN_HOST})"

while [ "$SELECTION_DONE" -eq 0 ]; do
    START=$((PAGE * PAGE_SIZE))
    if [ "$START" -ge "$TOTAL" ]; then
        PAGE=0
        START=0
    fi
    END=$((START + PAGE_SIZE))
    if [ "$END" -gt "$TOTAL" ]; then
        END=$TOTAL
    fi

    echo "🧭 Select blockchain(s) (page $((PAGE+1)) / $(( (TOTAL + PAGE_SIZE - 1)/PAGE_SIZE ))):"
    # Reprinted on every page: 0 is page-independent, so it must be reachable without
    # paging back to the first screen.
    printf "  %3s) %s\n" "0" "All Chains (${TOTAL})"
    for ((i=START; i<END; i++)); do
        num=$((i + 1))
        # %s, not %b: _colorize_chain already emits real escape bytes, and %b would
        # additionally reinterpret backslashes in the name.
        printf "  %3d) %s\n" "$num" "$(_colorize_chain "${CHAINS[$i]}")"
    done
    if [ "${#BLOCKCHAINS[@]}" -gt 0 ]; then
        echo "📋 Queued so far: $(join_chains "${BLOCKCHAINS[@]}")"
        echo "$TARGET_LINE"
    fi

    READ_RC=0
    read -r -t 900 -p "🙂 Enter number or comma-separated list (e.g. 3,7,12), 0=all, n=next, p=prev, q=quit: " CHOICE || READ_RC=$?
    if [ "$READ_RC" -gt 128 ]; then
        # Timed out: exit without building anything, even if chains are queued.
        echo ""
        echo "⏰ No input for 15 minutes. Exiting without building."
        exit 0
    fi
    if [ -z "$CHOICE" ]; then
        echo "No selection made. Exiting."
        exit 0
    fi
    case "$CHOICE" in
        [Nn])
            PAGE=$((PAGE + 1))
            ;;
        [Pp])
            if [ "$PAGE" -gt 0 ]; then
                PAGE=$((PAGE - 1))
            else
                echo "Already at first page."
            fi
            ;;
        [Qq])
            echo "Exiting."
            exit 0
            ;;
        *)
            # Parse the selection, splitting on commas AND whitespace so "22 3",
            # "22, 3", and "22,3" all mean the same thing (stripping spaces from
            # comma-split tokens would silently merge "22 3" into "223"). Any
            # invalid token rejects the whole entry so a typo can't silently
            # build the wrong subset.
            IFS=$', \t' read -r -a TOKENS <<< "$CHOICE"
            SELECTED=()
            VALID=1
            CHOSE_ALL=0
            for tok in "${TOKENS[@]}"; do
                [ -z "$tok" ] && continue
                if [ "$tok" = "0" ]; then
                    # 0 queues every chain. Mixing it with other numbers is harmless —
                    # the dedupe below drops the redundant ones — so "0,3" still means all.
                    SELECTED+=("${CHAINS[@]}")
                    CHOSE_ALL=1
                elif [[ "$tok" =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le "$TOTAL" ]; then
                    SELECTED+=("${CHAINS[$((tok-1))]}")
                else
                    echo "Invalid selection: '$tok'"
                    VALID=0
                    break
                fi
            done
            # Confirm the all-chains path before it lands in the queue. Building every
            # chain is a many-hour commitment, and 0 used to mean a single default build
            # in earlier versions of this script — so anyone acting on muscle memory gets
            # a chance to back out. Silence defaults to NO: a stray "0<Enter><Enter>"
            # declines and returns to the picker rather than starting the batch.
            if [ "$VALID" -eq 1 ] && [ "$CHOSE_ALL" -eq 1 ]; then
                echo "⚠️  That queues ALL ${TOTAL} chains, one after another — expect this to run for hours."
                READ_RC=0
                read -r -t 900 -p "❓ Build all ${TOTAL} chains? (y = yes, anything else = go back): " CONFIRM_ALL || READ_RC=$?
                if [ "$READ_RC" -gt 128 ]; then
                    echo ""
                    echo "⏰ No input for 15 minutes. Exiting without building."
                    exit 0
                fi
                if [[ ! "$CONFIRM_ALL" =~ ^[Yy] ]]; then
                    echo "↩️  Cancelled — nothing added to the queue."
                    continue
                fi
            fi
            if [ "$VALID" -eq 1 ] && [ "${#SELECTED[@]}" -gt 0 ]; then
                # Dedupe while preserving the order entered.
                for chain in "${SELECTED[@]}"; do
                    dup=0
                    for existing in "${BLOCKCHAINS[@]}"; do
                        if [ "$existing" = "$chain" ]; then
                            dup=1
                            break
                        fi
                    done
                    [ "$dup" -eq 0 ] && BLOCKCHAINS+=("$chain")
                done
                echo "📋 Build queue: $(join_chains "${BLOCKCHAINS[@]}")"
                echo "$TARGET_LINE"
                READ_RC=0
                read -r -t 900 -p "➕ Add more? (y = keep selecting, Enter = start detached build): " MORE || READ_RC=$?
                if [ "$READ_RC" -gt 128 ]; then
                    # Timed out: exit without building — starting a long batch
                    # unattended must be a deliberate keypress, not a timeout.
                    echo ""
                    echo "⏰ No input for 15 minutes. Exiting without building."
                    exit 0
                fi
                case "$MORE" in
                    [Yy]*) ;;                    # loop back to the picker
                    *)     SELECTION_DONE=1 ;;   # anything else starts the batch
                esac
            fi
            ;;
    esac
done
echo "✅ Selected blockchain(s) (${#BLOCKCHAINS[@]}): $(join_chains "${BLOCKCHAINS[@]}")"
echo "$TARGET_LINE"
print_risk_notice

# ── Detached build phase ────────────────────────────────────────────────────────
# Everything from here down (system prep, per-chain builds, summary) runs detached
# from the terminal so the SSH session can be closed while a multi-hour batch runs.
# The script is usually streamed (bash <(wget ...)), so $0 is an ephemeral /dev/fd
# and a setsid re-exec isn't possible; instead the phase runs in a backgrounded
# subshell — which inherits all functions and variables — with SIGHUP ignored,
# stdio detached from the TTY, and the job disowned, so neither bash's exit nor a
# dropped SSH connection can kill it. All output lands in $LOG_FILE.
run_build_phase() {
    echo "🕐 Build phase started: $(date)"

    # Supported OS / arch matrix:
    #   - Debian/Ubuntu: x86_64, arm-linux-gnueabihf (32-bit ARM), aarch64-linux-gnu (64-bit ARM)
    #   - RHEL family (Rocky/Alma/RHEL 8-9): x86_64 only (RHEL repos lack ARM cross-toolchains)

    # Prep the target OS. This sets locale, updates the system, and installs build deps.
    # Note: this is intentionally non-interactive and may take time on fresh systems.
    # This depends only on the distro/arch, so it runs once no matter how many chains build.
    echo "📦 Preparing system locale and build dependencies (output suppressed)..."
    if [ "$DISTRO_FAMILY" = "rhel" ]; then
        # RHEL ships en_US.UTF-8 via the glibc English langpack (no /etc/locale.gen).
        dnf install -y glibc-langpack-en >/dev/null 2>&1 || true
    else
        # Debian/Ubuntu: enable the locale in /etc/locale.gen, then generate it.
        LOCALE_ENTRY="en_US.UTF-8 UTF-8"
        if ! grep -q "^$LOCALE_ENTRY" /etc/locale.gen; then
            echo "$LOCALE_ENTRY" >> /etc/locale.gen
        fi
        sleep 2
        if ! locale -a 2>/dev/null | grep -qi '^en_us\.utf8$'; then
            locale-gen en_US.UTF-8
        fi
    fi
    sleep 2
    echo "🧰 Updating system packages (output suppressed)..."
    if [ "$DISTRO_FAMILY" = "rhel" ]; then
        dnf -y upgrade >/dev/null 2>&1 && dnf -y autoremove >/dev/null 2>&1
    else
        apt-get update -y >/dev/null 2>&1 && apt-get upgrade -y >/dev/null 2>&1 && apt-get dist-upgrade -y >/dev/null 2>&1 && apt-get autoremove -y >/dev/null 2>&1
    fi
    sleep 2
    echo "🧰 Installing build dependencies for $arch (output suppressed)..."
    if [ "$DISTRO_FAMILY" = "rhel" ]; then
        # RHEL family, x86_64 only (guarded above). Native toolchain via "Development Tools".
        # util-linux supplies hexdump (Debian's bsdmainutils); pkgconf-pkg-config supplies
        # pkg-config. --allowerasing lets curl replace curl-minimal.
        dnf -y groupinstall "Development Tools" >/dev/null 2>&1 || dnf -y group install "Development Tools" >/dev/null 2>&1
        dnf -y --allowerasing install make automake curl git libtool binutils util-linux \
            pkgconf-pkg-config python3 patch bison zip openssl >/dev/null 2>&1
    else
        # Debian/Ubuntu: native build tools for x86_64, cross-toolchains for ARM targets.
        # bsdextrautils provides hexdump on Debian 12+/Ubuntu (it replaced bsdmainutils).
        [ "$arch" = "x86_64-pc-linux-gnu" ] && apt install -qq -y build-essential make automake curl htop git libtool binutils bsdextrautils pkg-config python3 patch bison zip openssl >/dev/null 2>&1
        [ "$arch" = "arm-linux-gnueabihf" ] && apt install -qq -y build-essential make automake curl htop git libtool g++-arm-linux-gnueabihf binutils-arm-linux-gnueabihf gperf pkg-config bison byacc zip openssl >/dev/null 2>&1
        [ "$arch" = "aarch64-linux-gnu" ] && apt install -qq -y build-essential make automake curl htop git libtool g++-aarch64-linux-gnu binutils-aarch64-linux-gnu gperf pkg-config bison byacc zip openssl >/dev/null 2>&1
        # The mingw-w64 cross-toolchain, only when the Windows gate opened (Debian 12 x86_64).
        # The -posix variant matters: depends/hosts/mingw32.mk auto-selects
        # x86_64-w64-mingw32-g++-posix when it is on PATH, which is how the POSIX threading
        # model gets picked without the old 'update-alternatives' dance. binutils-mingw-w64-x86-64
        # supplies x86_64-w64-mingw32-windres — configure treats a missing windres as a HARD
        # error, not a warning — plus the matching strip used when archiving below.
        # nsis is deliberately not installed: this build ships .zip archives, not an installer,
        # and configure only warns when makensis is absent.
        if [ "$BUILD_WINDOWS" -eq 1 ]; then
            echo "🧰 Installing the mingw-w64 cross-toolchain for ${WIN_HOST} (output suppressed)..."
            apt install -qq -y g++-mingw-w64-x86-64-posix binutils-mingw-w64-x86-64 >/dev/null 2>&1
            # A missing cross-compiler must not silently degrade into "Windows just failed
            # every chain" three hours from now. Verify the three tools the build actually
            # shells out to, and disable the Windows target up front if any is absent.
            for _wintool in "${WIN_HOST}-g++-posix" "${WIN_HOST}-windres" "${WIN_HOST}-strip"; do
                if ! command -v "$_wintool" >/dev/null 2>&1; then
                    echo "⚠️  $_wintool not found after install — disabling the Windows target for this run."
                    BUILD_WINDOWS=0
                    break
                fi
            done
            [ "$BUILD_WINDOWS" -eq 1 ] && echo "✅ mingw-w64 cross-toolchain ready."
        fi
    fi

    # ── Per-chain build ─────────────────────────────────────────────────────────────
    # Everything chain-specific lives here: checkout, depends, configure, make, install,
    # strip, archive. Invoked once per selected blockchain, inside a subshell so a failed
    # chain can't leak state (cwd, variables) into the next build or abort the batch.
    # $2 is the target: "linux" (the native host) or "windows" (cross-compiled to
    # x86_64-w64-mingw32). It defaults to linux so any older call site still means what it
    # used to. Every target-specific value is derived once, here, and the body below reads
    # only those variables — there is no second copy of the build logic.
    build_chain() {
        local BLOCKCHAIN="$1"
        local TARGET="${2:-linux}"

        # Standardized names/paths derived from blockchain name.
        local BASE_NAME="${BLOCKCHAIN,,}"
        local BIN_BASE="$BASE_NAME"
        local WORKDIR="/root/${BASE_NAME}"

        # Per-target derivations.
        #
        # WORKDIR is deliberately a SEPARATE tree for Windows. The two targets cannot share
        # one checkout: a second ./configure would overwrite the first's config.status and
        # object cache, so every run would rebuild both targets from scratch and destroy the
        # "repeat builds are fast" property this script is built around. Two trees cost disk
        # and buy back incremental rebuilds for each target independently.
        #
        # EXEEXT mirrors the autotools variable of the same name; it is what makes the
        # binary lookups below find lynxd.exe rather than lynxd on the Windows target.
        local BUILD_HOST EXEEXT STRIP_BIN os_label arch_label target_label
        if [ "$TARGET" = "windows" ]; then
            BUILD_HOST="$WIN_HOST"
            WORKDIR="/root/${BASE_NAME}-win64"
            EXEEXT=".exe"
            STRIP_BIN="${WIN_HOST}-strip"
            # Archive labels. The arch token stays AMD, the same token x86_64 carries on
            # Linux — this builds for x86_64 Windows only, and reusing the token keeps one
            # vocabulary across every archive (and leaves ARM free if Windows-on-ARM is ever
            # built natively).
            #
            # The os_label is what keeps these archives away from headless Linux installs:
            # Spark (contrib/installer/install.sh) matches assets on ".<chain>.CLI." — which
            # the Windows CLI archive DOES match — and then filters with grep -iE
            # "debian|ubuntu", which "Windows" cannot pass. So never put a Linux distro name
            # in here; the arch token is not what provides that separation.
            os_label="Windows"
            arch_label="AMD"
            target_label="Windows"
        else
            BUILD_HOST="$DETECTED_ARCH"
            EXEEXT=""
            case "$DETECTED_ARCH" in
                arm-linux-gnueabihf)  STRIP_BIN="arm-linux-gnueabihf-strip" ;;
                aarch64-linux-gnu)    STRIP_BIN="aarch64-linux-gnu-strip" ;;
                *)                    STRIP_BIN="strip" ;;
            esac
            case "$DETECTED_ARCH" in
                x86_64-pc-linux-gnu)                      arch_label="AMD" ;;
                arm-linux-gnueabihf|aarch64-linux-gnu)    arch_label="ARM" ;;
                *)                                        arch_label="$DETECTED_ARCH" ;;
            esac
            os_label="${DETECTED_DISTRO^}.${DETECTED_DISTRO_VERSION}"
            target_label="Linux"
        fi
        # Falling back to the native strip is only ever right for a Linux target. Handing a
        # PE/COFF .exe to the host strip is not a graceful degradation — it either refuses
        # the format or produces a corrupt binary that fails at run time on Windows, long
        # after anyone is watching this log. The toolchain check during package install
        # should already have caught this and disabled the Windows target, so reaching here
        # means something removed the cross-strip mid-run: fail the chain instead.
        if ! command -v "$STRIP_BIN" >/dev/null 2>&1; then
            if [ "$TARGET" = "windows" ]; then
                echo "❗ $STRIP_BIN not found; refusing to strip a Windows .exe with the host strip."
                exit 1
            fi
            STRIP_BIN="strip"
        fi
        echo "🎯 Target: ${target_label} (host ${BUILD_HOST}, workdir ${WORKDIR})"

        cd /root
        # First run: clone fresh. Subsequent runs: fetch the latest source and hard-reset to the
        # upstream tip so ONLY changed files get new timestamps. make then recompiles just those
        # objects and reuses every unchanged cached object file, keeping repeat builds fast.
        if [ ! -d "$WORKDIR/.git" ]; then
            echo "⬇️  Cloning repository fresh..."
            rm -rf "$WORKDIR"   # clear any partial/non-git dir so the clone target is empty
            MAX_RETRIES=10
            RETRY_DELAY=5
            for attempt in $(seq 1 "$MAX_RETRIES"); do
                if git clone https://github.com/getlynx/Lynx.git "$WORKDIR"; then
                    break
                fi
                if [ "$attempt" -eq "$MAX_RETRIES" ]; then
                    echo "❌ git clone failed after $MAX_RETRIES attempts. Exiting."
                    exit 1
                fi
                rm -rf "$WORKDIR"
                echo "⚠️  git clone failed (attempt $attempt/$MAX_RETRIES). Retrying in ${RETRY_DELAY}s..."
                sleep "$RETRY_DELAY"
                RETRY_DELAY=$((RETRY_DELAY * 2))
            done
        else
            echo "🔄 Updating existing clone to latest source..."
            cd "$WORKDIR"
            MAX_RETRIES=10
            RETRY_DELAY=5
            for attempt in $(seq 1 "$MAX_RETRIES"); do
                if git fetch --prune origin; then
                    break
                fi
                if [ "$attempt" -eq "$MAX_RETRIES" ]; then
                    echo "❌ git fetch failed after $MAX_RETRIES attempts. Exiting."
                    exit 1
                fi
                echo "⚠️  git fetch failed (attempt $attempt/$MAX_RETRIES). Retrying in ${RETRY_DELAY}s..."
                sleep "$RETRY_DELAY"
                RETRY_DELAY=$((RETRY_DELAY * 2))
            done
            # Hard-reset tracked files to the fetched upstream tip (handles force-pushes/rebases too).
            # Untracked build artifacts (compiled objects, built depends) are left in place for reuse.
            git reset --hard "@{u}"
            cd /root
        fi
        cd "$WORKDIR/depends"

        # Build depends only when they haven't been built yet (config.site absent); an existing
        # depends build is reused to keep recompiles fast.
        if [ ! -f "$WORKDIR/depends/$BUILD_HOST/share/config.site" ]; then
            echo "🧰 Building depends for $BUILD_HOST ..."
            # _GNU_SOURCE exposes POSIX functions (fileno, fdopen) that OpenSSL 1.1.1n
            # needs but are hidden under strict -std=c11 on Debian 13+ / GCC 14+.
            # Python 3.12+ removed the 'imp' module that xcb_proto's build uses for
            # byte-compiling .py files. Setting am_cv_python_pyc_compile_flag to empty
            # and am_cv_python_pyo_compile_flag to empty skips the broken py_compile
            # step. Alternatively, we patch the generated Makefile after extraction.
            # The simplest fix: create a shim 'imp' module so the inline py_compile works.
            PYTHON_USER_SITE=$(python3 -m site --user-site 2>/dev/null || echo "/root/.local/lib/python3/dist-packages")
            mkdir -p "$PYTHON_USER_SITE"
            if ! python3 -c "import imp" 2>/dev/null; then
                cat > "$PYTHON_USER_SITE/imp.py" << 'IMPSHIM'
import importlib
import importlib.util

def find_module(name, path=None):
    spec = importlib.util.find_spec(name, path)
    if spec is None:
        raise ImportError(f"No module named {name!r}")
    return (None, spec.origin, ("", "", 0))

def load_module(name, file, pathname, description):
    return importlib.import_module(name)
IMPSHIM
                echo "🩹 Installed imp shim for Python 3.12+ compatibility (xcb_proto)."
            fi
            # The -fPIC/_GNU_SOURCE overrides are native-Linux workarounds and are wrong for
            # mingw: -fPIC is meaningless on Windows (configure skips it there outright) and
            # _GNU_SOURCE is a glibc concept. depends/hosts/mingw32.mk already supplies the
            # right flags for the Windows host, so pass it nothing and let it do its job.
            if [ "$TARGET" = "windows" ]; then
                make -j8 HOST=$BUILD_HOST
            else
                make -j8 HOST=$BUILD_HOST CFLAGS="-fPIC -D_GNU_SOURCE" CXXFLAGS="-fPIC -D_GNU_SOURCE"
            fi
        else
            echo "♻️  Reusing existing depends for $BUILD_HOST (no make)."
        fi
        cd ..

        # Always (re)generate the ./configure script via autogen so it is never stale.
        # The conditional skip below is intentionally left commented out.
        #if [ "$CLEAN" -eq 1 ] || [ ! -f "./configure" ]; then
            ./autogen.sh  # generate configure script
        #else
        #    echo "♻️  Reusing existing configure script (no autogen)."
        #fi
        # Always run ./configure; the conditional skip below is intentionally left commented out.
        #if [ "$CLEAN" -eq 1 ] || [ ! -f "$PWD/config.log" ]; then
            echo "🛠️  Running configure for $BUILD_HOST (Qt GUI on, no bench/tests, reduced exports)..."
            # The Qt wallet is built from the static Qt in depends (built above without NO_QT=1),
            # so no Qt host packages are needed; libqrencode is auto-detected from depends too.
            # Benches and tests are left out to speed up the build.
            # --enable-reduce-exports hides internal symbols (-fvisibility=hidden) to trim binary size.
            CONFIG_SITE=$PWD/depends/$BUILD_HOST/share/config.site ./configure --with-gui=qt5 --enable-bench=no --enable-tests=no --enable-reduce-exports
        #else
            #echo "♻️  Reusing existing configure output (skipping ./configure)."
        #fi
        echo "🔨 Building core binaries and the Qt wallet..."

        # NAME is what src/Makefile.am turns into -DCURRENT_CHAIN, which selects the chain's
        # row out of the spec table in chainparams.cpp and names its .conf file. Every chain
        # passes it, lynx included — omitting it compiles CURRENT_CHAIN as "", which looks up
        # an empty spec and trips the genesis assert at startup.
        make NAME="$BIN_BASE" V=1

        # Install the four binaries (daemon, CLI, tx tool, Qt wallet); they are stripped and
        # archived further below.
        local SRC_DIR="$WORKDIR/src"

        # Legacy: older builds always emitted lynx* binaries that had to be renamed per chain.
        # The current build passes 'make NAME=' (above) to emit ${BIN_BASE}* directly, so this
        # rename step is no longer needed and is kept here, disabled, only for reference.
        #if [ "$BIN_BASE" != "lynx" ]; then
        #    cp -n "$SRC_DIR/lynxd" "$SRC_DIR/${BIN_BASE}d"
        #    cp -n "$SRC_DIR/lynx-cli" "$SRC_DIR/${BIN_BASE}-cli"
        #    cp -n "$SRC_DIR/lynx-tx" "$SRC_DIR/${BIN_BASE}-tx"
        #fi

        # The Qt wallet is a required output: a chain whose GUI failed to build is a failed
        # chain, not a CLI-only success, so it is checked with the same loop as the rest.
        # $EXEEXT is "" on Linux and ".exe" on Windows, so this one list covers both targets.
        # These are the names autogen.sh's injected 'all:' rules produce from NAME=.
        local BINARIES=("$SRC_DIR/${BIN_BASE}d${EXEEXT}" "$SRC_DIR/${BIN_BASE}-cli${EXEEXT}" "$SRC_DIR/${BIN_BASE}-tx${EXEEXT}" "$SRC_DIR/${BIN_BASE}-qt${EXEEXT}")

        # Ensure expected binaries exist before installing.
        for bin_path in "${BINARIES[@]}"; do
            if [ ! -f "$bin_path" ]; then
                echo "❗ Expected binary not found: $bin_path"
                exit 1
            fi
        done

        # Stage the four binaries next to the script so they can be stripped without
        # touching the build tree's copies (which keep their symbols for debugging). They
        # are deleted again once the archives are sealed — only the .zip files are meant to survive.
        mkdir -p "$OUTPUT_DIR"
        for bin_path in "${BINARIES[@]}"; do
            echo "📥 Staging $(basename "$bin_path") in $OUTPUT_DIR..."
            install -m 755 "$bin_path" "$OUTPUT_DIR/"
        done

        # Strip symbols/debug info to shrink production binaries. $STRIP_BIN was resolved
        # per target at the top of this function (the ARM cross-strips, the mingw strip, or
        # the native one), so there is nothing arch-specific left to decide here.
        for bin_path in "${BINARIES[@]}"; do
            "$STRIP_BIN" --strip-all "$OUTPUT_DIR/$(basename "$bin_path")"
            echo "✂️  Stripped $(basename "$bin_path") with $STRIP_BIN"
        done

        # Build descriptive, space-free archive names, one per deliverable:
        #   DATE.Blockchain.CLI.vVERSION.Distro.DistroVer.ARCH.zip   (daemon, CLI, tx tool)
        #   DATE.Blockchain.QT.vVERSION.Distro.DistroVer.ARCH.zip    (Qt desktop wallet)
        local build_date
        build_date=$(date +%Y-%m-%d)

        # Derive the client version from the cloned source (e.g. v27.0.0).
        local CONFIGURE_AC="$WORKDIR/configure.ac"
        local ver_major ver_minor ver_build version
        ver_major=$(grep -oP '_CLIENT_VERSION_MAJOR,\s*\K[0-9]+' "$CONFIGURE_AC" 2>/dev/null | head -n1)
        ver_minor=$(grep -oP '_CLIENT_VERSION_MINOR,\s*\K[0-9]+' "$CONFIGURE_AC" 2>/dev/null | head -n1)
        ver_build=$(grep -oP '_CLIENT_VERSION_BUILD,\s*\K[0-9]+' "$CONFIGURE_AC" 2>/dev/null | head -n1)
        # Older Bitcoin-derived trees use REVISION instead of BUILD.
        [ -z "$ver_build" ] && ver_build=$(grep -oP '_CLIENT_VERSION_REVISION,\s*\K[0-9]+' "$CONFIGURE_AC" 2>/dev/null | head -n1)
        if [ -n "$ver_major" ]; then
            version="v${ver_major}.${ver_minor:-0}.${ver_build:-0}"
        else
            version="vunknown"
        fi

        # $os_label and $arch_label were resolved per target at the top of this function:
        #   Linux   -> "Debian.12"  + "AMD"  =>  ...CLI.v28.0.0.Debian.12.AMD.zip
        #   Windows -> "Windows"    + "AMD"  =>  ...CLI.v28.0.0.Windows.AMD.zip
        # The Windows name intentionally has one segment fewer than the Linux name, because
        # the Windows release version is not a build axis — one .exe covers Windows 7 to 11.
        local archive_path="$OUTPUT_DIR/${build_date}.${BLOCKCHAIN}.CLI.${version}.${os_label}.${arch_label}.zip"
        zip -q -j "$archive_path" "$OUTPUT_DIR/${BIN_BASE}d${EXEEXT}" "$OUTPUT_DIR/${BIN_BASE}-cli${EXEEXT}" "$OUTPUT_DIR/${BIN_BASE}-tx${EXEEXT}"
        echo "📦 Archived to $archive_path"

        # The Qt wallet ships in its own archive. Spark (contrib/installer/install.sh) only
        # downloads release assets whose name contains ".<chain>.CLI.", so a ".QT." archive is
        # invisible to headless installs and the CLI zip stays small. The Qt binary is statically
        # linked against depends' Qt; on a Linux desktop it still needs the distro's libxcb,
        # libxkbcommon, libfontconfig and libfreetype, which every desktop install already has.
        # The Windows .exe needs nothing installed at all — Qt, OpenSSL and the mingw runtime
        # are all linked in — but it is unsigned, so Windows SmartScreen will warn on first run.
        local qt_archive_path="$OUTPUT_DIR/${build_date}.${BLOCKCHAIN}.QT.${version}.${os_label}.${arch_label}.zip"
        zip -q -j "$qt_archive_path" "$OUTPUT_DIR/${BIN_BASE}-qt${EXEEXT}"
        echo "📦 Archived to $qt_archive_path"

        # Final cleanup: the archives now hold everything, so drop the four loose binaries
        # rather than leaving four per chain lying around next to the .zip files. Done only
        # after both zips have returned successfully — under 'set -e' a failed zip aborts the
        # chain before this point, leaving the staged binaries in place to inspect.
        rm -f "$OUTPUT_DIR/${BIN_BASE}d${EXEEXT}" "$OUTPUT_DIR/${BIN_BASE}-cli${EXEEXT}" "$OUTPUT_DIR/${BIN_BASE}-tx${EXEEXT}" "$OUTPUT_DIR/${BIN_BASE}-qt${EXEEXT}"
        echo "🧹 Removed the loose ${BIN_BASE}d${EXEEXT} / ${BIN_BASE}-cli${EXEEXT} / ${BIN_BASE}-tx${EXEEXT} / ${BIN_BASE}-qt${EXEEXT} binaries; the .zip files are the deliverable."
    }

    # Targets to build for every selected chain. Linux is always first so that a Windows
    # failure never costs the operator the Linux archives that already built cleanly.
    TARGETS=("linux")
    [ "$BUILD_WINDOWS" -eq 1 ] && TARGETS+=("windows")

    # Build each (chain x target) pair in turn. Each build runs in a subshell with errexit
    # re-enabled, so one pair failing (or calling exit 1) marks that pair failed and
    # the loop moves on to the next instead of killing the whole batch.
    BUILT=()
    FAILED=()
    CHAIN_NUM=0
    TOTAL_BUILDS=$(( ${#BLOCKCHAINS[@]} * ${#TARGETS[@]} ))
    for BLOCKCHAIN in "${BLOCKCHAINS[@]}"; do
        for TARGET in "${TARGETS[@]}"; do
            CHAIN_NUM=$((CHAIN_NUM + 1))
            # Only name the target when there is more than one, so a Linux-only host's log
            # reads exactly as it always has.
            if [ "${#TARGETS[@]}" -gt 1 ]; then
                BUILD_LABEL="${BLOCKCHAIN} (${TARGET})"
            else
                BUILD_LABEL="${BLOCKCHAIN}"
            fi
            echo ""
            echo "🏗️  [${CHAIN_NUM}/${TOTAL_BUILDS}] Building ${BUILD_LABEL}..."
            set +e
            ( set -e; build_chain "$BLOCKCHAIN" "$TARGET" )
            BUILD_RC=$?
            set -e
            if [ "$BUILD_RC" -eq 0 ]; then
                BUILT+=("$BUILD_LABEL")
            else
                FAILED+=("$BUILD_LABEL")
                echo "❌ Build failed for ${BUILD_LABEL} (exit ${BUILD_RC}); continuing with the next build."
            fi
        done
    done

    # Compile-only script: the .zip archives are now in $OUTPUT_DIR. Drop the
    # temp chainparams.cpp copy and finish — no conf/service/chainspecs are written and no
    # daemon is started.
    rm -f "$CHAINPARAMS_FILE"
    echo ""
    echo "🏁 Batch complete — ${#BUILT[@]}/${TOTAL_BUILDS} build(s) succeeded. Archives are in $OUTPUT_DIR."
    for chain in "${BUILT[@]}"; do
        echo "   ✅ $chain"
    done
    for chain in "${FAILED[@]}"; do
        echo "   ❌ $chain"
    done

    # Print a copy-paste scp command for pulling every built .zip archive down to the
    # local machine's Desktop. Prefer the public IP (what scp must dial from outside);
    # fall back to the primary local address if the lookup fails or times out.
    if compgen -G "$OUTPUT_DIR/*.zip" >/dev/null; then
        SERVER_IP=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null)
        [ -z "$SERVER_IP" ] && SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        if [ -n "$SERVER_IP" ]; then
            echo ""
            echo "⬇️  To download all built archives, run this on your LOCAL machine:"
            echo "    scp \"root@${SERVER_IP}:${OUTPUT_DIR}/*.zip\" ~/Desktop/"
        fi
    fi

    echo "🕐 Build phase finished: $(date)"
    if [ "${#FAILED[@]}" -gt 0 ]; then
        exit 1
    fi
}

# Launch the build phase detached (see the block comment above run_build_phase),
# hand the user the commands to watch/check it, and exit so the terminal is free.
LOG_FILE="/var/log/chain-build-$(date +%Y%m%d-%H%M%S).log"
PID_FILE="/var/run/chain-build.pid"

# Install a companion 'chain-build-stop' command so a running batch can be cancelled
# without hunting PIDs in top. Killing the recorded PID alone isn't enough — make
# spawns a tree of compiler children — so it signals the whole process group.
# NOTE: the PID file path is intentionally literal here; keep it in sync with
# PID_FILE above.
cat > "$BIN_DIR/chain-build-stop" << 'STOPSCRIPT'
#!/bin/bash
# Stop a detached chain build (the build shell, make, and all compiler children).
PID_FILE="/var/run/chain-build.pid"
if [ ! -f "$PID_FILE" ]; then
    echo "No build PID file at $PID_FILE — nothing to stop."
    exit 1
fi
PID=$(cat "$PID_FILE")
PGID=$(ps -o pgid= -p "$PID" 2>/dev/null | tr -d '[:space:]')
if [ -z "$PGID" ]; then
    echo "Build process $PID is not running (already finished?). Removing stale PID file."
    rm -f "$PID_FILE"
    exit 0
fi
echo "🛑 Stopping build process group $PGID (PID $PID)..."
kill -TERM -- "-$PGID"
for _ in $(seq 1 10); do
    kill -0 "$PID" 2>/dev/null || break
    sleep 1
done
if kill -0 "$PID" 2>/dev/null; then
    echo "Still running after 10s; forcing with SIGKILL..."
    kill -KILL -- "-$PGID"
fi
rm -f "$PID_FILE"
echo "✅ Build stopped. Re-run the LDSN Compiler to start a new batch."
STOPSCRIPT
chmod 755 "$BIN_DIR/chain-build-stop"
# Ignore HUP in the PARENT before forking: the subshell inherits the ignore from
# birth. Setting the trap inside the subshell instead would race — the terminal's
# HUP on parent exit can arrive before the child is ever scheduled, killing it.
trap '' HUP
( run_build_phase ) </dev/null >>"$LOG_FILE" 2>&1 &
BUILD_PID=$!
disown "$BUILD_PID"
echo "$BUILD_PID" > "$PID_FILE"
echo ""
echo "🛫 Build phase detached (PID ${BUILD_PID}) — you can close this terminal now."
echo "   🪵 Watch progress:  tail -f $LOG_FILE"
echo "   🔍 Still running?   ps -p \$(cat $PID_FILE) || echo done"
echo "   🛑 Cancel build:    chain-build-stop"
if [ "$BUILD_WINDOWS" -eq 1 ]; then
    echo "   📦 Results land in $OUTPUT_DIR (dated .zip archives: CLI + QT per chain, for Linux and Windows)."
else
    echo "   📦 Results land in $OUTPUT_DIR (dated .zip archives: one CLI and one QT per chain)."
fi
exit 0