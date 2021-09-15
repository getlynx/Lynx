#!/bin/bash
for i in $(seq 1 1 5); do echo "            (  $i, uint256S(\"0x$(lynx-cli getblockhash $i)\"))"; done
for i in $(seq 500000 500000 2949999); do echo "            (  $i, uint256S(\"0x$(lynx-cli getblockhash $i)\"))"; done
for i in $(seq 2979995 1 2980000); do echo "            (  $i, uint256S(\"0x$(lynx-cli getblockhash $i)\"))"; done