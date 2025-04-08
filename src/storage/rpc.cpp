// Copyright (c) 2023 Lynx Core Developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <time.h>

#include <key_io.h>
#include <opfile/src/protocol.h>
#include <opfile/src/util.h>
#include <rpc/register.h>
#include <rpc/request.h>
#include <rpc/server.h>
#include <rpc/server_util.h>
#include <rpc/util.h>
#include <storage/auth.h>
#include <storage/chunk.h>
#include <storage/storage.h>
#include <storage/util.h>
#include <storage/worker.h>
#include <sync.h>
#include <timedata.h>
#include <validation.h>

#include <wallet/rpc/util.h>
#include <wallet/rpc/wallet.h>

#include <wallet/coinselection.h>
#include <wallet/context.h>
#include <wallet/fees.h>
#include <wallet/receive.h>
#include <wallet/spend.h>
#include <wallet/transaction.h>
#include <wallet/wallet.h>

#include <pos/manager.h>

#include <util/system.h>

using namespace wallet;
using node::ReadBlockFromDisk;

// Staking state, set at daemon startup time
extern bool gblnDisableStaking;

extern uint160 ghshAuthenticatetenantPubkey;

// Nunber of consecutive authentication failures
int gintAuthenticationFailures;

// Store asset encrypt flag
int gintStoreAssetEncryptFlag;

// Authentication start time
extern uint32_t gu32AuthenticationTime;

extern uint160 authUser;
extern WalletContext* storage_context;
extern ChainstateManager* storage_chainman;
extern std::vector<std::pair<std::string, std::string>> workQueueResult;

extern std::map<std::string, int> gmapFileLength;

extern std::map<std::string, int> gmapBlockHeight;

extern std::map<std::string, int> gmapTimeStamp;

extern std::map<std::string, std::string> gmapExtension;

extern std::map<std::string, std::string> gmapEncrypted;

int gintFetchAssetFullProtocol;

int gintFetchDone;

std::string gstrAssetExtension;

std::string gstrAssetFilename;

static RPCHelpMan store()
{
    return RPCHelpMan{"store",
        "\nStore a file on the Lynx blockchain.\n",
         {
             {"filepath", RPCArg::Type::STR, RPCArg::Optional::NO, "Full path of file to be uploaded"},
             {"uuid", RPCArg::Type::STR, RPCArg::Optional::OMITTED, "Custom unique identifier (32 characters, hexadecimal format, must be unique across all files)"},
             {"encrypt", RPCArg::Type::STR, RPCArg::Optional::OMITTED, "Encrypt flag 0|1 (0: No, 1: Yes, default: No)"},
         },


            RPCResult{
                RPCResult::Type::ARR, "", "",
                {
                    {RPCResult::Type::OBJ, "", "",
                    {
                          {RPCResult::Type::STR, "result", "success | failure"},
                          {RPCResult::Type::STR, "message", "Not authenticated as tenent | Not authenticated | Repeated UUID | Improper length UUID | Invalid hex notation UUID | Zero length asset filesize | Insufficiently funded wallet"},
                          {RPCResult::Type::STR, "identifier", "Universally unique asset identifier"},
                          {RPCResult::Type::STR, "tenant", "Hashed public tenant key"},
                          {RPCResult::Type::NUM, "filesize", "filesize (B)"},
                          {RPCResult::Type::STR, "storagefee", "Storage transaction fee in lynx"},
                          {RPCResult::Type::STR, "storagetime", "Storage date and time"},
                          {RPCResult::Type::NUM, "currentblock", "Current block"},
                          {RPCResult::Type::STR, "stakingstatus", "enabled | disabled"},
                          {RPCResult::Type::STR, "encrypted", "yes | no"},
                    }},
                }
            },


            RPCExamples{
            "\nStore /home/username/documents/research.pdf on the Lynx blockchain.\n"
            + HelpExampleCli("store", "/home/username/documents/research.pdf")
        + HelpExampleRpc("store", "/home/username/documents/research.pdf")
                },
        [&](const RPCHelpMan& self, const JSONRPCRequest& request) -> UniValue
{



    // Get wallets
    auto vctWallets = GetWallets(*storage_context);

    // Number of suitable inputs
    int intNumberOfSuitableInputs;

    // Get number of suitable inputs
    estimate_coins_for_opreturn(vctWallets.front().get(), intNumberOfSuitableInputs);

    LogPrint (BCLog::ALL, "suitable inputs %d \n", intNumberOfSuitableInputs);



    // Entry
    UniValue entry(UniValue::VOBJ);

    // Results
    UniValue results(UniValue::VARR);



    // Staking status
    std::string strStakingStatus;

    // If staking disabled
    if (gblnDisableStaking) {

        // Set to disabled
        strStakingStatus = "disabled";

    // Else not if staking disabled
    } else {

        // Set to enabled
        strStakingStatus = "enabled";

    // End if staking disabled
    }



    // Set active chain
    const CChain& chnActiveChain = storage_chainman->ActiveChain();

    // Set tip height
    const int intTipHeight = chnActiveChain.Height();            
    


    // If manager
    if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {

        // Report and exit
        entry.pushKV("result", "failure");
        entry.pushKV("message", "Not authenticated as tenant.");
        entry.pushKV("identifier", "n/a");
        entry.pushKV("tenant", "n/a");
        entry.pushKV("filesize (B)", 0);
        entry.pushKV("storagefee", 0);
        entry.pushKV("storagetime", "n/a");
        entry.pushKV("currentblock", intTipHeight);
        entry.pushKV("stakingstatus", strStakingStatus);
        entry.pushKV("encrypted", "n/a");
        results.push_back(entry);
        return results;
    }



    // If not authenticated
    if (!is_auth_member(authUser)) {

        // Report and exit
        entry.pushKV("result", "failure");
        entry.pushKV("message", "Please authenticate to use this command.");
        entry.pushKV("identifier", "n/a");
        entry.pushKV("tenant", "n/a");
        entry.pushKV("filesize (B)", 0);
        entry.pushKV("storagefee", 0);
        entry.pushKV("storagetime", "n/a");
        entry.pushKV("currentblock", intTipHeight);
        entry.pushKV("stakingstatus", strStakingStatus);
        entry.pushKV("encrypted", "n/a");
        results.push_back(entry);
        return results;

    // Else not if not authenticated
    } else {



        // Get current time
        uint32_t u32CurrentTime = TicksSinceEpoch<std::chrono::seconds>(GetAdjustedTime());

        // LogPrint (BCLog::ALL, "u32CurrentTime  gu32AuthenticationTime %u %u\n", u32CurrentTime, gu32AuthenticationTime);

        // If authentication session expired
        if ((u32CurrentTime - gu32AuthenticationTime) > 21600) {

            // Report and exit
            entry.pushKV("result", "failure");
            entry.pushKV("message", "Please authenticate to use this command.");
            entry.pushKV("identifier", "n/a");
            entry.pushKV("tenant", "n/a");
            entry.pushKV("filesize (B)", 0);
            entry.pushKV("storagefee", 0);
            entry.pushKV("storagetime", "n/a");
            entry.pushKV("currentblock", intTipHeight);
            entry.pushKV("stakingstatus", strStakingStatus);
            entry.pushKV("encrypted", "n/a");
            results.push_back(entry);
            return results;
        }


 
    // End if not authenticatec
    }



    // Encrypt 
    std::string strEncrypt = "0";
    int intEncrypt;

    // First optional parameter
    std::string strFirstOptionalParameter;

    // Get asset filename
    std::string strAssetFilename = request.params[0].get_str();

    int filelen = read_file_size (strAssetFilename);

    LogPrint (BCLog::ALL, "transactions %d \n", filelen/512/256+1);

    if (intNumberOfSuitableInputs < ((filelen/512/256)+1)) {

        // Report and exit
        entry.pushKV("result", "failure");
        entry.pushKV("message", "Insufficiently funded wallet.");
        entry.pushKV("identifier", "n/a");
        entry.pushKV("tenant", "n/a");
        entry.pushKV("filesize (B)", filelen);
        entry.pushKV("storagefee", 0);
        entry.pushKV("storagetime", "n/a");
        entry.pushKV("currentblock", intTipHeight);
        entry.pushKV("stakingstatus", strStakingStatus);
        entry.pushKV("encrypted", "n/a");
        results.push_back(entry);
        return results;

    }

    // Initialize asset custom uuid
    std::string strAssetUUID = "";

    // Returned uuid
    std::string strAssetUUID0;

    // If first optional parameter
    if(!request.params[1].isNull()) {

        // Get first optional parameter
        strFirstOptionalParameter = request.params[1].get_str();

        // If size > 1
        if (strFirstOptionalParameter.size() > 1) {

            // Set custom uuid
            strAssetUUID = strFirstOptionalParameter;
         
        // Else not if size > 1
        } else {

            // If 1
            if (strFirstOptionalParameter == "1") {

                // Set encrypt
                strEncrypt = "1";

            // End if 1    
            }

        // End if size > 1
        }

    // End if first optional parameter
    }

    // If encrypt flag
    if(!request.params[2].isNull()) {

        // Get encrypt flag
        strEncrypt = request.params[2].get_str();

    // End if encrypt flag
    }



    // Convert encrypt flag to integer
    intEncrypt = stoi (strEncrypt);

    // For file_to_hexchunks
    gintStoreAssetEncryptFlag = intEncrypt;



LogPrint (BCLog::ALL, "uuid %s \n", strAssetUUID);
LogPrint (BCLog::ALL, "encrypt %d \n", intEncrypt);
LogPrint (BCLog::ALL, "\n");



    // If custom uuid
    if (strAssetUUID != "") {

        // uuid invalidity type
        int intUUIDInvalidityType;

        // If uuid valid (length, hex notation)
        if (is_valid_uuid(strAssetUUID, intUUIDInvalidityType)) {





            std::string strUUID1 = strAssetUUID;
            LogPrint (BCLog::ALL, "UUID1 %s \n", strUUID1);
            std::vector<uint8_t> vctUUID1(strUUID1.begin(), strUUID1.end());
            uint160 u16UUID2(Hash160(vctUUID1));
            LogPrint (BCLog::ALL, "UUID2 %s \n", u16UUID2.ToString());
            std::string strUUID2 = u16UUID2.ToString();
            std::string strUUID3 = strUUID2;
            for (int i = 0; i < 8; i++) {
                strUUID3[i] = strUUID1[i];
            }
            LogPrint (BCLog::ALL, "UUID3 %s \n", strUUID3);
            std::string strUUID4 = strUUID3;
            for (int i = 40; i < 64; i++) {
                strUUID4 = strUUID4 + strUUID1[i];
            }
            LogPrint (BCLog::ALL, "UUID4 %s \n", strUUID4);

            strAssetUUID0 = strAssetUUID;

            strAssetUUID = strUUID4;
                

            
    
    
            // Existing uuid's
            std::vector<std::string> vctExistingUUIDs;

            // Number uuid's asked for (-1 means all uuids, masquerading as manager)
            int intNumberOfUUIDsAskedFor = -1;

            // Get existing uuid's
            scan_blocks_for_uuids(*storage_chainman, vctExistingUUIDs, intNumberOfUUIDsAskedFor);

            // Traverse existing uuid's
            for (auto& uuid : vctExistingUUIDs) {

                // If current uuid = custom uuid
                if (uuid == strAssetUUID) {

                    // Report and exit
                    entry.pushKV("result", "failure");
                    entry.pushKV("message", "A duplicate unique identifier was discovered.");
                    entry.pushKV("identifier", strAssetUUID0);
                    entry.pushKV("tenant", authUser.ToString());
                    entry.pushKV("filesize (B)", 0);
                    entry.pushKV("storagefee", 0);
                    entry.pushKV("storagetime", "n/a");
                    entry.pushKV("currentblock", intTipHeight);
                    entry.pushKV("stakingstatus", strStakingStatus);
                    entry.pushKV("encrypted", "n/a");
                    results.push_back(entry);
                    return results;
                }     

            // End traverse existing uuid's
            }

        // Else not if uuid valid (length, hex notation)
        } else {

            // If invalid length
            if (intUUIDInvalidityType == 1) {

                // Report and exit
                entry.pushKV("result", "failure");
                entry.pushKV("message", "The custom unique identifier provided has an invalid length.");
                entry.pushKV("identifier", strAssetUUID);
                entry.pushKV("tenant", authUser.ToString());
                entry.pushKV("filesize (B)", 0);
                entry.pushKV("storagefee", 0);
                entry.pushKV("storagetime", "n/a");
                entry.pushKV("currentblock", intTipHeight);
                entry.pushKV("stakingstatus", strStakingStatus);
                entry.pushKV("encrypted", "n/a");
                results.push_back(entry);
                return results;
            }



            // If invalid hex notation
            if (intUUIDInvalidityType == 2) {

                // Report and exit
                entry.pushKV("result", "failure");
                entry.pushKV("message", "Invalid UUID hex notation.");
                entry.pushKV("identifier", strAssetUUID);
                entry.pushKV("tenant", authUser.ToString());
                entry.pushKV("filesize (B)", 0);
                entry.pushKV("storagefee", 0);
                entry.pushKV("storagetime", "n/a");
                entry.pushKV("currentblock", intTipHeight);
                entry.pushKV("stakingstatus", strStakingStatus);
                entry.pushKV("encrypted", "n/a");
                results.push_back(entry);
                return results;
            }
        }
    }

    // if no custom uuid
    if (strAssetUUID == "") {
        // int uuid_not_found_to_not_exist = 1;
        // while (uuid_not_found_to_not_exist == 1) {

            // generate uuid
            strAssetUUID = generate_uuid(OPENCODING_UUID);
            // std::vector<std::string> existing_uuids;
            // scan_blocks_for_uuids(*storage_chainman, existing_uuids);
            // int uuid_exists = 0;
            // for (auto& uuid : existing_uuids) {
                // if (uuid == strAssetUUID)
                // uuid_exists = 1; 
            // }
            // if (uuid_exists == 0) {
                // uuid_not_found_to_not_exist = 0;
            //}
        //}





        std::string strUUID1 = strAssetUUID;
        LogPrint (BCLog::ALL, "UUID1 %s \n", strUUID1);
        std::vector<uint8_t> vctUUID1(strUUID1.begin(), strUUID1.end());
        uint160 u16UUID2(Hash160(vctUUID1));
        LogPrint (BCLog::ALL, "UUID2 %s \n", u16UUID2.ToString());
        std::string strUUID2 = u16UUID2.ToString();
        std::string strUUID3 = strUUID2;
        for (int i = 0; i < 8; i++) {
            strUUID3[i] = strUUID1[i];
        }
        LogPrint (BCLog::ALL, "UUID3 %s \n", strUUID3);
        std::string strUUID4 = strUUID3;
        for (int i = 40; i < 64; i++) {
            strUUID4 = strUUID4 + strUUID1[i];
        }
        LogPrint (BCLog::ALL, "UUID4 %s \n", strUUID4);

        strAssetUUID0 = strAssetUUID;

        strAssetUUID = strUUID4;
            
        
        


    }

    // If asset filesize > 0
    if (read_file_size(strAssetFilename) > 0) {

        std::string extension;
        size_t dotposition = strAssetFilename.rfind('.');

        if (dotposition != std::string::npos && dotposition != strAssetFilename.size() - 1) {
            extension = strAssetFilename.substr(dotposition + 1);
            if (extension.size() != 4) {
                extension.resize(4);
            }
        }

        gstrAssetExtension = extension;

        gstrAssetFilename = strAssetFilename;

        // Add put task
        // add_put_task(strAssetFilename, strAssetUUID);
        add_put_task("", strAssetUUID);

        // LogPrint (BCLog::ALL, "uuid %s\n", strAssetUUID);



        // Get asset filesize
        int intAssetFilesize = read_file_size(strAssetFilename);

        // Get estimated number of chunks
        // int intEstimatedNumberOfChunks = calculate_chunks_from_filesize(intAssetFilesize);
        // int suitable_inputs = ((intEstimatedNumberOfChunks+(OPRETURN_PER_TX-1))/OPRETURN_PER_TX);



        // Get current timestamp
        uint32_t intCurentTimestamp = TicksSinceEpoch<std::chrono::seconds>(GetAdjustedTime());

        // Convert to time_t
        time_t tmtCurrentTimestamp = intCurentTimestamp;

        // Localize current timestamp
        tm* tmsLocalizedCurrentTimestamp = localtime(&tmtCurrentTimestamp);

        // Formatted current timestamp
        char chrFormattedCurrentTmestamp[80];

        // Format current timestamp
        strftime(chrFormattedCurrentTmestamp, sizeof(chrFormattedCurrentTmestamp), "%Y-%m-%d %H:%M:%S", tmsLocalizedCurrentTimestamp);

        // Convert to string
        std::string strFormattedCurrentTimestamp(chrFormattedCurrentTmestamp);

        // Transaction fee in lynx
        std::ostringstream ossTransactionFee;

        // Convert satoshi's to lynx (transaction fee is one satoshi per byte)
        ossTransactionFee << std::fixed << std::setprecision(8) << (double)intAssetFilesize/100000000.0;

        // Convert to string 
        std::string strTransactionFee = ossTransactionFee.str();

        // Encrypted status
        std::string strEncryptedStatus = "no";

        if (intEncrypt == 1) {
            strEncryptedStatus = "yes";
        }



        // Report and exit
        entry.pushKV("result", "success");
        entry.pushKV("message", "n/a");
        entry.pushKV("identifier", strAssetUUID0);
        entry.pushKV("tenant", authUser.ToString());
        entry.pushKV("filesize (B)", intAssetFilesize);
        entry.pushKV("storagefee", strTransactionFee);
        entry.pushKV("storagetime", strFormattedCurrentTimestamp);
        entry.pushKV("currentblock", intTipHeight);
        entry.pushKV("stakingstatus", strStakingStatus);
        entry.pushKV("encrypted", strEncryptedStatus);
        results.push_back(entry);
        return results;

    // Else not if asset filesize > 0
    } else {

        // Report and exit
        entry.pushKV("result", "failure");
        entry.pushKV("message", "Zero length asset filesize.");
        entry.pushKV("identifier", "n/a");
        entry.pushKV("tenant", authUser.ToString());
        entry.pushKV("filesize (B)", 0);
        entry.pushKV("storagefee", 0);
        entry.pushKV("storagetime", "n/a");
        entry.pushKV("currentblock", intTipHeight);
        entry.pushKV("stakingstatus", strStakingStatus);
        entry.pushKV("encrypted", "n/a");
        results.push_back(entry);
        return results;
    }

},
    };
}

/*
static RPCHelpMan fetchall()
{
    return RPCHelpMan{"fetchall",
        "\nRetrieve asset(s) stored on the Lynx blockchain in reverse chronological order\nLearn more at https://docs.getlynx.io/\n",
         {
             {"count", RPCArg::Type::STR, RPCArg::Optional::NO, "The number of assets to fetch (enter 0 to signify all)."}, 
             {"path", RPCArg::Type::STR, RPCArg::Optional::NO, "Fully qualified asset download path."},
         },
         RPCResult{
//             RPCResult::Type::STR, "", "success or failure"},

            RPCResult{
                RPCResult::Type::ARR, "", "",
                {
                    {RPCResult::Type::OBJ, "", "",
                    {
                          {RPCResult::Type::STR, "result", "success | failure"},
                          {RPCResult::Type::STR, "message", "invalid path | Not authenticated | Nunber of assets fetched: x"},
                          {RPCResult::Type::STR, "tenant", "Store asset authenticated tenant"},
                    }},
                }
            },

         },    



         RPCExamples{
            "\nRetrieve file 00112233445566778899aabbccddeeff and store in /home/username/downloads.\n"
            + HelpExampleCli("fetchall", "00112233445566778899aabbccddeeff /home/username/downloads")
        + HelpExampleRpc("fetchall", "00112233445566778899aabbccddeeff /home/username/downloads")
                },
        [&](const RPCHelpMan& self, const JSONRPCRequest& request) -> UniValue
{
    // Results
    UniValue unvResults(UniValue::VARR);

    // Entry
    UniValue unvEntry(UniValue::VOBJ);

    // Get input parameters
    std::string strCount = request.params[0].get_str();
    std::string strPath = request.params[1].get_str();

    // If unauthenticated
    if (authUser.ToString() == "0000000000000000000000000000000000000000") {

        // Report and exit
        unvEntry.pushKV("result", "failure");
        unvEntry.pushKV("message", "Not authenticated.");
        unvEntry.pushKV("tenant", "n/a");
        unvResults.push_back(unvEntry);
        return unvResults;
    }

    // If bad path
    if (!does_path_exist(strPath)) {

        // Report and exit
        unvEntry.pushKV("result", "failure");
        unvEntry.pushKV("message", "Invalid path: " + strPath + ".");
        unvEntry.pushKV("tenant", "n/a");
        unvResults.push_back(unvEntry);
        return unvResults;
    }

    // Number of assets to fetch
    int intCount;

    // Attempt to convert to integer
    try {
        intCount = stoi(strCount);

    // Invalid integer    
    } catch (const std::invalid_argument& e) {

        // Report and exit
        unvEntry.pushKV("result", "failure");
        unvEntry.pushKV("message", "Invalid count: " + strCount + ".");
        unvEntry.pushKV("tenant", "n/a");
        unvResults.push_back(unvEntry);
        return unvResults;
    }

    // Vector of uuid's
    std::vector<std::string> vctUUIDs;

    // Get uuid's plus metadata
    scan_blocks_for_uuids(*storage_chainman, vctUUIDs, intCount);

    // uuid
    std::string strUUID;

    // Traverse uuid's
    for (auto& uuid : vctUUIDs) {

        // Get uuid
        strUUID = uuid;

        // if (scan_blocks_for_pubkey (*storage_chainman, strUUID)) {

            // Initialize to fetch not done
            gintFetchDone = 0;

            // Perform fetch
            add_get_task(std::make_pair(strUUID, strPath));

            // Whikle fetch not done
            while (gintFetchDone == 0) {

                // Sleep
                sleep (1);

            // End while fetch not done
            }

        // }
    
    // End traverse uuid's
    }

    // Construct message
    std::string strMessage = "Number of assets fetched: " + std::to_string(intCount);

    // Report 
    unvEntry.pushKV("result", "success");
    unvEntry.pushKV("message", strMessage);

    // If manager
    if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {

        // No tenant
        unvEntry.pushKV("tenant", "n/a");

    // Else not if manager
    } else {

        // Tenant
        unvEntry.pushKV("tenant", authUser.ToString());

    // end if manager
    }

    unvResults.push_back(unvEntry);

    // Exit
    return unvResults;            

},
    };
}

*/

static RPCHelpMan fetch()
{
    return RPCHelpMan{"fetch",
        "\nRetrieve an asset stored on the Lynx blockchain.\nLearn more at https://docs.getlynx.io/\n",
         {
             {"uuid", RPCArg::Type::STR, RPCArg::Optional::NO, "The unique identifier of the asset."},
             {"path", RPCArg::Type::STR, RPCArg::Optional::NO, "The full path where you want to download the asset."},
             // {"pubkeyflag", RPCArg::Type::STR, RPCArg::Optional::OMITTED, "Enter 0 to return no tenant."},
         },
         RPCResult{
//             RPCResult::Type::STR, "", "success or failure"},

            RPCResult{
                RPCResult::Type::ARR, "", "",
                {
                    {RPCResult::Type::OBJ, "", "",
                    {
                          {RPCResult::Type::STR, "result", "success | failure"},
                          {RPCResult::Type::STR, "message", "Invalid path | Invalid UUID | UUID not found"},
                          {RPCResult::Type::STR, "tenant", "Authenticated store tenant public key"},
                          {RPCResult::Type::STR, "encrypted", "yes | no"},
                    }},
                }
            },

         },    



         RPCExamples{
            "\nRetrieve file 00112233445566778899aabbccddeeff and store in /home/username/downloads.\n"
            + HelpExampleCli("fetch", "00112233445566778899aabbccddeeff /home/username/downloads")
        + HelpExampleRpc("fetch", "00112233445566778899aabbccddeeff /home/username/downloads")
                },
        [&](const RPCHelpMan& self, const JSONRPCRequest& request) -> UniValue
{
    // Results
    UniValue unvResults(UniValue::VARR);

    // Entry
    UniValue unvEntry(UniValue::VOBJ);

    // Get input
    std::string strUUID = request.params[0].get_str();
    std::string strPath = request.params[1].get_str();
    std::string strTenantFlag;

    // Display tenant flag
    int intTenantFlag = 1;

    // If optional third input
    if (!request.params[2].isNull()) {

        // Get display tenant flag
        strTenantFlag = request.params[2].get_str();

        // Convert to integer
        intTenantFlag = stoi (strTenantFlag);
    }

    // Always display tenant (scan_blocks_for_pubkey detects encryption and sets gintFetchAssetFullProtocol)
    intTenantFlag = 1;

    // If bad path
    if (!does_path_exist(strPath)) {

        // Report and exit
        unvEntry.pushKV("result", "failure");
        unvEntry.pushKV("message", "Invalid path " + strPath + ".");
        unvEntry.pushKV("tenant", "n/a");
        unvEntry.pushKV("encrypted", "n/a");
        unvResults.push_back(unvEntry);
        return unvResults;
    }

    // If uuid correct length
    if (strUUID.size() == OPENCODING_UUID*2) {

        // If display tenant
        if (intTenantFlag == 1) {





            std::string strUUID1 = strUUID;
            LogPrint (BCLog::ALL, "UUID1 %s \n", strUUID1);
            std::vector<uint8_t> vctUUID1(strUUID1.begin(), strUUID1.end());
            uint160 u16UUID2(Hash160(vctUUID1));
            LogPrint (BCLog::ALL, "UUID2 %s \n", u16UUID2.ToString());
            std::string strUUID2 = u16UUID2.ToString();
            std::string strUUID3 = strUUID2;
            for (int i = 0; i < 8; i++) {
                strUUID3[i] = strUUID1[i];
            }
            LogPrint (BCLog::ALL, "UUID3 %s \n", strUUID3);
            std::string strUUID4 = strUUID3;
            for (int i = 40; i < 64; i++) {
                strUUID4 = strUUID4 + strUUID1[i];
            }
            LogPrint (BCLog::ALL, "UUID4 %s \n", strUUID4);

            strUUID = strUUID4;
                
            
    
    

            // If tenant unfound (bad uuid)
            if (!scan_blocks_for_pubkey (*storage_chainman, strUUID)) {

                // Report and exit
                unvEntry.pushKV("result", "failure");
                unvEntry.pushKV("message", "UUID not found: " + strUUID + ".");
                unvEntry.pushKV("tenant", "n/a");
                unvEntry.pushKV("encrypted", "n/a");
                unvResults.push_back(unvEntry);
                return unvResults;

            // Else not if tenant unfound (bad uuid)
            } else {

LogPrint (BCLog::ALL, "gintFetchAssetFullProtocol from fetch() %d \n", gintFetchAssetFullProtocol);
LogPrint (BCLog::ALL, "\n");

// return "test";

                std::string strFetchAssetEncryptedStatus = "no";
                if ((gintFetchAssetFullProtocol == 2) || (gintFetchAssetFullProtocol == 3)) {
                    strFetchAssetEncryptedStatus = "yes";
                }

                // Fetch
                add_get_task(std::make_pair(strUUID, strPath));

                // Repoet and exit
                unvEntry.pushKV("result", "success");
                unvEntry.pushKV("message", "n/a");
                unvEntry.pushKV("tenant", ghshAuthenticatetenantPubkey.ToString());
                unvEntry.pushKV("encrypted", strFetchAssetEncryptedStatus);
                unvResults.push_back(unvEntry);
                return unvResults;

            // End if tenant unfound (bad uuid)
            }

        // Else not if display tenant
        } else {

            // Fetch
            add_get_task(std::make_pair(strUUID, strPath));
           
            // Report and exit 
            unvEntry.pushKV("result", "success");
            unvEntry.pushKV("message", "n/a");
            unvEntry.pushKV("tenant", "n/a");
            unvEntry.pushKV("encrypted", "n/a");
            unvResults.push_back(unvEntry);
            return unvResults;            

        // End if display tenant
        }

    // Else not if uuid correct length
    } else {

        // Report and exit
        unvEntry.pushKV("result", "failure");
        unvEntry.pushKV("message", "Invalid UUID length: " + strUUID + ".");
        unvEntry.pushKV("tenant", "n/a");
        unvEntry.pushKV("encrypted", "n/a");
        unvResults.push_back(unvEntry);
        return unvResults;

    // End if uuid correct length
    } 

},
    };
}

static RPCHelpMan list()
{
    return RPCHelpMan{"list",
                "\nLists metadata for tenants's blockchain assets in chronological order (newest first).\n",
                {
                    // Optional number of uuid's to return, defaults to all.
                    {"count", RPCArg::Type::STR, RPCArg::Optional::OMITTED, "Number of results to return (0 for all).  If omitted, shows most recent 10 results."},
                }, {

                    RPCResult{
                        RPCResult::Type::ARR, "", "", {{
                            RPCResult::Type::ARR, "", "", {{
                                RPCResult::Type::OBJ, "", "", {
                                {RPCResult::Type::STR, "uuid", "Unique identifier of the asset"},
                                {RPCResult::Type::STR, "message", "Not authenticated"},
                                {RPCResult::Type::NUM, "length", "Asset filesize in bytes"},
                                {RPCResult::Type::NUM, "height", "Starting block number for asset storage (may span multiple blocks)"},
                                {RPCResult::Type::STR, "timestamp", "Date and time asset storage began"},
                                {RPCResult::Type::STR, "extension", "Asset extension"},
                                {RPCResult::Type::STR, "encrypted", "yes | no"},
                            }},
                        }},
                    }
                },

            },
            RPCExamples{
                HelpExampleCli("list", "")
                + HelpExampleRpc("list", "")
            },
        [&](const RPCHelpMan& self, const JSONRPCRequest& request) -> UniValue
{

    // Output data structures
    UniValue unvResult0(UniValue::VOBJ);
    UniValue unvResult1(UniValue::VARR);
    UniValue unvResult2(UniValue::VARR);

    // If not authenticated
    if (authUser.ToString() == "0000000000000000000000000000000000000000") {

        // Pack results
        unvResult0.pushKV("uuid", "n/a");
        unvResult0.pushKV("message", "Not authenticated");
        unvResult0.pushKV("length", 0);
        unvResult0.pushKV("height", 0);
        unvResult0.pushKV("timestamp", "n/a");
        unvResult0.pushKV("extension", "n/a");
        unvResult0.pushKV("encrypted", "n/a");

        // Pack results
        unvResult1.push_back (unvResult0);

        // Pack results
        unvResult2.push_back (unvResult1);

        // Return results
        return unvResult2;

    // End if not authenticated
    }

    // Initialize number of uuids asked for (0 means all)
    std::string strCount = "10";

    // Integer number of uuids asked for
    int intCount;

    // If optional parameter (number of uuids asked for)
    if (!request.params[0].isNull()) {

        // Get n umber of uuids asked for
        strCount = request.params[0].get_str();

    // End if optional parameter (number of uuids asked for)
    }

    // Convert to integer     
    intCount = stoi (strCount);

    // Vector of uuids found
    std::vector<std::string> vctUUIDs;

    // Clock start
    clock_t clkStart;

    // Clock end 
    clock_t clkEnd;

    // Elapsed time
    double dblElapsedTime;

    // Start timer
    clkStart = clock ();

    // Get list of uuids
    scan_blocks_for_uuids(*storage_chainman, vctUUIDs, intCount);

    // Asset filelength
    int intFileLength;

    // Asset blockheight
    int intBlockHeight;

    // Asset timestamp (seconds since epoch (first second of 1970))
    int intTimeStamp;

    // Traverse returned uuids
    for (auto& strUUID : vctUUIDs) {

        // Initialize file length
        intFileLength = 0;

        // Traverse filelength map
        for (const auto& m : gmapFileLength) {

            // If match
            if (m.first == strUUID) {

                // Get filelength
                intFileLength = m.second;

            // End if match
            }

        // End traverse filelength map
        }

        // Traverse blockheight map
        for (const auto& m : gmapBlockHeight) {

            // If match
            if (m.first == strUUID) {

                // Get blockheight
                intBlockHeight = m.second;

            // End if map
            }

        // End traverse blockheight map
        }

        // Traverse timestamp map
        for (const auto& m : gmapTimeStamp) {

            // If match
            if (m.first == strUUID) {

                // Get timestamp
                intTimeStamp = m.second;

            // End if match
            }

        // End traverse timestamp map
        }

        // Convert to time_t
        time_t tmtEpochTime = intTimeStamp;

        // Convert to local time
        tm* timLocalTime = localtime(&tmtEpochTime);

        // Formatted local time
        char chrFormattedLocalTime[80];

        // Format local time
        strftime(chrFormattedLocalTime, sizeof(chrFormattedLocalTime), "%Y-%m-%d %H:%M:%S", timLocalTime);

        // Convert to string
        std::string strFormattedLocalTime(chrFormattedLocalTime);



        // If all data chunks found
        if (intFileLength > 0) {

            // Pack results
            unvResult0.pushKV("uuid", strUUID);
            unvResult0.pushKV("message", "n/a");
            unvResult0.pushKV("length", intFileLength);
            unvResult0.pushKV("height", intBlockHeight);
            unvResult0.pushKV("timestamp", strFormattedLocalTime);
            unvResult0.pushKV("extension", gmapExtension[strUUID]);
            unvResult0.pushKV("encrypted", gmapEncrypted[strUUID]);

            // Pack results
            unvResult1.push_back (unvResult0);

        } 



    }

    // Pack results
    unvResult2.push_back (unvResult1);

    // End timer
    clkEnd = clock ();

    // Compute elapsed time
    dblElapsedTime = (double) (clkEnd - clkStart) / CLOCKS_PER_SEC;

    // Output elapsed time to debug
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "Elapsed time for list %ld \n", dblElapsedTime);
    LogPrint (BCLog::ALL, "\n");

    // Return results
    return unvResult2;

},
    };
}

static RPCHelpMan status()
{
    return RPCHelpMan{"status",
                "\nReturn the recent job and worker status.\n",
                {},
                {
                    RPCResult{
                        RPCResult::Type::ARR, "", "",
                            {{RPCResult::Type::STR, "", "Worker and job status information."}}
                    },
                },
                RPCExamples{
                    HelpExampleCli("status", "")
            + HelpExampleRpc("status", "")
                },
        [&](const RPCHelpMan& self, const JSONRPCRequest& request) -> UniValue
{
    UniValue ret(UniValue::VARR);

    // worker
    int status;
    get_storage_worker_status(status);
    if (status == WORKER_IDLE) {
        ret.push_back(std::string("WORKER_IDLE"));
    } else if (status == WORKER_BUSY) {
        ret.push_back(std::string("WORKER_BUSY"));
    } else {
        ret.push_back(std::string("WORKER_ERROR"));
    }

    // job list
    int total_jobs = workQueueResult.size();
    int start_jobs = total_jobs - 15;
    if (start_jobs < 0) start_jobs = 0;
    for (int i=start_jobs; i<total_jobs; i++) {
        std::string job_result = workQueueResult[i].first + ", " + workQueueResult[i].second;
        ret.push_back(job_result);
    }

    return ret;
},
    };
}

static RPCHelpMan tenants()
{
    return RPCHelpMan{"tenants",
                "\nDisplay the current list of data storage tenants.\n",
                {},
                {
                    RPCResult{
                        RPCResult::Type::ARR, "", "",
                        {{RPCResult::Type::STR_HEX, "", "A list of current data storage tenant keys."}}},
                },
                RPCExamples{
                    HelpExampleCli("tenants", "")
            + HelpExampleRpc("tenants", "")
                },
        [&](const RPCHelpMan& self, const JSONRPCRequest& request) -> UniValue
{

    if (authUser.ToString() != Params().GetConsensus().initAuthUser.ToString()) {
        return std::string("Role-based restriction: Current role cannot perform this action");
    }

    UniValue ret(UniValue::VARR);

    std::vector<uint160> tempList;
    copy_auth_list(tempList);
    for (auto& l : tempList) {
        if (l.ToString() != Params().GetConsensus().initAuthUser.ToString()) {
            ret.push_back(l.ToString());
        }
    }

    return ret;
},
    };
}

static RPCHelpMan auth()
{
    return RPCHelpMan{"auth",
                "\nAuthenticate a data storage tenant for a 72 block (~6 hour) session.\n",
                {
                    {"privatekey", RPCArg::Type::STR, RPCArg::Optional::NO, "WIF-Format Privatekey."},
                },
                {
                    RPCResult{
                        RPCResult::Type::ARR, "", "",
                        {
                            {RPCResult::Type::OBJ, "", "",
                            {
                                  {RPCResult::Type::STR, "result", "success | failure"},
                                  {RPCResult::Type::STR, "message", "Authenticated as Manager | Authenticated as tenant | Invalid key | Unauthorized tenant | No wallet"},
                                  {RPCResult::Type::NUM, "capacity", "Number of aqvailable store asset KB."},
                                  {RPCResult::Type::STR, "sessionstart", "Authentication session start timestamp."},
                                  {RPCResult::Type::STR, "sessionend", "Authentication session end timestamp."},
                                  {RPCResult::Type::STR, "sessionstartblock", "Authentication session start block."},
                                  {RPCResult::Type::STR, "sessionendtime", "Authentication session end block."},
                                  {RPCResult::Type::STR, "stakingstatus", "enabled | disabled"},
                            }},
                        }
                    },
                },

    RPCExamples{
                    HelpExampleCli("auth", "cVDy3BpQNFpGVnsrmXTgGSuU3eq5aeyo513hJazyCEj9s6eDiFj8")
            + HelpExampleRpc("auth", "cVDy3BpQNFpGVnsrmXTgGSuU3eq5aeyo513hJazyCEj9s6eDiFj8")
                },
        [&](const RPCHelpMan& self, const JSONRPCRequest& request) -> UniValue
{

    /*
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "disablestaking %d \n", gArgs.GetBoolArg("-disablestaking", false));

    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "rpcuser %s \n", gArgs.GetArg("-rpcuser", ""));

    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "rpctenant %s \n", gArgs.GetArg("-rpctenant", ""));
    */

    // Results
    UniValue unvResults(UniValue::VARR);

    // Entry
    UniValue unvEntry(UniValue::VOBJ);

    // Initialize sleep time
    int intSleep = 1;

    // Staking status
    std::string strStakingStatus;

    // If staking disabled
    if (gblnDisableStaking) {

        // Set staking status to disabled
        strStakingStatus = "disabled";

    // Else not if staking disbled
    } else {

        // Set staking status to enabled
        strStakingStatus = "enabled";

    // End if staking disabled
    }

    // Get private key
    std::string strPrivateKey = request.params[0].get_str();
    // std::string strPrivateKey = gArgs.GetArg("-rpctenant", "");

    // If private key empty or invalid
    if (strPrivateKey.empty() || !set_auth_user(strPrivateKey)) {

        // Report
        unvEntry.pushKV("result", "failure");
        unvEntry.pushKV("message", "Invalid key.");
        unvEntry.pushKV("capacity (KB)", 0);
        unvEntry.pushKV("sessionstart", "n/a");
        unvEntry.pushKV("sessionend", "n/a");
        unvEntry.pushKV("sessionstartblock", "n/a");
        unvEntry.pushKV("sessionendblock", "n/a");
        unvEntry.pushKV("stakingstatus", strStakingStatus);
        unvResults.push_back(unvEntry);

        // Increment number of consecutive failures
        gintAuthenticationFailures = gintAuthenticationFailures + 1;

        // Double sleep time once per consecutive failure
        for (int i = 0; i < gintAuthenticationFailures; i++) {
            intSleep = intSleep * 2;
        }

        // Sleep
        sleep (intSleep);

        // Exit
        return unvResults;

    // Else not if private key empty or invalid
    } else {

        // If unauthorized
        if (!is_auth_member(authUser)) {

            // Report
            unvEntry.pushKV("result", "failure");
            unvEntry.pushKV("message", "Unauthorized tenant.");
            unvEntry.pushKV("capacity (KB)", 0);
            unvEntry.pushKV("sessionstart", "n/a");
            unvEntry.pushKV("sessionend", "n/a");
            unvEntry.pushKV("sessionstartblock", "n/a");
            unvEntry.pushKV("sessionendblock", "n/a");
            unvEntry.pushKV("stakingstatus", strStakingStatus);
            unvResults.push_back(unvEntry);

            // Increment number of consecutive failures
            gintAuthenticationFailures = gintAuthenticationFailures + 1;
            
            // Double sleep time once per consecutive failure
            for (int i = 0; i < gintAuthenticationFailures; i++) {
                intSleep = intSleep * 2;
            }

            // Sleep
            sleep (intSleep);

            // Exit
            return unvResults;

        // Else not if unauthorized    
        } else {

            // Get wallets
            auto vctWallets = GetWallets(*storage_context);

            // Get number of wallets
            size_t sztNumberOfWallets = vctWallets.size();

            // If no wallet
            if (sztNumberOfWallets < 1) {

                // Report and exit
                unvEntry.pushKV("result", "failure");
                unvEntry.pushKV("message", "No wallet.");
                unvEntry.pushKV("capacity (KB)", 0);
                unvEntry.pushKV("sessionstart", "n/a");
                unvEntry.pushKV("sessionend", "n/a");
                unvEntry.pushKV("sessionstartblock", "n/a");
                unvEntry.pushKV("sessionendblock", "n/a");
                unvEntry.pushKV("stakingstatus", strStakingStatus);
                unvResults.push_back(unvEntry);

                // Increment number of consecutive failures
                gintAuthenticationFailures = gintAuthenticationFailures + 1;

                // Double sleep time once per consecutive failure
                for (int i = 0; i < gintAuthenticationFailures; i++) {
                    intSleep = intSleep * 2;
                }

                // Sleep
                sleep (intSleep);
        
                // Exit
                return unvResults;

            // End if no wallet    
            }

            // Number of suitable inputs
            int intNumberOfSuitableInputs;

            // Get number of suitable inputs
            estimate_coins_for_opreturn(vctWallets.front().get(), intNumberOfSuitableInputs);

            // If not manager
            if (authUser.ToString() != Params().GetConsensus().initAuthUser.ToString()) {

                // Status
                int intStatus;

                // Command
                char chrCommand[256];

                // Construct command
                snprintf(chrCommand, sizeof(chrCommand), "/root/capacitor %d", intNumberOfSuitableInputs);

                // Issue command
                intStatus = system (chrCommand);            

                // Report status
                LogPrint (BCLog::ALL, "status %d\n", intStatus);
            }
            
            // result
            unvEntry.pushKV("result", "success");

            // If tenant
            if (authUser.ToString() != Params().GetConsensus().initAuthUser.ToString()) {

                // message
                unvEntry.pushKV("message", "You are authenticated as a tenant.");

            // Else not tenant    
            } else {                

                // message
                unvEntry.pushKV("message", "You are authenticated as the manager.");
            }

            // Set capacity in KB
            uint32_t u32Capacity = intNumberOfSuitableInputs * 512 * 256 / 1000;

            // If manager
            if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {

                // Zero capacity
                u32Capacity = 0;
            }

            // capacity
            unvEntry.pushKV("capacity (KB)", u32Capacity);

            // Get current time
            uint32_t u32CurrentTime = TicksSinceEpoch<std::chrono::seconds>(GetAdjustedTime());

            // Convert to time_t
            time_t tmtCurrentTime = u32CurrentTime;

            // Localize current time
            tm* tmsLocalizedCurrentTime = localtime(&tmtCurrentTime);

            // Formatted current time
            char chrFormattedCurrentTime[80];

            // Format current time
            strftime(chrFormattedCurrentTime, sizeof(chrFormattedCurrentTime), "%Y-%m-%d %H:%M:%S", tmsLocalizedCurrentTime);

            // Convert to string
            std::string strFormattedCurrentTime(chrFormattedCurrentTime);

            // If manager
            if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {

                // Lose session start time
                strFormattedCurrentTime = "n/a";
            }

            // Session start
            unvEntry.pushKV("sessionstart", strFormattedCurrentTime);

            // Set session end time 
            uint32_t u32SessionEndTime = u32CurrentTime + 21600;

            // Convert to time_t
            time_t tmtSessionEndTime = u32SessionEndTime;

            // Localize session end time
            tm* tmsLocalizedSessionEndTime = localtime(&tmtSessionEndTime);

            char chrFormattedSessionEndTime[80];

            // Format session end time
            strftime(chrFormattedSessionEndTime, sizeof(chrFormattedSessionEndTime), "%Y-%m-%d %H:%M:%S", tmsLocalizedSessionEndTime);

            // Convert to string
            std::string strFormattedSessionEndTime(chrFormattedSessionEndTime);

            // If manager
            if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {

                // Lose session end time
                strFormattedSessionEndTime = "n/a";
            }

            // session end
            unvEntry.pushKV("sessionend", strFormattedSessionEndTime);

            // Get active chain
            const CChain& chnActiveChain = storage_chainman->ActiveChain();

            // Get tip height
            const int intTipHeight = chnActiveChain.Height();          
            
            // If manager
            if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {

                // Lose session start block
                unvEntry.pushKV("sessionstartblock", 0);
            } else {                

                // sessionstartblock
                unvEntry.pushKV("sessionstartblock", intTipHeight);
            }

            // If manager
            if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {

                // Lose session end block
                unvEntry.pushKV("sessionendblock", 0);
            } else {                

                // sessionendblock (72 blocks = 6 hours)
                unvEntry.pushKV("sessionendblock", intTipHeight + 72);
            }

            // If manager
            if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {

                // stakingstatus
                unvEntry.pushKV("stakingstatus", strStakingStatus);

            // Else not if manager
            } else {            
                
                // Disable staking
                stakeman_request_stop();

                // Record staking status
                gblnDisableStaking = true;

                // stakingstatus
                unvEntry.pushKV("stakingstatus", "disabled");
            }



            // Reset number of consecutive failures
            gintAuthenticationFailures = 0;

            // Sleep
            sleep (1);

            unvResults.push_back(unvEntry);

            // Exit
            return unvResults;
        
        }
    }

},
    };
}

static RPCHelpMan allow()
{
    return RPCHelpMan{"allow",
                "\nAdd a new data storage tenant.\n",
                {
                    {"hash160", RPCArg::Type::STR, RPCArg::Optional::NO, "A new tenant key to be allowed to store data."},
                },
                RPCResult{
                    RPCResult::Type::ARR, "", "",
                    {{RPCResult::Type::STR, "", "The status of the operation."}}},
//              RPCResult{
//                  RPCResult::Type::STR, "", "success or failure"},
                RPCExamples{
                    HelpExampleCli("allow", "00112233445566778899aabbccddeeff00112233")
            + HelpExampleRpc("allow", "00112233445566778899aabbccddeeff00112233")
                },
        [&](const RPCHelpMan& self, const JSONRPCRequest& request) -> UniValue
{
    // const CTxMemPool& mempool = EnsureAnyMemPool(request.context);
    // if (check_mempool_for_authdata(mempool)) {
        // return std::string("authtx-in-mempool");
    // }

    UniValue ret(UniValue::VARR);

    std::string hash160 = request.params[0].get_str();
    if (hash160.size() != OPAUTH_HASHLEN*2) {
        ret.push_back("hash160-wrong-size");
        return ret;
        // return std::string("hash160-wrong-size");
    }
    uint160 hash = uint160S(hash160);

    // are we authenticated
    if (is_auth_member(authUser)) {

        if (authUser.ToString() != Params().GetConsensus().initAuthUser.ToString()) {
            ret.push_back("Role-based restriction: Current role cannot perform this action");
            return ret;
            // return std::string("Role-based restriction: Current role cannot perform this action");
        }

        int type;
        uint32_t time;
        CMutableTransaction tx;
        std::string opreturn_payload;

        type = 0;
        time = TicksSinceEpoch<std::chrono::seconds>(GetAdjustedTime());

        // LogPrint (BCLog::ALL, "\n");
        // LogPrint (BCLog::ALL, "time in seconds since the first second of 1970 (3600*24*365*54 ..): %d\n", time);

        if (!generate_auth_payload(opreturn_payload, type, time, hash160)) {
            ret.push_back("error-generating-authpayload");
            return ret;
            // return std::string("error-generating-authpayload");
        }

        if (!generate_auth_transaction(*storage_context, tx, opreturn_payload)) {
            ret.push_back("error-generating-authtransaction");
            return ret;
            // return std::string("error-generating-authtransaction");
        }

        // add_auth_member(hash);

        ret.push_back("success");
        ret.push_back(hash160);
        return ret;
        // return std::string("success");

    } else {
        ret.push_back("authentication failure");
        return ret;
        // return std::string("authentication failure");
    }

    ret.push_back("failure");
    return ret;
    // return std::string("failure");
},
    };
}

static RPCHelpMan deny()
{
    return RPCHelpMan{"deny",
                "\nRemove a data storage tenant.\n",
                {
                    {"hash160", RPCArg::Type::STR, RPCArg::Optional::NO, "The data storage tenant key to be removed."},
                },
                RPCResult{
                    RPCResult::Type::STR, "", "success or failure"},
                RPCExamples{
                    HelpExampleCli("deny", "00112233445566778899aabbccddeeff00112233")
            + HelpExampleRpc("deny", "00112233445566778899aabbccddeeff00112233")
                },
        [&](const RPCHelpMan& self, const JSONRPCRequest& request) -> UniValue
{
    // const CTxMemPool& mempool = EnsureAnyMemPool(request.context);
    // if (check_mempool_for_authdata(mempool)) {
        // return std::string("authtx-in-mempool");
    // }

    std::string hash160 = request.params[0].get_str();
    if (hash160.size() != OPAUTH_HASHLEN*2) {
        return std::string("hash160-wrong-size");
    }
    uint160 hash = uint160S(hash160);

    // are we authenticated
    if (is_auth_member(authUser)) {

        if (authUser.ToString() != Params().GetConsensus().initAuthUser.ToString()) {
            return std::string("Role-based restriction: Current role cannot perform this action");
        }

        int type;
        uint32_t time;
        CMutableTransaction tx;
        std::string opreturn_payload;

        type = 1;
        time = TicksSinceEpoch<std::chrono::seconds>(GetAdjustedTime());

        if (!generate_auth_payload(opreturn_payload, type, time, hash160)) {
            return std::string("error-generating-authpayload");
        }

        if (!generate_auth_transaction(*storage_context, tx, opreturn_payload)) {
            return std::string("error-generating-authtransaction");
        }

        return std::string("success");

    } else {
        return std::string("failure");
    }

    return std::string("failure");
},
    };
}

void RegisterStorageRPCCommands(CRPCTable& t)
{
    static const CRPCCommand commands[]{
        {"storage", &store},
        // {"storage", &fetchall},
        {"storage", &fetch},
        {"storage", &list},
        {"storage", &status},
        {"storage", &tenants},
        {"storage", &auth},
        {"storage", &allow},
        {"storage", &deny},
    };

    for (const auto& c : commands) {
        t.appendCommand(c.name, &c);
    }
}
