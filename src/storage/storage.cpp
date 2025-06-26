// Copyright (c) 2023 Lynx Core Developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

// #define TIMING 1

#include <map>

#include <time.h>

#include "util.h"

#include <logging.h>
#include <key_io.h>
#include <opfile/src/chunk.h>
#include <opfile/src/decode.h>
#include <opfile/src/protocol.h>
#include <pos/minter.h>
#include <primitives/transaction.h>
#include <rpc/register.h>
#include <rpc/server.h>
#include <rpc/server_util.h>
#include <rpc/util.h>
#include <storage/util.h>
#include <sync.h>
#include <validation.h>
#include <storage/auth.h>

#include <wallet/rpc/util.h>
#include <wallet/rpc/wallet.h>

#include <wallet/coinselection.h>
#include <wallet/context.h>
#include <wallet/fees.h>
#include <wallet/receive.h>
#include <wallet/spend.h>
#include <wallet/transaction.h>
#include <wallet/wallet.h>
#include <storage/chunk.h>

#include <vector>

using namespace node;
using namespace wallet;

// Authenticatetenant pubkey at storeasset time 
uint160 ghshAuthenticatetenantPubkey;

// Currently authenticated user
extern uint160 authUser;

// Asset filelength
std::map<std::string, int> gmapFileLength;

// Asset blockheight 
std::map<std::string, int> gmapBlockHeight;

// Asset timestamp (seconds since 1970)
std::map<std::string, int> gmapTimeStamp;

// Asset extension
std::map<std::string, std::string> gmapExtension;

// Asset encrypted status
std::map<std::string, std::string> gmapEncrypted;

// Fetch asset encrypted status
// int gintFetchAssetEncyptedStatus;

extern int gintFetchAssetFullProtocol;

// Tenwant
std::map<std::string, std::string> gmapTenant;





// Extract pubkey, protocol
bool scan_blocks_for_pubkey (ChainstateManager& chainman, std::string& uuid)
{

    clock_t start, end;

    double t_hs = 0.0;
    double t_rbfd = 0.0;
    double t_sofc = 0.0;
    double t_ccc = 0.0;
    double t_iva = 0.0;
    double t_gctfc = 0.0;
    double t_gcnfc = 0.0;
    double t_gufc = 0.0;
    double t_gclfc = 0.0;

    int error_level;

    bool hasauth;
    const CChain& active_chain = chainman.ActiveChain();
    const int tip_height = active_chain.Height();

    hasauth = false;

    int chunktotal2 = 0;

    int offset;

    int count = 0;

    CBlock block{};
    CBlockIndex* pindex = nullptr;

    std::string magic;
    std::string strProtocol;
    std::string uuid2;
    std::string signature;
    std::string chunklen;

    int intAllDataChunksFound = 0;

    int intAuthenticateTenantPubkeyFound = 0;

    std::string strAuthenticatetenantPubkeyCandidate;
                        
    // long lngCutoff = Params().GetConsensus().nUUIDBlockStart;

    long lngCutoff = 3107495;

    // In reverse, skip POW blocks
    for (int height = (tip_height - 1); height > lngCutoff; height--) {

        pindex = active_chain[height];

#ifdef TIMING
    start = clock ();    
#endif

        if (!ReadBlockFromDisk(block, pindex, chainman.GetConsensus())) {
            return false;
        }

#ifdef TIMING
    end = clock ();    
    t_rbfd = t_rbfd + (double) (end - start) / CLOCKS_PER_SEC;
#endif
    
        // Traverse transactions
        for (unsigned int vtx = 0; vtx < block.vtx.size(); vtx++) {
    
            if (block.vtx[vtx]->IsCoinBase() || block.vtx[vtx]->IsCoinStake()) {
                continue;
            }
    
            // Traverse outputs
            for (unsigned int vout = 0; vout < block.vtx[vtx]->vout.size(); vout++) {
    
                // If OP_RETURN
                if (block.vtx[vtx]->vout[vout].scriptPubKey.IsOpReturn()) {
    
                    std::string opdata, chunk, this_uuid;
    
#ifdef TIMING
    start = clock ();    
#endif
    
                    opdata = HexStr(block.vtx[vtx]->vout[vout].scriptPubKey);
    
#ifdef TIMING
    end = clock ();    
    t_hs = t_hs + (double) (end - start) / CLOCKS_PER_SEC;
#endif
    
#ifdef TIMING
    start = clock ();    
#endif
    
                    // Return offset, rather then strip OP_RETURN + metadata
                    if (!strip_opreturndata_from_chunk (opdata, chunk, offset)) {
                        // LogPrintf ("%s - failed at strip_opreturndata_from_chunk\n", __func__);
                        continue;
                    }    

#ifdef TIMING
    end = clock ();    
    t_sofc = t_sofc + (double) (end - start) / CLOCKS_PER_SEC;
#endif
                        
                    int protocol;
                                            
#ifdef TIMING
    start = clock ();    
#endif
                        
                    // Check for chunk data, check for valid protocal, return protocol
                    if (!check_chunk_contextual (opdata, protocol, error_level, offset)) {
                        // LogPrintf ("%s - failed at check_chunk_contextual. error_level %d\n", __func__, error_level);
                        continue;
                    }

#ifdef TIMING
    end = clock ();    
    t_ccc = t_ccc + (double) (end - start) / CLOCKS_PER_SEC;
#endif
                        
#ifdef TIMING
    start = clock ();    
#endif
                        
                    // Extract UUID
                    get_uuid_from_chunk (opdata, this_uuid, offset);
                        
#ifdef TIMING
     end = clock ();    
    t_gufc = t_gufc + (double) (end - start) / CLOCKS_PER_SEC;
#endif
                        
                    // If chunk UUID equals fetchasset UUID
                    if (uuid == this_uuid) {
                        int chunklen2;

#ifdef TIMING
    start = clock ();    
#endif
                                                
                        get_chunklen_from_chunk (opdata, chunklen, offset);
                                                
                        chunklen2 = std::stoul(chunklen, nullptr, 16);
                                                
#ifdef TIMING
    end = clock ();    
    t_gclfc = t_gclfc + (double) (end - start) / CLOCKS_PER_SEC;
#endif
                                                
                        if (chunklen2 == 0) {
                                                
#ifdef TIMING
    start = clock ();    
#endif
                                                
                            if (!is_valid_authchunk (opdata, error_level, offset)) {
                                                
                                LogPrint (BCLog::ALL, "error_level from is_valid_authchunk %d\n", error_level);
                                continue;
                            }
                                                
#ifdef TIMING
    end = clock ();    
    t_iva = t_iva + (double) (end - start) / CLOCKS_PER_SEC;
#endif

                            get_magic_from_chunk (opdata, magic, offset);
                            get_version_from_chunk (opdata, strProtocol, offset);
                            get_uuid_from_chunk (opdata, uuid2, offset);
                            get_chunklen_from_chunk (opdata, chunklen, offset);
                            get_signature_from_chunk (opdata, signature, offset);
                    
                            /*
                            LogPrint (BCLog::ALL, "Found valid header chunk for UUID: %s\n", this_uuid);
                            LogPrint (BCLog::ALL, "\n");
                            LogPrint (BCLog::ALL, "Header Chunk Magic: %s\n", magic);
                            LogPrint (BCLog::ALL, "Header Chunk Protocol: %s\n", strProtocol);
                            LogPrint (BCLog::ALL, "Header Chunk UUID: %s\n", uuid2);
                            LogPrint (BCLog::ALL, "Header Chunk Length: %s\n", chunklen);
                            LogPrint (BCLog::ALL, "Header Chunk Signature: %s\n", signature);
                            LogPrint (BCLog::ALL, "\n");
                            */
                    
                            hasauth = true;

                            // Set full protocol
                            gintFetchAssetFullProtocol = protocol;
                    
                            // Extract authenticated tenant at storeasset time from header chunk (ghshAuthenticatetenantPubkey)
                            extract_pubkey_from_signature (opdata, offset); 
                    
                            // if (is_auth_member(ghshAuthenticatetenantPubkey)) {
                    
                            //     intAuthenticateTenantPubkeyFound = 1;
                    
                            if (intAllDataChunksFound == 1) {
                    
                                height = lngCutoff;
                    
                            }
                    
                            // }
                    
                                                
                            continue;
                        } else {
                            count++;
                        }
                    
#ifdef TIMING
    start = clock ();    
#endif
                    
                        std::string chunktotal;
                        get_chunktotal_from_chunk (opdata, chunktotal, offset);
                        chunktotal2 = std::stoul(chunktotal, nullptr, 16);

//                     chunks.resize(chunktotal2);

#ifdef TIMING
    end = clock ();    
    t_gctfc = t_gctfc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

#ifdef TIMING
    start = clock ();    
#endif

                        int chunknum2;
                        std::string chunknum;
                        get_chunknum_from_chunk (opdata, chunknum, offset);
                        chunknum2 = std::stoul(chunknum, nullptr, 16);

                        if (count == chunktotal2) {

                            intAllDataChunksFound = 1;

                            if (hasauth) {

                                height = lngCutoff;

                            }
    
                        }

                    // put chunk in correct position
//                     chunks[chunknum2-1] = opdata;

#ifdef TIMING
    end = clock ();    
    t_gcnfc = t_gcnfc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

                    }
                }
            }
        }
    }

    // If header chunk not found
    if (!hasauth) {
        LogPrintf("Header chunk not found for uuid %s\n", uuid);
        //error_level = ERR_CHUNKAUTHNONE;
        return false;
    }

    // If not all data chunks
    if (count != chunktotal2) {
        LogPrint (BCLog::ALL, "Not all data chunks found for uuid %s\n", uuid);
        // error_level = ERR_NOTALLDATACHUNKS;
        return false;
    }

    // If authenticatetenant pubkey not found
    // if (intAuthenticateTenantPubkeyFound == 0) {
        // LogPrint (BCLog::ALL, "authenticatetenant pubkey not found for uuid %s\n", uuid);
        // error_level = ERR_CHUNKAUTHUNK;
        // return false;
    // }


#ifdef TIMING
    LogPrint (BCLog::ALL, "%d data chunks found.\n", chunktotal2);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time ReadBlockFromDisk %ld \n", t_rbfd);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time HexStr %ld \n", t_hs);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time strip_opreturn_from_chunk %ld \n", t_sofc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time check_chunk_contextual %ld \n", t_ccc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time get_chunklen_from_chunk %ld \n", t_gclfc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time get_uuid_from_chunk %ld \n", t_gufc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time is_valid_authchunk %ld \n", t_iva);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time get_chunktotal_from_chunk %ld \n", t_gctfc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time get_chunknumber_from_chunk %ld \n", t_gcnfc);
    LogPrint (BCLog::ALL, "\n");
#endif

    return true;
}

                                                                                            



// Scan blockchain for unique uuids
bool scan_blocks_for_uuids(ChainstateManager& chainman, std::vector<std::string>& pvctUUIDs, int pintCount) {

    // Current chunklength
    std::string strChunkLength;

    int intChunkLength;

    // Total number of asset chunks
    std::string strChunkTotal;

    int intChunkTotal;

    // Current chunknumber
    std::string strChunkNumber;

    // 0 - authenticated user is manager, 1 - authenticated user is tenant
    int intIsTenant = 0;

    // OP_RETURN output
    std::string strOpreturnOutput;

    // Unused
    std::string chunk;

    // Current asset uuid
    std::string strUUID;

    // If authenticatedc user is not manager
    if (authUser.ToString() != Params().GetConsensus().initAuthUser.ToString()) {

        // Set is tenant
        intIsTenant = 1;

    // End if authenticated user is not manager
    }

    // If masquerading as manager, asking for all uuids
    if (pintCount == -1) {

        // Unset is tenant 
        intIsTenant = 0;

        // Set count to all
        pintCount = 0;

    }

    // Total number of unique uuids found so far
    int intUUIDCount = 0;

    // Empty vector of uuids
    pvctUUIDs.clear();

    // Active blockchain
    const CChain& active_chain = chainman.ActiveChain();

    // Get tipheight
    const int tip_height = active_chain.Height();

    // Current block
    CBlock block{};

    // Initialize index
    CBlockIndex* pindex = nullptr;

    // Set cutoff
    // long lngCutoff = Params().GetConsensus().nUUIDBlockStart;

    // Set cutoff to beginning of optional encryption
    long lngCutoff = 3107495;

    // Skip POW blocks in reverse
    for (int height = (tip_height - 1); height > lngCutoff; height--) {
    
        // Convert block number to index
        pindex = active_chain[height];

        // Get block
        if (!ReadBlockFromDisk(block, pindex, chainman.GetConsensus())) {
            return false;
        }

        // Traverse transactions
        for (unsigned int vtx = 0; vtx < block.vtx.size(); vtx++) {

            // Skip irrelevant transactions
            if (block.vtx[vtx]->IsCoinBase() || block.vtx[vtx]->IsCoinStake()) {
                continue;
            }

            // Traverse outputs
            for (unsigned int vout = 0; vout < block.vtx[vtx]->vout.size(); vout++) {

                // If OP_RETURN
                if (block.vtx[vtx]->vout[vout].scriptPubKey.IsOpReturn()) {

                    // Convert OP_RETURN output to hex string
                    strOpreturnOutput = HexStr(block.vtx[vtx]->vout[vout].scriptPubKey);

                    // Offset to payload
                    int intOffset;

                    // Return offset, rather then strip OP_RETURN + metadata
                    if (!strip_opreturndata_from_chunk (strOpreturnOutput, chunk, intOffset)) {

                        continue;
                    }

                    // Error
                    int intError;

                    // 0 - no extension, 1 - extension
                    int intExtension;

                    // Check for chunk data, valid extension flag
                    if (!check_chunk_contextual (strOpreturnOutput, intExtension, intError, intOffset)) {

                        //LogPrintf("%s - failed at check_chunk_contextual\n", __func__);
                        continue;
                    }

                    // Get uuid
                    get_uuid_from_chunk (strOpreturnOutput, strUUID, intOffset);

                    // Get chunklength
                    get_chunklen_from_chunk (strOpreturnOutput, strChunkLength, intOffset);

                    // Convert to integer
                    intChunkLength = std::stoul(strChunkLength, nullptr, 16);

                    // WAhen the header proccessing is complete for entire blockchain, pvctUUIDs will contain 
                    // the number asked for of uuids associated with authenticated user.

                    // If header chunk
                    if (intChunkLength == 0) {

                        // Extract authenticated tenant at storeasset time from header chunk (ghshAuthenticatetenantPubkey)
                        extract_pubkey_from_signature (strOpreturnOutput, intOffset); 

                        // If authenticated user is manager
                        if (intIsTenant == 0) {

                            // If not all uuids asked for
                           if (pintCount > 0) {

                                // If less uuids found than asked for
                                if (intUUIDCount < pintCount) {

                                    gmapTenant[strUUID] = ghshAuthenticatetenantPubkey.ToString();

                                    // Add blockheight to global map for processing later
                                    // Key on uuid
                                    gmapBlockHeight[strUUID] = height;

                                    // Add seconds since epoch (first second in 1970) to global map for processing later
                                    // Key on uuid
                                    gmapTimeStamp[strUUID] = block.nTime;

                                    // Add uuid to vector of uuids
                                    pvctUUIDs.push_back(strUUID);

                                    // Increment number of uuids found
                                    intUUIDCount = intUUIDCount + 1;

                                    // Record uuid to log
                                    LogPrint (BCLog::ALL, "UUID %s\n", strUUID);

                                // End if less uuids found than asked for
                                }

                            // Else not not all uuids asked for (all asked for)
                            } else {

                                gmapTenant[strUUID] = ghshAuthenticatetenantPubkey.ToString();

                                // Add blockheight to global map for processing later
                                // Key on uuid
                                gmapBlockHeight[strUUID] = height;

                                // Add seconds since epoch (first second in 1970) to global map for processing later
                                // Key on uuid
                                gmapTimeStamp[strUUID] = block.nTime;

                                // Add uuid to vector of uuids
                                pvctUUIDs.push_back(strUUID);

                                // Increment number of uuids found
                                intUUIDCount = intUUIDCount + 1;

                                // Record uuid to log
                                LogPrint (BCLog::ALL, "UUID %s\n", strUUID);

                            // End if not all uuids asked for
                            }

                        // Else not authenticated user is manager
                        } else {

                            // If currently authenticated tenant is authenticated tenant at storeasset time
                            if (authUser.ToString() == ghshAuthenticatetenantPubkey.ToString()) {
  
                                // If not all uuids asked for
                                if (pintCount > 0) {

                                    // If less uuids found than asked for
                                    if (intUUIDCount < pintCount) {

                                        gmapTenant[strUUID] = ghshAuthenticatetenantPubkey.ToString();

                                        // Add blockheight to global map for processing later
                                        // Key on uuid
                                        gmapBlockHeight[strUUID] = height;

                                        // Add seconds since epoch (first second in 1970) to global map for processing later
                                        // Key on uuid
                                        gmapTimeStamp[strUUID] = block.nTime;

                                        // Add uuid to vector of uuids
                                        pvctUUIDs.push_back(strUUID);

                                        // Increment number of uuids found
                                        intUUIDCount = intUUIDCount + 1;

                                        // Record uuid to log
                                        LogPrint (BCLog::ALL, "UUID %s\n", strUUID);

                                    // End if less uuids found than asked for 
                                    }

                                // Else not not all uuids asked for (all asked for)
                                } else {

                                    gmapTenant[strUUID] = ghshAuthenticatetenantPubkey.ToString();

                                    // Add blockheight to global map for processing later
                                    // Key on uuid
                                    gmapBlockHeight[strUUID] = height;

                                    // Add seconds since epoch (first second in 1970) to global map for processing later
                                    // Key on uuid
                                    gmapTimeStamp[strUUID] = block.nTime;

                                    // Add uuid to vector of uuids
                                    pvctUUIDs.push_back(strUUID);

                                    // Increment number of uuids found
                                    intUUIDCount = intUUIDCount + 1;

                                    // Record uuid to log
                                    LogPrint (BCLog::ALL, "UUID %s\n", strUUID);

                                // End if not all uuids asked for 
                                }

                            // End if currently authenticated tenant is authenticated tenant at storeasset time
                            }

                        // End if authenticated user is manager
                        }

                    // Else not header chunk
                    } else {

                        // When following final chunk filelength processing is complete for entire blockchain, 
                        // gmapFileLength will contain the filelength of every asset in blockchain.  Later, 
                        // calling routine will use pvctUUIDs to select filelengths from gmapFileLength, the 
                        // number of assets asked for, associated with currently authenticated tenent.

                        // The processing rolls this way because only the header chunk contains the 
                        // authenticated tenant at storeasset time, therefore the header chunk is where 
                        // we constrain the uuids returned to the uuids associated with the 
                        // currently authenticated user.  The final data chunk is where the filelength 
                        // lives (indirectly), and there is no guarantee about where in the blockchain the 
                        // header chunk is in relation to the final data chunk for a given asset. 

                        // Get current data chunk number
                        get_chunknum_from_chunk (strOpreturnOutput, strChunkNumber, intOffset);

                        // Get total number of data chunks
                        get_chunktotal_from_chunk (strOpreturnOutput, strChunkTotal, intOffset);

                        // If final data chunk
                        if (strChunkNumber == strChunkTotal) {





                            // Initialize extension to no extension
                            std::string strExtension = "n/a";

                            // LogPrint (BCLog::ALL, "intExtension intChunkLength %d %d \n", intExtension, intChunkLength);

                            // Chunk data
                            std::string strChunkData;

                            // Get chunk data
                            get_chunkdata_from_chunk (strOpreturnOutput, strChunkData, intChunkLength, intOffset);

                            // LogPrint (BCLog::ALL, "strChunkData %s %d \n", strChunkData, strChunkData.size());

                            // Buffer
                            unsigned char buffer[OPENCODING_CHUNKMAX*2];

                            // Convert chunk data from hex
                            binlify_from_hex(&buffer[0], strChunkData.c_str(), strChunkData.size());

                            // LogPrint (BCLog::ALL, "buffer %s \n", buffer);

                            // If extension
                            if ((intExtension == 1) || (intExtension == 3)) {

                                // Extension
                                std::string extension;

                                // Extension offset
                                int extoffset = (strChunkData.size() / 2) - 4;

                                // Snatch extension
                                for (int extwrite = extoffset; extwrite < extoffset + OPENCODING_EXTENSION; extwrite++) {
                                    extension += buffer[extwrite];
                                }

                                // LogPrint (BCLog::ALL, "extension %s \n", extension);

                                // Convert '\x00' to '\0' in 4th extension position, if present
                                if (extension[3] == '\x00') {

                                    // LogPrint (BCLog::ALL, "true \n");

                                    strExtension = extension.substr(0,3);;

                                    extension[3] = '\0';

                                } else {

				                    strExtension = extension;

                                }

                            }

                            // LogPrint (BCLog::ALL, "extension %s \n", strExtension);

                            // Record extension for caller
                            gmapExtension[strUUID] = strExtension;

                            if ((intExtension == 2) || (intExtension == 3)) {
                                gmapEncrypted[strUUID] = "yes";
                            } else {
                                gmapEncrypted[strUUID] = "no";
                            }





                            // Convert total number of chunks to integer
                            intChunkTotal = std::stoul(strChunkTotal, nullptr, 16);

                            // Filelength is (totalchunks - 1) * 512 + finalchunklength
                            int intFileLengthInBytes = (intChunkTotal - 1) * 512 + intChunkLength;

                            if ((intExtension == 1) || (intExtension == 3)) {
                                intFileLengthInBytes = intFileLengthInBytes - 4;
                            }

                            // Record filelength in global map for processing in calling routine
                            gmapFileLength[strUUID] = intFileLengthInBytes;

                            // If all uuids asked for found
                            if ((intUUIDCount == pintCount) && (intUUIDCount > 0)) {

                                // End scan
                                height = lngCutoff;

                            // End if all uuids asked for found
                            }

                        // End if final data chunk
                        }

                    // End if header chunk
                    }

                    // Unused
                    if (std::find(pvctUUIDs.begin(), pvctUUIDs.end(), strUUID) != pvctUUIDs.end()) {
                        continue;
                    } else {
                    }

                // End if OP_RETURN    
                }

            // End traverse outputs
            }

        // End traverse transactions 
        }

    // End Skip POW blocks in reverse
    }

    return true;

// End Scan blockchain for unique uuids
}

// Extract asset
bool scan_blocks_for_specific_uuid (ChainstateManager& icsmChainStateManager, std::string& istrUUID, int& error_level, std::vector<std::string>& ovctChunks, int& ointOffset)
{

    // Timing
    clock_t start, end;

    double t_hs = 0.0;
    double t_rbfd = 0.0;
    double t_sofc = 0.0;
    double t_ccc = 0.0;
    double t_iva = 0.0;
    double t_gctfc = 0.0;
    double t_gcnfc = 0.0;
    double t_gufc = 0.0;
    double t_gclfc = 0.0;

    // Header chunk found
    bool blnHeaderChunkFound;

    // Emmpty vector of chunks
    ovctChunks.clear();

    // Get active chain
    const CChain& chnActiveChain = icsmChainStateManager.ActiveChain();

    // Set tip height 
    const int intTipHeight = chnActiveChain.Height();

    // Initialize to header chunk not found
    blnHeaderChunkFound = false;

    // Total asset chunks
    int intTotalChunks = 0;

    // Offset
    int intOffset;

    // Initialize chunk count to no chunks found
    int intChunkCount = 0;

    // Block
    CBlock blkBlock{};

    // Initialize block index to no block index
    CBlockIndex* bliBlockIndex = nullptr;

    // Header chunk info
    std::string strMagic;
    std::string strProtocol;
    std::string strHeaderUUID;
    std::string strSignature;
    std::string strChunkLength;

    // Initialize to all data chunks not found
    int intAllDataChunksFound = 0;

    // Initialize to authenticated tenant public key not found
    // int intAuthenticateTenantPubkeyFound = 0;

    // Authenticated tenant public key candidate
    // std::string strAuthenticatetenantPubkeyCandidate;
       
    // pos start block
    // long lngCutoff = Params().GetConsensus().nUUIDBlockStart;

    // Start of optional encryption functionality
    long lngCutoff = 3107495;

    // In reverse, skip POW blocks
    for (int height = (intTipHeight - 1); height > lngCutoff; height--) {

        // Get current block index
        bliBlockIndex = chnActiveChain[height];

#ifdef TIMING
    start = clock ();    
#endif

        // Read block from disk
        if (!ReadBlockFromDisk(blkBlock, bliBlockIndex, icsmChainStateManager.GetConsensus())) {
            return false;
        }

#ifdef TIMING
    end = clock ();    
    t_rbfd = t_rbfd + (double) (end - start) / CLOCKS_PER_SEC;
#endif

        // Traverse transactions
        for (unsigned int intTransaction = 0; intTransaction < blkBlock.vtx.size(); intTransaction++) {

            // Skip irrelevant transactions
            if (blkBlock.vtx[intTransaction]->IsCoinBase() || blkBlock.vtx[intTransaction]->IsCoinStake()) {
                continue;
            }

            // Traverse outputs
            for (unsigned int intOutput = 0; intOutput < blkBlock.vtx[intTransaction]->vout.size(); intOutput++) {

                // If OP_RETURN
                if (blkBlock.vtx[intTransaction]->vout[intOutput].scriptPubKey.IsOpReturn()) {

                    // OP_RETURN data
                    std::string strOpreturnData;

                    // Unused
                    std::string chunk;
     
                    // Current uuid
                    std::string strCurrentUUID;

#ifdef TIMING
    start = clock ();    
#endif

                    // Get OP_RETURN data
                    strOpreturnData = HexStr(blkBlock.vtx[intTransaction]->vout[intOutput].scriptPubKey);

#ifdef TIMING
    end = clock ();    
    t_hs = t_hs + (double) (end - start) / CLOCKS_PER_SEC;
#endif

#ifdef TIMING
    start = clock ();    
#endif

                    // Return offset, rather then strip OP_RETURN + metadata
                    if (!strip_opreturndata_from_chunk (strOpreturnData, chunk, intOffset)) {
                        // LogPrintf ("%s - failed at strip_opreturndata_from_chunk\n", __func__);
                        continue;
                    }    

#ifdef TIMING
    end = clock ();    
    t_sofc = t_sofc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

                    // Protocol
                    int intProtocol;
                    
#ifdef TIMING
    start = clock ();    
#endif

                    // Check for chunk data, check for valid protocal, return protocol
                    if (!check_chunk_contextual (strOpreturnData, intProtocol, error_level, intOffset)) {
                        // LogPrintf ("%s - failed at check_chunk_contextual. error_level %d\n", __func__, error_level);
                        continue;
                    }

#ifdef TIMING
    end = clock ();    
    t_ccc = t_ccc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

#ifdef TIMING
    start = clock ();    
#endif

                    // Extract UUID
                    get_uuid_from_chunk (strOpreturnData, strCurrentUUID, intOffset);

#ifdef TIMING
    end = clock ();    
    t_gufc = t_gufc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

                    // If chunk UUID equals fetch UUID
                    if (istrUUID == strCurrentUUID) {

                        // Chunk length
                        int intChunkLength;

#ifdef TIMING
    start = clock ();    
#endif

                        // Get chunk length 
                        get_chunklen_from_chunk (strOpreturnData, strChunkLength, intOffset);

                        // Convert to integer
                        intChunkLength = std::stoul(strChunkLength, nullptr, 16);

#ifdef TIMING
    end = clock ();    
    t_gclfc = t_gclfc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

                        // If header chunk
                        if (intChunkLength == 0) {

#ifdef TIMING
    start = clock ();    
#endif

                            // Validate header chunk
                            if (!is_valid_authchunk (strOpreturnData, error_level, intOffset)) {

                                LogPrint (BCLog::ALL, "error_level from is_valid_authchunk %d\n", error_level);
                                continue;
                            }

#ifdef TIMING
    end = clock ();    
    t_iva = t_iva + (double) (end - start) / CLOCKS_PER_SEC;
#endif

                            // Get header chunk data
                            get_magic_from_chunk (strOpreturnData, strMagic, intOffset);
                            get_version_from_chunk (strOpreturnData, strProtocol, intOffset);
                            get_uuid_from_chunk (strOpreturnData, strHeaderUUID, intOffset);
                            get_chunklen_from_chunk (strOpreturnData, strChunkLength, intOffset);
                            get_signature_from_chunk (strOpreturnData, strSignature, intOffset);

                            // Log header chunk data
                            LogPrint (BCLog::ALL, "Found valid header chunk for UUID: %s\n", strCurrentUUID);
                            LogPrint (BCLog::ALL, "\n");
                            LogPrint (BCLog::ALL, "Header Chunk Magic: %s\n", strMagic);
                            LogPrint (BCLog::ALL, "Header Chunk Protocol: %s\n", strProtocol);
                            LogPrint (BCLog::ALL, "Header Chunk UUID: %s\n", strHeaderUUID);
                            LogPrint (BCLog::ALL, "Header Chunk Length: %s\n", strChunkLength);
                            LogPrint (BCLog::ALL, "Header Chunk Signature: %s\n", strSignature);
                            LogPrint (BCLog::ALL, "\n");

                            // Set to header chunk found
                            blnHeaderChunkFound = true;


// if (is_auth_member(ghshAuthenticatetenantPubkey)) {

//     intAuthenticateTenantPubkeyFound = 1;

    // If all data chunks found
    if (intAllDataChunksFound == 1) {

        // Stop scan
        height = lngCutoff;

    }

// }

                            // Skip to next output
                            continue;

                        // Else not header chunk
                        } else {

                            // Increment number of data chunks found
                            intChunkCount++;
                        }

                        // Return offset for build_file_from_chunks
                        ointOffset = intOffset;

#ifdef TIMING
    start = clock ();    
#endif

                        // Total number of data chunks
                        std::string strTotalChunks;

                        // Get total number of data chunks
                        get_chunktotal_from_chunk (strOpreturnData, strTotalChunks, intOffset);

                        // Convert to integer
                        intTotalChunks = std::stoul(strTotalChunks, nullptr, 16);

                        // Size vector of chunks appropriately
                        ovctChunks.resize(intTotalChunks);

#ifdef TIMING
    end = clock ();    
    t_gctfc = t_gctfc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

#ifdef TIMING
    start = clock ();    
#endif

                        // Chunk number
                        int intChunkNumber;
                        std::string strChunkNumber;

                        // Get chunk number
                        get_chunknum_from_chunk (strOpreturnData, strChunkNumber, intOffset);

                        // Convert to integer
                        intChunkNumber = std::stoul(strChunkNumber, nullptr, 16);

                        // If all data chunks found
                        if (intChunkCount == intTotalChunks) {

                            // Set to all data chunks found
                            intAllDataChunksFound = 1;

// If header chunk found                            
if (blnHeaderChunkFound) {

    // Stop scan
    height = lngCutoff;

}

                        }

                        // put chunk in correct position
                        ovctChunks[intChunkNumber-1] = strOpreturnData;

#ifdef TIMING
    end = clock ();    
    t_gcnfc = t_gcnfc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

                    }
                }
            }
        }
    }

    // If header chunk not found
    if (!blnHeaderChunkFound) {
        LogPrintf("Header chunk not found for uuid %s\n", istrUUID);
        error_level = ERR_CHUNKAUTHNONE;
        return false;
    }

    // If not all data chunks
    if (intChunkCount != intTotalChunks) {
        LogPrint (BCLog::ALL, "Not all data chunks found for uuid %s\n", istrUUID);
        error_level = ERR_NOTALLDATACHUNKS;
        return false;
    }

    // If authenticatetenant pubkey not found
    // if (intAuthenticateTenantPubkeyFound == 0) {
        // LogPrint (BCLog::ALL, "authenticatetenant pubkey not found for uuid %s\n", uuid);
        // error_level = ERR_CHUNKAUTHUNK;
        // return false;
    // }

#ifdef TIMING
    LogPrint (BCLog::ALL, "%d data chunks found.\n", intTotalChunks);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time ReadBlockFromDisk %ld \n", t_rbfd);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time HexStr %ld \n", t_hs);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time strip_opreturn_from_chunk %ld \n", t_sofc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time check_chunk_contextual %ld \n", t_ccc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time get_chunklen_from_chunk %ld \n", t_gclfc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time get_uuid_from_chunk %ld \n", t_gufc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time is_valid_authchunk %ld \n", t_iva);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time get_chunktotal_from_chunk %ld \n", t_gctfc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed time get_chunknumber_from_chunk %ld \n", t_gcnfc);
    LogPrint (BCLog::ALL, "\n");
#endif

    return true;
}

void estimate_coins_for_opreturn(CWallet* wallet, int& suitable_inputs)
{
    suitable_inputs = 0;

    std::vector<COutput> vCoins;
    {
        LOCK(wallet->cs_wallet);
        auto res = AvailableCoins(*wallet);
        for (auto entry : res.All()) {
            vCoins.push_back(entry);
        }
    }

    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "DETERMINE NUMBER OF TRANSACTIONS IN ACTIVE WALLET SUITABLE FOR PUTFILE TRANSACTIONS (estimate_coins_for_opreturn)\n");
    LogPrint (BCLog::ALL, "For a given putfile operation, each group of 256 chunks requires a separate transaction from the active wallet.\n");
    LogPrint (BCLog::ALL, "A given suitable transaction will be associated with lynx coins to be used to pay for the chunk storage.\n");
    LogPrint (BCLog::ALL, "A count of the transactions in the active wallet follow.\n");
    LogPrint (BCLog::ALL, "After that, the number of satoshis associated with each transaction are given, regardless of suitability.\n");
    LogPrint (BCLog::ALL, "Several things can make a transaction unsuitable (for instance, less than 100,000,000 satoshis).\n");
    LogPrint (BCLog::ALL, "Next, the number of suitable transactions is given.\n");
    LogPrint (BCLog::ALL, "Because a given transaction may become the input for a putfile transaction, suitable input is used interchangeably with suitable transaction.\n");
    LogPrint (BCLog::ALL, "Finally, the number of groups of 256 chunks is given\n");
    
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "Number of UTXO's (Unspent Transaction Outputs): %d\n", vCoins.size());    

int intNumberOfImmatureCoins = 0;    

    for (const auto& output : vCoins) {
        const auto& txout = output.txout;
        {

            LogPrint (BCLog::ALL, "Satoshis: %d\n", output.txout.nValue);

            LOCK(wallet->cs_wallet);

            COutPoint kernel(output.outpoint);
            if (wallet->IsLockedCoin(kernel)) {
                continue;
            }

            isminetype mine = wallet->IsMine(txout);
            if (!(mine & ISMINE_SPENDABLE)) {
                continue;
            }

            const CWalletTx* wtx = wallet->GetWalletTx(output.outpoint.hash);
            int depth = wallet->GetTxDepthInMainChain(*wtx);
            if (depth < COINBASE_MATURITY) {

LogPrint (BCLog::ALL, "depth %d COINBASE_MATURITY %d \n", depth, COINBASE_MATURITY);
LogPrint (BCLog::ALL, "\n");

intNumberOfImmatureCoins++;

                continue;
            }

            if (output.txout.nValue < 1 * COIN) {
                continue;
            }
            ++suitable_inputs;
        }
    }

    LogPrint (BCLog::ALL, "Suitable inputs: %d\n", suitable_inputs);    
    LogPrint (BCLog::ALL, "Number of immature UTXO's: %d\n", intNumberOfImmatureCoins);    
    LogPrint (BCLog::ALL, "\n");

}

bool select_coins_for_opreturn(CWallet* wallet, std::set<std::pair<const CWalletTx*, unsigned int>>& setCoinsRet, CAmount& valueRet)
{
    std::vector<COutput> vCoins;
    {
        LOCK(wallet->cs_wallet);
        auto res = AvailableCoins(*wallet);
        for (auto entry : res.All()) {
            vCoins.push_back(entry);
        }
    }

    setCoinsRet.clear();

    for (const auto& output : vCoins) {

        const auto& txout = output.txout;
        {
            LOCK(wallet->cs_wallet);

            COutPoint kernel(output.outpoint);
            if (wallet->IsLockedCoin(kernel)) {
                continue;
            }

            isminetype mine = wallet->IsMine(txout);
            if (!(mine & ISMINE_SPENDABLE)) {
                continue;
            }

            const CWalletTx* wtx = wallet->GetWalletTx(output.outpoint.hash);
            int depth = wallet->GetTxDepthInMainChain(*wtx);
            if (depth < COINBASE_MATURITY) {
                continue;
            }

            if (output.txout.nValue < 1 * COIN) {
                continue;
            }

            //LogPrintf("%s %d %llu LYNX\n", wtx->GetHash().ToString(), output.outpoint.n, output.txout.nValue);
 
            setCoinsRet.insert(std::make_pair(wtx, output.outpoint.n));
            valueRet = output.txout.nValue;

            return true;
        }
    }

    return false;
}

bool generate_selfsend_transaction(WalletContext& wallet_context, CMutableTransaction& tx, std::vector<std::string>& opPayload)
{

    LogPrint (BCLog::ALL, "(generate_selfsend_transaction)\n");

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

    LogPrint (BCLog::ALL, "Input value in satoshis: %llu\n", setValue);

    CTxIn txIn(out);

    //CScript receiver = it->first->tx->vout[0].scriptPubKey;
    CScript receiver = it->first->tx->vout[it->second].scriptPubKey;

    CTxOut txOut(setValue, receiver);

    // build tx
    tx.nVersion = CTransaction::CURRENT_VERSION;
    tx.vin.push_back(txIn);
    tx.vout.push_back(txOut);

    // build opreturn(s)
    CTxOut txOpOut;
    for (auto& l : opPayload) {
        txOpOut = build_opreturn_txout(l);
        tx.vout.push_back(txOpOut);
    }

    {
        //! sign tx once to get complete size
        LOCK(vpwallets[0]->cs_wallet);
        if (!vpwallets[0]->SignTransaction(tx)) {
            return false;
        }

        // calculate and adjust fee (with 32byte fudge)
        unsigned int nBytes = GetSerializeSize(tx) + 32;
        CAmount nFee = GetRequiredFee(*vpwallets[0].get(), nBytes);

        LogPrint (BCLog::ALL, "Transaction bytes: %d\n", nBytes);
        LogPrint (BCLog::ALL, "Transaction fee in satoshis: %llu\n", nFee);

        tx.vout[0].nValue -= nFee;

        LogPrint (BCLog::ALL, "Change in satoshis: %llu\n", tx.vout[0].nValue);
        LogPrint (BCLog::ALL, "\n");
        
        //! sign tx again with correct fee in place
        if (!vpwallets[0]->SignTransaction(tx)) {
            return false;
        }

//
// Harness: uncomment the following three lines to bail from 
// putfile before committing to wallet and blockchain - MH
//
// LogPrint (BCLog::ALL, "bail from generate_selfsend_transaction\n");
// LogPrint (BCLog::ALL, "\n");
// return false;    

        //! commit to wallet and relay to network
        CTransactionRef txRef = MakeTransactionRef(tx);
        vpwallets[0]->CommitTransaction(txRef, {}, {});
    }

    return true;
}
