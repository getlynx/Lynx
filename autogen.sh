#!/bin/sh
# Copyright (c) 2013-2019 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.

export LC_ALL=C
set -e
srcdir="$(dirname "$0")"
cd "$srcdir"
if [ -z "${LIBTOOLIZE}" ] && GLIBTOOLIZE="$(command -v glibtoolize)"; then
  LIBTOOLIZE="${GLIBTOOLIZE}"
  export LIBTOOLIZE
fi
command -v autoreconf >/dev/null || \
  (echo "configuration failed, please install autoconf first" && exit 1)
autoreconf --install --force --warnings=all

if expr "'$(build-aux/config.guess --timestamp)" \< "'$(depends/config.guess --timestamp)" > /dev/null; then
  cp depends/config.guess build-aux
  cp depends/config.guess src/secp256k1/build-aux
fi
if expr "'$(build-aux/config.sub --timestamp)" \< "'$(depends/config.sub --timestamp)" > /dev/null; then
  cp depends/config.sub build-aux
  cp depends/config.sub src/secp256k1/build-aux
fi

# --- PATCH THE GENERATED FILES AFTER ALL AUTORECONF ---
sed -i '1i\
ifndef NAME\nNAME = lynx\nendif\n' Makefile.in

sed -i '/^endif$/a\
ifeq ($(NAME),lynx)\n\tCPFLAGS := -n\nelse\n\tCPFLAGS :=\nendif\n' Makefile.in

# The Qt wallet copy is prefixed with automake's @ENABLE_QT_TRUE@, which configure turns
# into "" for --with-gui=qt5 and "#" for --with-gui=no, so a CLI-only build never trips
# over a missing (or stale, from an earlier GUI build) src/qt/lynx-qt. It uses -f rather
# than $(CPFLAGS): src/qt/lynx-qt -> src/lynx-qt is a real copy even for NAME=lynx, and -n
# would freeze a stale first copy on later rebuilds.
#
# $(EXEEXT) is what lets these copies survive a Windows cross-build, where the real
# outputs are lynxd.exe / lynx-cli.exe / lynx-tx.exe / src/qt/lynx-qt.exe. Without it
# every one of these four lines fails and 'make' dies at the 'all' target AFTER a
# successful multi-hour compile. Automake substitutes EXEEXT into every generated
# Makefile.in including this one, and it is empty for every Linux host, so adding it
# is a no-op for the native x86_64/armhf/aarch64 builds.
sed -i '/^all: all-recursive$/a\
\tcp $(CPFLAGS) src/lynxd$(EXEEXT) src/$(NAME)d$(EXEEXT)\
\tcp $(CPFLAGS) src/lynx-cli$(EXEEXT) src/$(NAME)-cli$(EXEEXT)\
\tcp $(CPFLAGS) src/lynx-tx$(EXEEXT) src/$(NAME)-tx$(EXEEXT)\
@ENABLE_QT_TRUE@\tcp -f src/qt/lynx-qt$(EXEEXT) src/$(NAME)-qt$(EXEEXT)' Makefile.in

sed -i '1i\
ifndef NAME\nNAME = lynx\nendif\n' src/Makefile.in
