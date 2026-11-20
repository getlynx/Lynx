// Copyright (c) 2011-2022 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <test/data/key_io_invalid.json.h>
#include <test/data/key_io_valid.json.h>

#include <key.h>
#include <key_io.h>
#include <script/script.h>
#include <test/util/json.h>
#include <test/util/setup_common.h>
#include <util/chaintype.h>
#include <util/strencodings.h>

#include <boost/test/unit_test.hpp>

#include <univalue.h>

#include <map>

namespace {
// The key_io_valid.json vectors are digitalcoin-encoded; lynx uses different base58/bech32
// prefixes (pubkey 45 / script 22 / secret 173 / hrp "lynx"). This maps the main-chain
// vectors to their lynx re-encodings, applied when CURRENT_CHAIN=="lynx" so one vector set
// serves both chains. (testnet/regtest prefixes are chain-independent, so those vectors need no entry.)
const std::map<std::string, std::string> kDgcToLynx = {
    {"DL1YFq6WDUGvmx6tkrv6QHGws6HBBMTzpa", "KN5b2TZpsBE53TCC89usgAMkJf9KoYipUe"},
    {"36j4NfKv6Akva9amjWrLG6MuSQym1GuEmm", "9wUK7WPpAEdpUWxF9eWkWDzH8zMo2GVF6u"},
    {"digitalcoin1qvyq0cc6rahyvsazfdje0twl7ez82ndmurjejyf", "lynx1qvyq0cc6rahyvsazfdje0twl7ez82ndmux9aaff"},
    {"digitalcoin1qyucykdlhp62tezs0hagqury402qwhk589q80tqs5myh3rxq34nwqxmtcdu", "lynx1qyucykdlhp62tezs0hagqury402qwhk589q80tqs5myh3rxq34nwqx3qugu"},
    {"digitalcoin1p83n3au0rjylefxq2nc2xh2y4jzz4pm6zxj4mw5pagdjjr2a9f36stl5uj7", "lynx1p83n3au0rjylefxq2nc2xh2y4jzz4pm6zxj4mw5pagdjjr2a9f36st4lch7"},
    {"digitalcoin1z2rks2dmz2f", "lynx1z2rksuxrgzv"},
    {"DKsRfNmRSAsP2bmXMbYrBxs2R2YGBJVi19", "KMwUS1Ek5spXJ6rpitYdTqwprbQQsMiN3a"},
    {"3BZECeAH8gSKkjrTx8PwMrNQBLG18yHpvf", "A2JUwVEBCkKDf7DwNG4Mbyzmsue3BvYyhQ"},
    {"digitalcoin1qhxt04s5xnpy0kxw4x99n5hpdf5pmtzpqw7e5r0", "lynx1qhxt04s5xnpy0kxw4x99n5hpdf5pmtzpqtfamw0"},
    {"digitalcoin1qgc9ljrvdf2e0zg9rmmq86xklqwfys7r6wptjlacdgrcdc7sa6ggqdc9v8t", "lynx1qgc9ljrvdf2e0zg9rmmq86xklqwfys7r6wptjlacdgrcdc7sa6ggqdjwgzt"},
    {"5JuW2AMDYu4xVwRG9DZW18VbzQrGcd5RCgb99sS6ehJsNQXu5b9", "6pNzxbYeu3W9ZrZzwJVTvZUTCYZasJzpcSmz8cPSPBcKaTGP7vS"},
    {"L5nJeqKmpHp4P7F8ZYyjwc5a7P4d8EabuGAzfGJk7yC1BJyzNaEd", "SjsgP6YFhD3FEPqhSxjvmSLVJw6yh4nKE9Crqhu1DW72rCxkXNFD"},
    {"5HsL2nZuEebU5nM3RxNVQD9GcAnvNMahqQskf4fkqHe54zwd14e", "6oLpyDmLao2f9hVnE3JTKe87pJWEd3W7FB4bdod6ZmwXGyFeefQ"},
    {"KwuVvu6hsuEMHrfFWJQV64tRrWX3QzqHH18JuAHYqYV6dqBvNKxd", "SbzsfAKBkpTY99FpPiAfuu9M44ZPyq2zbtAB5bsow5Q8Jj4124sq"},
};
std::string PortKeyIo(std::string s)
{
    if (std::string(CURRENT_CHAIN) == "lynx") {
        auto it = kDgcToLynx.find(s);
        if (it != kDgcToLynx.end()) return it->second;
    }
    return s;
}
} // namespace

BOOST_FIXTURE_TEST_SUITE(key_io_tests, BasicTestingSetup)

// Goal: check that parsed keys match test payload
BOOST_AUTO_TEST_CASE(key_io_valid_parse)
{
    UniValue tests = read_json(std::string(json_tests::key_io_valid, json_tests::key_io_valid + sizeof(json_tests::key_io_valid)));
    CKey privkey;
    CTxDestination destination;
    SelectParams(ChainType::MAIN);

    for (unsigned int idx = 0; idx < tests.size(); idx++) {
        const UniValue& test = tests[idx];
        std::string strTest = test.write();
        if (test.size() < 3) { // Allow for extra stuff (useful for comments)
            BOOST_ERROR("Bad test: " << strTest);
            continue;
        }
        std::string exp_base58string = PortKeyIo(test[0].get_str());
        const std::vector<std::byte> exp_payload{ParseHex<std::byte>(test[1].get_str())};
        const UniValue &metadata = test[2].get_obj();
        bool isPrivkey = metadata.find_value("isPrivkey").get_bool();
        SelectParams(ChainTypeFromString(metadata.find_value("chain").get_str()).value());
        bool try_case_flip = metadata.find_value("tryCaseFlip").isNull() ? false : metadata.find_value("tryCaseFlip").get_bool();
        if (isPrivkey) {
            bool isCompressed = metadata.find_value("isCompressed").get_bool();
            // Must be valid private key
            privkey = DecodeSecret(exp_base58string);
            BOOST_CHECK_MESSAGE(privkey.IsValid(), "!IsValid:" + strTest);
            BOOST_CHECK_MESSAGE(privkey.IsCompressed() == isCompressed, "compressed mismatch:" + strTest);
            BOOST_CHECK_MESSAGE(Span{privkey} == Span{exp_payload}, "key mismatch:" + strTest);

            // Private key must be invalid public key
            destination = DecodeDestination(exp_base58string);
            BOOST_CHECK_MESSAGE(!IsValidDestination(destination), "IsValid privkey as pubkey:" + strTest);
        } else {
            // Must be valid public key
            destination = DecodeDestination(exp_base58string);
            CScript script = GetScriptForDestination(destination);
            BOOST_CHECK_MESSAGE(IsValidDestination(destination), "!IsValid:" + strTest);
            BOOST_CHECK_EQUAL(HexStr(script), HexStr(exp_payload));

            // Try flipped case version
            for (char& c : exp_base58string) {
                if (c >= 'a' && c <= 'z') {
                    c = (c - 'a') + 'A';
                } else if (c >= 'A' && c <= 'Z') {
                    c = (c - 'A') + 'a';
                }
            }
            destination = DecodeDestination(exp_base58string);
            BOOST_CHECK_MESSAGE(IsValidDestination(destination) == try_case_flip, "!IsValid case flipped:" + strTest);
            if (IsValidDestination(destination)) {
                script = GetScriptForDestination(destination);
                BOOST_CHECK_EQUAL(HexStr(script), HexStr(exp_payload));
            }

            // Public key must be invalid private key
            privkey = DecodeSecret(exp_base58string);
            BOOST_CHECK_MESSAGE(!privkey.IsValid(), "IsValid pubkey as privkey:" + strTest);
        }
    }
}

// Goal: check that generated keys match test vectors
BOOST_AUTO_TEST_CASE(key_io_valid_gen)
{
    UniValue tests = read_json(std::string(json_tests::key_io_valid, json_tests::key_io_valid + sizeof(json_tests::key_io_valid)));

    for (unsigned int idx = 0; idx < tests.size(); idx++) {
        const UniValue& test = tests[idx];
        std::string strTest = test.write();
        if (test.size() < 3) // Allow for extra stuff (useful for comments)
        {
            BOOST_ERROR("Bad test: " << strTest);
            continue;
        }
        std::string exp_base58string = PortKeyIo(test[0].get_str());
        std::vector<unsigned char> exp_payload = ParseHex(test[1].get_str());
        const UniValue &metadata = test[2].get_obj();
        bool isPrivkey = metadata.find_value("isPrivkey").get_bool();
        SelectParams(ChainTypeFromString(metadata.find_value("chain").get_str()).value());
        if (isPrivkey) {
            bool isCompressed = metadata.find_value("isCompressed").get_bool();
            CKey key;
            key.Set(exp_payload.begin(), exp_payload.end(), isCompressed);
            assert(key.IsValid());
            BOOST_CHECK_MESSAGE(EncodeSecret(key) == exp_base58string, "result mismatch: " + strTest);
        } else {
            CTxDestination dest;
            CScript exp_script(exp_payload.begin(), exp_payload.end());
            BOOST_CHECK(ExtractDestination(exp_script, dest));
            std::string address = EncodeDestination(dest);

            BOOST_CHECK_EQUAL(address, exp_base58string);
        }
    }

    SelectParams(ChainType::MAIN);
}


// Goal: check that base58 parsing code is robust against a variety of corrupted data
BOOST_AUTO_TEST_CASE(key_io_invalid)
{
    UniValue tests = read_json(std::string(json_tests::key_io_invalid, json_tests::key_io_invalid + sizeof(json_tests::key_io_invalid))); // Negative testcases
    CKey privkey;
    CTxDestination destination;

    for (unsigned int idx = 0; idx < tests.size(); idx++) {
        const UniValue& test = tests[idx];
        std::string strTest = test.write();
        if (test.size() < 1) // Allow for extra stuff (useful for comments)
        {
            BOOST_ERROR("Bad test: " << strTest);
            continue;
        }
        std::string exp_base58string = PortKeyIo(test[0].get_str());

        // must be invalid as public and as private key
        for (const auto& chain : {ChainType::MAIN, ChainType::TESTNET, ChainType::SIGNET, ChainType::REGTEST}) {
            SelectParams(chain);
            destination = DecodeDestination(exp_base58string);
            BOOST_CHECK_MESSAGE(!IsValidDestination(destination), "IsValid pubkey in mainnet:" + strTest);
            privkey = DecodeSecret(exp_base58string);
            BOOST_CHECK_MESSAGE(!privkey.IsValid(), "IsValid privkey in mainnet:" + strTest);
        }
    }
}

BOOST_AUTO_TEST_SUITE_END()
