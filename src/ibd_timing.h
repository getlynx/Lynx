// Copyright (c) 2026 The Lynx developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef BITCOIN_IBD_TIMING_H
#define BITCOIN_IBD_TIMING_H

#include <atomic>
#include <chrono>

// Compile-time switch for the sync-timing instrumentation. When false, every
// stamp folds away: `IBD_TIMING && g_sync_active` is a constant-false condition
// so the accumulation is dead-code-eliminated, and ibd_now() returns a zero
// time_point without reading the clock. Set to true to compile the timing in.
inline constexpr bool IBD_TIMING = true;

// Clock read for the instrumentation only. Real (no syscall elided) when timing
// is compiled in; a zero time_point when it is not.
// Defined here (inline) rather than in a node TU so ibd_now() can gate on it
// from the lower-level consensus library too, without a cross-library symbol.
inline bool g_sync_active{false};

// Network tip height as advertised by peers (their `blocks=` in the version
// message). Captured once per connection in the version handler (a cold path,
// not the block-download routing) and read on the connect thread to space the
// ~100 "new best" UpdateTip log lines evenly from sync start. inline so both
// net_processing (writer) and validation (reader) share one symbol.
inline std::atomic<int> g_network_tip_height{0};

// [ANCHOR-ONLY SYNC] True while the node is in initial block download. Seeded
// once at startup from IsInitialBlockDownload() (init.cpp, after chain load and
// before the connect thread starts) and kept current thereafter by
// Chainstate::UpdateTip. Read on the connect thread (net.cpp
// ThreadOpenConnections) to suppress auto-outbound peer dialing during the sync,
// leaving only the 5 manual anchor connections (whose staking state we control).
// A synced node seeds false and is never restricted; a syncing node seeds true
// and reopens to normal peer selection when IBD latches off. To revert, remove
// this symbol and the four [ANCHOR-ONLY SYNC] blocks (init.cpp, validation.cpp,
// net.cpp).
inline std::atomic<bool> g_ibd_active{true};

inline std::chrono::steady_clock::time_point ibd_now()
{
    if constexpr (IBD_TIMING) return std::chrono::steady_clock::now();
    else return {};
}

#endif // BITCOIN_IBD_TIMING_H
