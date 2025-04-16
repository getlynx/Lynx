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
    uint256 u25ProofOfStakeHash, u25WeightedDifficulty;

    // Stake coin
    Coin coiStakeCoin;
    {
        LOCK(::cs_main);

        // Get stake coin
        if (!chnChainState.CoinsTip().GetCoin(ioptStakeOutpoint, coiStakeCoin)) {
            return error("%s: stake outpoint not found", __func__);
        }
    }

    // If stake coin spent
    if (coiStakeCoin.IsSpent()) {
        return error("%s: stake outpoint is spent", __func__);
    }

    // Get stake block
    CBlockIndex* bliStakeBlock = chnChainState.m_chain[coiStakeCoin.nHeight];
    if (!bliStakeBlock) {
        return false;
    }

    // Set required depth
    int intRequiredDepth = std::min((int)COINBASE_MATURITY, (int)(ibliCurrentBlock->nHeight / 2));

    // Set stake depth
    int intStakeDepth = ibliCurrentBlock->nHeight - coiStakeCoin.nHeight;

    // If required depth > stake depth
    if (intRequiredDepth > intStakeDepth) {
        return false;
    }

    // Get UTXO time
    if (ocmpUTXOBlockTime) {
        *ocmpUTXOBlockTime = bliStakeBlock->GetBlockTime();
    }

    // Set stake amount
    CAmount mntStakeAmount = coiStakeCoin.out.nValue;

    // Check stake kernel hash
    return blnfncCheckStakeKernelHash(ibliCurrentBlock, icmpDifficulty, *ocmpUTXOBlockTime,
        mntStakeAmount, ioptStakeOutpoint, icmpCandidateBlockTime, u25ProofOfStakeHash, u25WeightedDifficulty);
}

bool blnfncCheckProofOfStake(
    Chainstate& chain_state,          
    BlockValidationState& state,      
    const CBlockIndex* ibliCurrentBlock,    
    const CTransaction& tx,           
    int64_t nTime,                    
    unsigned int nBits,               
    uint256& hashProofOfStake,        
    uint256& targetProofOfStake)      
{
    // ibliCurrentBlock points to the latest block in our chain
    // nTime represents when the new block was created

    // Get access to the block database through the chain state
    auto& pblocktree { chain_state.m_blockman.m_block_tree_db };

    // Verify this is a valid staking transaction with at least one input
    if (!tx.IsCoinStake() || tx.vin.size() < 1) {
        LogPrintf("ERROR: %s: malformed-txn %s\n", __func__, tx.GetHash().ToString());
        return false;
    }

    // Reference to hold the previous transaction (though unused in this function)
    CTransactionRef txPrev;

    // Get the first input of the coinstake transaction
    // This input (known as the kernel) must meet the staking target
    // Kernel (input 0) must match the stake hash target per coin age (nBits)
    const CTxIn& txin = tx.vin[0];

    // Variables to store information about the staking coin
    uint32_t nBlockFromTime;    // Timestamp of block containing the staked coin
    int nDepth;                 // How many blocks deep is the staked coin
    CScript kernelPubKey;       // Public key script that controls the stake
    CAmount amount;             // Amount of coins being staked

    // Try to find the coin being staked in the UTXO (unspent transaction output) set
    Coin coin;
    if (!chain_state.CoinsTip().GetCoin(txin.prevout, coin) || coin.IsSpent()) {
        return false;  // Coin doesn't exist or was already spent
    }

    // Find the block that contains the coin being staked
    CBlockIndex* pindex = chain_state.m_chain[coin.nHeight];
    if (!pindex) {
        return false;  // Block not found in main chain
    }

    // Calculate the coin's age in blocks and verify it meets minimum age requirement
    nDepth = ibliCurrentBlock->nHeight - coin.nHeight;
    // Required depth is the lesser of COINBASE_MATURITY or half the chain height
    int nRequiredDepth = std::min((int)COINBASE_MATURITY, (int)(ibliCurrentBlock->nHeight / 2));
    if (nRequiredDepth > nDepth) {
        return false;  // Coin isn't mature enough to stake
    }

    // Store the staking coin's details for validation
    kernelPubKey = coin.out.scriptPubKey;      // Script controlling the coins
    amount = coin.out.nValue;                   // Amount being staked
    nBlockFromTime = pindex->GetBlockTime();    // When the coin's block was mined

    // Get the spending transaction's signature details
    const CScript& scriptSig = txin.scriptSig;
    const CScriptWitness* witness = &txin.scriptWitness;
    ScriptError serror = SCRIPT_ERR_OK;
    std::vector<uint8_t> vchAmount(8);

    // Verify the transaction signature is valid and the spender owns the coins
    if (!VerifyScript(scriptSig, kernelPubKey, witness, STANDARD_SCRIPT_VERIFY_FLAGS, TransactionSignatureChecker(&tx, 0, amount, MissingDataBehavior::FAIL), &serror)) {
        LogPrintf("ERROR: %s: verify-script-failed, txn %s, reason %s\n", __func__, tx.GetHash().ToString(), ScriptErrorString(serror));
        return false;
    }

    if (!blnfncCheckStakeKernelHash (ibliCurrentBlock, nBits, nBlockFromTime,
            amount, txin.prevout, nTime, hashProofOfStake, targetProofOfStake, LogAcceptCategory(BCLog::POS, BCLog::Level::Debug))) {
        LogPrintf("WARNING: %s: Check kernel failed on coinstake %s, hashProof=%s\n", __func__, tx.GetHash().ToString(), hashProofOfStake.ToString());
        return false;
    }

    // All validation checks passed - this is a valid stake
    return true;
}



/* Calculate the difficulty for a given block index.
 * Duplicated from rpc/blockchain.cpp for linking
 */
static double GetDifficulty(const CBlockIndex* blockindex)
{
    CHECK_NONFATAL(blockindex);

    int nShift = (blockindex->nBits >> 24) & 0xff;
    double dDiff = (double)0x0000ffff / (double)(blockindex->nBits & 0x00ffffff);

    while (nShift < 29) {
        dDiff *= 256.0;
        nShift++;
    }
    while (nShift > 29) {
        dDiff /= 256.0;
        nShift--;
    }

    return dDiff;
}

double GetPoSKernelPS(CBlockIndex* pindex)
{
    LOCK(cs_main);

    CBlockIndex* pindexPrevStake = nullptr;

    int nBestHeight = pindex->nHeight;

    int nPoSInterval = 72; // blocks sampled
    double dStakeKernelsTriedAvg = 0;
    int nStakesHandled = 0, nStakesTime = 0;

    while (pindex && nStakesHandled < nPoSInterval) {
        if (pindex->IsProofOfStake()) {
            if (pindexPrevStake) {
                dStakeKernelsTriedAvg += GetDifficulty(pindexPrevStake) * 4294967296.0;
                nStakesTime += pindexPrevStake->nTime - pindex->nTime;
                nStakesHandled++;
            }
            pindexPrevStake = pindex;
        }
        pindex = pindex->pprev;
    }

    double result = 0;

    if (nStakesTime) {
        result = dStakeKernelsTriedAvg / nStakesTime;
    }

    result *= nStakeTimestampMask + 1;

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
    if (!pindexPrev)
        return uint256(); // genesis block's modifier is 0

    CDataStream ss(SER_GETHASH, 0);
    ss << kernel << pindexPrev->nStakeModifier;
    return Hash(ss);
}

/**
 * BlackCoin Proof-of-Stake Kernel Validation
 * 
 * This implements the core validation logic for BlackCoin's proof-of-stake protocol.
 * In proof-of-stake, instead of solving computational puzzles (like in Bitcoin),
 * participants can create new blocks proportional to the coins they hold.
 *
 * The protocol uses this formula to validate stake attempts:
 *     hash(nStakeModifier + txPrev.block.nTime + txPrev.nTime + 
 *          txPrev.vout.hash + txPrev.vout.n + nTime) < bnTarget * nWeight
 *
 * Security measures in the hash calculation:
 * 1. nStakeModifier: A changing value that prevents future stake calculations
 *                    This stops attackers from pre-computing future stakes
 *
 * 2. Transaction times: Multiple timestamps are included to prevent manipulation
 *    - txPrev.block.nTime: Previous block time (obsolete since v3)
 *    - txPrev.nTime: Transaction time adds randomization
 *    - nTime: Current time ensures freshness
 *
 * 3. Transaction details: Unique transaction identifiers reduce collisions
 *    - txPrev.vout.hash: Previous transaction hash
 *    - txPrev.vout.n: Output index in previous transaction
 *
 * Design Note: Block and transaction hashes are intentionally not used since they
 * can be generated rapidly, which would effectively turn this back into a 
 * proof-of-work system.
 */

bool CheckStakeKernelHash(
    const CBlockIndex* pindexPrev,     // Previous block in the chain. Contains stake modifier and timing data
    uint32_t nBits,                    // Current difficulty target in compact form. Controls how hard it is to find valid stakes
    uint32_t nBlockFromTime,           // Timestamp of the previous block. Used for basic time ordering checks
    CAmount prevOutAmount,             // Number of coins being staked. Affects probability of successful stake
    const COutPoint& prevout,          // Reference to previous transaction output. Contains both transaction hash and index
    uint32_t nTime,                    // Current block timestamp. Must be after previous block time
    uint256& hashProofOfStake,         // Output: The calculated stake hash. Must be below target to be valid
    uint256& targetProofOfStake,       // Output: Weighted target threshold. Adjusted by stake amount
    bool fPrintProofOfStake)           // Enable detailed debug logging
{
    const Consensus::Params& params = Params().GetConsensus();

    // 1. Basic timestamp validation
    if (nTime < nBlockFromTime) {
        // Ensure current time is after previous block time
        return error("%s: nTime violation", __func__);
    }

    // 2. Calculate target difficulty
    arith_uint256 bnTarget;
    bool fNegative;
    bool fOverflow;

    // Convert compact bits representation to full 256-bit target
    bnTarget.SetCompact(nBits, &fNegative, &fOverflow);
    if (fNegative || fOverflow || bnTarget == 0) {
        // Ensure target is valid (positive, not overflowed, non-zero)
        return error("%s: SetCompact failed.", __func__);
    }

    // 3. Weight target by stake amount
    int64_t nValueIn = prevOutAmount;
    if (pindexPrev->nHeight + 1 >= params.weightDampenerHeight &&
        nValueIn >= params.weightDampener) {
        nValueIn = params.weightDampener;
    }

    arith_uint256 bnWeight = arith_uint256(nValueIn);
    // The target is multiplied by the stake weight (coin amount)
    // This implements the core proof-of-stake principle:
    // - Larger stakes = larger target = higher chance of successful stake
    // - Probability is directly proportional to stake size
    bnTarget *= bnWeight;

    // Store weighted target for output
    targetProofOfStake = ArithToUint256(bnTarget);

    // 4. Get stake modifier from previous block
    const uint256& nStakeModifier = pindexPrev->nStakeModifier;
    int nStakeModifierHeight = pindexPrev->nHeight;
    int64_t nStakeModifierTime = pindexPrev->nTime;

    // 5. Build data stream for hash calculation
    CDataStream ss(SER_GETHASH, 0);
    // Combine inputs to create a unique, unpredictable stake hash
    // Order matters! This matches the protocol specification:
    ss << nStakeModifier;              // Changes each block - prevents precomputation
    ss << nBlockFromTime               // Previous block time - time ordering
       << prevout.hash                 // Unique transaction ID - prevents duplicates
       << prevout.n                    // Output index - adds uniqueness
       << nTime;                       // Current time - ensures freshness
    // Final hash must be below weighted target to be valid
    hashProofOfStake = Hash(ss);

    // 6. Debug logging if enabled
    if (fPrintProofOfStake) {
        // Log stake modifier details and hash computation inputs
        LogPrintf("%s: using modifier=%s at height=%d timestamp=%s\n",
            __func__, nStakeModifier.ToString(), nStakeModifierHeight,
            FormatISO8601DateTime(nStakeModifierTime));
        LogPrintf("%s: check modifier=%s nTimeKernel=%u nPrevout=%u nTime=%u hashProof=%s\n",
            __func__, nStakeModifier.ToString(),
            nBlockFromTime, prevout.n, nTime,
            hashProofOfStake.ToString());
    }

    // 7. Final proof-of-stake validation
    // Convert hash to integer and compare against weighted target
    // This check implements the core staking formula:
    // hash < target * weight
    // The larger your stake (weight), the larger the target,
    // making it more likely for a hash to be valid
    if (UintToArith256(hashProofOfStake) > bnTarget) {
        LogPrint (BCLog::POS, "Hash exceeds target - stake attempt invalid \n");
        return false;  // Hash exceeds target - stake attempt invalid
    }

    // 8. Additional debug logging
    if (LogAcceptCategory(BCLog::POS, BCLog::Level::Debug) && !fPrintProofOfStake) {
        // Log successful validation details
        LogPrintf("%s: using modifier=%s at height=%d timestamp=%s\n",
            __func__, nStakeModifier.ToString(), nStakeModifierHeight,
            FormatISO8601DateTime(nStakeModifierTime));
        LogPrintf("%s: pass modifier=%s nTimeKernel=%u nPrevout=%u nTime=%u hashProof=%s\n",
            __func__, nStakeModifier.ToString(),
            nBlockFromTime, prevout.n, nTime,
            hashProofOfStake.ToString());
    }

    return true; // All validation checks passed
}

/**
 * This function performs the core validation of a proof-of-stake 
 * attempt. Here's what's happening at a high level:
 * 
 * 1) Basic Validation: Ensures we're actually dealing with a staking transaction.
 * 2) Input Verification: Checks that the coin being staked exists and isn't already spent.
 * 3) Maturity Check: Verifies the coin is old enough to be used for staking. This prevents
 *    newly received coins from being immediately used for staking.
 * 4) Ownership Verification: Validates that the staker actually owns the coins through
 *    cryptographic signatures.
 * 5) Stake Hash Check: The core proof-of-stake verification, ensuring the stake hash meets
 *    the required difficulty target, weighted by the amount being staked.
 *
 * The function acts as a gatekeeper, ensuring all proof-of-stake rules are followed before
 * allowing a new block to be created.
 */
bool CheckProofOfStake(
    Chainstate& chain_state,          // Current blockchain state
    BlockValidationState& state,      // Tracks validation status/errors
    const CBlockIndex* pindexPrev,    // Previous block index (current chain tip)
    const CTransaction& tx,           // Transaction being validated
    int64_t nTime,                    // Timestamp of the new block being validated
    unsigned int nBits,               // Target difficulty for the block
    uint256& hashProofOfStake,        // Output parameter: Will contain the computed stake hash
    uint256& targetProofOfStake)      // Output parameter: Will contain the target threshold
{
    // pindexPrev points to the latest block in our chain
    // nTime represents when the new block was created

    // Get access to the block database through the chain state
    auto& pblocktree { chain_state.m_blockman.m_block_tree_db };

    // Verify this is a valid staking transaction with at least one input
    if (!tx.IsCoinStake() || tx.vin.size() < 1) {
        LogPrintf("ERROR: %s: malformed-txn %s\n", __func__, tx.GetHash().ToString());
        return false;
    }

    // Reference to hold the previous transaction (though unused in this function)
    CTransactionRef txPrev;

    // Get the first input of the coinstake transaction
    // This input (known as the kernel) must meet the staking target
    // Kernel (input 0) must match the stake hash target per coin age (nBits)
    const CTxIn& txin = tx.vin[0];

    // Variables to store information about the staking coin
    uint32_t nBlockFromTime;    // Timestamp of block containing the staked coin
    int nDepth;                 // How many blocks deep is the staked coin
    CScript kernelPubKey;       // Public key script that controls the stake
    CAmount amount;             // Amount of coins being staked

    // Try to find the coin being staked in the UTXO (unspent transaction output) set
    Coin coin;
    if (!chain_state.CoinsTip().GetCoin(txin.prevout, coin) || coin.IsSpent()) {
        return false;  // Coin doesn't exist or was already spent
    }

    // Find the block that contains the coin being staked
    CBlockIndex* pindex = chain_state.m_chain[coin.nHeight];
    if (!pindex) {
        return false;  // Block not found in main chain
    }

    // Calculate the coin's age in blocks and verify it meets minimum age requirement
    nDepth = pindexPrev->nHeight - coin.nHeight;
    // Required depth is the lesser of COINBASE_MATURITY or half the chain height
    int nRequiredDepth = std::min((int)COINBASE_MATURITY, (int)(pindexPrev->nHeight / 2));
    if (nRequiredDepth > nDepth) {
        return false;  // Coin isn't mature enough to stake
    }

    // Store the staking coin's details for validation
    kernelPubKey = coin.out.scriptPubKey;      // Script controlling the coins
    amount = coin.out.nValue;                   // Amount being staked
    nBlockFromTime = pindex->GetBlockTime();    // When the coin's block was mined

    // Get the spending transaction's signature details
    const CScript& scriptSig = txin.scriptSig;
    const CScriptWitness* witness = &txin.scriptWitness;
    ScriptError serror = SCRIPT_ERR_OK;
    std::vector<uint8_t> vchAmount(8);

    // Verify the transaction signature is valid and the spender owns the coins
    if (!VerifyScript(scriptSig, kernelPubKey, witness, STANDARD_SCRIPT_VERIFY_FLAGS, TransactionSignatureChecker(&tx, 0, amount, MissingDataBehavior::FAIL), &serror)) {
        LogPrintf("ERROR: %s: verify-script-failed, txn %s, reason %s\n", __func__, tx.GetHash().ToString(), ScriptErrorString(serror));
        return false;
    }

    // Finally, verify the proof-of-stake kernel hash meets required target
    // This is the core staking check that proves the staker's right to create a block
    if (!CheckStakeKernelHash(pindexPrev, nBits, nBlockFromTime,
            amount, txin.prevout, nTime, hashProofOfStake, targetProofOfStake, LogAcceptCategory(BCLog::POS, BCLog::Level::Debug))) {
        LogPrintf("WARNING: %s: Check kernel failed on coinstake %s, hashProof=%s\n", __func__, tx.GetHash().ToString(), hashProofOfStake.ToString());
        return false;
    }

    // All validation checks passed - this is a valid stake
    return true;
}

// Check whether the coinstake timestamp meets protocol
bool CheckCoinStakeTimestamp(int64_t nTimeBlock)
{
    return (nTimeBlock & nStakeTimestampMask) == 0;
}

// Used only when staking, not during validation
bool CheckKernel(Chainstate& chain_state, const CBlockIndex* pindexPrev, unsigned int nBits, int64_t nTime, const COutPoint& prevout, int64_t* pBlockTime)
{
    uint256 hashProofOfStake, targetProofOfStake;

    Coin coin;
    {
        LOCK(::cs_main);
        if (!chain_state.CoinsTip().GetCoin(prevout, coin)) {
            return error("%s: prevout not found", __func__);
        }
    }
    if (coin.IsSpent()) {
        return error("%s: prevout is spent", __func__);
    }

    CBlockIndex* pindex = chain_state.m_chain[coin.nHeight];
    if (!pindex) {
        return false;
    }

    int nRequiredDepth = std::min((int)COINBASE_MATURITY, (int)(pindexPrev->nHeight / 2));
    int nDepth = pindexPrev->nHeight - coin.nHeight;

    if (nRequiredDepth > nDepth) {
        return false;
    }
    if (pBlockTime) {
        *pBlockTime = pindex->GetBlockTime();
    }

    CAmount amount = coin.out.nValue;
    return CheckStakeKernelHash(pindexPrev, nBits, *pBlockTime,
        amount, prevout, nTime, hashProofOfStake, targetProofOfStake);
}

bool AddToMapStakeSeen(const COutPoint& kernel, const uint256& blockHash)
{
    // Overwrites existing values

    std::pair<std::map<COutPoint, uint256>::iterator, bool> ret;
    ret = mapStakeSeen.insert(std::pair<COutPoint, uint256>(kernel, blockHash));
    if (ret.second == false) { // existing element
        ret.first->second = blockHash;
    } else {
        listStakeSeen.push_back(kernel);
    }

    return true;
};

bool CheckStakeUnused(const COutPoint& kernel)
{
    std::map<COutPoint, uint256>::const_iterator mi = mapStakeSeen.find(kernel);
    return (mi == mapStakeSeen.end());
}

bool CheckStakeUnique(const CBlock& block, bool fUpdate)
{
    LOCK(cs_main);

    uint256 blockHash = block.GetHash();
    const COutPoint& kernel = block.vtx[0]->vin[0].prevout;

    std::map<COutPoint, uint256>::const_iterator mi = mapStakeSeen.find(kernel);
    if (mi != mapStakeSeen.end()) {
        if (mi->second == blockHash) {
            return true;
        }
        return error("%s: Stake kernel for %s first seen on %s.", __func__, blockHash.ToString(), mi->second.ToString());
    }

    if (!fUpdate) {
        return true;
    }

    while (listStakeSeen.size() > 1024) {
        const COutPoint& oldest = listStakeSeen.front();
        if (1 != mapStakeSeen.erase(oldest)) {
            LogPrintf("%s: Warning: mapStakeSeen did not erase %s %n\n", __func__, oldest.hash.ToString(), oldest.n);
        }
        listStakeSeen.pop_front();
    }

    return AddToMapStakeSeen(kernel, blockHash);
};
