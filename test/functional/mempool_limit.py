#!/usr/bin/env python3
# Copyright (c) 2014-2022 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
"""Test mempool limiting together/eviction with the wallet."""

from decimal import Decimal

from test_framework.blocktools import COINBASE_MATURITY
from test_framework.test_framework import BitcoinTestFramework
from test_framework.util import (
    assert_equal,
    assert_greater_than,
    assert_raises_rpc_error,
    create_lots_of_big_transactions,
    gen_return_txouts,
)
from test_framework.wallet import MiniWallet


class MempoolLimitTest(BitcoinTestFramework):
    def set_test_params(self):
        self.setup_clean_chain = True
        self.num_nodes = 1
        self.extra_args = [[
            "-datacarriersize=100000",
            "-maxmempool=220",
        ]]
        self.supports_cli = False

    def run_test(self):
        txouts = gen_return_txouts()
        node = self.nodes[0]
        miniwallet = MiniWallet(node)
        relayfee = node.getnetworkinfo()['relayfee']

        self.log.info('Check that mempoolminfee is minrelaytxfee')
        assert_equal(node.getmempoolinfo()['minrelaytxfee'], Decimal('0.00001000'))
        assert_equal(node.getmempoolinfo()['mempoolminfee'], Decimal('0.00001000'))

        tx_batch_size = 1200  # bidha -maxmempool min 220 MB; 3600 ~67KB txs (~243 MB) to overflow and evict
        num_of_batches = 3
        # bidha's -maxmempool floor is 220 MB (5x Bitcoin via MAX_BLOCK_WEIGHT),
        # so the fill needs thousands of utxos. Halving-every-150 makes late
        # coinbases worth less than the fill fee, so fund from a few fat early
        # coinbases, split each into many equal outputs (all well above the fee),
        # and confirm them so the fill txs are not unconfirmed descendants.
        num_fill_utxos = num_of_batches * tx_batch_size + 10  # fill + evicted + min-fee txs
        self.generate(miniwallet, COINBASE_MATURITY + 10)  # fat 50-coin coinbases; +COINBASE_MATURITY so the first ~10 are matured, well before halving
        outputs_remaining = num_fill_utxos
        while outputs_remaining > 0:
            n = min(2000, outputs_remaining)
            miniwallet.send_self_transfer_multi(from_node=node, num_outputs=n)
            outputs_remaining -= n
        self.generate(node, 1)  # confirm split outputs so fill txs aren't mempool descendants

        self.log.info('Create a mempool tx that will be evicted')
        tx_to_be_evicted_id = miniwallet.send_self_transfer(from_node=node, fee_rate=relayfee)["txid"]

        # Increase the tx fee rate to give the subsequent transactions a higher priority in the mempool
        # The tx has an approx. vsize of 65k, i.e. multiplying the previous fee rate (in sats/kvB)
        # by 130 should result in a fee that corresponds to 2x of that fee rate
        base_fee = relayfee * 130

        self.log.info("Fill up the mempool with txs with higher fee rate")
        for batch_of_txid in range(num_of_batches):
            fee = (batch_of_txid + 1) * base_fee
            create_lots_of_big_transactions(miniwallet, node, fee, tx_batch_size, txouts)

        self.log.info('The tx should be evicted by now')
        # The number of transactions created should be greater than the ones present in the mempool
        assert_greater_than(tx_batch_size * num_of_batches, len(node.getrawmempool()))
        # Initial tx created should not be present in the mempool anymore as it had a lower fee rate
        assert tx_to_be_evicted_id not in node.getrawmempool()

        self.log.info('Check that mempoolminfee is larger than minrelaytxfee')
        assert_equal(node.getmempoolinfo()['minrelaytxfee'], Decimal('0.00001000'))
        assert_greater_than(node.getmempoolinfo()['mempoolminfee'], Decimal('0.00001000'))

        # Deliberately try to create a tx with a fee less than the minimum mempool fee to assert that it does not get added to the mempool
        self.log.info('Create a mempool tx that will not pass mempoolminfee')
        assert_raises_rpc_error(-26, "mempool min fee not met", miniwallet.send_self_transfer, from_node=node, fee_rate=relayfee)

        # Mine the ~290 MB fill into blocks so the node stops with a normal (empty) mempool,
        # like every other test, instead of tearing down a full mempool at shutdown
        while len(node.getrawmempool()) > 0:
            self.generate(node, 40)

        self.log.info('Test passing a value below the minimum (5 MB) to -maxmempool throws an error')
        self.stop_node(0)
        self.nodes[0].assert_start_raises_init_error(["-maxmempool=219"], "Error: -maxmempool must be at least 220 MB")


if __name__ == '__main__':
    MempoolLimitTest().main()
