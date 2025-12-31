// Copyright (c) 2010 Satoshi Nakamoto
// Copyright (c) 2009-2021 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <kernel/chainparams.h>

#include <arith_uint256.h>
#include <chainparamsseeds.h>
#include <consensus/amount.h>
#include <consensus/merkle.h>
#include <consensus/params.h>
#include <hash.h>
#include <logging.h>
#include <primitives/block.h>
#include <primitives/transaction.h>
#include <script/interpreter.h>
#include <script/script.h>
#include <uint256.h>
#include <util/chaintype.h>
#include <util/strencodings.h>

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <type_traits>

// #define PANTHER



#include <map>
#include <string>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <stdexcept>
#include <iostream>

struct ChainSpec {
    std::string name;
    int nDefaultPort;
    unsigned char pchMessageStart[4];
    int pubkeyPrefix;
    int scriptPrefix;
    int secretPrefix;
    std::string coinSymbol;
    int lasttimestamp;
    int uuidlastblock;
    std::string initauthuser;
    std::string psztimestamp;
    int timestamp;
    int nonce;
    std::string genesishash;
    std::string genesismerkleroot;
};

ChainSpec spec;

static inline std::string trim(const std::string& s) {
    auto start = s.find_first_not_of(" \t\r\n");
    auto end = s.find_last_not_of(" \t\r\n");
    return (start == std::string::npos) ? "" : s.substr(start, end - start + 1);
}

ChainSpec LoadChainSpec(const std::string& specFile, const std::string& chainName) {
    std::ifstream in(specFile);
    if (!in.is_open()) throw std::runtime_error("Unable to open chainspec file");

    ChainSpec current;
    bool found = false;
    std::string line;
    while (std::getline(in, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') continue;

        if (line.front() == '[' && line.back() == ']') {
            if (found) break;
            current.name = line.substr(1, line.size() - 2);
            found = (current.name == chainName);
            continue;
        }
        if (!found) continue;

        auto pos = line.find('=');
        if (pos == std::string::npos) continue;
        std::string key = trim(line.substr(0, pos));
        std::string val = trim(line.substr(pos + 1));

        if (key == "nDefaultPort") current.nDefaultPort = std::stoi(val);
        else if (key == "pchMessageStart") {
            std::replace(val.begin(), val.end(), ',', ' ');
            std::istringstream ss(val);
            int i = 0; int num;
            while (ss >> std::hex >> num && i < 4)
                current.pchMessageStart[i++] = static_cast<unsigned char>(num);
        }
        else if (key == "PUBKEY_ADDRESS") current.pubkeyPrefix = std::stoi(val);
        else if (key == "SCRIPT_ADDRESS") current.scriptPrefix = std::stoi(val);
        else if (key == "SECRET_KEY") current.secretPrefix = std::stoi(val);
        else if (key == "COIN") current.coinSymbol = val;
        else if (key == "LASTTIMESTAMP") current.lasttimestamp = std::stoi(val);
        else if (key == "UUIDLASTBLOCK") current.uuidlastblock = std::stoi(val);
        else if (key == "INITAUTHUSER") current.initauthuser = val;
        else if (key == "PSZTIMESTAMP") current.psztimestamp = val;
        else if (key == "TIMESTAMP") current.timestamp = std::stoi(val);
        else if (key == "NONCE") current.nonce = std::stoi(val);
        else if (key == "GENESISHASH") current.genesishash = val;
        else if (key == "GENESISMERKLEROOT") current.genesismerkleroot = val;
    }

    if (!found)
        throw std::runtime_error("Chain spec not found for " + chainName);
    return current;
}




static void CalculateGenesis(CBlock& block, uint256 powLimit)
{
    while (UintToArith256(block.GetPoWHash()) > UintToArith256(powLimit)) {
        ++block.nNonce;
    }
}

static CBlock CreateGenesisBlock(const char* pszTimestamp, const CScript& genesisOutputScript, uint32_t nTime, uint32_t nNonce, uint32_t nBits, int32_t nVersion, const CAmount& genesisReward)
{
    CMutableTransaction txNew;
    txNew.nVersion = 1;
    txNew.vin.resize(1);
    txNew.vout.resize(1);
    txNew.vin[0].scriptSig = CScript() << 486604799 << CScriptNum(4) << std::vector<unsigned char>((const unsigned char*)pszTimestamp, (const unsigned char*)pszTimestamp + strlen(pszTimestamp));
    txNew.vout[0].nValue = genesisReward;
    txNew.vout[0].scriptPubKey = genesisOutputScript;

    CBlock genesis;
    genesis.nTime    = nTime;
    genesis.nBits    = nBits;
    genesis.nNonce   = nNonce;
    genesis.nVersion = nVersion;
    genesis.vtx.push_back(MakeTransactionRef(std::move(txNew)));
    genesis.hashPrevBlock.SetNull();
    genesis.hashMerkleRoot = BlockMerkleRoot(genesis);
    return genesis;
}

/**
 * Build the genesis block. Note that the output of its generation
 * transaction cannot be spent since it did not originally exist in the
 * database.
 *
 * CBlock(hash=000000000019d6, ver=1, hashPrevBlock=00000000000000, hashMerkleRoot=4a5e1e, nTime=1231006505, nBits=1d00ffff, nNonce=2083236893, vtx=1)
 *   CTransaction(hash=4a5e1e, ver=1, vin.size=1, vout.size=1, nLockTime=0)
 *     CTxIn(COutPoint(000000, -1), coinbase 04ffff001d0104455468652054696d65732030332f4a616e2f32303039204368616e63656c6c6f72206f6e206272696e6b206f66207365636f6e64206261696c6f757420666f722062616e6b73)
 *     CTxOut(nValue=50.00000000, scriptPubKey=0x5F1DF16B2B704C8A578D0B)
 *   vMerkleTree: 4a5e1e
 */
static CBlock CreateGenesisBlock2(uint32_t nTime, uint32_t nNonce, uint32_t nBits, int32_t nVersion, const CAmount& genesisReward)
{

    char pszTimestamp[] = { 0x49,0x43,0x61,0x6e,0x48,0x61,0x7a,0x4b,0x69,0x74,0x74,0x65,0x68,0x20,0x61,0x74,0x20,0x65,0x70,0x6f,0x63,0x68,0x20,0x31,0x33,0x38,0x37,0x37,0x37,0x39,0x36,0x38,0x34,0x2e,0x20,0x4d,0x65,0x6f,0x77,0x2e,0x20,0x4e,0x6f,0x77,0x20,0x70,0x65,0x74,0x20,0x6d,0x65,0x2e,0x00 };

    const CScript genesisOutputScript = CScript() << ParseHex("040184710fa689ad5023690c80f3a49c8f13f8d45b8c857fbcbc8bc4a8e4d3eb4b10f4d4604fa08dce601aaf0f470216fe1b51850b4acf21b179c45070ac7b03a9") << OP_CHECKSIG;
    return CreateGenesisBlock(pszTimestamp, genesisOutputScript, nTime, nNonce, nBits, nVersion, genesisReward);
}

static CBlock CreateGenesisBlock(uint32_t nTime, uint32_t nNonce, uint32_t nBits, int32_t nVersion, const CAmount& genesisReward)
{

// #ifdef LYNX        
// 
//     char pszTimestamp[] = { 0x49,0x43,0x61,0x6e,0x48,0x61,0x7a,0x4b,0x69,0x74,0x74,0x65,0x68,0x20,0x61,0x74,0x20,0x65,0x70,0x6f,0x63,0x68,0x20,0x31,0x33,0x38,0x37,0x37,0x37,0x39,0x36,0x38,0x34,0x2e,0x20,0x4d,0x65,0x6f,0x77,0x2e,0x20,0x4e,0x6f,0x77,0x20,0x70,0x65,0x74,0x20,0x6d,0x65,0x2e,0x00 };
// 
// #elif defined(PANTHER)
// 
//     char pszTimestamp[] = "rehtnap";
// 
// #endif

const char* pszTimestamp = nullptr;

if (std::string(CURRENT_CHAIN) == "lynx") {
    static char psz[] = { 0x49,0x43,0x61,0x6e,0x48,0x61,0x7a,0x4b,0x69,0x74,0x74,0x65,0x68,0x20,0x61,0x74,0x20,0x65,0x70,0x6f,0x63,0x68,0x20,0x31,0x33,0x38,0x37,0x37,0x37,0x39,0x36,0x38,0x34,0x2e,0x20,0x4d,0x65,0x6f,0x77,0x2e,0x20,0x4e,0x6f,0x77,0x20,0x70,0x65,0x74,0x20,0x6d,0x65,0x2e,0x00 };
    pszTimestamp = psz;
} else {
    // char pszTimestamp[] = spec.psztimestamp;
    // std::string psztimestamp = spec.psztimestamp;
    // const char* pszTimestamp = psztimestamp.c_str();
    //// std::string s = spec.psztimestamp;
    //// pszTimestamp = s.c_str();
    // static char psz[] = "rehtnap";
    // pszTimestamp = psz;
    pszTimestamp = spec.psztimestamp.c_str();
    
}

LogPrintf ("pszTimestamp %s \n", pszTimestamp);

    const CScript genesisOutputScript = CScript() << ParseHex("040184710fa689ad5023690c80f3a49c8f13f8d45b8c857fbcbc8bc4a8e4d3eb4b10f4d4604fa08dce601aaf0f470216fe1b51850b4acf21b179c45070ac7b03a9") << OP_CHECKSIG;
    return CreateGenesisBlock(pszTimestamp, genesisOutputScript, nTime, nNonce, nBits, nVersion, genesisReward);
}

/**
 * Main network on which people trade goods and services.
 */

// /* 
class CMainParams : public CChainParams {
public:
    CMainParams() {
        m_chain_type = ChainType::MAIN;
        consensus.signet_blocks = false;
        consensus.signet_challenge.clear();
        consensus.nSubsidyHalvingInterval = 210000;
        consensus.script_flag_exceptions.emplace( // BIP16 exception
            uint256S("0x00000000000002dc756eebf4f49723ed8d30cc28a5f108eb94b1ba88ac4f9c22"), SCRIPT_VERIFY_NONE);
        consensus.script_flag_exceptions.emplace( // Taproot exception
            uint256S("0x0000000000000000000f14c35b2d841e986ab5441de8c585d5ffe55ea1e395ad"), SCRIPT_VERIFY_P2SH | SCRIPT_VERIFY_WITNESS);
        consensus.BIP34Height = 710000;
        consensus.BIP34Hash = uint256S("fa09d204a83a768ed5a7c8d441fa62f2043abf420cff1226c7b4329aeb9d51cf");
        consensus.BIP65Height = 918684; // bab3041e8977e0dc3eeff63fe707b92bde1dd449d8efafb248c27c8264cc311a
        consensus.BIP66Height = 811879; // 7aceee012833fa8952f8835d8b1b3ae233cd6ab08fdb27a771d2bd7bdc491894
        consensus.MinBIP9WarningHeight = 483840; // segwit activation height + miner confirmation window
        consensus.powLimit = uint256S("00000fffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.nPowTargetTimespan = 1 * 60 * 60;

LogPrintf ("CURRENT_CHAIN chainparams.cpp %s \n", CURRENT_CHAIN);

// spec = LoadChainSpec("/root/." + CURRENT_CHAIN + "/chainspecs.txt", "panther");

if (std::string(CURRENT_CHAIN) != "lynx") {

    spec = LoadChainSpec(std::string("/root/.") + CURRENT_CHAIN + "/chainspecs.txt", CURRENT_CHAIN);

    LogPrintf ("spec.nDefaultPort %d \n", spec.nDefaultPort);

}

// #ifdef LYNX    
//         consensus.fPowAllowMinDifficultyBlocks = false;
//         consensus.posLimit = uint256S("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
//         consensus.initAuthUser = uint160S("1c04e67bf21dc44abe42e84a5ef3bce31b77aa6d");
//         consensus.nUUIDBlockStart = 3084941;
// #elif defined(PANTHER)
//         consensus.initAuthUser = uint160S("5750e9a38dcd514742b6375135def837490cca22");
//         consensus.fPowAllowMinDifficultyBlocks = false;
//         consensus.posLimit = uint256S("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
//         consensus.nUUIDBlockStart = 1700;
//         // consensus.fPowAllowMinDifficultyBlocks = true;
//         // consensus.posLimit = uint256S("007fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
// #endif

        consensus.fPowAllowMinDifficultyBlocks = false;
        consensus.posLimit = uint256S("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

if (std::string(CURRENT_CHAIN) == "lynx") {
        consensus.initAuthUser = uint160S("1c04e67bf21dc44abe42e84a5ef3bce31b77aa6d");
        consensus.nUUIDBlockStart = 3084941;
} else {

LogPrintf ("spec.initauthuser %s \n", spec.initauthuser.c_str());

        consensus.initAuthUser = uint160S(spec.initauthuser);
        consensus.nUUIDBlockStart = spec.uuidlastblock ;
}

consensus.fPowNoRetargeting = false;
        // consensus.lastPoWBlock = std::numeric_limits<int>::max();
        // consensus.lastPoWBlock = 1500;
        consensus.lastPoWBlock = 3085114;
        consensus.nPosTargetTimespan = 5 * 60;
        consensus.nPosTargetSpacing = 5 * 60;
        consensus.nStakeMinAge = 10 * 60;
        consensus.nStakeMaxAge = 60 * 60 * 24 * 120;
        consensus.nRuleChangeActivationThreshold = 6048; // 75% of 8064
        consensus.nMinerConfirmationWindow = 8064;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].bit = 28;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nStartTime = 1199145601; // January 1, 2008
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nTimeout = 1230767999; // December 31, 2008
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].min_activation_height = 0; // No activation delay

        // Deployment of BIP68, BIP112, and BIP113.
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].bit = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nStartTime = 1485561600; // January 28, 2017
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nTimeout = 1517356801; // January 31st, 2018
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].min_activation_height = 0; // No activation delay

        // Deployment of SegWit (BIP141, BIP143, and BIP147)
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].bit = 1;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nStartTime = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nTimeout = 999999999999ULL;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].min_activation_height = 0; // No activation delay

        // Deployment of Taproot (BIPs 340-342)
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].bit = 2;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nStartTime = 1619222400; // April 24th, 2021
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nTimeout = 1628640000; // August 11th, 2021
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].min_activation_height = 709632; // Approximately November 12th, 2021

        consensus.nMinimumChainWork = uint256S("0x0000000000000000000000000000000000000000000000000000000000000000");
        consensus.defaultAssumeValid = uint256S("0x0000000000000000000000000000000000000000000000000000000000000000");

        // Lynx specific parameters
        consensus.HardForkHeight = 126250;
        consensus.HardFork2Height = 1711675;
        consensus.HardFork3Height = 1838000;
        consensus.HardForkRule1params = {{2630000, 10},
                                         {2730000, 20},
                                         {2780000, 30},
                                         {2800000, 40},
                                         {2820000, 50}};
        consensus.HardForkRule2params = {{2680000, 2},
                                         {2850000, 3},
                                         {3000000, 4}};
        consensus.HardForkRule3params = {{2760000, 1},
                                         {2940000, 2},
                                         {9000000, 3}};
        consensus.WhiteAddress = "KQoKm4bzQvDAwiiFsPz3AE4UJHkHBvX6Bz";
        consensus.BlackAdresses = {{2820000, "KJ2MGS3jq4DPkVmE1ephMCbT7ojDcDSJRG", 1000000000 * COIN, 1000000 * COIN, COIN / 10},
                                   {2820000, "KSho9zUYrFdTPPxfF6ye9sLurgKygeUEzL", 1000000000 * COIN, 1000000 * COIN, COIN / 10}};
        consensus.HardForkRule2DifficultyPrevBlockCount = 10;
        consensus.HardForkRule2LowerLimitMinBalance = 1000 * COIN;
        consensus.HardForkRule2UpperLimitMinBalance = 100000000 * COIN;
        consensus.PowTargetSpacingV1 = 30;
        consensus.PowTargetSpacingV2 = 60;
        consensus.PowTargetSpacingV3 = 30;
        consensus.weightDampener = 10000000 * COIN;
        consensus.weightDampenerHeight = 3086200;



// cout << spec.name << " " << spec.nDefaultPort << " " << hex << (int)spec.pchMessageStart[0] << " " << (int)spec.pchMessageStart[1] << " " << (int)spec.pchMessageStart[2] << " " << (int)spec.pchMessageStart[3] << dec << " " << spec.pubkeyPrefix  << " " << spec.scriptPrefix  << " " << spec.secretPrefix  << " " << spec.coinSymbol << endl;



// #ifdef LYNX        
//         pchMessageStart[0] = 0xfa;
//         pchMessageStart[1] = 0xcf;
//         pchMessageStart[2] = 0xb3;
//         pchMessageStart[3] = 0xdc;
//         nDefaultPort = 22566;
// #elif defined(PANTHER)
//         pchMessageStart[0] = 0xe7; 
//         pchMessageStart[1] = 0xc5;
//         pchMessageStart[2] = 0xd3;
//         pchMessageStart[3] = 0xb6;
//         // nDefaultPort = 45466;
//         nDefaultPort = spec.nDefaultPort;
// #endif

if (std::string(CURRENT_CHAIN) == "lynx") {
        pchMessageStart[0] = 0xfa;
        pchMessageStart[1] = 0xcf;
        pchMessageStart[2] = 0xb3;
        pchMessageStart[3] = 0xdc;
        nDefaultPort = 22566;
} else {

LogPrintf ("nDefaultPort %d \n", nDefaultPort);

        pchMessageStart[0] = spec.pchMessageStart[0];
        pchMessageStart[1] = spec.pchMessageStart[1];
        pchMessageStart[2] = spec.pchMessageStart[2];
        pchMessageStart[3] = spec.pchMessageStart[3];
        nDefaultPort = spec.nDefaultPort;
}

        nPruneAfterHeight = 100000;
        m_assumed_blockchain_size = 1;
        m_assumed_chain_state_size = 0;

/*
FILE *f = fopen ("/root/flurb", "a");

uint32_t nBits = 0x1e0ffff0;

arith_uint256 target;
bool fNegative, fOverflow;
target.SetCompact(nBits, &fNegative, &fOverflow);

int nonce = -1;
fprintf (f, "nonce %d \n", nonce);
while (true) {
  nonce++;

  genesis = CreateGenesisBlock2(1757546169, nonce, nBits, 1, 88 * COIN);

  arith_uint256 hashInt = UintToArith256(genesis.GetPoWHash());

  if (hashInt <= target) {

    fprintf (f, "target %s \n", target.GetHex().c_str());
    fprintf (f, "nonce %d \n", nonce);
    fprintf (f, "GetHash %s \n", genesis.GetHash().GetHex().c_str());
    fprintf (f, "GetPoWHash %s \n", genesis.GetPoWHash().GetHex().c_str());
    fprintf (f, "hashMerkleRoot %s \n", genesis.hashMerkleRoot.GetHex().c_str());
//    std::cout << "=== Genesis Block Found ===\n";
//    std::cout << "Nonce: " << nonce << "\n";
//    std::cout << "Hash: " << genesis.GetHash().GetHex() << "\n";
//    std::cout << "Merkle root: " << genesis.hashMerkleRoot.GetHex() << "\n";
    break;
  }

  if (nonce % 100 == 0) {
    fprintf (f, "nonce %d \n", nonce);
    fflush (f);
  }


}

fclose(f);
*/

// #ifdef LYNX    
// 
//         genesis = CreateGenesisBlock(1387779684, 2714385, 0x1e0ffff0, 1, 88 * COIN);
//                                                 
// #elif defined(PANTHER)
// 
//         genesis = CreateGenesisBlock(1757546169, 3081890, 0x1e0ffff0, 1, 88 * COIN);
// 
// #endif



if (std::string(CURRENT_CHAIN) == "lynx") {
        genesis = CreateGenesisBlock(1387779684, 2714385, 0x1e0ffff0, 1, 88 * COIN);
} else {
        genesis = CreateGenesisBlock(spec.timestamp, spec.nonce, 0x1e0ffff0, 1, 88 * COIN);
}

// #ifdef LYNX    
//         consensus.hashGenesisBlock = genesis.GetHash();
//         assert(consensus.hashGenesisBlock == uint256S("0x984b30fc9bb5e5ff424ad7f4ec1930538a7b14a2d93e58ad7976c23154ea4a76"));
//         assert(genesis.hashMerkleRoot == uint256S("0xc2adb964220f170f6c4fe9002f0db19a6f9c9608f6f765ba0629ac3897028de5"));
// #elif defined(PANTHER)
//         consensus.hashGenesisBlock = genesis.GetHash();
//         assert(consensus.hashGenesisBlock == uint256S("0xc72d4b9b80c956e25dcead4c8d093cf0c83a448ee78d90709fc8df22e5bef058"));
//         assert(genesis.hashMerkleRoot == uint256S("0x7859ebe6fc610559c58228dc5e7a27d9ca80bd4674e642ce512820eaa51f5050"));
// #endif

        consensus.hashGenesisBlock = genesis.GetHash();

if (std::string(CURRENT_CHAIN) == "lynx") {
        assert(consensus.hashGenesisBlock == uint256S("0x984b30fc9bb5e5ff424ad7f4ec1930538a7b14a2d93e58ad7976c23154ea4a76"));
        assert(genesis.hashMerkleRoot == uint256S("0xc2adb964220f170f6c4fe9002f0db19a6f9c9608f6f765ba0629ac3897028de5"));
} else {
        assert(consensus.hashGenesisBlock == uint256S(spec.genesishash));
        assert(genesis.hashMerkleRoot == uint256S(spec.genesismerkleroot));
}

/*
FILE *f = fopen ("/root/flurm", "w");
fprintf(f,"  chainparams.cpp nVersion = %d\n", genesis.nVersion);
fprintf(f, "  nTime    = %u\n", genesis.nTime);
fprintf(f, "  nBits    = 0x%08x\n", genesis.nBits);
fprintf(f, "  nNonce   = %u\n", genesis.nNonce);
fprintf(f, "  hash     = %s\n", genesis.GetHash().ToString().c_str());
fprintf(f, "  merkle   = %s\n", genesis.hashMerkleRoot.ToString().c_str());
fclose(f);
*/

        consensus.initAuthTime = genesis.nTime;

// #ifdef LYNX    
//         vSeeds.emplace_back("node1.getlynx.io.");
//         vSeeds.emplace_back("node2.getlynx.io.");
//         vSeeds.emplace_back("node3.getlynx.io.");
//         vSeeds.emplace_back("node4.getlynx.io.");
//         vSeeds.emplace_back("node5.getlynx.io.");
// 
//         vFixedSeeds = std::vector<uint8_t>(std::begin(chainparams_seed_main), std::end(chainparams_seed_main));
// 
//         base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,45);
//         base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,22);
//         base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,173);
//         base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x88, 0xB2, 0x1E};
//         base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x88, 0xAD, 0xE4};
// 
//         bech32_hrp = "lynx";
// #elif defined(PANTHER)
//         vSeeds.clear();
//         vFixedSeeds.clear();
// 
//         base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,65);
//         base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,196);
//         base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,128);
//         base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x88, 0xB2, 0x1E};
//         base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x88, 0xAD, 0xE4};
// 
//         bech32_hrp = "panther";
// #endif
 
if (std::string(CURRENT_CHAIN) == "lynx") {
        vSeeds.emplace_back("node1.getlynx.io.");
        vSeeds.emplace_back("node2.getlynx.io.");
        vSeeds.emplace_back("node3.getlynx.io.");
        vSeeds.emplace_back("node4.getlynx.io.");
        vSeeds.emplace_back("node5.getlynx.io.");

        vFixedSeeds = std::vector<uint8_t>(std::begin(chainparams_seed_main), std::end(chainparams_seed_main));

        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,45);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,22);
        base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,173);
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x88, 0xB2, 0x1E};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x88, 0xAD, 0xE4};

        bech32_hrp = "lynx";
} else {
        vSeeds.clear();
        vFixedSeeds.clear();

        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,spec.pubkeyPrefix);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,spec.scriptPrefix);
        base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,spec.secretPrefix);	
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x88, 0xB2, 0x1E};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x88, 0xAD, 0xE4};

        bech32_hrp = CURRENT_CHAIN;
}



        fDefaultConsistencyChecks = false;
        fRequireStandard = true;
        m_is_test_chain = false;
        m_is_mockable_chain = false;

        checkpointData = {
            {
                {     0, genesis.GetHash()},
            }
        };

        m_assumeutxo_data = MapAssumeutxo{
         // TODO to be specified in a future patch.
        };

// #ifdef LYNX    
//         chainTxData = ChainTxData{
//             // Data from RPC: getchaintxstats 4096 000000000000000000035c3f0d31e71a5ee24c5aaf3354689f65bd7b07dee632
//             1387905669, // * UNIX timestamp of last known number of transactions
//             1717,       // * total number of transactions between genesis and that timestamp
//                         //   (the tx=... number in the SetBestChain debug.log lines)
//             3.0         // * estimated number of transactions per second after that timestamp
//         };
// #elif defined(PANTHER)
//         chainTxData = ChainTxData{
//             // Data from RPC: getchaintxstats 4096 000000000000000000035c3f0d31e71a5ee24c5aaf3354689f65bd7b07dee632
//             1757546169, // * UNIX timestamp of last known number of transactions
//             0,       // * total number of transactions between genesis and that timestamp
//                         //   (the tx=... number in the SetBestChain debug.log lines)
//             0.0         // * estimated number of transactions per second after that timestamp
//         };
// #endif

if (std::string(CURRENT_CHAIN) == "lynx") {
        chainTxData = ChainTxData{
            // Data from RPC: getchaintxstats 4096 000000000000000000035c3f0d31e71a5ee24c5aaf3354689f65bd7b07dee632
            1387905669, // * UNIX timestamp of last known number of transactions
            1717,       // * total number of transactions between genesis and that timestamp
                        //   (the tx=... number in the SetBestChain debug.log lines)
            3.0         // * estimated number of transactions per second after that timestamp
        };
} else {
        chainTxData = ChainTxData{
            // Data from RPC: getchaintxstats 4096 000000000000000000035c3f0d31e71a5ee24c5aaf3354689f65bd7b07dee632
            1757546169, // * UNIX timestamp of last known number of transactions
            0,       // * total number of transactions between genesis and that timestamp
                        //   (the tx=... number in the SetBestChain debug.log lines)
            0.0         // * estimated number of transactions per second after that timestamp
        };
}

    }
};
// */

/*
class CMainParams : public CChainParams {
public:
    CMainParams() {
        m_chain_type = ChainType::MAIN;

        // Consensus parameters
        consensus.signet_blocks = false;
        consensus.signet_challenge.clear();
        consensus.nSubsidyHalvingInterval = 210000;

        consensus.script_flag_exceptions.clear();

        consensus.BIP34Height = 710000;
        consensus.BIP34Hash = uint256S("fa09d204a83a768ed5a7c8d441fa62f2043abf420cff1226c7b4329aeb9d51cf");
        consensus.BIP65Height = 918684;
        consensus.BIP66Height = 811879;
        consensus.MinBIP9WarningHeight = 483840;

        consensus.powLimit = uint256S("00000fffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.nPowTargetTimespan = 1 * 60 * 60;
        consensus.fPowAllowMinDifficultyBlocks = false;
        consensus.fPowNoRetargeting = false;
        consensus.lastPoWBlock = 3085114;

        consensus.posLimit = uint256S("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.nPosTargetTimespan = 5 * 60;
        consensus.nPosTargetSpacing = 5 * 60;
        consensus.nStakeMinAge = 10 * 60;
        consensus.nStakeMaxAge = 60 * 60 * 24 * 120;

        consensus.nRuleChangeActivationThreshold = 6048; // 75% of 8064
        consensus.nMinerConfirmationWindow = 8064;
        consensus.nUUIDBlockStart = 3084941;

        // BIP deployments (CSV, SegWit, Taproot)
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY] = {28, 1199145601, 1230767999, 0};
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV] = {0, 1485561600, 1517356801, 0};
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT] = {1, 0, 999999999999ULL, 0};
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT] = {2, 1619222400, 1628640000, 709632};

        consensus.nMinimumChainWork = uint256S("0x0000000000000000000000000000000000000000000000000000000000000000");
        consensus.defaultAssumeValid = uint256S("0x0000000000000000000000000000000000000000000000000000000000000000");

        // Genesis block
        genesis = CreateGenesisBlock(1757546169, 791506, 0x1e0ffff0, 1, 88 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S("0x000009f2d965b3367ee24d95a73989d1ae7af28e6cc3a3380d44f810b2829cfa"));
        assert(genesis.hashMerkleRoot == uint256S("0x7859ebe6fc610559c58228dc5e7a27d9ca80bd4674e642ce512820eaa51f5050"));
        consensus.initAuthTime = genesis.nTime;

        // Network parameters
        pchMessageStart[0] = 0xe7;
        pchMessageStart[1] = 0xc5;
        pchMessageStart[2] = 0xd3;
        pchMessageStart[3] = 0xb6;
        nDefaultPort = 45466;
        nPruneAfterHeight = 100000;

        // Seeds
        vSeeds.clear();
        vFixedSeeds.clear();

        // Address prefixes
        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,65);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,196);
        base58Prefixes[SECRET_KEY] = std::vector<unsigned char>(1,128);
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x88, 0xB2, 0x1E};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x88, 0xAD, 0xE4};
        bech32_hrp = "panther";

        // Checkpoints
        checkpointData = {
            {
                {0, genesis.GetHash()},
            }
        };

        // ChainTxData
        chainTxData = ChainTxData{
            1757546169, // UNIX timestamp of last known tx
            0,          // total txs
            0.0         // tx/sec estimate
        };

        // Misc flags
        fDefaultConsistencyChecks = false;
        fRequireStandard = true;
        m_is_test_chain = false;
        m_is_mockable_chain = false;

        m_assumed_blockchain_size = 1;
        m_assumed_chain_state_size = 0;
    }
};
*/

/**
 * Testnet (v3): public test network which is reset from time to time.
 */
class CTestNetParams : public CChainParams {
public:
    CTestNetParams() {
        m_chain_type = ChainType::TESTNET;
        consensus.signet_blocks = false;
        consensus.signet_challenge.clear();
        consensus.nSubsidyHalvingInterval = 210000;
        consensus.script_flag_exceptions.emplace( // BIP16 exception
            uint256S("0x00000000dd30457c001f4095d208cc1296b0eed002427aa599874af7a432b105"), SCRIPT_VERIFY_NONE);
        consensus.BIP34Height = 21111;
        consensus.BIP34Hash = uint256S("0x0000000023b3a96d3484e5abb3755c413e7d41500f8e2a5c3f0dd01299cd8ef8");
        consensus.BIP65Height = 581885; // 00000000007f6655f22f98e72ed80d8b06dc761d5da09df0fa1dc4be4f861eb6
        consensus.BIP66Height = 330776; // 000000002104c8c45e99a8853285a3b592602a3ccde2b832481da85e9e4ba182
        consensus.MinBIP9WarningHeight = 836640; // segwit activation height + miner confirmation window
        consensus.powLimit = uint256S("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.nPowTargetTimespan = 14 * 24 * 60 * 60; // two weeks
        consensus.nPowTargetSpacing = 10 * 60;
        consensus.fPowAllowMinDifficultyBlocks = true;
        consensus.fPowNoRetargeting = false;
        consensus.lastPoWBlock = 6000;
        consensus.posLimit = uint256S("007fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.nPosTargetTimespan = 5 * 60;
        consensus.nPosTargetSpacing = 5 * 60;
        consensus.nStakeMinAge = 10 * 60;
        consensus.nStakeMaxAge = 60 * 60 * 24 * 30;
        consensus.nRuleChangeActivationThreshold = 1512; // 75% for testchains
        consensus.nMinerConfirmationWindow = 2016; // nPowTargetTimespan / nPowTargetSpacing
        consensus.nUUIDBlockStart = 6000;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].bit = 28;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nStartTime = Consensus::BIP9Deployment::NEVER_ACTIVE;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].min_activation_height = 0; // No activation delay

        // Deployment of BIP68, BIP112, and BIP113.
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].bit = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nStartTime = 1485561600; // January 28, 2017
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nTimeout = 1517356801; // January 31st, 2018
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].min_activation_height = 0; // No activation delay

        // Deployment of SegWit (BIP141, BIP143, and BIP147)
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].bit = 1;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nStartTime = 1485561600; // January 28, 2017
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nTimeout = 1517356801; // January 31st, 2018
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].min_activation_height = 0; // No activation delay

        // Deployment of Taproot (BIPs 340-342)
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].bit = 2;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nStartTime = 1619222400; // April 24th, 2021
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nTimeout = 1628640000; // August 11th, 2021
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].min_activation_height = 0; // No activation delay

        consensus.nMinimumChainWork = uint256S("0x0000000000000000000000000000000000000000000000000000000000000000");
        consensus.defaultAssumeValid = uint256S("0x0000000000000000000000000000000000000000000000000000000000000000");

        // Lynx specific parameters

        // Original testnet skeleton key
        consensus.initAuthUser = uint160S("2eba8c3d9038b739d4b2a85fa40eb91648ee2366");

        // New testnet wallet generated skeleton key
        // consensus.initAuthUser = uint160S("ee78c09ab25ea0f5df7112968ce6592019dd9401");

        // mainnet wallet generated skeleton key
        // consensus.initAuthUser = uint160S("1c04e67bf21dc44abe42e84a5ef3bce31b77aa6d");

        consensus.HardForkHeight = 1;
        consensus.HardFork2Height = 2;
        consensus.HardFork3Height = 3;
        consensus.HardForkRule1params = {{   250, 10},
                                         {   260, 20},
                                         {   270, 30},
                                         {   280, 40},
                                         {   290, 50},
                                         {200000, 60}};
        consensus.HardForkRule2params = {{255, 2},
                                         {310, 3},
                                         {360, 4}};
        consensus.HardForkRule3params = {{265, 1}};
        consensus.WhiteAddress = "mtzbBN6s3VN1AZoyXuaACzR4mWG1qwWdgq";
        consensus.BlackAdresses = {{60, "mgk3Z3R2S7RhrTU7P1z4J7vJwVwcQSpmzi", 5 * COIN,  1 * COIN, COIN / 10},
                                   {60, "mnzkVQKfQ6TjvLev7y9QfJAhrzM4pLDfiK", 5 * COIN,  1 * COIN, COIN / 10}};
        consensus.HardForkRule2DifficultyPrevBlockCount = 10;
        consensus.HardForkRule2LowerLimitMinBalance = 0.001*COIN;
        consensus.HardForkRule2UpperLimitMinBalance = 100000000*COIN;
        consensus.PowTargetSpacingV1 = 30;
        consensus.PowTargetSpacingV2 = 60;
        consensus.PowTargetSpacingV3 = 30;
        consensus.weightDampener = 10000000 * COIN;
        consensus.weightDampenerHeight = std::numeric_limits<int>::max();

        pchMessageStart[0] = 0x0b;
        pchMessageStart[1] = 0x11;
        pchMessageStart[2] = 0x09;
        pchMessageStart[3] = 0x07;
        nDefaultPort = 19333;
        nPruneAfterHeight = 1000;
        m_assumed_blockchain_size = 42;
        m_assumed_chain_state_size = 3;

/*
#ifdef LYNX    
        genesis = CreateGenesisBlock(1685504092, 5, 0x207fffff, 1, 50 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S("0x03536bed1d498da393f19961ed78f8c47ecf601717c3b4b28a3923db29ec58d2"));
        assert(genesis.hashMerkleRoot == uint256S("0xe17e4369f534691fade36848437428efdd6c51141b504aca65568ae564f171bf"));
#elif defined(PANTHER)
        genesis = CreateGenesisBlock(1757546169, 791506, 0x1e0ffff0, 1, 88 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S("0x000009f2d965b3367ee24d95a73989d1ae7af28e6cc3a3380d44f810b2829cfa"));
        assert(genesis.hashMerkleRoot == uint256S("0x7859ebe6fc610559c58228dc5e7a27d9ca80bd4674e642ce512820eaa51f5050"));
#endif
*/

if (std::string(CURRENT_CHAIN) == "lynx") {
        genesis = CreateGenesisBlock(1685504092, 5, 0x207fffff, 1, 50 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S("0x03536bed1d498da393f19961ed78f8c47ecf601717c3b4b28a3923db29ec58d2"));
        assert(genesis.hashMerkleRoot == uint256S("0xe17e4369f534691fade36848437428efdd6c51141b504aca65568ae564f171bf"));
} else {
        genesis = CreateGenesisBlock(spec.timestamp, spec.nonce, 0x1e0ffff0, 1, 88 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S(spec.genesishash));
        assert(genesis.hashMerkleRoot == uint256S(spec.genesismerkleroot));
}

        consensus.initAuthTime = genesis.nTime;

        //vFixedSeeds.clear();
        //vSeeds.clear();

        vSeeds.emplace_back("test1.getlynx.io.");
        vSeeds.emplace_back("test2.getlynx.io.");
        vSeeds.emplace_back("test3.getlynx.io.");

        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,111);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,196);
        base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,239);
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x35, 0x87, 0xCF};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x35, 0x83, 0x94};

        bech32_hrp = "tlynx";

        //vFixedSeeds = std::vector<uint8_t>(std::begin(chainparams_seed_test), std::end(chainparams_seed_test));

        fDefaultConsistencyChecks = false;
        fRequireStandard = false;
        m_is_test_chain = true;
        m_is_mockable_chain = false;

        checkpointData = {
            {
                {0, genesis.GetHash()},
            }
        };

        m_assumeutxo_data = MapAssumeutxo{
            // TODO to be specified in a future patch.
        };

        chainTxData = ChainTxData{
            // Data from RPC: getchaintxstats 4096 0000000000000021bc50a89cde4870d4a81ffe0153b3c8de77b435a2fd3f6761
            .nTime    = 1681542696,
            .nTxCount = 65345929,
            .dTxRate  = 0.09855282814711661,
        };
    }
};

/**
 * Signet: test network with an additional consensus parameter (see BIP325).
 */
class SigNetParams : public CChainParams {
public:
    explicit SigNetParams(const SigNetOptions& options)
    {
        std::vector<uint8_t> bin;
        vSeeds.clear();

        if (!options.challenge) {
            bin = ParseHex("512103ad5e0edad18cb1f0fc0d28a3d4f1f3e445640337489abb10404f2d1e086be430210359ef5021964fe22d6f8e05b2463c9540ce96883fe3b278760f048f5189f2e6c452ae");
            vSeeds.emplace_back("seed.signet.bitcoin.sprovoost.nl.");

            // Hardcoded nodes can be removed once there are more DNS seeds
            vSeeds.emplace_back("178.128.221.177");
            vSeeds.emplace_back("v7ajjeirttkbnt32wpy3c6w3emwnfr3fkla7hpxcfokr3ysd3kqtzmqd.onion:38333");

            consensus.nMinimumChainWork = uint256S("0x000000000000000000000000000000000000000000000000000001899d8142b0");
            consensus.defaultAssumeValid = uint256S("0x0000004429ef154f7e00b4f6b46bfbe2d2678ecd351d95bbfca437ab9a5b84ec"); // 138000
            m_assumed_blockchain_size = 1;
            m_assumed_chain_state_size = 0;
            chainTxData = ChainTxData{
                // Data from RPC: getchaintxstats 4096 0000004429ef154f7e00b4f6b46bfbe2d2678ecd351d95bbfca437ab9a5b84ec
                .nTime    = 1681127428,
                .nTxCount = 2226359,
                .dTxRate  = 0.006424463050600656,
            };
        } else {
            bin = *options.challenge;
            consensus.nMinimumChainWork = uint256{};
            consensus.defaultAssumeValid = uint256{};
            m_assumed_blockchain_size = 0;
            m_assumed_chain_state_size = 0;
            chainTxData = ChainTxData{
                0,
                0,
                0,
            };
            LogPrintf("Signet with challenge %s\n", HexStr(bin));
        }

        if (options.seeds) {
            vSeeds = *options.seeds;
        }

        m_chain_type = ChainType::SIGNET;
        consensus.signet_blocks = true;
        consensus.signet_challenge.assign(bin.begin(), bin.end());
        consensus.nSubsidyHalvingInterval = 210000;
        consensus.BIP34Height = 1;
        consensus.BIP34Hash = uint256{};
        consensus.BIP65Height = 1;
        consensus.BIP66Height = 1;
        consensus.nPowTargetTimespan = 14 * 24 * 60 * 60; // two weeks
        consensus.nPowTargetSpacing = 10 * 60;
        consensus.fPowAllowMinDifficultyBlocks = false;
        consensus.fPowNoRetargeting = false;
        consensus.lastPoWBlock = 250;
        consensus.posLimit = uint256S("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.nPosTargetTimespan = 5 * 60;
        consensus.nPosTargetSpacing = 5 * 60;
        consensus.nStakeMinAge = 10 * 60;
        consensus.nStakeMaxAge = 60 * 60 * 24 * 30;
        consensus.nRuleChangeActivationThreshold = 1815; // 90% of 2016
        consensus.nUUIDBlockStart = 1;
        consensus.nMinerConfirmationWindow = 2016; // nPowTargetTimespan / nPowTargetSpacing
        consensus.MinBIP9WarningHeight = 0;
        consensus.powLimit = uint256S("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].bit = 28;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nStartTime = Consensus::BIP9Deployment::NEVER_ACTIVE;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].min_activation_height = 0; // No activation delay

        // Deployment of BIP68, BIP112, and BIP113.
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].bit = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nStartTime = Consensus::BIP9Deployment::ALWAYS_ACTIVE;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].min_activation_height = 0; // No activation delay

        // Deployment of SegWit (BIP141, BIP143, and BIP147)
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].bit = 1;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nStartTime = Consensus::BIP9Deployment::ALWAYS_ACTIVE;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].min_activation_height = 0; // No activation delay

        // Activation of Taproot (BIPs 340-342)
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].bit = 2;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nStartTime = Consensus::BIP9Deployment::ALWAYS_ACTIVE;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].min_activation_height = 0; // No activation delay

        // message start is defined as the first 4 bytes of the sha256d of the block script
        HashWriter h{};
        h << consensus.signet_challenge;
        uint256 hash = h.GetHash();
        memcpy(pchMessageStart, hash.begin(), 4);

        nDefaultPort = 38333;
        nPruneAfterHeight = 1000;

/*
#ifdef LYNX    
        genesis = CreateGenesisBlock(1598918400, 52613770, 0x207fffff, 1, 50 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        //assert(consensus.hashGenesisBlock == uint256S("0x00000008819873e925422c1ff0f99f7cc9bbb232af63a077a480a3633bee1ef6"));
        //assert(genesis.hashMerkleRoot == uint256S("0x4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"));
#elif defined(PANTHER)
        genesis = CreateGenesisBlock(1757546169, 791506, 0x1e0ffff0, 1, 88 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S("0x000009f2d965b3367ee24d95a73989d1ae7af28e6cc3a3380d44f810b2829cfa"));
        assert(genesis.hashMerkleRoot == uint256S("0x7859ebe6fc610559c58228dc5e7a27d9ca80bd4674e642ce512820eaa51f5050"));
#endif
*/

if (std::string(CURRENT_CHAIN) == "lynx") {
        genesis = CreateGenesisBlock(1757546169, 791506, 0x1e0ffff0, 1, 88 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        // assert(consensus.hashGenesisBlock == uint256S("0x000009f2d965b3367ee24d95a73989d1ae7af28e6cc3a3380d44f810b2829cfa"));
        // assert(genesis.hashMerkleRoot == uint256S("0x7859ebe6fc610559c58228dc5e7a27d9ca80bd4674e642ce512820eaa51f5050"));
} else {
        genesis = CreateGenesisBlock(spec.timestamp, spec.nonce, 0x1e0ffff0, 1, 88 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S(spec.genesishash));
        assert(genesis.hashMerkleRoot == uint256S(spec.genesismerkleroot));
}

        vFixedSeeds.clear();

        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,111);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,196);
        base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,239);
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x35, 0x87, 0xCF};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x35, 0x83, 0x94};

        bech32_hrp = "tb";

        fDefaultConsistencyChecks = false;
        fRequireStandard = true;
        m_is_test_chain = true;
        m_is_mockable_chain = false;
    }
};

/**
 * Regression test: intended for private networks only. Has minimal difficulty to ensure that
 * blocks can be found instantly.
 */
class CRegTestParams : public CChainParams
{
public:
    explicit CRegTestParams(const RegTestOptions& opts)
    {
        m_chain_type = ChainType::REGTEST;
        consensus.signet_blocks = false;
        consensus.signet_challenge.clear();
        consensus.nSubsidyHalvingInterval = 150;
        consensus.BIP34Height = 1; // Always active unless overridden
        consensus.BIP34Hash = uint256();
        consensus.BIP65Height = 1;  // Always active unless overridden
        consensus.BIP66Height = 1;  // Always active unless overridden
        consensus.MinBIP9WarningHeight = 0;
        consensus.powLimit = uint256S("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.nPowTargetTimespan = 14 * 24 * 60 * 60; // two weeks
        consensus.nPowTargetSpacing = 10 * 60;
        consensus.fPowAllowMinDifficultyBlocks = true;
        consensus.fPowNoRetargeting = true;
        consensus.lastPoWBlock = 250;
        consensus.posLimit = uint256S("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.nPosTargetTimespan = 5 * 60;
        consensus.nPosTargetSpacing = 5 * 60;
        consensus.nStakeMinAge = 10 * 60;
        consensus.nStakeMaxAge = 60 * 60 * 24 * 30;
        consensus.nRuleChangeActivationThreshold = 108; // 75% for testchains
        consensus.nMinerConfirmationWindow = 144; // Faster than normal for regtest (144 instead of 2016)
        consensus.nUUIDBlockStart = 1;

        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].bit = 28;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nStartTime = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].min_activation_height = 0; // No activation delay

        // Deployment of BIP68, BIP112, and BIP113.
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].bit = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nStartTime = Consensus::BIP9Deployment::ALWAYS_ACTIVE;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].min_activation_height = 0; // No activation delay

        // Deployment of SegWit (BIP141, BIP143, and BIP147)
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].bit = 1;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nStartTime = Consensus::BIP9Deployment::ALWAYS_ACTIVE;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].min_activation_height = 0; // No activation delay

        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].bit = 2;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nStartTime = Consensus::BIP9Deployment::ALWAYS_ACTIVE;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].min_activation_height = 0; // No activation delay

        consensus.nMinimumChainWork = uint256{};
        consensus.defaultAssumeValid = uint256{};

        pchMessageStart[0] = 0xfa;
        pchMessageStart[1] = 0xbf;
        pchMessageStart[2] = 0xb5;
        pchMessageStart[3] = 0xda;
        nDefaultPort = 18444;
        nPruneAfterHeight = opts.fastprune ? 100 : 1000;
        m_assumed_blockchain_size = 0;
        m_assumed_chain_state_size = 0;

        for (const auto& [dep, height] : opts.activation_heights) {
            switch (dep) {
            case Consensus::BuriedDeployment::DEPLOYMENT_HEIGHTINCB:
                consensus.BIP34Height = int{height};
                break;
            case Consensus::BuriedDeployment::DEPLOYMENT_DERSIG:
                consensus.BIP66Height = int{height};
                break;
            case Consensus::BuriedDeployment::DEPLOYMENT_CLTV:
                consensus.BIP65Height = int{height};
                break;
            }
        }

        for (const auto& [deployment_pos, version_bits_params] : opts.version_bits_parameters) {
            consensus.vDeployments[deployment_pos].nStartTime = version_bits_params.start_time;
            consensus.vDeployments[deployment_pos].nTimeout = version_bits_params.timeout;
            consensus.vDeployments[deployment_pos].min_activation_height = version_bits_params.min_activation_height;
        }

/*
#ifdef LYNX    
        genesis = CreateGenesisBlock(1296688602, 2, 0x207fffff, 1, 50 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        //assert(consensus.hashGenesisBlock == uint256S("0x0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206"));
        //assert(genesis.hashMerkleRoot == uint256S("0x4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"));
#elif defined(PANTHER)
        genesis = CreateGenesisBlock(1757546169, 791506, 0x1e0ffff0, 1, 88 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S("0x000009f2d965b3367ee24d95a73989d1ae7af28e6cc3a3380d44f810b2829cfa"));
        assert(genesis.hashMerkleRoot == uint256S("0x7859ebe6fc610559c58228dc5e7a27d9ca80bd4674e642ce512820eaa51f5050"));
#endif
*/

if (std::string(CURRENT_CHAIN) == "lynx") {
        genesis = CreateGenesisBlock(1296688602, 2, 0x207fffff, 1, 50 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        //assert(consensus.hashGenesisBlock == uint256S("0x0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206"));
        //assert(genesis.hashMerkleRoot == uint256S("0x4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"));
} else {
        genesis = CreateGenesisBlock(spec.timestamp, spec.nonce, 0x1e0ffff0, 1, 88 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S(spec.genesishash));
        assert(genesis.hashMerkleRoot == uint256S(spec.genesismerkleroot));
}

        vFixedSeeds.clear(); //!< Regtest mode doesn't have any fixed seeds.
        vSeeds.clear();
        vSeeds.emplace_back("dummySeed.invalid.");

        fDefaultConsistencyChecks = true;
        fRequireStandard = true;
        m_is_test_chain = true;
        m_is_mockable_chain = true;

        checkpointData = {
            {
                {0, uint256S("0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206")},
            }
        };

        m_assumeutxo_data = MapAssumeutxo{
            {
                110,
                {AssumeutxoHash{uint256S("0x1ebbf5850204c0bdb15bf030f47c7fe91d45c44c712697e4509ba67adb01c618")}, 110},
            },
            {
                200,
                {AssumeutxoHash{uint256S("0x51c8d11d8b5c1de51543c579736e786aa2736206d1e11e627568029ce092cf62")}, 200},
            },
        };

        chainTxData = ChainTxData{
            0,
            0,
            0
        };

        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,111);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,196);
        base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,239);
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x35, 0x87, 0xCF};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x35, 0x83, 0x94};

        bech32_hrp = "rlynx";
    }
};

std::unique_ptr<const CChainParams> CChainParams::SigNet(const SigNetOptions& options)
{
    return std::make_unique<const SigNetParams>(options);
}

std::unique_ptr<const CChainParams> CChainParams::RegTest(const RegTestOptions& options)
{
    return std::make_unique<const CRegTestParams>(options);
}

std::unique_ptr<const CChainParams> CChainParams::Main()
{
    return std::make_unique<const CMainParams>();
}

std::unique_ptr<const CChainParams> CChainParams::TestNet()
{
    return std::make_unique<const CTestNetParams>();
}
