#!/bin/bash

# Run this script as root on the target Debian 11/12.

# For easier error trapping.
set -e

if pgrep -f "lynx" >/dev/null; then
    systemctl stop lynx
    #lynx-cli stop
    # Give it a moment to shut down gracefully
    sleep 5
    rm -rf /root/.lynx/debug.log
fi

date=$(date +%Y-%m-%d)

# Format Lynx [CLI|GUI] v25.0.28 [Debian|Ubuntu] [11|12|X] [AMD|ARM]
version="Lynx CLI v25.0.30 Debian 12 AMD"

# Required <arch> argument from the list below. If not provided, defaults to "x86 Linux"

[ -z "$1" ] && arch="x86_64-pc-linux-gnu" || arch="$1"

# Options
# i686-pc-linux-gnu for Linux 32 bit
# x86_64-pc-linux-gnu for x86 Linux
# x86_64-w64-mingw32 for Win64
# x86_64-apple-darwin for macOS
# arm64-apple-darwin for ARM macOS
# arm-linux-gnueabihf for Linux ARM 32 bit
# aarch64-linux-gnu for Linux ARM 64 bit

# Prep the target OS. This will set locale, update, upgrade and install needed packages for the task.
#echo "en_US.UTF-8 UTF-8" | tee -a /etc/locale.gen
#locale-gen en_US.UTF-8
#apt-get update -y && apt-get upgrade -y && apt-get dist-upgrade -y && apt-get autoremove -y
#[ "$arch" = "x86_64-pc-linux-gnu" ] && apt install build-essential make automake curl htop git libtool binutils bsdmainutils pkg-config python3 patch bison -y
#[ "$arch" = "arm-linux-gnueabihf" ] && apt install build-essential make automake curl htop git libtool g++-arm-linux-gnueabihf binutils-arm-linux-gnueabihf gperf pkg-config bison byacc -y
#[ "$arch" = "aarch64-linux-gnu" ] && apt install build-essential make automake curl htop git libtool g++-arm-linux-gnueabihf binutils-arm-linux-gnueabihf gperf pkg-config bison byacc -y


#rm -rf /root/Lynx*
#cd /root
#git clone https://github.com/getlynx/Lynx.git
cd /root/Lynx/depends

make HOST="$arch"
cd ..
./autogen.sh
CONFIG_SITE=$PWD/depends/$arch/share/config.site ./configure --with-gui=no --enable-bench=no --enable-tests=no
make -j4

sleep 5

#apt-get install zip -y
cd /root/Lynx/src/
cp /root/Lynx/src/lynxd /usr/local/bin/.
cp /root/Lynx/src/lynx-cli /usr/local/bin/.
cp /root/Lynx/src/lynx-tx /usr/local/bin/.

zip "$date $version.zip" lynxd lynx-cli lynx-tx
mv "/root/Lynx/src/$date $version.zip" /root

