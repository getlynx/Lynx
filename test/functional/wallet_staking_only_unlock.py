#!/usr/bin/env python3
# Copyright (c) 2026 The Lynx developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
"""Test the staking_only option of walletpassphrase.

A staking-only unlock keeps the keys in memory for the staker but refuses
other key operations. Locking the wallet, by walletlock or by the unlock
timeout, must clear the restriction, and walletpassphrasechange must keep it.
send and sendall sign through a different path from sendtoaddress, so they are
checked separately.
"""

import time

from test_framework.test_framework import BitcoinTestFramework
from test_framework.util import assert_raises_rpc_error

STAKING_ONLY_ERROR = "Wallet is unlocked for staking only"
LOCKED_ERROR = "Please enter the wallet passphrase with walletpassphrase first"


class WalletStakingOnlyUnlockTest(BitcoinTestFramework):
    def add_options(self, parser):
        self.add_wallet_options(parser)

    def set_test_params(self):
        self.setup_clean_chain = True
        self.num_nodes = 1

    def skip_test_if_missing_module(self):
        self.skip_if_no_wallet()

    def run_test(self):
        node = self.nodes[0]
        passphrase = "WalletPassphrase"
        passphrase2 = "SecondWalletPassphrase"
        msg = "test message"
        address = node.getnewaddress(address_type='legacy')
        # Mature coins so send/sendall get past coin selection and reach the signing step
        self.generatetoaddress(node, 101, address)
        node.encryptwallet(passphrase)

        self.log.info("Staking-only unlock refuses key operations")
        node.walletpassphrase(passphrase, 0, True)
        assert_raises_rpc_error(-13, STAKING_ONLY_ERROR, node.signmessage, address, msg)
        assert_raises_rpc_error(-13, STAKING_ONLY_ERROR, node.sendtoaddress, address, 1)
        assert_raises_rpc_error(-13, STAKING_ONLY_ERROR, node.send, outputs={address: 1})
        assert_raises_rpc_error(-13, STAKING_ONLY_ERROR, node.sendall, recipients=[address])

        self.log.info("walletlock clears the staking-only state")
        node.walletlock()
        assert_raises_rpc_error(-13, LOCKED_ERROR, node.signmessage, address, msg)

        self.log.info("walletpassphrasechange keeps a staking-only unlock restricted")
        node.walletpassphrase(passphrase, 0, True)
        node.walletpassphrasechange(passphrase, passphrase2)
        assert_raises_rpc_error(-13, STAKING_ONLY_ERROR, node.signmessage, address, msg)
        node.walletlock()

        self.log.info("Timed relock clears the staking-only state")
        node.walletpassphrase(passphrase2, 2, True)
        time.sleep(3)
        assert_raises_rpc_error(-13, LOCKED_ERROR, node.signmessage, address, msg)

        self.log.info("A full unlock allows key operations")
        node.walletpassphrase(passphrase2, 0)
        sig = node.signmessage(address, msg)
        assert node.verifymessage(address, sig, msg)
        assert node.send(outputs={address: 1})["complete"]
        node.walletlock()


if __name__ == '__main__':
    WalletStakingOnlyUnlockTest().main()
