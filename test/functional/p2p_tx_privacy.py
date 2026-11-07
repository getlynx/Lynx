#!/usr/bin/env python3
# Copyright (c) 2022 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
"""
Test that transaction announcements are only queued for peers that have
successfully completed the version handshake.

Topology:

  tx_originator ----> node[0] <---- spy

We test that a transaction sent by tx_originator is only relayed to spy
if it was received after spy's version handshake completed.

1. Fully connect tx_originator
2. Connect spy (no version handshake)
3. tx_originator sends tx1
4. spy completes the version handshake
5. tx_originator sends tx2
6. We check that only tx2 is announced on the spy interface
"""
from test_framework.messages import (
    msg_wtxidrelay,
    msg_verack,
    msg_tx,
    CInv,
    MSG_TX,
)
from test_framework.p2p import (
    P2PInterface,
)
from test_framework.test_framework import BitcoinTestFramework
from test_framework.wallet import MiniWallet

class P2PTxSpy(P2PInterface):
    def __init__(self):
        super().__init__()
        self.all_invs = []

    def on_version(self, message):
        self.send_message(msg_wtxidrelay())

    def on_inv(self, message):
        self.all_invs += message.inv

    def wait_for_inv_match(self, expected_inv):
        self.wait_until(lambda: len(self.all_invs) == 1 and self.all_invs[0] == expected_inv)

class TxPrivacyTest(BitcoinTestFramework):
    def set_test_params(self):
        self.num_nodes = 1

    def run_test(self):
        self.wallet = MiniWallet(self.nodes[0])

        tx_originator = self.nodes[0].add_p2p_connection(P2PInterface())
        spy = self.nodes[0].add_p2p_connection(P2PTxSpy(), wait_for_verack=False)
        spy.wait_for_verack()

        # tx_originator sends tx1
        tx1 = self.wallet.create_self_transfer()["tx"]
        tx_originator.send_and_ping(msg_tx(tx1))

        # Spy sends the verack
        spy.send_and_ping(msg_verack())

        # tx_originator sends tx2
        tx2 = self.wallet.create_self_transfer()["tx"]
        tx_originator.send_and_ping(msg_tx(tx2))

        # DIAG: capture what the spy actually receives before asserting
        import time
        deadline = time.time() + 25
        while time.time() < deadline and len(spy.all_invs) == 0:
            spy.sync_with_ping()
            time.sleep(1)
        self.log.info("DIAG spy invs=%s" % [(i.type, "%064x" % i.hash) for i in spy.all_invs])
        self.log.info("DIAG tx1 txid=%064x wtxid=%064x" % (tx1.calc_sha256(False), tx1.calc_sha256(True)))
        self.log.info("DIAG tx2 txid=%064x wtxid=%064x" % (tx2.calc_sha256(False), tx2.calc_sha256(True)))

        # Spy should only get an inv for the second transaction as the first
        # one was received pre-verack with the spy
        # PROTOCOL_VERSION=70006 ignores the spy's wtxidrelay (BIP339 needs 70016),
        # so the node announces by txid (MSG_TX), not wtxid (MSG_WTX).
        spy.wait_for_inv_match(CInv(MSG_TX, tx2.calc_sha256(False)))

if __name__ == '__main__':
    TxPrivacyTest().main()
