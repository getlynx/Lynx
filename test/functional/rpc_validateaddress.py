#!/usr/bin/env python3
# Copyright (c) 2023 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
"""Test validateaddress for main chain"""

from test_framework.test_framework import BitcoinTestFramework

from test_framework.util import assert_equal

INVALID_DATA = [
    # bidha's main bech32 hrp is "digitalcoin" (CURRENT_CHAIN). key_io.cpp:86 only
    # runs the Bech32 decode/error path when the address prefix equals the chain hrp,
    # so the bc/BC vectors were re-encoded to the digitalcoin hrp with their
    # (encoding, witness version, program, defect) preserved; the tb/tc/TB/TC vectors
    # keep their generic "unsupported encoding" error (their prefix never matches).
    # BIP 173
    (
        "tc1qw508d6qejxtdg4y5r3zarvary0c5xw7kg3g4ty",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # Invalid hrp
        [],
    ),
    ("lynx1qrp33g0q4c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qflysgn", "Invalid Bech32 checksum", [13]),
    (
        "lynx13w508d6qejxtdg4y5r3zarvary0c5xw7kggcvh0",
        "Version 1+ witness address must use Bech32m checksum",
        [],
    ),
    (
        "lynx1rw5r98lkr",
        "Version 1+ witness address must use Bech32m checksum",  # Invalid program length
        [],
    ),
    (
        "lynx10w508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kw5wkflc3",
        "Version 1+ witness address must use Bech32m checksum",  # Invalid program length
        [],
    ),
    (
        "lynx1qr508d6qejxtdg4y5r3zarvaryvumxz5j",
        "Invalid Bech32 v0 address program size (16 byte), per BIP141",
        [],
    ),
    (
        "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sL5k7",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Mixed case
        [],
    ),
    (
        "lynx1qRp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qf405dn",
        "Invalid character or mixed case",  # lynx1, Mixed case
        [6],
    ),
    (
        "lynx1zw508d6qejxtdg4y5r3zarvaryvqw0ppgq",
        "Version 1+ witness address must use Bech32m checksum",  # Wrong padding
        [],
    ),
    (
        "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3pjxtptv",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Non-zero padding in 8-to-5 conversion
        [],
    ),
    ("lynx1699zex", "Empty Bech32 data section", []),
    # BIP 350
    (
        "tc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq5zuyut",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # Invalid human-readable part
        [],
    ),
    (
        "lynx1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqxdf4n0",
        "Version 1+ witness address must use Bech32m checksum",  # Invalid checksum (Bech32 instead of Bech32m)
        [],
    ),
    (
        "tb1z0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqglt7rf",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Invalid checksum (Bech32 instead of Bech32m)
        [],
    ),
    (
        "lynx1s0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq9jrjma",
        "Version 1+ witness address must use Bech32m checksum",  # Invalid checksum (Bech32 instead of Bech32m)
        [],
    ),
    (
        "lynx1qw508d6qejxtdg4y5r3zarvary0c5xw7kzxwlsj",
        "Version 0 witness address must use Bech32 checksum",  # Invalid checksum (Bech32m instead of Bech32)
        [],
    ),
    (
        "tb1q0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq24jc47",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Invalid checksum (Bech32m instead of Bech32)
        [],
    ),
    (
        "lynx1qrp33gbq5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qf405dn",
        "Invalid Base 32 character",  # Invalid character
        [11],
    ),
    (
        "lynx130xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq09rmrp",
        "Invalid Bech32 address witness version",
        [],
    ),
    ("lynx1pw5ja95gc", "Invalid Bech32 address program size (1 byte)", []),
    (
        "lynx1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v8n0nx0muaewav25utnkqj",
        "Invalid Bech32 address program size (41 byte)",
        [],
    ),
    (
        "lynx1qr508d6qejxtdg4y5r3zarvaryvumxz5j",
        "Invalid Bech32 v0 address program size (16 byte), per BIP141",
        [],
    ),
    (
        "tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq47Zagq",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Mixed case
        [],
    ),
    (
        "lynx1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v07qt5cwa3",
        "Invalid padding in Bech32 data section",  # zero padding of more than 4 bits
        [],
    ),
    (
        "tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vpggkg4j",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Non-zero padding in 8-to-5 conversion
        [],
    ),
    ("lynx1699zex", "Empty Bech32 data section", []),
]
VALID_DATA = [
    # BIP 350 — re-encoded under the digitalcoin main hrp; scriptPubKeys are
    # hrp-independent so they are unchanged.
    (
        "lynx1qw508d6qejxtdg4y5r3zarvary0c5xw7kh67n4s",
        "0014751e76e8199196d454941c45d1b3a323f1433bd6",
    ),
    (
        "lynx1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qflysgn",
        "00201863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262",
    ),
    (
        "lynx1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7k7p97rh",
        "5128751e76e8199196d454941c45d1b3a323f1433bd6751e76e8199196d454941c45d1b3a323f1433bd6",
    ),
    ("lynx1sw50qgahs4e", "6002751e"),
    ("lynx1zw508d6qejxtdg4y5r3zarvaryvy6g3fr", "5210751e76e8199196d454941c45d1b3a323"),
    (
        "lynx1qqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvses9fv7ff",
        "0020000000c4a5cad46221b2a187905e5266362b99d5e91c6ce24d165dab93e86433",
    ),
    (
        "lynx1pqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvses07vh34",
        "5120000000c4a5cad46221b2a187905e5266362b99d5e91c6ce24d165dab93e86433",
    ),
    (
        "lynx1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqn3eekd",
        "512079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
    ),
]


class ValidateAddressMainTest(BitcoinTestFramework):
    def set_test_params(self):
        self.setup_clean_chain = True
        self.chain = ""  # main
        self.num_nodes = 1
        # bidha does not register -prune (blockmanager_args.cpp:20 reads it but no
        # AddArg), so passing it is rejected at parse. Pruning is incidental here.
        self.extra_args = [[]] * self.num_nodes

    def check_valid(self, addr, spk):
        info = self.nodes[0].validateaddress(addr)
        assert_equal(info["isvalid"], True)
        assert_equal(info["scriptPubKey"], spk)
        assert "error" not in info
        assert "error_locations" not in info

    def check_invalid(self, addr, error_str, error_locations):
        res = self.nodes[0].validateaddress(addr)
        assert_equal(res["isvalid"], False)
        assert_equal(res["error"], error_str)
        assert_equal(res["error_locations"], error_locations)

    def test_validateaddress(self):
        for (addr, error, locs) in INVALID_DATA:
            self.check_invalid(addr, error, locs)
        for (addr, spk) in VALID_DATA:
            self.check_valid(addr, spk)

    def run_test(self):
        self.test_validateaddress()


if __name__ == "__main__":
    ValidateAddressMainTest().main()
