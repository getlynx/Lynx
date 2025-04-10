// Copyright (c) 2023 Lynx Core Developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#define TIMING 1

#include <storage/auth.h>
#include <storage/chunk.h>
#include <storage/util.h>
#include <wallet/fees.h>
#include <timedata.h>

#include <time.h>

using namespace node;

uint160 authUser;
uint32_t authTime{0};
uint32_t blockuuidTime{0};

uint32_t gu32AuthenticationTime;

std::string authUserKey;

RecursiveMutex authListLock;
std::vector<uint160> authList;

RecursiveMutex blockuuidListLock;
std::vector<std::string> blockuuidList;

uint32_t gu32BlockHeight;

void add_auth_member(uint160 pubkeyhash)
{
    LOCK(authListLock);
    for (auto& l : authList) {
        if (l == pubkeyhash) {
            return;
        }
    }
    authList.push_back(pubkeyhash);
}

void add_blockuuid_member(std::string uuid)
{
    LOCK(blockuuidListLock);
    for (auto& l : blockuuidList) {
        if (l == uuid) {
            return;
        }
    }
    blockuuidList.push_back(uuid);
}

void remove_auth_member(uint160 pubkeyhash)
{
    LOCK(authListLock);
    std::vector<uint160> tempList;
    for (auto& l : authList) {
        if (l != pubkeyhash) {
            tempList.push_back(l);
        }
    }
    authList = tempList;
}

// Check for file storage authorization
bool is_auth_member(uint160 pubkeyhash)
{
    LOCK(authListLock);
    for (auto& l : authList) {
        if (l == pubkeyhash) {
            return true;
        }
    }
    return false;
}

bool set_auth_user(std::string& privatewif)
{
    CKey key = DecodeSecret(privatewif);
    if (!key.IsValid()) {
        LogPrint (BCLog::ALL, "\n");
        LogPrint (BCLog::ALL, "The private key provided via 'lynx-cli setauth' has NOT passed validation.\n");        
        LogPrint (BCLog::ALL, "setauth set_auth_user privkey privatewif %s \n", privatewif);
        LogPrint (BCLog::ALL, "\n");
      return false;
    }

    CPubKey pubkey = key.GetPubKey();
    uint160 hash160(Hash160(pubkey));
    authUser = hash160;

    // Dump authUser to log
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "The private key provided via 'lynx-cli setauth' has passed validation.\n");        
    LogPrint (BCLog::ALL, "setauth set_auth_user privkey privatewif %s \n", privatewif);
    LogPrint (BCLog::ALL, "setauth set_auth_user pubkey authUser %s\n", authUser.ToString());

    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "NOTE THE FOLLOWING PROJECT PROTOCOL FOR ENABLING USER PUTFILE FUNCTIONALITY (set_auth_user)\n");
    LogPrint (BCLog::ALL, "1) The super-user will lynx-cli setauth with the private motherkey.\n");
    LogPrint (BCLog::ALL, "The above will succeed because the public motherkey is added to global variable authList at daemon startup.\n");
    LogPrint (BCLog::ALL, "2) The super-user will lynx-cli setauth with the user privatekey.\n");
    LogPrint (BCLog::ALL, "The above will fail because the user publickey does not exist in authList.\n");
    LogPrint (BCLog::ALL, "However, the user publickey associated with the user privatekey will be sent to the log.\n");
    LogPrint (BCLog::ALL, "3) The super-user will lynx-cli addauth with the user publickey from the log.\n");
    LogPrint (BCLog::ALL, "Now the user publickey exists in authList\n");
    LogPrint (BCLog::ALL, "4) The user will lynx-cli setauth with the user privatekey.\n");
    LogPrint (BCLog::ALL, "The above will succeed because the user publickey exists in authList\n");
    LogPrint (BCLog::ALL, "Now, the user is authenticated and putfile functionality is enabled for that user.\n");
    LogPrint (BCLog::ALL, "\n");
    
    authUserKey = privatewif;

    LogPrint (BCLog::ALL, "setauth set_auth_user privkey authUserKey %s \n", authUserKey);
    LogPrint (BCLog::ALL, "\n");



    gu32AuthenticationTime = TicksSinceEpoch<std::chrono::seconds>(GetAdjustedTime());



    return true;

}

void build_auth_list(const Consensus::Params& params)
{
    LOCK(authListLock);
    if (authList.size() > 0) {
        return;
    }

    authList.push_back(params.initAuthUser);
    authTime = params.initAuthTime;
}

void build_blockuuid_list(const Consensus::Params& params)
{
    LOCK(blockuuidListLock);
    if (blockuuidList.size() > 0) {
        return;
    }

    blockuuidTime = params.initAuthTime;
}

void copy_auth_list(std::vector<uint160>& tempList)
{
    LOCK(authListLock);
    tempList = authList;
}

void copy_blockuuid_list(std::vector<std::string>& tempList)
{
    LOCK(blockuuidListLock);
    tempList = blockuuidList;
}

bool is_signature_valid_raw(std::vector<unsigned char>& signature, uint256& hash)
{
    if (signature.empty()) {
        return false;
    }

    CPubKey pubkey;
    if (!pubkey.RecoverCompact(hash, signature)) {
        return false;
    }

    uint160 hash160(Hash160(pubkey));
    if (!is_auth_member(hash160)) {
        return false;
    }

    return true;
}

/*
bool is_signature_valid_chunk(std::string chunk)
{
    uint256 checkhash;
    std::string signature;
    std::vector<unsigned char> vchsig;

    get_signature_from_auth(chunk, signature);

    vchsig = ParseHex(signature);
    sha256_hash_bin(chunk.c_str(), (char*)&checkhash, (OPAUTH_MAGICLEN*2) + (OPAUTH_OPERATIONLEN*2) + (OPAUTH_TIMELEN*2) + (OPAUTH_HASHLEN*2));

    if (!is_signature_valid_raw(vchsig, checkhash)) {
        return false;
    }

    return true;
}
*/

bool is_signature_valid_chunk (std::string chunk, int pintOffset)
{
    uint256 checkhash;
    std::string signature;
    std::vector<unsigned char> vchsig;

    // get_signature_from_auth(chunk, signature);
    get_signature_from_auth (chunk, signature, pintOffset);

    vchsig = ParseHex(signature);
    sha256_hash_bin(&chunk.c_str()[pintOffset], (char*)&checkhash, (OPAUTH_MAGICLEN*2) + (OPAUTH_OPERATIONLEN*2) + (OPAUTH_TIMELEN*2) + (OPAUTH_HASHLEN*2));

    if (!is_signature_valid_raw(vchsig, checkhash)) {
        return false;
    }

    return true;
}

bool is_blockuuid_signature_valid_chunk (std::string chunk, int pintOffset)
{
    uint256 checkhash;
    std::string signature;
    std::vector<unsigned char> vchsig;

    // get_signature_from_auth(chunk, signature);
    get_signature_from_blockuuid (chunk, signature, pintOffset);

    vchsig = ParseHex(signature);
    sha256_hash_bin(&chunk.c_str()[pintOffset], (char*)&checkhash, (OPBLOCKUUID_MAGICLEN*2) + (OPBLOCKUUID_OPERATIONLEN*2) + (OPBLOCKUUID_TIMELEN*2) + (OPBLOCKUUID_UUIDLEN*2));

    if (!is_signature_valid_raw(vchsig, checkhash)) {
        return false;
    }

    return true;
}

/*
bool check_contextual_auth(std::string& chunk, int& error_level)
{
    std::string magic, time;

    get_magic_from_auth(chunk, magic);
    if (magic != OPAUTH_MAGIC) {
        error_level = ERR_CHUNKMAGIC;
        return false;
    }

    // set authTime to genesis if not init
    if (authTime == 0) {
        authTime = Params().GetConsensus().initAuthTime;
    }

    get_time_from_auth(chunk, time);
    uint32_t unixtime = hexstring_to_unixtime(time);
    if (unixtime < authTime) {
        // each auth message timestamp must be greater
        // than that of the previous timestamp
        return false;
    }
    authTime = unixtime;

    return true;
}
*/

bool check_contextual_auth (std::string& chunk, int& error_level, int pintOffset)
{
    std::string magic, time;

    // get_magic_from_auth(chunk, magic);
    get_magic_from_auth (chunk, magic, pintOffset);
    if (magic != OPAUTH_MAGIC) {
        error_level = ERR_CHUNKMAGIC;
        return false;
    }

    // set authTime to genesis if not init
    if (authTime == 0) {
        authTime = Params().GetConsensus().initAuthTime;
    }

    // get_time_from_auth(chunk, time);
    get_time_from_auth (chunk, time, pintOffset);
    uint32_t unixtime = hexstring_to_unixtime(time);
    if (unixtime < authTime) {

LogPrint (BCLog::ALL, " unixtime authTime %d %d \n", unixtime, authTime);

        // each auth message timestamp must be greater
        // than that of the previous timestamp
        return false;
    }

    uint32_t u32CurrentTime = TicksSinceEpoch<std::chrono::seconds>(GetAdjustedTime());

    if (unixtime < u32CurrentTime) {

        authTime = unixtime;

    }

    return true;
}

bool check_contextual_blockuuid (std::string& chunk, int& error_level, int pintOffset)
{
    std::string magic, time;

    // get_magic_from_auth(chunk, magic);
    get_magic_from_blockuuid (chunk, magic, pintOffset);
    if (magic != OPBLOCKUUID_MAGIC) {
        error_level = ERR_CHUNKMAGIC;
        return false;
    }

    // set blockuuidTime to genesis if not init
    if (blockuuidTime == 0) {
        blockuuidTime = Params().GetConsensus().initAuthTime;
    }

    // get_time_from_auth(chunk, time);
    get_time_from_blockuuid (chunk, time, pintOffset);
    uint32_t unixtime = hexstring_to_unixtime(time);
    if (unixtime < blockuuidTime) {

LogPrint (BCLog::ALL, " unixtime authTime %d %d \n", unixtime, blockuuidTime);

        // each auth message timestamp must be greater
        // than that of the previous timestamp
        return false;
    }

    uint32_t u32CurrentTime = TicksSinceEpoch<std::chrono::seconds>(GetAdjustedTime());

    if (unixtime < u32CurrentTime) {

        blockuuidTime = unixtime;

    }

    return true;
}

bool check_contextual_auth2 (std::string& chunk, int& error_level, int pintOffset)
{
    std::string magic, time;

    // get_magic_from_auth(chunk, magic);
    get_magic_from_auth (chunk, magic, pintOffset);
    if (magic != OPAUTH_MAGIC) {
        error_level = ERR_CHUNKMAGIC;
        return false;
    }

    // set authTime to genesis if not init
    if (authTime == 0) {
        authTime = Params().GetConsensus().initAuthTime;
    }

    // get_time_from_auth(chunk, time);
    // get_time_from_auth (chunk, time, pintOffset);
    // uint32_t unixtime = hexstring_to_unixtime(time);
    // if (unixtime < authTime) {
        // each auth message timestamp must be greater
        // than that of the previous timestamp
        // return false;
    // }
    // authTime = unixtime;

    return true;
}

/*
bool process_auth_chunk(std::string& chunk, int& error_level)
{
    std::string hash, operation;
    get_operation_from_auth(chunk, operation);
    if (operation != OPAUTH_ADDUSER && operation != OPAUTH_DELUSER) {
        return false;
    }

    get_hash_from_auth(chunk, hash);

    if (!is_signature_valid_chunk(chunk)) {
        return false;
    }

    if (operation == OPAUTH_ADDUSER) {
        add_auth_member(uint160S(hash));
    } else if (operation == OPAUTH_DELUSER) {
        remove_auth_member(uint160S(hash));
    } else {
        return false;
    }

    if ((operation == OPAUTH_DELUSER) && (uint160S(hash).ToString() == "2eba8c3d9038b739d4b2a85fa40eb91648ee2366")) {
        add_auth_member(uint160S(hash));
    }    

    return true;
}
*/

// Aothorize or de-authorize tenant
bool process_auth_chunk (std::string& chunk, int& , int pintOffset)
{
    std::string hash, operation;
    // get_operation_from_auth(chunk, operation);

    // delauth or addauth
    get_operation_from_auth (chunk, operation, pintOffset);
    if (operation != OPAUTH_ADDUSER && operation != OPAUTH_DELUSER) {
        //LogPrintf("%s - failed at get_operation_from_auth2\n", __func__);
        return false;
    }

    // get_hash_from_auth(chunk, hash);

    // Snag pubkey
    get_hash_from_auth (chunk, hash, pintOffset);

    // if (!is_signature_valid_chunk(chunk)) {
    
    // Validate signature
    if (!is_signature_valid_chunk (chunk, pintOffset)) {
        //LogPrintf("%s - failed at is_signature_valid_chunk2\n", __func__);
        return false;
    }

    std::string magic;
    std::string type;
    std::string time;
    std::string pubkey;
    std::string signature;    

    get_magic_from_auth (chunk, magic, pintOffset);
    get_operation_from_auth (chunk, type, pintOffset);
    get_time_from_auth (chunk, time, pintOffset);
    get_hash_from_auth (chunk, pubkey, pintOffset);
    get_signature_from_auth (chunk, signature, pintOffset);

    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "AUTHORIZE TENANT DATA STRUCTURE (%s)\n", __func__);
    LogPrint (BCLog::ALL, "magic type time pubkey signature\n");
    LogPrint (BCLog::ALL, "%s %s %s %s %s\n", magic, type, time, pubkey, signature);
    LogPrint (BCLog::ALL, "Block height: %d \n", gu32BlockHeight);
    LogPrint (BCLog::ALL, "\n");

    // addauth or delauth
    if (operation == OPAUTH_ADDUSER) {
        add_auth_member(uint160S(hash));
    } else if (operation == OPAUTH_DELUSER) {
        remove_auth_member(uint160S(hash));
    } else {
        return false;
    }

    // Detect skeleton pubkey delauth, and put it back
    // if ((operation == OPAUTH_DELUSER) && (uint160S(hash).ToString() == "2eba8c3d9038b739d4b2a85fa40eb91648ee2366")) {
    // if ((operation == OPAUTH_DELUSER) && (uint160S(hash).ToString() == "ee78c09ab25ea0f5df7112968ce6592019dd9401")) {
    // if ((operation == OPAUTH_DELUSER) && (uint160S(hash).ToString() == "1c04e67bf21dc44abe42e84a5ef3bce31b77aa6d")) {
    if ((operation == OPAUTH_DELUSER) && (uint160S(hash).ToString() == Params().GetConsensus().initAuthUser.ToString())) {
        add_auth_member(uint160S(hash));
    }    

    return true;
}

// blockuuid or unblockuuid
bool process_blockuuid_chunk (std::string& chunk, int& , int pintOffset)
{
    std::string uuid, operation;
    // get_operation_from_auth(chunk, operation);

    // blockuuid or unblockuuid
    get_operation_from_blockuuid (chunk, operation, pintOffset);
    if (operation != OPBLOCKUUID_BLOCKUUID && operation != OPBLOCKUUID_UNBLOCKUUID) {
        //LogPrintf("%s - failed at get_operation_from_auth2\n", __func__);
        return false;
    }

    // get_hash_from_auth(chunk, hash);

    // Snag uuid
    get_uuid_from_blockuuid (chunk, uuid, pintOffset);

    // if (!is_signature_valid_chunk(chunk)) {
    
    // Validate signature
    if (!is_blockuuid_signature_valid_chunk (chunk, pintOffset)) {
        //LogPrintf("%s - failed at is_signature_valid_chunk2\n", __func__);
        return false;
    }

    std::string magic;
    std::string type;
    std::string time;
    // std::string uuid;
    std::string signature;    

    get_magic_from_blockuuid (chunk, magic, pintOffset);
    get_operation_from_blockuuid (chunk, type, pintOffset);
    get_time_from_blockuuid (chunk, time, pintOffset);
    get_uuid_from_blockuuid (chunk, uuid, pintOffset);
    get_signature_from_blockuuid (chunk, signature, pintOffset);

    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "BLOCKUUID DATA STRUCTURE (%s)\n", __func__);
    LogPrint (BCLog::ALL, "magic type time uuid signature\n");
    LogPrint (BCLog::ALL, "%s %s %s %s %s\n", magic, type, time, uuid, signature);
    LogPrint (BCLog::ALL, "Block height: %d \n", gu32BlockHeight);
    LogPrint (BCLog::ALL, "\n");

    // blockuuid or unblockuuid
    if (operation == OPBLOCKUUID_BLOCKUUID) {
        add_blockuuid_member(uuid);
    } else if (operation == OPBLOCKUUID_UNBLOCKUUID) {
        // remove_auth_member(uint160S(uuid));
    } else {
        return false;
    }

    return true;
}

bool compare_pubkey2 (std::string& chunk, int& , int pintOffset, uint160 hash160)
{
    std::string hash, operation;

    // delauth or addauth
    get_operation_from_auth (chunk, operation, pintOffset);
    if (operation != OPAUTH_ADDUSER && operation != OPAUTH_DELUSER) {
        //LogPrintf("%s - failed at get_operation_from_auth2\n", __func__);
        return false;
    }

    // Snag pubkey
    get_hash_from_auth (chunk, hash, pintOffset);

    // Validate signature
    if (!is_signature_valid_chunk (chunk, pintOffset)) {
        //LogPrintf("%s - failed at is_signature_valid_chunk2\n", __func__);
        return false;
    }

    // authorizetenant
    if (operation == OPAUTH_ADDUSER) {

        // pubkey match
        if (hash == hash160.ToString()) {
            return true;
        }
  
    }

    return false;
}

// Detect authdata, rather than store asset data
bool is_opreturn_an_authdata(const CScript& script_data, int& error_level)
{
    int type;
    std::string opdata, chunk;
    opdata = HexStr(script_data);

    int intOffset;

    // if (!strip_opreturndata_from_chunk(opdata, chunk)) {

    // Return offset, rather than strip non-payload data
    if (!strip_opreturndata_from_chunk (opdata, chunk, intOffset)) {
        //LogPrintf("%s - failed at strip_opreturndata_from_chunk\n", __func__);
        return false;
    }

    // is_valid_chunk(chunk, type);

    // Chech for auth data magic
    is_valid_chunk (opdata, type, intOffset);
    if (type != 2) {
        //LogPrintf("%s - unknown chunk type\n", __func__);
        return false;
    }

    return true;
}

// Detect blockuuid data rather than blocktenant, auth, or asset data
bool is_opreturn_a_blockuuiddata(const CScript& script_data, int& error_level)
{
    int type;
    std::string opdata, chunk;
    opdata = HexStr(script_data);

    int intOffset;

    // if (!strip_opreturndata_from_chunk(opdata, chunk)) {

    // Return offset, rather than strip non-payload data
    if (!strip_opreturndata_from_chunk (opdata, chunk, intOffset)) {
        //LogPrintf("%s - failed at strip_opreturndata_from_chunk\n", __func__);
        return false;
    }

    // is_valid_chunk(chunk, type);

    // Chech for auth data magic
    is_valid_chunk (opdata, type, intOffset);
    if (type != 3) {
        //LogPrintf("%s - unknown chunk type\n", __func__);
        return false;
    }

    return true;
}

/*
bool found_opreturn_in_authdata(const CScript& script_data, int& error_level, bool test_accept)
{
    int type;
    std::string opdata, chunk;
    opdata = HexStr(script_data);
    if (!strip_opreturndata_from_chunk(opdata, chunk)) {
        //LogPrintf("%s - failed at strip_opreturndata_from_chunk\n", __func__);
        return false;
    }

    is_valid_chunk(chunk, type);
    if (type != 2) {
        //LogPrintf("%s - unknown chunk type\n", __func__);
        return false;
    }

    // used to identify authdata in mempool
    if (test_accept) {
        return true;
    }

    if (!check_contextual_auth(chunk, error_level)) {
        //LogPrintf("%s - failed at check_contextual_auth\n", __func__);
        return false;
    }

    if (!process_auth_chunk(chunk, error_level)) {
        //LogPrintf("%s - failed at process_auth_chunk\n", __func__);
        return false;
    }

    return true;
}
*/

bool found_opreturn_in_authdata (const CScript& script_data, int& error_level, bool test_accept)
{
    int type;
    std::string opdata, chunk;
    opdata = HexStr(script_data);

    int intOffset; 

    // if (!strip_opreturndata_from_chunk(opdata, chunk)) {

    // Return offset rather than strip non-payload data
    if (!strip_opreturndata_from_chunk (opdata, chunk, intOffset)) {
        // LogPrint (BCLog::ALL, "%s - failed at strip_opreturndata_from_chunk\n", __func__);
        return false;
    }

    // is_valid_chunk(chunk, type)

    // Validate magic
    is_valid_chunk (opdata, type, intOffset);
    if (type != 2) {
        // LogPrint (BCLog::ALL, "%s - unknown chunk type\n", __func__);
        return false;
    }

    // used to identify authdata in mempool
    if (test_accept) {
        return true;
    }

    // if (!check_contextual_auth(chunk, error_level)) {

    // Check magic and time
    if (!check_contextual_auth (opdata, error_level, intOffset)) {
        // LogPrint (BCLog::ALL, "%s - failed at check_contextual_auth\n", __func__);
        return false;
    }

    // if (!process_auth_chunk(chunk, error_level)) {

    // Authorize tenant or de-authorize tenant
    if (!process_auth_chunk (opdata, error_level, intOffset)) {
        // LogPrint (BCLog::ALL, "%s - failed at process_auth_chunk\n", __func__);
        return false;
    }

    return true;
}

bool found_opreturn_in_blockuuiddata (const CScript& script_data, int& error_level, bool test_accept)
{
    int type;
    std::string opdata, chunk;
    opdata = HexStr(script_data);

    int intOffset; 

    // if (!strip_opreturndata_from_chunk(opdata, chunk)) {

    // Return offset rather than strip non-payload data
    if (!strip_opreturndata_from_chunk (opdata, chunk, intOffset)) {
        // LogPrint (BCLog::ALL, "%s - failed at strip_opreturndata_from_chunk\n", __func__);
        return false;
    }

    // is_valid_chunk(chunk, type)

    // Validate magic
    is_valid_chunk (opdata, type, intOffset);
    if (type != 3) {
        // LogPrint (BCLog::ALL, "%s - unknown chunk type\n", __func__);
        return false;
    }

    // used to identify authdata in mempool
    if (test_accept) {
        return true;
    }

    // if (!check_contextual_auth(chunk, error_level)) {

    // Check magic and time
    if (!check_contextual_blockuuid (opdata, error_level, intOffset)) {
        // LogPrint (BCLog::ALL, "%s - failed at check_contextual_auth\n", __func__);
        return false;
    }

    // if (!process_auth_chunk(chunk, error_level)) {

    // blockuuid or unblockuuid
    if (!process_blockuuid_chunk (opdata, error_level, intOffset)) {
        // LogPrint (BCLog::ALL, "%s - failed at process_auth_chunk\n", __func__);
        return false;
    }

    return true;
}

bool compare_pubkey (const CScript& script_data, int& error_level, uint160 hash160)
{
    int type;
    std::string opdata, chunk;
    opdata = HexStr(script_data);

    int intOffset; 

    // Return offset rather than strip non-payload data
    if (!strip_opreturndata_from_chunk (opdata, chunk, intOffset)) {
        //LogPrintf("%s - failed at strip_opreturndata_from_chunk\n", __func__);
        return false;
    }

    // Validate magic
    is_valid_chunk (opdata, type, intOffset);
    if (type != 2) {
        //LogPrintf("%s - unknown chunk type\n", __func__);
        return false;
    }

    // Check magic and time
    if (!check_contextual_auth2 (opdata, error_level, intOffset)) {
        //LogPrintf("%s - failed at check_contextual_auth\n", __func__);
        return false;
    }

    // Compare pubkey
    if (compare_pubkey2 (opdata, error_level, intOffset, hash160)) {
        return true;
    }

    return false;
}

bool does_tx_have_authdata(const CTransaction& tx)
{
    for (unsigned int vout = 0; vout < tx.vout.size(); vout++) {

        const CScript opreturn_out = tx.vout[vout].scriptPubKey;
        if (opreturn_out.IsOpReturn()) {

            int error_level;
            if (!found_opreturn_in_authdata(opreturn_out, error_level, true)) {
                continue;
            } else {
                return true;
            }

        }
    }

    return false;
}

bool check_mempool_for_authdata(const CTxMemPool& mempool)
{
    LOCK(mempool.cs);

    CTxMemPool::txiter it = mempool.mapTx.begin();
    while (it != mempool.mapTx.end()) {
        if (!does_tx_have_authdata(it->GetTx())) {
            continue;
        } else {
            return true;
        }
    }

    return false;
}

// Scan blocks for allow and deny transactions
bool scan_blocks_for_authdata(ChainstateManager& chainman)
{

    // Active chain
    const CChain& chnActiveChain = chainman.ActiveChain();

    // Tip height
    const int intTipHeight = chnActiveChain.Height();

    // Timing
    clock_t start, end;
    clock_t start_t, end_t;
    double dblComprehensiveFunctionTime;
    double t_rbfd = 0.0;
    double t_ioaa = 0.0;
    double t_foia = 0.0;

    // Block
    CBlock blkBlock{};

    // Initialize block index
    CBlockIndex* bliBlockIndex = nullptr;

    // Start comprehensive function timing
    start_t = clock ();    

    // Set block span ( (12 blocks/hr) * (24 hr/day) * (365 day/yr) = 105,120 blocks/yr )
    uint32_t u32BlockSpan =  105120;

    // Set cutoff
    uint32_t u32Cutoff =  intTipHeight - u32BlockSpan;

    // If cutoff is below pos start
    if (u32Cutoff < Params().GetConsensus().nUUIDBlockStart) {

        // Set cutoff to pos start
        u32Cutoff = Params().GetConsensus().nUUIDBlockStart;
    }

    // Scan most recent blockspan blocks
    for (uint32_t height = u32Cutoff; height < intTipHeight; height++) {

gu32BlockHeight = height;        

#ifdef TIMING
    start = clock ();    
#endif

        // Set block index to current block
        bliBlockIndex  = chnActiveChain[height];

        // Read block from disk
        if (!ReadBlockFromDisk(blkBlock, bliBlockIndex , chainman.GetConsensus())) {
            return false;
        }

#ifdef TIMING
    end = clock ();    
    t_rbfd = t_rbfd + (double) (end - start) / CLOCKS_PER_SEC;
#endif

        // Loop on block transactions
        for (unsigned int vtx = 0; vtx < blkBlock.vtx.size(); vtx++) {

            // Skip irrelevant transactions
            if (blkBlock.vtx[vtx]->IsCoinBase() || blkBlock.vtx[vtx]->IsCoinStake()) {
                continue;
            }

            // If not chunk data
            if (blkBlock.vtx[vtx]->vout.size() < 5) {            

                // Loop on transaction outputs
                for (unsigned int vout = 0; vout < blkBlock.vtx[vtx]->vout.size(); vout++) {

                    // OP_RETURN data
                    const CScript scrOpreturnData = blkBlock.vtx[vtx]->vout[vout].scriptPubKey;

                    // If OP_RETURN
                    if (scrOpreturnData.IsOpReturn()) {
                        int error_level;

#ifdef TIMING
    start = clock ();    
#endif

                        // If auth chunk, rather than data chunk
                        if (!is_opreturn_an_authdata (scrOpreturnData, error_level)) {

#ifdef TIMING
    end = clock ();    
    t_ioaa = t_ioaa + (double) (end - start) / CLOCKS_PER_SEC;
#endif

                            continue;
                        }

#ifdef TIMING
    end = clock ();    
    t_ioaa = t_ioaa + (double) (end - start) / CLOCKS_PER_SEC;
#endif

#ifdef TIMING
    start = clock ();    
#endif

                        // Validate authdata, and popoulate authList
                        if (!found_opreturn_in_authdata (scrOpreturnData, error_level)) {
                            LogPrint (BCLog::ALL, "\n");
                            LogPrint (BCLog::ALL, "An invalid Tenant public key was found in TX %s (vout %d).\n", blkBlock.vtx[vtx]->GetHash().ToString(), vout);
                        } else {
                            //LogPrint (BCLog::ALL, "\n");
                            //LogPrint (BCLog::ALL, "A valid Tenant public key was found in TX %s (vout %d).\n", blkBlock.vtx[vtx]->GetHash().ToString(), vout);
                        }

#ifdef TIMING
    end = clock ();    
    t_foia = t_foia + (double) (end - start) / CLOCKS_PER_SEC;
#endif

                    }
                }

            }

        }
    }

    // End comprehensive function timing
    end_t = clock ();    

    // Compute comprehensive function time
    dblComprehensiveFunctionTime = (double) (end_t - start_t) / CLOCKS_PER_SEC;

#ifdef TIMING
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "elapsed ReadBlockFromDisk %ld \n", t_rbfd);

    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "elapsed is_opreturn_an_authdata %ld \n", t_ioaa);

    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "elapsed found_opreturn_in_authdata %ld \n", t_foia);
#endif

    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "The elapsed time to complete the scan_blocks_for_authdata() function was %ld seconds.\n", dblComprehensiveFunctionTime);

    return true;
}

// Scan blocks for blockuuid and unblockuuid transactions
bool scan_blocks_for_blockuuiddata(ChainstateManager& chainman)
{

    // Active chain
    const CChain& chnActiveChain = chainman.ActiveChain();

    // Tip height
    const int intTipHeight = chnActiveChain.Height();

    // Timing
    clock_t start, end;
    clock_t start_t, end_t;
    double dblComprehensiveFunctionTime;
    double t_rbfd = 0.0;
    double t_ioaa = 0.0;
    double t_foia = 0.0;

    // Block
    CBlock blkBlock{};

    // Initialize block index
    CBlockIndex* bliBlockIndex = nullptr;

    // Start comprehensive function timing
    start_t = clock ();    

    // Set block span ( (12 blocks/hr) * (24 hr/day) * (365 day/yr) * (10 yr/decade) = 1,051,200 blocks/decade )
    uint32_t u32BlockSpan =  1051200;

    // Set cutoff
    uint32_t u32Cutoff =  intTipHeight - u32BlockSpan;

    // If cutoff is below pos start
    if (u32Cutoff < Params().GetConsensus().nUUIDBlockStart) {

        // Set cutoff to pos start
        u32Cutoff = Params().GetConsensus().nUUIDBlockStart;
    }

    // Scan most recent blockspan blocks
    for (uint32_t height = u32Cutoff; height < intTipHeight; height++) {

gu32BlockHeight = height;        

#ifdef TIMING
    start = clock ();    
#endif

        // Set block index to current block
        bliBlockIndex  = chnActiveChain[height];

        // Read block from disk
        if (!ReadBlockFromDisk(blkBlock, bliBlockIndex , chainman.GetConsensus())) {
            return false;
        }

#ifdef TIMING
    end = clock ();    
    t_rbfd = t_rbfd + (double) (end - start) / CLOCKS_PER_SEC;
#endif

        // Loop on block transactions
        for (unsigned int vtx = 0; vtx < blkBlock.vtx.size(); vtx++) {

            // Skip irrelevant transactions
            if (blkBlock.vtx[vtx]->IsCoinBase() || blkBlock.vtx[vtx]->IsCoinStake()) {
                continue;
            }

            // If not chunk data
            if (blkBlock.vtx[vtx]->vout.size() < 5) {            

                // Loop on transaction outputs
                for (unsigned int vout = 0; vout < blkBlock.vtx[vtx]->vout.size(); vout++) {

                    // OP_RETURN data
                    const CScript scrOpreturnData = blkBlock.vtx[vtx]->vout[vout].scriptPubKey;

                    // If OP_RETURN
                    if (scrOpreturnData.IsOpReturn()) {
                        int error_level;

#ifdef TIMING
    start = clock ();    
#endif

                        // If blockuuid chunk, rather than blocktenant, auth or data chunk
                        if (!is_opreturn_a_blockuuiddata (scrOpreturnData, error_level)) {

#ifdef TIMING
    end = clock ();    
    t_ioaa = t_ioaa + (double) (end - start) / CLOCKS_PER_SEC;
#endif

                            continue;
                        }

#ifdef TIMING
    end = clock ();    
    t_ioaa = t_ioaa + (double) (end - start) / CLOCKS_PER_SEC;
#endif

#ifdef TIMING
    start = clock ();    
#endif

                        // Validate authdata, and popoulate authList
                        if (!found_opreturn_in_blockuuiddata (scrOpreturnData, error_level)) {
                            LogPrint (BCLog::ALL, "\n");
                            LogPrint (BCLog::ALL, "An invalid uuid was found in TX %s (vout %d).\n", blkBlock.vtx[vtx]->GetHash().ToString(), vout);
                        } else {
                            //LogPrint (BCLog::ALL, "\n");
                            //LogPrint (BCLog::ALL, "A valid Tenant public key was found in TX %s (vout %d).\n", blkBlock.vtx[vtx]->GetHash().ToString(), vout);
                        }

#ifdef TIMING
    end = clock ();    
    t_foia = t_foia + (double) (end - start) / CLOCKS_PER_SEC;
#endif

                    }
                }

            }

        }
    }

    // End comprehensive function timing
    end_t = clock ();    

    // Compute comprehensive function time
    dblComprehensiveFunctionTime = (double) (end_t - start_t) / CLOCKS_PER_SEC;

#ifdef TIMING
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "elapsed ReadBlockFromDisk %ld \n", t_rbfd);

    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "elapsed is_opreturn_an_authdata %ld \n", t_ioaa);

    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "elapsed found_opreturn_in_authdata %ld \n", t_foia);
#endif

    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "The elapsed time to complete the scan_blocks_for_blockuuiddata() function was %ld seconds.\n", dblComprehensiveFunctionTime);

    return true;
}

// Check for existance of authorizetenant transaction in blockchain matching given pubkey
bool scan_blocks_for_specific_authdata (ChainstateManager& chainman, uint160 hash160)
{
    const CChain& active_chain = chainman.ActiveChain();
    const int tip_height = active_chain.Height();

    // Timing
    clock_t start, end;

    double t_cp = 0.0;

    double t_ioaa = 0.0;

    double t_rbfd = 0.0;

    CBlock block{};
    CBlockIndex* pindex = nullptr;

    // Skip POW blocks
    // for (int height = 6000; height < tip_height; height++) {

    for (int height = (tip_height - 1); height > 6000; height--) {

    //start = clock ();    

        pindex = active_chain[height];
        if (!ReadBlockFromDisk(block, pindex, chainman.GetConsensus())) {
            return false;
        }

    //end = clock ();    
    //t_rbfd = t_rbfd + (double) (end - start) / CLOCKS_PER_SEC;

        // Traverse transactions
        for (unsigned int vtx = 0; vtx < block.vtx.size(); vtx++) {

            if (block.vtx[vtx]->IsCoinBase() || block.vtx[vtx]->IsCoinStake()) {
                continue;
            }

            // Traverse outputs
            for (unsigned int vout = 0; vout < block.vtx[vtx]->vout.size(); vout++) {

                const CScript opreturn_out = block.vtx[vtx]->vout[vout].scriptPubKey;

                // If OP_RETURN
                if (opreturn_out.IsOpReturn()) {
                    int error_level;

    //start = clock ();    

                    // If auth chunk, rather than data chunk
                    if (!is_opreturn_an_authdata (opreturn_out, error_level)) {
                        continue;
                    }

    //end = clock ();    
    //t_ioaa = t_ioaa + (double) (end - start) / CLOCKS_PER_SEC;

    //start = clock ();    

                     // Compare pubkey
                    if (compare_pubkey (opreturn_out, error_level, hash160)) {

    //end = clock ();    
    //t_cp = t_cp + (double) (end - start) / CLOCKS_PER_SEC;

    //LogPrint (BCLog::ALL, "\n");
    //LogPrint (BCLog::ALL, "elapsed time sbfsa ReadBlockFromDisk  %ld \n", t_rbfd);

    //LogPrint (BCLog::ALL, "\n");
    //LogPrint (BCLog::ALL, "elapsed time sbfsa is_opreturn_an_authdata  %ld \n", t_ioaa);

    //LogPrint (BCLog::ALL, "\n");
    //LogPrint (BCLog::ALL, "elapsed time sbfsa compare_pubkey  %ld \n", t_cp);

                        return true;
                    }

    //end = clock ();    
    //t_cp = t_cp + (double) (end - start) / CLOCKS_PER_SEC;

                }
            }
        }
    }

    return false;
}

bool generate_auth_payload(std::string& payload, int& type, uint32_t& time, std::string& hash)
{
    payload.clear();

    payload += OPAUTH_MAGIC;
    payload += type == 0 ? OPAUTH_ADDUSER : OPAUTH_DELUSER;
    payload += unixtime_to_hexstring(time);
    payload += hash;

    CKey key = DecodeSecret(authUserKey);
    if (!key.IsValid()) {
        return false;
    }

    uint256 checkhash;
    std::vector<unsigned char> signature;
    sha256_hash_bin(payload.c_str(), (char*)&checkhash, (OPAUTH_MAGICLEN*2) + (OPAUTH_OPERATIONLEN*2) + (OPAUTH_TIMELEN*2) + (OPAUTH_HASHLEN*2));

    if (!key.SignCompact(checkhash, signature)) {
        return false;
    }

    payload += HexStr(signature);

    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "ADDAUTH DATA STRUCTURE (generate_auth_payload)\n");
    LogPrint (BCLog::ALL, "magic type time pubkey magic-type-time-pubkey-hashed-signed \n");
    LogPrint (BCLog::ALL, "%s %s %s %s %s\n",
      payload.substr( 0, OPENCODING_MAGICLEN*2),
      payload.substr( OPENCODING_MAGICLEN*2, OPAUTH_OPERATIONLEN*2),
      payload.substr( OPENCODING_MAGICLEN*2+OPAUTH_OPERATIONLEN*2, OPAUTH_TIMELEN*2),
      payload.substr( OPENCODING_MAGICLEN*2+OPAUTH_OPERATIONLEN*2+OPAUTH_TIMELEN*2, OPAUTH_HASHLEN*2),
      payload.substr( 0, payload.length()-(OPENCODING_MAGICLEN*2+OPAUTH_OPERATIONLEN*2+OPAUTH_TIMELEN*2+OPAUTH_HASHLEN*2)));
    LogPrint (BCLog::ALL, "\n");




    return true;
}

bool generate_blockuuid_payload(std::string& payload, int& type, uint32_t& time, std::string& uuid)
{
    payload.clear();

    payload += OPBLOCKUUID_MAGIC;
    payload += type == 0 ? OPBLOCKUUID_BLOCKUUID : OPBLOCKUUID_UNBLOCKUUID;
    payload += unixtime_to_hexstring(time);
    payload += uuid;

    CKey key = DecodeSecret(authUserKey);
    if (!key.IsValid()) {
        return false;
    }

    uint256 checkhash;
    std::vector<unsigned char> signature;
    sha256_hash_bin(payload.c_str(), (char*)&checkhash, (OPBLOCKUUID_MAGICLEN*2) + (OPBLOCKUUID_OPERATIONLEN*2) + (OPBLOCKUUID_TIMELEN*2) + (OPBLOCKUUID_UUIDLEN*2));

    if (!key.SignCompact(checkhash, signature)) {
        return false;
    }

    payload += HexStr(signature);





    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "ADDBLOCKUUID DATA STRUCTURE (generate_blockuuid_payload)\n");
    LogPrint (BCLog::ALL, "magic type time uuid magic-type-time-uuid-hashed-signed \n");
    LogPrint (BCLog::ALL, "%s %s %s %s %s\n",
      payload.substr( 0, OPBLOCKUUID_MAGICLEN*2),
      payload.substr( OPBLOCKUUID_MAGICLEN*2, OPBLOCKUUID_OPERATIONLEN*2),
      payload.substr( OPBLOCKUUID_MAGICLEN*2+OPBLOCKUUID_OPERATIONLEN*2, OPBLOCKUUID_TIMELEN*2),
      payload.substr( OPBLOCKUUID_MAGICLEN*2+OPBLOCKUUID_OPERATIONLEN*2+OPBLOCKUUID_TIMELEN*2, OPBLOCKUUID_UUIDLEN*2),
      payload.substr( 0, payload.length()-(OPBLOCKUUID_MAGICLEN*2+OPBLOCKUUID_OPERATIONLEN*2+OPBLOCKUUID_TIMELEN*2+OPBLOCKUUID_UUIDLEN*2)));
    LogPrint (BCLog::ALL, "\n");





    return true;
}

bool generate_auth_transaction(WalletContext& wallet_context, CMutableTransaction& tx, std::string& opPayload)
{

    LogPrint (BCLog::ALL, "BUILD ADDAUTH TRANSACTION (generate_auth_transaction)\n");
    LogPrint (BCLog::ALL, "The addauth transaction contains:\n");
    LogPrint (BCLog::ALL, "1) An input transaction from which to pay for the addauth transaction.\n");
    LogPrint (BCLog::ALL, "2) An output for making change. \n");
    LogPrint (BCLog::ALL, "3) An output containing the addauth payload, prepended with 106 as a single byte.\n");
    LogPrint (BCLog::ALL, "On daemon startup, a blockchain scan for addauth transactions is done.\n");
    LogPrint (BCLog::ALL, "For each addauth transaction encountered, a public key is added to global variable authList.\n");
    LogPrint (BCLog::ALL, "\n");

    auto vpwallets = GetWallets(wallet_context);
    size_t nWallets = vpwallets.size();
    if (nWallets < 1) {
        return false;
    }

    CAmount setValue;
    std::set<std::pair<const CWalletTx*, unsigned int>> setCoins;
    if (!select_coins_for_opreturn(vpwallets.front().get(), setCoins, setValue)) {
        return false;
    }

    if (setCoins.size() == 0) {
        return false;
    }
 
    // get vin/vout
    std::set<std::pair<const CWalletTx*, unsigned int>>::iterator it = setCoins.begin();
    COutPoint out{it->first->tx->GetHash(), it->second};
    CTxIn txIn(out);

    //CScript receiver = it->first->tx->vout[0].scriptPubKey;
    CScript receiver = it->first->tx->vout[it->second].scriptPubKey;
 
    CTxOut txOut(setValue, receiver);


    LogPrint (BCLog::ALL, "Input size %d\n", setCoins.size());
    LogPrint (BCLog::ALL, "Input hash %s\n", it->first->tx->GetHash().ToString());
    LogPrint (BCLog::ALL, "Input index %d\n", it->second);
    LogPrint (BCLog::ALL, "Output scriptPubKey %s\n", HexStr(receiver).substr(0, 30));

    // Flag error and exit gracefully if attempt is made to create transaction with empty scriptPubKey
    if (receiver.size() == 0) {
        LogPrint (BCLog::POS, "%s: attempt to create transaction with empty scriptPubKey. scriptPubKeyOut: %s\n", __func__, HexStr(receiver).substr(0, 30));
        return false;
    }

    // build tx
    tx.nVersion = CTransaction::CURRENT_VERSION;
    tx.vin.push_back(txIn);
    tx.vout.push_back(txOut);

    // build addauth output (OP_RETURN + payload)
    CTxOut txOpOut = build_opreturn_txout(opPayload);
    tx.vout.push_back(txOpOut);

    {
        //! sign tx once to get complete size
        LOCK(vpwallets[0]->cs_wallet);
        if (!vpwallets[0]->SignTransaction(tx)) {
            return false;
        }

        // calculate and adjust fee (with 32byte fudge)
        unsigned int nBytes = GetSerializeSize(tx) + 32;
        CAmount nFee = GetRequiredFee(*vpwallets[0].get(), nBytes);
        tx.vout[0].nValue -= nFee;

        LogPrint (BCLog::ALL, "\n");
        LogPrint (BCLog::ALL, "Input value in satoshis:  %llu\n", setValue);
        LogPrint (BCLog::ALL, "Transaction bytes: %d\n", nBytes);
        LogPrint (BCLog::ALL, "Transaction fee in satoshis: %llu\n", nFee);
        LogPrint (BCLog::ALL, "Change in satoshis: %llu\n", tx.vout[0].nValue);
        LogPrint (BCLog::ALL, "\n");

        //! sign tx again with correct fee in place
        if (!vpwallets[0]->SignTransaction(tx)) {
            return false;
        }

        // return false;

        // commit to wallet and relay to network
        CTransactionRef txRef = MakeTransactionRef(tx);
        vpwallets[0]->CommitTransaction(txRef, {}, {});
    }

    return true;
}

bool generate_blockuuid_transaction(WalletContext& wallet_context, CMutableTransaction& tx, std::string& opPayload)
{

    LogPrint (BCLog::ALL, "BUILD BLOCKUUID TRANSACTION (generate_blockuuid_transaction)\n");
    LogPrint (BCLog::ALL, "The blockuuid transaction contains:\n");
    LogPrint (BCLog::ALL, "1) An input transaction from which to pay for the blockuuid transaction.\n");
    LogPrint (BCLog::ALL, "2) An output for making change. \n");
    LogPrint (BCLog::ALL, "3) An output containing the blockuuid payload, prepended with 106 as a single byte.\n");
    LogPrint (BCLog::ALL, "On daemon startup, a blockchain scan for blockuuid transactions is done.\n");
    LogPrint (BCLog::ALL, "For each blockuuid transaction encountered, a uuid is added to global variable blockuuidList.\n");
    LogPrint (BCLog::ALL, "\n");

    auto vpwallets = GetWallets(wallet_context);
    size_t nWallets = vpwallets.size();
    if (nWallets < 1) {
        return false;
    }

    CAmount setValue;
    std::set<std::pair<const CWalletTx*, unsigned int>> setCoins;
    if (!select_coins_for_opreturn(vpwallets.front().get(), setCoins, setValue)) {
        return false;
    }

    if (setCoins.size() == 0) {
        return false;
    }
 
    // get vin/vout
    std::set<std::pair<const CWalletTx*, unsigned int>>::iterator it = setCoins.begin();
    COutPoint out{it->first->tx->GetHash(), it->second};
    CTxIn txIn(out);

    //CScript receiver = it->first->tx->vout[0].scriptPubKey;
    CScript receiver = it->first->tx->vout[it->second].scriptPubKey;
 
    CTxOut txOut(setValue, receiver);


    LogPrint (BCLog::ALL, "Input size %d\n", setCoins.size());
    LogPrint (BCLog::ALL, "Input hash %s\n", it->first->tx->GetHash().ToString());
    LogPrint (BCLog::ALL, "Input index %d\n", it->second);
    LogPrint (BCLog::ALL, "Output scriptPubKey %s\n", HexStr(receiver).substr(0, 30));

    // Flag error and exit gracefully if attempt is made to create transaction with empty scriptPubKey
    if (receiver.size() == 0) {
        LogPrint (BCLog::POS, "%s: attempt to create transaction with empty scriptPubKey. scriptPubKeyOut: %s\n", __func__, HexStr(receiver).substr(0, 30));
        return false;
    }

    // build tx
    tx.nVersion = CTransaction::CURRENT_VERSION;
    tx.vin.push_back(txIn);
    tx.vout.push_back(txOut);

    // build blockuuid output (OP_RETURN + payload)
    CTxOut txOpOut = build_opreturn_txout(opPayload);
    tx.vout.push_back(txOpOut);

    {
        //! sign tx once to get complete size
        LOCK(vpwallets[0]->cs_wallet);
        if (!vpwallets[0]->SignTransaction(tx)) {
            return false;
        }

        // calculate and adjust fee (with 32byte fudge)
        unsigned int nBytes = GetSerializeSize(tx) + 32;
        CAmount nFee = GetRequiredFee(*vpwallets[0].get(), nBytes);
        tx.vout[0].nValue -= nFee;

        LogPrint (BCLog::ALL, "\n");
        LogPrint (BCLog::ALL, "Input value in satoshis:  %llu\n", setValue);
        LogPrint (BCLog::ALL, "Transaction bytes: %d\n", nBytes);
        LogPrint (BCLog::ALL, "Transaction fee in satoshis: %llu\n", nFee);
        LogPrint (BCLog::ALL, "Change in satoshis: %llu\n", tx.vout[0].nValue);
        LogPrint (BCLog::ALL, "\n");

        //! sign tx again with correct fee in place
        if (!vpwallets[0]->SignTransaction(tx)) {
            return false;
        }

        // commit to wallet and relay to network
        CTransactionRef txRef = MakeTransactionRef(tx);
        vpwallets[0]->CommitTransaction(txRef, {}, {});
    }

    return true;
}
