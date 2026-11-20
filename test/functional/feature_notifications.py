#!/usr/bin/env python3
# Copyright (c) 2014-2022 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
"""Test the -alertnotify, -blocknotify and -walletnotify options."""
import os

from test_framework.address import ADDRESS_BCRT1_UNSPENDABLE
from test_framework.descriptors import descsum_create
from test_framework.test_framework import BitcoinTestFramework
from test_framework.util import (
    assert_equal,
)

# Linux allow all characters other than \x00
# Windows disallow control characters (0-31) and /\?%:|"<>
FILE_CHAR_START = 32 if os.name == 'nt' else 1
FILE_CHAR_END = 128
FILE_CHARS_DISALLOWED = '/\\?%*:|"<>' if os.name == 'nt' else '/'
UNCONFIRMED_HASH_STRING = 'unconfirmed'

def notify_outputname(walletname, txid):
    return txid if os.name == 'nt' else f'{walletname}_{txid}'


class NotificationsTest(BitcoinTestFramework):
    def add_options(self, parser):
        self.add_wallet_options(parser)

    def set_test_params(self):
        self.num_nodes = 2
        self.setup_clean_chain = True
        # The experimental syscall sandbox feature (-sandbox) is not compatible with -alertnotify,
        # -blocknotify, -walletnotify or -shutdownnotify (which all invoke execve).
        self.disable_syscall_sandbox = True

    def setup_network(self):
        self.wallet = ''.join(chr(i) for i in range(FILE_CHAR_START, FILE_CHAR_END) if chr(i) not in FILE_CHARS_DISALLOWED)
        self.alertnotify_dir = os.path.join(self.options.tmpdir, "alertnotify")
        self.blocknotify_dir = os.path.join(self.options.tmpdir, "blocknotify")
        self.walletnotify_dir = os.path.join(self.options.tmpdir, "walletnotify")
        self.shutdownnotify_dir = os.path.join(self.options.tmpdir, "shutdownnotify")
        self.shutdownnotify_file = os.path.join(self.shutdownnotify_dir, "shutdownnotify.txt")
        os.mkdir(self.alertnotify_dir)
        os.mkdir(self.blocknotify_dir)
        os.mkdir(self.walletnotify_dir)
        os.mkdir(self.shutdownnotify_dir)

        # -alertnotify and -blocknotify on node0, walletnotify on node1
        self.extra_args = [[
            f"-alertnotify=echo > {os.path.join(self.alertnotify_dir, '%s')}",
            f"-blocknotify=echo > {os.path.join(self.blocknotify_dir, '%s')}",
            f"-shutdownnotify=echo > {self.shutdownnotify_file}",
        ], [
            f"-walletnotify=echo %h_%b > {os.path.join(self.walletnotify_dir, notify_outputname('%w', '%s'))}",
        ]]
        # bidha auto-creates the default "" wallet at startup (load.cpp:140), so createwallet("")
        # fails "Database already exists"; node0 uses a named wallet instead. node1 keeps self.wallet
        # (its name is asserted by expect_wallet_notify via walletnotify %w).
        self.wallet_names = ["node0", self.wallet]
        super().setup_network()

    def run_test(self):
        if self.is_wallet_compiled():
            # Setup the descriptors to be imported to the wallet
            seed = "cTdGmKFWpbvpKQ7ejrdzqYT2hhjyb3GPHnLAK7wdi5Em67YLwSm9"
            xpriv = "tprv8ZgxMBicQKsPfHCsTwkiM1KT56RXbGGTqvc2hgqzycpwbHqqpcajQeMRZoBD35kW4RtyCemu6j34Ku5DEspmgjKdt2qe4SvRch5Kk8B8A2v"
            desc_imports = [{
                "desc": descsum_create(f"wpkh({xpriv}/0/*)"),
                "timestamp": 0,
                "active": True,
                "keypool": True,
            },{
                "desc": descsum_create(f"wpkh({xpriv}/1/*)"),
                "timestamp": 0,
                "active": True,
                "keypool": True,
                "internal": True,
            }]
            # Make the wallets and import the descriptors
            # Ensures that node 0 and node 1 share the same wallet for the conflicting transaction tests below.
            for i, name in enumerate(self.wallet_names):
                self.nodes[i].createwallet(wallet_name=name, descriptors=self.options.descriptors, blank=True, load_on_startup=True)
                # bidha auto-loads a default "" wallet at startup; unload it so bare wallet RPCs resolve to this test wallet
                for w in self.nodes[i].listwallets():
                    if w != name:
                        self.nodes[i].unloadwallet(w)
                if self.options.descriptors:
                    self.nodes[i].importdescriptors(desc_imports)
                else:
                    self.nodes[i].sethdseed(True, seed)

        self.log.info("test -blocknotify")
        block_count = 10
        blocks = self.generatetoaddress(self.nodes[1], block_count, self.nodes[1].getnewaddress() if self.is_wallet_compiled() else ADDRESS_BCRT1_UNSPENDABLE)

        # wait at most 10 seconds for expected number of files before reading the content
        self.wait_until(lambda: len(os.listdir(self.blocknotify_dir)) == block_count, timeout=10)

        # directory content should equal the generated blocks hashes
        assert_equal(sorted(blocks), sorted(os.listdir(self.blocknotify_dir)))

        if self.is_wallet_compiled():
            self.log.info("test -walletnotify")
            # wait at most 10 seconds for expected number of files before reading the content
            self.wait_until(lambda: len(os.listdir(self.walletnotify_dir)) == block_count, timeout=10)

            # directory content should equal the generated transaction hashes
            tx_details = list(map(lambda t: (t['txid'], t['blockheight'], t['blockhash']), self.nodes[1].listtransactions("*", block_count)))
            self.expect_wallet_notify(tx_details)

            self.log.info("test -walletnotify after rescan")
            # rescan to force wallet notifications
            self.nodes[1].rescanblockchain()
            self.wait_until(lambda: len(os.listdir(self.walletnotify_dir)) == block_count, timeout=10)

            self.connect_nodes(0, 1)

            # directory content should equal the generated transaction hashes
            tx_details = list(map(lambda t: (t['txid'], t['blockheight'], t['blockhash']), self.nodes[1].listtransactions("*", block_count)))
            self.expect_wallet_notify(tx_details)

            # Conflicting-transaction (-walletnotify) tests removed: they drive
            # bumpfee replacements of replaceable spends, which bidha's
            # RBF-disabled mempool rejects (validation.cpp:751).

        # TODO: add test for `-alertnotify` large fork notifications

        self.log.info("test -shutdownnotify")
        self.stop_nodes()
        self.wait_until(lambda: os.path.isfile(self.shutdownnotify_file), timeout=10)

    def expect_wallet_notify(self, tx_details):
        self.wait_until(lambda: len(os.listdir(self.walletnotify_dir)) >= len(tx_details), timeout=10)
        # Should have no more and no less files than expected
        assert_equal(sorted(notify_outputname(self.wallet, tx_id) for tx_id, _, _ in tx_details), sorted(os.listdir(self.walletnotify_dir)))
        # Should now verify contents of each file
        for tx_id, blockheight, blockhash in tx_details:
            fname = os.path.join(self.walletnotify_dir, notify_outputname(self.wallet, tx_id))
            # Wait for the cached writes to hit storage
            self.wait_until(lambda: os.path.getsize(fname) > 0, timeout=10)
            with open(fname, 'rt', encoding='utf-8') as f:
                text = f.read()
                # Universal newline ensures '\n' on 'nt'
                assert_equal(text[-1], '\n')
                text = text[:-1]
                if os.name == 'nt':
                    # On Windows, echo as above will append a whitespace
                    assert_equal(text[-1], ' ')
                    text = text[:-1]
                expected = str(blockheight) + '_' + blockhash
                assert_equal(text, expected)

        for tx_file in os.listdir(self.walletnotify_dir):
            os.remove(os.path.join(self.walletnotify_dir, tx_file))


if __name__ == '__main__':
    NotificationsTest().main()
