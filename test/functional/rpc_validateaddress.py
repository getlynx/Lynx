#!/usr/bin/env python3
# Copyright (c) 2023 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
"""Test validateaddress for main chain"""

from test_framework.test_framework import BitcoinTestFramework

from test_framework.util import assert_equal

INVALID_DATA = [
    # infiniloop's main bech32 hrp is "infiniloop" (CURRENT_CHAIN). key_io.cpp:86 only
    # runs the Bech32 decode/error path when the address prefix equals the chain hrp,
    # so the bc/BC vectors were re-encoded to the infiniloop hrp with their
    # (encoding, witness version, program, defect) preserved; the tb/tc/TB/TC vectors
    # keep their generic "unsupported encoding" error (their prefix never matches).
    # BIP 173
    (
        "tc1qw508d6qejxtdg4y5r3zarvary0c5xw7kg3g4ty",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # Invalid hrp
        [],
    ),
    ("infiniloop1qrp33g0q4c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q00uznx", "Invalid Bech32 checksum", [19]),
    (
        "infiniloop13w508d6qejxtdg4y5r3zarvary0c5xw7kg57qrh",
        "Version 1+ witness address must use Bech32m checksum",
        [],
    ),
    (
        "infiniloop1rw52sh6zp",
        "Version 1+ witness address must use Bech32m checksum",  # Invalid program length
        [],
    ),
    (
        "infiniloop10w508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kw5wghw4c",
        "Version 1+ witness address must use Bech32m checksum",  # Invalid program length
        [],
    ),
    (
        "infiniloop1qr508d6qejxtdg4y5r3zarvaryve82d50",
        "Invalid Bech32 v0 address program size (16 byte), per BIP141",
        [],
    ),
    (
        "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sL5k7",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Mixed case
        [],
    ),
    (
        "infiniloop1qRp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q00uznx",
        "Invalid character or mixed case",  # infiniloop1, Mixed case
        [12],
    ),
    (
        "infiniloop1zw508d6qejxtdg4y5r3zarvaryvqqlcj8g",
        "Version 1+ witness address must use Bech32m checksum",  # Wrong padding
        [],
    ),
    (
        "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3pjxtptv",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Non-zero padding in 8-to-5 conversion
        [],
    ),
    ("infiniloop1d8l2gw", "Empty Bech32 data section", []),
    # BIP 350
    (
        "tc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq5zuyut",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # Invalid human-readable part
        [],
    ),
    (
        "infiniloop1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqqa38g6",
        "Version 1+ witness address must use Bech32m checksum",  # Invalid checksum (Bech32 instead of Bech32m)
        [],
    ),
    (
        "tb1z0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqglt7rf",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Invalid checksum (Bech32 instead of Bech32m)
        [],
    ),
    (
        "infiniloop1s0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqrzmqqg",
        "Version 1+ witness address must use Bech32m checksum",  # Invalid checksum (Bech32 instead of Bech32m)
        [],
    ),
    (
        "infiniloop1qw508d6qejxtdg4y5r3zarvary0c5xw7kz6gny2",
        "Version 0 witness address must use Bech32 checksum",  # Invalid checksum (Bech32m instead of Bech32)
        [],
    ),
    (
        "tb1q0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq24jc47",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Invalid checksum (Bech32m instead of Bech32)
        [],
    ),
    (
        "infiniloop1qrp33gbq5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q00uznx",
        "Invalid Base 32 character",  # Invalid character
        [17],
    ),
    (
        "infiniloop130xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqf4mfc5",
        "Invalid Bech32 address witness version",
        [],
    ),
    ("infiniloop1pw5mg43u6", "Invalid Bech32 address program size (1 byte)", []),
    (
        "infiniloop1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v8n0nx0muaewav25u4d8dm",
        "Invalid Bech32 address program size (41 byte)",
        [],
    ),
    (
        "infiniloop1qr508d6qejxtdg4y5r3zarvaryve82d50",
        "Invalid Bech32 v0 address program size (16 byte), per BIP141",
        [],
    ),
    (
        "tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq47Zagq",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Mixed case
        [],
    ),
    (
        "infiniloop1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v07qdmqdmk",
        "Invalid padding in Bech32 data section",  # zero padding of more than 4 bits
        [],
    ),
    (
        "tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vpggkg4j",
        "Invalid or unsupported Segwit (Bech32) or Base58 encoding.",  # tb1, Non-zero padding in 8-to-5 conversion
        [],
    ),
    ("infiniloop1d8l2gw", "Empty Bech32 data section", []),
]
VALID_DATA = [
    # BIP 350 — re-encoded under the infiniloop main hrp; scriptPubKeys are
    # hrp-independent so they are unchanged.
    (
        "infiniloop1qw508d6qejxtdg4y5r3zarvary0c5xw7khxclpg",
        "0014751e76e8199196d454941c45d1b3a323f1433bd6",
    ),
    (
        "infiniloop1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q00uznx",
        "00201863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262",
    ),
    (
        "infiniloop1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kcfsgjy",
        "5128751e76e8199196d454941c45d1b3a323f1433bd6751e76e8199196d454941c45d1b3a323f1433bd6",
    ),
    ("infiniloop1sw50qnx3vna", "6002751e"),
    ("infiniloop1zw508d6qejxtdg4y5r3zarvaryvpxy7f7", "5210751e76e8199196d454941c45d1b3a323"),
    (
        "infiniloop1qqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesre5vju",
        "0020000000c4a5cad46221b2a187905e5266362b99d5e91c6ce24d165dab93e86433",
    ),
    (
        "infiniloop1pqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesfw592q",
        "5120000000c4a5cad46221b2a187905e5266362b99d5e91c6ce24d165dab93e86433",
    ),
    (
        "infiniloop1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq4pptdc",
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
