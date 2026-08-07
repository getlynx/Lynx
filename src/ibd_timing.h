// Copyright (c) 2026 The Lynx developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef BITCOIN_IBD_TIMING_H
#define BITCOIN_IBD_TIMING_H

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

inline std::chrono::steady_clock::time_point ibd_now()
{
    if constexpr (IBD_TIMING) return std::chrono::steady_clock::now();
    else return {};
}

#endif // BITCOIN_IBD_TIMING_H
