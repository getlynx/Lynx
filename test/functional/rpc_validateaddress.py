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
    ("digitalcoin1qrp33g0q4c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qf405dn", "Invalid Bech32 checksum", [20]),
    (
        "digitalcoin13w508d6qejxtdg4y5r3zarvary0c5xw7kdlur60",
        "Version 1+ witness address must use Bech32m checksum",
        [],
    ),
    (
        "digitalcoin1rw5hcm88r",
        "Version 1+ witness address must use Bech32m checksum",  # Invalid program length
        [],
    ),
    (
        "digitalcoin10w508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kw5e4agk9",
        "Version 1+ witness address must use Bech32m checksum",  # Invalid program length
        [],
    ),
    (
        "digitalcoin1qr508d6qejxtdg4y5r3zarvaryvst7wcl",
        "Invalid Bech32 v0 address program size (16 byte), per BIP141",
        [],
    ),
    (
        "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sL5k7",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Mixed case
        [],
    ),
    (
        "digitalcoin1qRp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qf405dn",
        "Invalid character or mixed case",  # digitalcoin1, Mixed case
        [13],
    ),
    (
        "digitalcoin1zw508d6qejxtdg4y5r3zarvaryvq0ft858",
        "Version 1+ witness address must use Bech32m checksum",  # Wrong padding
        [],
    ),
    (
        "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3pjxtptv",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Non-zero padding in 8-to-5 conversion
        [],
    ),
    ("digitalcoin1jq553x", "Empty Bech32 data section", []),
    # BIP 350
    (
        "tc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq5zuyut",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # Invalid human-readable part
        [],
    ),
    (
        "digitalcoin1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqx8z3k0",
        "Version 1+ witness address must use Bech32m checksum",  # Invalid checksum (Bech32 instead of Bech32m)
        [],
    ),
    (
        "tb1z0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqglt7rf",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Invalid checksum (Bech32 instead of Bech32m)
        [],
    ),
    (
        "digitalcoin1s0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq9cgk7a",
        "Version 1+ witness address must use Bech32m checksum",  # Invalid checksum (Bech32 instead of Bech32m)
        [],
    ),
    (
        "digitalcoin1qw508d6qejxtdg4y5r3zarvary0c5xw7k832saj",
        "Version 0 witness address must use Bech32 checksum",  # Invalid checksum (Bech32m instead of Bech32)
        [],
    ),
    (
        "tb1q0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq24jc47",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Invalid checksum (Bech32m instead of Bech32)
        [],
    ),
    (
        "digitalcoin1qrp33gbq5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qf405dn",
        "Invalid Base 32 character",  # Invalid character
        [18],
    ),
    (
        "digitalcoin130xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq00glxp",
        "Invalid Bech32 address witness version",
        [],
    ),
    ("digitalcoin1pw5xqevec", "Invalid Bech32 address program size (1 byte)", []),
    (
        "digitalcoin1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v8n0nx0muaewav25tg8pwx",
        "Invalid Bech32 address program size (41 byte)",
        [],
    ),
    (
        "digitalcoin1qr508d6qejxtdg4y5r3zarvaryvst7wcl",
        "Invalid Bech32 v0 address program size (16 byte), per BIP141",
        [],
    ),
    (
        "tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq47Zagq",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Mixed case
        [],
    ),
    (
        "digitalcoin1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v07qdpcpsp",
        "Invalid padding in Bech32 data section",  # zero padding of more than 4 bits
        [],
    ),
    (
        "tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vpggkg4j",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Non-zero padding in 8-to-5 conversion
        [],
    ),
    ("digitalcoin1jq553x", "Empty Bech32 data section", []),
]
VALID_DATA = [
    # BIP 350 — re-encoded under the digitalcoin main hrp; scriptPubKeys are
    # hrp-independent so they are unchanged.
    (
        "digitalcoin1qw508d6qejxtdg4y5r3zarvary0c5xw7kjd6ucs",
        "0014751e76e8199196d454941c45d1b3a323f1433bd6",
    ),
    (
        "digitalcoin1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qf405dn",
        "00201863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262",
    ),
    (
        "digitalcoin1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7ksld9ss",
        "5128751e76e8199196d454941c45d1b3a323f1433bd6751e76e8199196d454941c45d1b3a323f1433bd6",
    ),
    ("digitalcoin1sw50q7k06au", "6002751e"),
    ("digitalcoin1zw508d6qejxtdg4y5r3zarvaryvg2sa9w", "5210751e76e8199196d454941c45d1b3a323"),
    (
        "digitalcoin1qqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvses9r86vf",
        "0020000000c4a5cad46221b2a187905e5266362b99d5e91c6ce24d165dab93e86433",
    ),
    (
        "digitalcoin1pqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvses058n54",
        "5120000000c4a5cad46221b2a187905e5266362b99d5e91c6ce24d165dab93e86433",
    ),
    (
        "digitalcoin1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqnmjand",
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
