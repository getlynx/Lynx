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

sed -i '/^all: all-recursive$/a\
\tcp $(CPFLAGS) src/lynxd src/$(NAME)d\
\tcp $(CPFLAGS) src/lynx-cli src/$(NAME)-cli\
\tcp $(CPFLAGS) src/lynx-tx src/$(NAME)-tx' Makefile.in

sed -i '1i\
ifndef NAME\nNAME = lynx\nendif\n' src/Makefile.in
