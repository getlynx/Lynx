#!/usr/bin/env python3
# Copyright (c) 2020-2022 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
"""Test datacarrier functionality"""
from test_framework.messages import (
    CTxOut,
    MAX_OP_RETURN_RELAY,
)
from test_framework.script import (
    CScript,
    OP_RETURN,
)
from test_framework.test_framework import BitcoinTestFramework
from test_framework.test_node import TestNode
from test_framework.util import (
    assert_raises_rpc_error,
    random_bytes,
)
from test_framework.wallet import MiniWallet

# The daemon's datacarrier limit is 640, not Bitcoin's 83 (script/standard.h:39) —
# Lynx uses large OP_RETURN payloads for its storage model, and the default
# -datacarriersize equals MAX_OP_RETURN_RELAY. Shadow the framework constant so the
# data-size relationships below track the node's actual limit.
MAX_OP_RETURN_RELAY = 640


class DataCarrierTest(BitcoinTestFramework):
    def set_test_params(self):
        self.num_nodes = 3
        self.extra_args = [
            [],
            ["-datacarrier=0"],
            ["-datacarrier=1", f"-datacarriersize={MAX_OP_RETURN_RELAY - 1}"]
        ]

    def test_null_data_transaction(self, node: TestNode, data: bytes, success: bool) -> None:
        tx = self.wallet.create_self_transfer(fee_rate=0)["tx"]
        tx.vout.append(CTxOut(nValue=0, scriptPubKey=CScript([OP_RETURN, data])))
        tx.vout[0].nValue -= tx.get_vsize()  # simply pay 1sat/vbyte fee

        tx_hex = tx.serialize().hex()

        if success:
            self.wallet.sendrawtransaction(from_node=node, tx_hex=tx_hex)
            assert tx.rehash() in node.getrawmempool(True), f'{tx_hex} not in mempool'
        else:
            assert_raises_rpc_error(-26, "scriptpubkey", self.wallet.sendrawtransaction, from_node=node, tx_hex=tx_hex)

    def run_test(self):
        self.wallet = MiniWallet(self.nodes[0])

        # The datacarrier check is on scriptPubKey size (<= -datacarriersize). At the
        # daemon's 640-byte limit the data push uses OP_PUSHDATA2, so the OP_RETURN
        # script overhead is 4 (OP_RETURN + OP_PUSHDATA2 + 2-byte length), not 3.
        # Size the data so the scripts land at exactly 640 / 641 / 639 bytes.
        default_size_data = random_bytes(MAX_OP_RETURN_RELAY - 4)
        too_long_data = random_bytes(MAX_OP_RETURN_RELAY - 3)
        small_data = random_bytes(MAX_OP_RETURN_RELAY - 5)

        self.log.info("Testing null data transaction with default -datacarrier and -datacarriersize values.")
        self.test_null_data_transaction(node=self.nodes[0], data=default_size_data, success=True)

        self.log.info("Testing a null data transaction larger than allowed by the default -datacarriersize value.")
        self.test_null_data_transaction(node=self.nodes[0], data=too_long_data, success=False)

        self.log.info("Testing a null data transaction with -datacarrier=false.")
        self.test_null_data_transaction(node=self.nodes[1], data=default_size_data, success=False)

        self.log.info("Testing a null data transaction with a size larger than accepted by -datacarriersize.")
        self.test_null_data_transaction(node=self.nodes[2], data=default_size_data, success=False)

        self.log.info("Testing a null data transaction with a size smaller than accepted by -datacarriersize.")
        self.test_null_data_transaction(node=self.nodes[2], data=small_data, success=True)


if __name__ == '__main__':
    DataCarrierTest().main()
