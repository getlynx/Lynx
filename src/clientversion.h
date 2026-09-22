// Copyright (c) 2009-2022 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef BITCOIN_CLIENTVERSION_H
#define BITCOIN_CLIENTVERSION_H

#include <util/macros.h>

#if defined(HAVE_CONFIG_H)
#include <config/bitcoin-config.h>
#endif //HAVE_CONFIG_H

// Check that required client information is defined
#if !defined(CLIENT_VERSION_MAJOR) || !defined(CLIENT_VERSION_MINOR) || !defined(CLIENT_VERSION_BUILD) || !defined(CLIENT_VERSION_IS_RELEASE) || !defined(COPYRIGHT_YEAR)
#error Client version information missing: version is not defined by bitcoin-config.h or in any other way
#endif

//! Copyright string used in Windows .rc files
#define COPYRIGHT_STR "2009-" STRINGIZE(COPYRIGHT_YEAR) " " COPYRIGHT_HOLDERS_FINAL

/**
 * bitcoind-res.rc includes this file, but it cannot cope with real c++ code.
 * WINDRES_PREPROC is defined to indicate that its pre-processor is running.
 * Anything other than a define should be guarded below.
 */

#if !defined(WINDRES_PREPROC)

#include <string>
#include <vector>

static const int CLIENT_VERSION =
                             10000 * CLIENT_VERSION_MAJOR
                         +     100 * CLIENT_VERSION_MINOR
                         +       1 * CLIENT_VERSION_BUILD;

extern std::string CLIENT_NAME;


std::string FormatFullVersion();
std::string FormatSubVersion(const std::string& name, int nClientVersion, const std::vector<std::string>& comments);

std::string CopyrightHolders(const std::string& strPrefix);

/** Returns licensing information (for -version) */
std::string LicenseInfo();

/**
 * The network description shown at startup in debug.log and in the GUI's About dialog.
 *
 * Kept here, in one place, so the two cannot drift apart. The chain's display name is
 * passed in rather than read from CurrentChainDisplayName(): that lives in
 * kernel/chainparams.cpp, and calling it from here would drag chainparams and its
 * genesis/merkle dependencies into every binary that links clientversion.cpp - the same
 * link-order problem the -version banner already caused for lynx-cli (see the
 * LIBBITCOIN_CONSENSUS comment in src/Makefile.am).
 *
 * Line breaks are meaningful: the text is hard-wrapped for the log, and the About dialog
 * reproduces that layout so both read identically.
 */
std::string NetworkInfo(const std::string& chain_display_name);

#endif // WINDRES_PREPROC

#endif // BITCOIN_CLIENTVERSION_H
