// Copyright (c) 2012-2013 The PPCoin developers
// Copyright (c) 2014 The BlackCoin developers
// Copyright (c) 2017-2022 The Particl Core developers
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <pos/pos.h>

#include <chainparams.h>
#include <coins.h>
#include <consensus/validation.h>
#include <hash.h>
#include <node/transaction.h>
#include <policy/policy.h>
#include <script/interpreter.h>
#include <script/script.h>
#include <serialize.h>
#include <streams.h>
#include <txmempool.h>
#include <util/system.h>
#include <validation.h>

std::list<COutPoint> listStakeSeen;
std::map<COutPoint, uint256> mapStakeSeen;

// 
// Proof of stake core algorithm 
// 
// (proof of stake hash) < (weighted difficulty)
// (proof of stake hash) < ((difficulty) * (stake))
// 
// The smaller the difficulty, the harder to meet the condition.
// 
// The larger the stake, the easier to meet the condition
// 


// 
// Current block = blockchain tip
// Next block = candidate block
//

// 
// Compact data format (uint32_t)
// From left to right:
// 8 bit exponent, e
// 24 bit mantissa, m
// Value, v = m x (256 ^ (e-3))
// 

//
// FormatISO8601DateTime
// Number of seconds since the first second of 1970 -> 
// GMT year month day hour minute second
// 

// 
// SER_GETHASH
// Avoid inclusion of unnecessary metadata
// 

bool blnfncCheckStakeKernelHash (

    // Current block
    const CBlockIndex* ibliCurrentBlock,    
    
    // Difficulty (compact)
    uint32_t icmpDifficulty,                   

    // UTXO block time (compact)
    uint32_t icmpUTXOBlockTime,     

    // Stake amount   
    CAmount imntStakeAmount,        

    // Stake outpoint     
    const COutPoint& ioptStakeOutpoint,          
    
    // Candidate block time (compact)
    uint32_t icmpCandidateBlockTime,    

    // Proof of stake hash             
    uint256& ou25ProofOfStakeHash,         

    // Weighted difficulty
    uint256& ou25WeightedDifficulty,     

    // Log flag
    bool iblnLogFlag) {
    
    // Verbose logging for function entry
    LogPrint(BCLog::POS, "blnfncCheckStakeKernelHash: Entered for block height %d, difficulty 0x%x, UTXO time %u, stake amount %lld, outpoint %s:%d, candidate time %u\n", 
        ibliCurrentBlock ? ibliCurrentBlock->nHeight : -1, icmpDifficulty, icmpUTXOBlockTime, (long long)imntStakeAmount, ioptStakeOutpoint.hash.ToString(), ioptStakeOutpoint.n, icmpCandidateBlockTime);
    
    // Consensus variables
    const Consensus::Params& cnsConsensusVariables = Params().GetConsensus();

    // If candidate block time < UTXO block time
    if (icmpCandidateBlockTime < icmpUTXOBlockTime) {

        // Log error
        return error("%s: Candidate block time violation", __func__);
    }

    // Difficulty
    arith_uint256 rthDifficulty;

    // Negative flag
    bool blnNegativeFlag;

    // Overflow flag
    bool blnOverflowFlag;

    // Set difficulty
    rthDifficulty.SetCompact(icmpDifficulty, &blnNegativeFlag, &blnOverflowFlag);

    // If negative or overflow or zero
    if (blnNegativeFlag || blnOverflowFlag || rthDifficulty == 0) {

        // Return error
        return error("%s: SetCompact failed.", __func__);
    }

    // Set stake amount
    int64_t i64StakeAmount = imntStakeAmount;

    // If current block height exceeds threshold and stake exceeds threthold
    if (ibliCurrentBlock->nHeight + 1 >= cnsConsensusVariables.weightDampenerHeight &&
        i64StakeAmount >= cnsConsensusVariables.weightDampener) {

        // Cap stake
        i64StakeAmount = cnsConsensusVariables.weightDampener;
    }

    // Set stake amount
    arith_uint256 rthStakeAmount = arith_uint256(i64StakeAmount);

    // Weighted difficulty
    arith_uint256 rthWeightedDifficulty;

    // Weight difficulty
    rthWeightedDifficulty = rthDifficulty * rthStakeAmount;

    // Set weighted difficulty
    ou25WeightedDifficulty = ArithToUint256(rthWeightedDifficulty);

    // Set stake modifier
    const uint256& u25StakeModifier = ibliCurrentBlock->nStakeModifier;

    // Set stake modifier height 
    int intStakeModifierHeight = ibliCurrentBlock->nHeight;

    // Set stake modifier time
    int64_t i64StakeModifierTime = ibliCurrentBlock->nTime;

    // Hash data stream
    CDataStream dstHashDatastream(SER_GETHASH, 0);

    // Stake modifier
    dstHashDatastream << u25StakeModifier;             

    // UTXO block time
    dstHashDatastream << icmpUTXOBlockTime               

    // Stake outpoint transaction    
    << ioptStakeOutpoint.hash                

    // Stake outpoint index
    << ioptStakeOutpoint.n                    

    // Candidate block time
    << icmpCandidateBlockTime;                      

    // Compute hash
    ou25ProofOfStakeHash = Hash(dstHashDatastream);

    // Log stake modifier, stake modifier height, stake modifier time 
    if (iblnLogFlag) {
        LogPrintf("%s: using stake modifier=%s at stake modifier height=%d stake modifier time=%s\n",
            __func__, u25StakeModifier.ToString(), intStakeModifierHeight,
            FormatISO8601DateTime(i64StakeModifierTime));

        // Log stake modifier, utxo block time, outpoint index, candidate block time, proof of hash stake
        LogPrintf("%s: check stake modifier=%s utxo block time=%u stake outpoint index=%u candidate block time =%u proof of stake hash=%s\n",
            __func__, u25StakeModifier.ToString(),
            icmpUTXOBlockTime, ioptStakeOutpoint.n, icmpCandidateBlockTime,
            ou25ProofOfStakeHash.ToString());
    }

    // If proof of stake hash < weighted difficulty
    if (UintToArith256(ou25ProofOfStakeHash) > rthWeightedDifficulty) {

        // Report 
        LogPrint (BCLog::POS, "Hash exceeds target - stake attempt invalid \n");

        // Return false
        return false;  
    }

    // Log stake modifier, stake modifier height, stake modifier time 
    if (iblnLogFlag) {
        LogPrintf("%s: using stake modifier=%s at stake modifier height=%d stake modifier time=%s\n",
            __func__, u25StakeModifier.ToString(), intStakeModifierHeight,
            FormatISO8601DateTime(i64StakeModifierTime));

        // Log stake modifier, utxo block time, outpoint index, candidate block time, proof of hash stake
        LogPrintf("%s: pass stake modifier=%s utxo block time=%u stake outpoint index=%u candidate block time =%u proof of stake hash=%s\n",
            __func__, u25StakeModifier.ToString(),
            icmpUTXOBlockTime, ioptStakeOutpoint.n, icmpCandidateBlockTime,
            ou25ProofOfStakeHash.ToString());
    }

    // Return true
    return true; 
}

// Ckeck kernel
bool blnfncCheckKernel(Chainstate& chnChainState, const CBlockIndex* ibliCurrentBlock, unsigned int icmpDifficulty, int64_t icmpCandidateBlockTime, const COutPoint& ioptStakeOutpoint, int64_t* ocmpUTXOBlockTime)
{
    LogPrint(BCLog::POS, "blnfncCheckKernel: Starting kernel check for block height %d, outpoint %s:%d\n", ibliCurrentBlock ? ibliCurrentBlock->nHeight : -1, ioptStakeOutpoint.hash.ToString(), ioptStakeOutpoint.n);

    uint256 u25ProofOfStakeHash, u25WeightedDifficulty;

    // Stake coin
    Coin coiStakeCoin;
    {
        LOCK(::cs_main);
        LogPrint(BCLog::POS, "blnfncCheckKernel: Attempting to fetch stake coin for outpoint %s:%d\n", ioptStakeOutpoint.hash.ToString(), ioptStakeOutpoint.n);
        if (!chnChainState.CoinsTip().GetCoin(ioptStakeOutpoint, coiStakeCoin)) {
            LogPrint(BCLog::POS, "blnfncCheckKernel: Stake outpoint not found\n");
            return error("%s: stake outpoint not found", __func__);
        }
    }

    if (coiStakeCoin.IsSpent()) {
        LogPrint(BCLog::POS, "blnfncCheckKernel: Stake outpoint is spent\n");
        return error("%s: stake outpoint is spent", __func__);
    }

    // Get stake block
    CBlockIndex* bliStakeBlock = chnChainState.m_chain[coiStakeCoin.nHeight];
    if (!bliStakeBlock) {
        LogPrint(BCLog::POS, "blnfncCheckKernel: Stake block not found for coin height %d\n", coiStakeCoin.nHeight);
        return false;
    }

    // Set required depth
    int intRequiredDepth = std::min((int)COINBASE_MATURITY, (int)(ibliCurrentBlock->nHeight / 2));

    // Set stake depth
    int intStakeDepth = ibliCurrentBlock->nHeight - coiStakeCoin.nHeight;
    LogPrint(BCLog::POS, "blnfncCheckKernel: Stake depth %d, required depth %d\n", intStakeDepth, intRequiredDepth);
    if (intRequiredDepth > intStakeDepth) {
        LogPrint(BCLog::POS, "blnfncCheckKernel: Stake depth insufficient\n");
        return false;
    }

    // Get UTXO time
    if (ocmpUTXOBlockTime) {
        *ocmpUTXOBlockTime = bliStakeBlock->GetBlockTime();
        LogPrint(BCLog::POS, "blnfncCheckKernel: UTXO block time set to %lld\n", (long long)*ocmpUTXOBlockTime);
    }

    // Set stake amount
    CAmount mntStakeAmount = coiStakeCoin.out.nValue;
    LogPrint(BCLog::POS, "blnfncCheckKernel: Stake amount is %lld\n", mntStakeAmount);

    // Check stake kernel hash
    return blnfncCheckStakeKernelHash(ibliCurrentBlock, icmpDifficulty, *ocmpUTXOBlockTime,
        mntStakeAmount, ioptStakeOutpoint, icmpCandidateBlockTime, u25ProofOfStakeHash, u25WeightedDifficulty);
}

bool blnfncCheckProofOfStake(
    Chainstate& chain_state,          
    BlockValidationState& state,      
    const CBlockIndex* ibliCurrentBlock,    
    const CTransaction& itxnStakeTransaction,           
    int64_t icmpCandidateBlockTime,                    
    unsigned int icmpDifficulty,               
    uint256& ou25ProofOfStakeHash,        
    uint256& ou25WeightedDifficulty)      
{
    LogPrint(BCLog::POS, "blnfncCheckProofOfStake: Starting PoS validation for block height %d, txid %s\n", ibliCurrentBlock ? ibliCurrentBlock->nHeight : -1, itxnStakeTransaction.GetHash().ToString());

    // If coin stake or no inputs
    if (!itxnStakeTransaction.IsCoinStake() || itxnStakeTransaction.vin.size() < 1) {
        LogPrintf("ERROR: %s: malformed-txn %s\n", __func__, itxnStakeTransaction.GetHash().ToString());
        LogPrint(BCLog::POS, "blnfncCheckProofOfStake: Transaction is not coinstake or has no inputs\n");
        return false;
    }

    // CTransactionRef txPrev;

    // Stake transaction input
    const CTxIn& txiStakeTransactionInput = itxnStakeTransaction.vin[0];
    LogPrint(BCLog::POS, "blnfncCheckProofOfStake: Using input prevout %s:%d\n", txiStakeTransactionInput.prevout.hash.ToString(), txiStakeTransactionInput.prevout.n);

    // UTXO block time
    uint32_t cmpUTXOBlockTime;    

    // Stake depth
    int intStakeDepth;                 

    // scriptPubKey
    CScript scrScriptPubKey;       

    // Stake amount
    CAmount mntStakeAmount;            

    // Stake coin 
    Coin coiStakeCoin;

    if (!chain_state.CoinsTip().GetCoin(txiStakeTransactionInput.prevout, coiStakeCoin) || coiStakeCoin.IsSpent()) {
        LogPrint(BCLog::POS, "blnfncCheckProofOfStake: Coin not found or spent for input\n");
        return false;
    }

    // Set stake block
    CBlockIndex* bliStakeBlock = chain_state.m_chain[coiStakeCoin.nHeight];
    if (!bliStakeBlock) {
        LogPrint(BCLog::POS, "blnfncCheckProofOfStake: Stake block not found for coin height %d\n", coiStakeCoin.nHeight);
        return false;
    }

    // Set stake depth
    intStakeDepth = ibliCurrentBlock->nHeight - coiStakeCoin.nHeight;

    // Set required depth
    int nRequiredDepth = std::min((int)COINBASE_MATURITY, (int)(ibliCurrentBlock->nHeight / 2));
    LogPrint(BCLog::POS, "blnfncCheckProofOfStake: Stake depth %d, required depth %d\n", intStakeDepth, nRequiredDepth);
    if (nRequiredDepth > intStakeDepth) {
        LogPrint(BCLog::POS, "blnfncCheckProofOfStake: Stake depth insufficient\n");
        return false;
    }

    scrScriptPubKey = coiStakeCoin.out.scriptPubKey;
    mntStakeAmount = coiStakeCoin.out.nValue;
    cmpUTXOBlockTime = bliStakeBlock->GetBlockTime();
    LogPrint(BCLog::POS, "blnfncCheckProofOfStake: Stake amount %lld, UTXO block time %u\n", mntStakeAmount, cmpUTXOBlockTime);

    // Get sciptSig
    const CScript& scrScriptSig = txiStakeTransactionInput.scriptSig;

    // Get script witness
    const CScriptWitness* scwScriptWitness = &txiStakeTransactionInput.scriptWitness;

    // Initializine script error
    ScriptError sceScriptError = SCRIPT_ERR_OK;

    // std::vector<uint8_t> vchAmount(8);

    // If invalid script
    if (!VerifyScript(scrScriptSig, scrScriptPubKey, scwScriptWitness, STANDARD_SCRIPT_VERIFY_FLAGS, TransactionSignatureChecker(&itxnStakeTransaction, 0, mntStakeAmount, MissingDataBehavior::FAIL), &sceScriptError)) {
        LogPrintf("ERROR: %s: verify-script-failed, txn %s, reason %s\n", __func__, itxnStakeTransaction.GetHash().ToString(), ScriptErrorString(sceScriptError));
        LogPrint(BCLog::POS, "blnfncCheckProofOfStake: Script verification failed\n");
        return false;
    }

    LogPrint(BCLog::POS, "blnfncCheckProofOfStake: Script verified successfully\n");

    if (!blnfncCheckStakeKernelHash (ibliCurrentBlock, icmpDifficulty, cmpUTXOBlockTime,
            mntStakeAmount, txiStakeTransactionInput.prevout, icmpCandidateBlockTime, ou25ProofOfStakeHash, ou25WeightedDifficulty, LogAcceptCategory(BCLog::POS, BCLog::Level::Debug))) {
        LogPrintf("WARNING: %s: Check kernel failed on coinstake %s, proof of stake hash=%s\n", __func__, itxnStakeTransaction.GetHash().ToString(), ou25ProofOfStakeHash.ToString());
        LogPrint(BCLog::POS, "blnfncCheckProofOfStake: Kernel check failed\n");
        return false;
    }

    LogPrint(BCLog::POS, "blnfncCheckProofOfStake: Kernel check passed, PoS validation successful\n");
    return true;
}



/* Calculate the difficulty for a given block index.
 * Duplicated from rpc/blockchain.cpp for linking
 */
static double GetDifficulty(const CBlockIndex* blockindex)
{
    CHECK_NONFATAL(blockindex);
    LogPrint(BCLog::POS, "GetDifficulty: Calculating difficulty for block at height %d, nBits: 0x%x\n", blockindex->nHeight, blockindex->nBits);

    int nShift = (blockindex->nBits >> 24) & 0xff;
    LogPrint(BCLog::POS, "GetDifficulty: Initial nShift value: %d\n", nShift);
    double dDiff = (double)0x0000ffff / (double)(blockindex->nBits & 0x00ffffff);
    LogPrint(BCLog::POS, "GetDifficulty: Initial dDiff value: %f\n", dDiff);

    while (nShift < 29) {
        dDiff *= 256.0;
        nShift++;
        LogPrint(BCLog::POS, "GetDifficulty: Increasing nShift to %d, dDiff now %f\n", nShift, dDiff);
    }
    while (nShift > 29) {
        dDiff /= 256.0;
        nShift--;
        LogPrint(BCLog::POS, "GetDifficulty: Decreasing nShift to %d, dDiff now %f\n", nShift, dDiff);
    }

    LogPrint(BCLog::POS, "GetDifficulty: Final difficulty for block at height %d is %f\n", blockindex->nHeight, dDiff);
    return dDiff;
}

double GetPoSKernelPS(CBlockIndex* pindex)
{
    LOCK(cs_main);
    LogPrint(BCLog::POS, "GetPoSKernelPS: Calculating proof-of-stake kernel per second for height %d\n", pindex->nHeight);

    CBlockIndex* pindexPrevStake = nullptr;

    int nBestHeight = pindex->nHeight;

    int nPoSInterval = 72; // blocks sampled
    double dStakeKernelsTriedAvg = 0;
    int nStakesHandled = 0, nStakesTime = 0;

    while (pindex && nStakesHandled < nPoSInterval) {
        if (pindex->IsProofOfStake()) {
            if (pindexPrevStake) {
                double difficulty = GetDifficulty(pindexPrevStake);
                dStakeKernelsTriedAvg += difficulty * 4294967296.0;
                nStakesTime += pindexPrevStake->nTime - pindex->nTime;
                nStakesHandled++;
                LogPrint(BCLog::POS, "GetPoSKernelPS: Processed stake block at height %d, difficulty: %f\n", pindex->nHeight, difficulty);
            }
            pindexPrevStake = pindex;
        }
        pindex = pindex->pprev;
    }

    double result = 0;

    if (nStakesTime) {
        result = dStakeKernelsTriedAvg / nStakesTime;
        LogPrint(BCLog::POS, "GetPoSKernelPS: Calculated base rate: %f kernels/sec from %d stakes over %d seconds\n", result, nStakesHandled, nStakesTime);
    } else {
        LogPrint(BCLog::POS, "GetPoSKernelPS: No stake time available, returning 0\n");
    }

    result *= nStakeTimestampMask + 1;
    LogPrint(BCLog::POS, "GetPoSKernelPS: Final adjusted rate: %f kernels/sec (mask multiplier: %d)\n", result, nStakeTimestampMask + 1);

    return result;
}

/**
 * Stake Modifier (hash modifier of proof-of-stake):
 * The purpose of stake modifier is to prevent a txout (coin) owner from
 * computing future proof-of-stake generated by this txout at the time
 * of transaction confirmation. To meet kernel protocol, the txout
 * must hash with a future stake modifier to generate the proof.
 */
uint256 ComputeStakeModifier(const CBlockIndex* pindexPrev, const uint256& kernel)
{
    if (!pindexPrev) {
        LogPrint(BCLog::POS, "ComputeStakeModifier: Genesis block - returning zero modifier\n");
        return uint256(); // genesis block's modifier is 0
    }

    LogPrint(BCLog::POS, "ComputeStakeModifier: Computing new stake modifier from kernel %s and previous modifier\n", kernel.ToString());
    CDataStream ss(SER_GETHASH, 0);
    ss << kernel << pindexPrev->nStakeModifier;
    uint256 newModifier = Hash(ss);
    LogPrint(BCLog::POS, "ComputeStakeModifier: New stake modifier: %s\n", newModifier.ToString());
    return newModifier;
}

// Check whether the coinstake timestamp meets protocol
bool CheckCoinStakeTimestamp(int64_t nTimeBlock)
{
    bool isValid = (nTimeBlock & nStakeTimestampMask) == 0;
    LogPrint(BCLog::POS, "CheckCoinStakeTimestamp: Time %d mask check: %s (mask: %d)\n", nTimeBlock, isValid ? "VALID" : "INVALID", nStakeTimestampMask);
    return isValid;
}

bool AddToMapStakeSeen(const COutPoint& kernel, const uint256& blockHash)
{
    // Overwrites existing values
    LogPrint(BCLog::POS, "AddToMapStakeSeen: Recording stake kernel %s:%d for block %s\n", kernel.hash.ToString(), kernel.n, blockHash.ToString());

    std::pair<std::map<COutPoint, uint256>::iterator, bool> ret;
    ret = mapStakeSeen.insert(std::pair<COutPoint, uint256>(kernel, blockHash));
    if (ret.second == false) { // existing element
        LogPrint(BCLog::POS, "AddToMapStakeSeen: Kernel already exists, updating block hash from %s to %s\n", ret.first->second.ToString(), blockHash.ToString());
        ret.first->second = blockHash;
    } else {
        LogPrint(BCLog::POS, "AddToMapStakeSeen: New kernel added to tracking list (total: %d)\n", listStakeSeen.size() + 1);
        listStakeSeen.push_back(kernel);
    }

    return true;
};

bool CheckStakeUnused(const COutPoint& kernel)
{
    std::map<COutPoint, uint256>::const_iterator mi = mapStakeSeen.find(kernel);
    bool unused = (mi == mapStakeSeen.end());
    LogPrint(BCLog::POS, "CheckStakeUnused: Kernel %s:%d is %s\n", kernel.hash.ToString(), kernel.n, unused ? "UNUSED (available)" : "USED (already staked)");
    if (!unused && mi != mapStakeSeen.end()) {
        LogPrint(BCLog::POS, "CheckStakeUnused: Kernel was used in block %s\n", mi->second.ToString());
    }
    return unused;
}

bool CheckStakeUnique(const CBlock& block, bool fUpdate)
{
    LOCK(cs_main);

    uint256 blockHash = block.GetHash();
    const COutPoint& kernel = block.vtx[0]->vin[0].prevout;
    LogPrint(BCLog::POS, "CheckStakeUnique: Checking uniqueness of kernel %s:%d for block %s (update: %s)\n", 
             kernel.hash.ToString(), kernel.n, blockHash.ToString(), fUpdate ? "yes" : "no");

    std::map<COutPoint, uint256>::const_iterator mi = mapStakeSeen.find(kernel);
    if (mi != mapStakeSeen.end()) {
        if (mi->second == blockHash) {
            LogPrint(BCLog::POS, "CheckStakeUnique: Kernel already registered for this same block - OK\n");
            return true;
        }
        LogPrint(BCLog::POS, "CheckStakeUnique: ERROR - Kernel already used in different block %s\n", mi->second.ToString());
        return error("%s: Stake kernel for %s first seen on %s.", __func__, blockHash.ToString(), mi->second.ToString());
    }
    LogPrint(BCLog::POS, "CheckStakeUnique: Kernel not previously used - OK\n");

    if (!fUpdate) {
        LogPrint(BCLog::POS, "CheckStakeUnique: Update not requested, returning success\n");
        return true;
    }

    while (listStakeSeen.size() > 1024) {
        const COutPoint& oldest = listStakeSeen.front();
        LogPrint(BCLog::POS, "CheckStakeUnique: Pruning old stake entry %s:%d (maintaining 1024 entry limit)\n", oldest.hash.ToString(), oldest.n);
        if (1 != mapStakeSeen.erase(oldest)) {
            LogPrintf("%s: Warning: mapStakeSeen did not erase %s %n\n", __func__, oldest.hash.ToString(), oldest.n);
        }
        listStakeSeen.pop_front();
    }

    return AddToMapStakeSeen(kernel, blockHash);
};
