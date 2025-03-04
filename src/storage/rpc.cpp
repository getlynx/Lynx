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

using namespace wallet;
using node::ReadBlockFromDisk;

// Staking state, set at daemon startup time
extern bool gblnDisableStaking;

// Nunber of consecutive authentication failures
int gintAuthenticationFailures;

// Authentication start time
extern uint32_t gu32AuthenticationTime;

extern uint160 authUser;
extern WalletContext* storage_context;
extern ChainstateManager* storage_chainman;
extern std::vector<std::pair<std::string, std::string>> workQueueResult;

extern std::map<std::string, int> gmapFileLength;

extern std::map<std::string, int> gmapBlockHeight;

extern std::map<std::string, int> gmapTimeStamp;

static RPCHelpMan store()
{
    return RPCHelpMan{"store",
        "\nStore a file on the Lynx blockchain.\n",
         {
             {"filepath", RPCArg::Type::STR, RPCArg::Optional::NO, "Full path of file to be uploaded"},
             {"uuid", RPCArg::Type::STR, RPCArg::Optional::OMITTED, "Custom unique identifier (32 characters, hexadecimal format, must be unique across all files)"},
         },


            RPCResult{
                RPCResult::Type::ARR, "", "",
                {
                    {RPCResult::Type::OBJ, "", "",
                    {
                          {RPCResult::Type::STR, "result", "success | failure"},
                          {RPCResult::Type::STR, "message", "Not authenticated as tenent | Not authenticated | Repeated UUID | Improper length UUID | Invalid hex notation UUID"},
                          {RPCResult::Type::STR, "identifier", "Universally unique asset identifier"},
                          {RPCResult::Type::STR, "tenant", "Hashed public tenant key"},
                          {RPCResult::Type::NUM, "filesize", "filesize (B)"},
                          {RPCResult::Type::STR, "storagefee", "Storage transaction fee in lynx"},
                          {RPCResult::Type::STR, "storagetime", "Storage date and time"},
                          {RPCResult::Type::NUM, "currentblock", "Current block"},
                          {RPCResult::Type::STR, "stakingstatus", "enabled | disabled"},
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



    // Entry
    UniValue entry(UniValue::VOBJ);

    // Results
    UniValue results(UniValue::VARR);



    // Staking status
    std::string strStakingslStatus;

    // If staking disabled
    if (gblnDisableStaking) {

        // Set to disabled
        strStakingslStatus = "disabled";

    // Else not if staking disabled
    } else {

        // Set to enabled
        strStakingslStatus = "enabled";

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
        entry.pushKV("filesize", 0);
        entry.pushKV("storagefee", 0);
        entry.pushKV("storagetime", "n/a");
        entry.pushKV("currentblock", intTipHeight);
        entry.pushKV("stakingstatus", strStakingslStatus);
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
        entry.pushKV("filesize", 0);
        entry.pushKV("storagefee", 0);
        entry.pushKV("storagetime", "n/a");
        entry.pushKV("currentblock", intTipHeight);
        entry.pushKV("stakingstatus", strStakingslStatus);
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
            entry.pushKV("filesize", 0);
            entry.pushKV("storagefee", 0);
            entry.pushKV("storagetime", "n/a");
            entry.pushKV("currentblock", intTipHeight);
            entry.pushKV("stakingstatus", strStakingslStatus);
            results.push_back(entry);
            return results;
        }


 
    // End if not authenticatec
    }



    // Get asset filename
    std::string strAssetFilename = request.params[0].get_str();

    // Initialize asset custom uuid
    std::string strAssetCustomUUID = "";

    // If custom uuid
    if(!request.params[1].isNull()) {

        // Get custom uuid
        strAssetCustomUUID = request.params[1].get_str();
    }

    // If custom uuid
    if (strAssetCustomUUID != "") {

        // uuid invalidity type
        int intUUIDInvalidityType;

        // If uuid valid (length, hex notation)
        if (is_valid_uuid(strAssetCustomUUID, intUUIDInvalidityType)) {

            // Existing uuid's
            std::vector<std::string> vctExistingUUIDs;

            // Number uuid's asked for (-1 means all uuids, masquerading as manager)
            int intNumberOfUUIDsAskedFor = -1;

            // Get existing uuid's
            scan_blocks_for_uuids(*storage_chainman, vctExistingUUIDs, intNumberOfUUIDsAskedFor);

            // Traverse existing uuid's
            for (auto& uuid : vctExistingUUIDs) {

                // If current uuid = custom uuid
                if (uuid == strAssetCustomUUID) {
                    entry.pushKV("result", "failure");
                    entry.pushKV("message", "A duplicate unique identifier was discovered.");
                    entry.pushKV("identifier", strAssetCustomUUID);
                    entry.pushKV("tenant", authUser.ToString());
                    entry.pushKV("filesize", 0);
                    entry.pushKV("storagefee", 0);
                    entry.pushKV("storagetime", "n/a");
                    entry.pushKV("currentblock", intTipHeight);
                    entry.pushKV("stakingstatus", strStakingslStatus);
                    results.push_back(entry);
                    return results;
                
//                     return std::string("A duplicate unique identifier was discovered.");
                }     
            }
        } else {
            if (intUUIDInvalidityType == 1) {
                entry.pushKV("result", "failure");
                entry.pushKV("message", "The custom unique identifier provided has an invalid length.");
                entry.pushKV("identifier", strAssetCustomUUID);
                entry.pushKV("tenant", authUser.ToString());
                entry.pushKV("filesize", 0);
                entry.pushKV("storagefee", 0);
                entry.pushKV("storagetime", "n/a");
                entry.pushKV("currentblock", intTipHeight);
                entry.pushKV("stakingstatus", strStakingslStatus);
                results.push_back(entry);
                return results;
            
//                 return std::string ("The custom unique identifier provided has an invalid length.");
            }



            if (intUUIDInvalidityType == 2) {
                entry.pushKV("result", "failure");
                entry.pushKV("message", "Invalid UUID hex notation.");
                entry.pushKV("identifier", strAssetCustomUUID);
                entry.pushKV("tenant", authUser.ToString());
                entry.pushKV("filesize", 0);
                entry.pushKV("storagefee", 0);
                entry.pushKV("storagetime", "n/a");
                entry.pushKV("currentblock", intTipHeight);
                entry.pushKV("stakingstatus", strStakingslStatus);
                results.push_back(entry);
                return results;
            
//                 return std::string ("uuid_invalid_hex_notation");
            }
        }
    }

    // if no custom uuid
    if (strAssetCustomUUID == "") {
        // int uuid_not_found_to_not_exist = 1;
        // while (uuid_not_found_to_not_exist == 1) {

            // generate uuid
            strAssetCustomUUID = generate_uuid(OPENCODING_UUID);
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
    }

    if (read_file_size(strAssetFilename) > 0) {
        add_put_task(strAssetFilename, strAssetCustomUUID);

LogPrint (BCLog::ALL, "uuid %s\n", strAssetCustomUUID);



int filelen = read_file_size(strAssetFilename);
int est_chunks = calculate_chunks_from_filesize(filelen);
int suitable_inputs = ((est_chunks+(OPRETURN_PER_TX-1))/OPRETURN_PER_TX);



uint32_t time = TicksSinceEpoch<std::chrono::seconds>(GetAdjustedTime());
time_t time2 = time;
tm* time3 = localtime(&time2);
char time4[80];
strftime(time4, sizeof(time4), "%Y-%m-%d %H:%M:%S", time3);
std::string storagetime(time4);

std::ostringstream oss;
oss << std::fixed << std::setprecision(8) << (double)filelen/100000000.0;
std::string str_value = oss.str();



        entry.pushKV("result", "success");
        entry.pushKV("message", "n/a");
        entry.pushKV("identifier", strAssetCustomUUID);
        entry.pushKV("tenant", authUser.ToString());
        entry.pushKV("filesize", filelen);
        entry.pushKV("storagefee", str_value);
        entry.pushKV("storagetime", storagetime);
        entry.pushKV("currentblock", intTipHeight);
        entry.pushKV("stakingstatus", strStakingslStatus);
        results.push_back(entry);
        return results;
    }

    return std::string("failure");
},
    };
}

static RPCHelpMan fetch()
{
    return RPCHelpMan{"fetch",
        "\nRetrieve an file stored on the Lynx blockchain.\nLearn more at https://docs.getlynx.io/\n",
         {
             {"uuid", RPCArg::Type::STR, RPCArg::Optional::NO, "The unique identifier of the file."},
             {"path", RPCArg::Type::STR, RPCArg::Optional::NO, "The full path where you want to download the file."},
         },
         RPCResult{
            RPCResult::Type::STR, "", "success or failure"},
         RPCExamples{
            "\nRetrieve file 00112233445566778899aabbccddeeff and store in /home/username/downloads.\n"
            + HelpExampleCli("fetch", "00112233445566778899aabbccddeeff /home/username/downloads")
        + HelpExampleRpc("fetch", "00112233445566778899aabbccddeeff /home/username/downloads")
                },
        [&](const RPCHelpMan& self, const JSONRPCRequest& request) -> UniValue
{
    std::string uuid = request.params[0].get_str();
    std::string path = request.params[1].get_str();
    if (!does_path_exist(path)) {
        return std::string("invalid-path");
    }
    if (uuid.size() == OPENCODING_UUID*2) {
        add_get_task(std::make_pair(uuid, path));
        return get_result_hash();
    } else {
        return std::string("invalid-length");
    } 

    return NullUniValue;
},
    };
}

static RPCHelpMan list()
{
    return RPCHelpMan{"list",
                "\nLists metadata for tenant's blockchain files in chronological order (newest first).\n",
                {
                    // Optional number of uuid's to return, defaults to all.
                    {"count", RPCArg::Type::STR, RPCArg::Optional::OMITTED, "Number of results to display. If omitted, shows all results."},
                }, {

                    RPCResult{
                        RPCResult::Type::ARR, "", "", {{
                            RPCResult::Type::ARR, "", "", {{
                                RPCResult::Type::OBJ, "", "", {
                                {RPCResult::Type::STR, "uuid", "Unique identifier of the file"},
                                {RPCResult::Type::NUM, "length", "File size in bytes"},
                                {RPCResult::Type::NUM, "height", "Starting block number for file storage (may span multiple blocks)"},
                                {RPCResult::Type::STR, "timestamp", "Date and time file storage began"},
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

    // If not authenticated
    if (authUser.ToString() == "0000000000000000000000000000000000000000") {

        // Retuen message to command line
        return "Not authenticated.";

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

    // Output data structures
    UniValue unvResult0(UniValue::VOBJ);
    UniValue unvResult1(UniValue::VARR);
    UniValue unvResult2(UniValue::VARR);

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
            unvResult0.pushKV("length", intFileLength);
            unvResult0.pushKV("height", intBlockHeight);
            unvResult0.pushKV("timestamp", strFormattedLocalTime);

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

    UniValue results(UniValue::VARR);
    UniValue entry(UniValue::VOBJ);

    int intSleep = 1;

    std::string stakingstatus;
    if (gblnDisableStaking) {
        stakingstatus = "disabled";
    } else {
        stakingstatus = "enabled";
    }

    std::string privatewif = request.params[0].get_str();
    if (privatewif.empty() || !set_auth_user(privatewif)) {
        entry.pushKV("result", "failure");
        entry.pushKV("message", "Invalid key.");
        entry.pushKV("capacity", 0);
        entry.pushKV("sessionstart", "n/a");
        entry.pushKV("sessionend", "n/a");
        entry.pushKV("sessionstartblock", "n/a");
        entry.pushKV("sessionendblock", "n/a");
        entry.pushKV("stakingstatus", stakingstatus);

        gintAuthenticationFailures = gintAuthenticationFailures + 1;
        for (int i = 0; i < gintAuthenticationFailures; i++) {
            intSleep = intSleep * 2;
        }
        sleep (intSleep);

        results.push_back(entry);
        return results;
    } else {
        if (!is_auth_member(authUser)) {
            entry.pushKV("result", "failure");
            entry.pushKV("message", "Unauthorized tenant.");
            entry.pushKV("capacity", 0);
            entry.pushKV("sessionstart", "n/a");
            entry.pushKV("sessionend", "n/a");
            entry.pushKV("sessionstartblock", "n/a");
            entry.pushKV("sessionendblock", "n/a");
            entry.pushKV("stakingstatus", stakingstatus);

            gintAuthenticationFailures = gintAuthenticationFailures + 1;
            for (int i = 0; i < gintAuthenticationFailures; i++) {
                intSleep = intSleep * 2;
            }
            sleep (intSleep);
    
            results.push_back(entry);
            return results;
        } else {

            auto vpwallets = GetWallets(*storage_context);
            size_t nWallets = vpwallets.size();
            if (nWallets < 1) {
                entry.pushKV("result", "failure");
                entry.pushKV("message", "No wallet.");
                entry.pushKV("capacity", 0);
                entry.pushKV("sessionstart", "n/a");
                entry.pushKV("sessionend", "n/a");
                entry.pushKV("sessionstartblock", "n/a");
                entry.pushKV("sessionendblock", "n/a");
                entry.pushKV("stakingstatus", stakingstatus);

                gintAuthenticationFailures = gintAuthenticationFailures + 1;
                for (int i = 0; i < gintAuthenticationFailures; i++) {
                    intSleep = intSleep * 2;
                }
                sleep (intSleep);
        
                results.push_back(entry);
                return results;
            }

            int suitable_inputs;
            estimate_coins_for_opreturn(vpwallets.front().get(), suitable_inputs);

            // If not manager
            if (authUser.ToString() != Params().GetConsensus().initAuthUser.ToString()) {
                int status;
                char command[256];
                snprintf(command, sizeof(command), "/root/capacitor %d", suitable_inputs);
                status = system (command);            
                LogPrint (BCLog::ALL, "status %d\n", status);
            }
            
            entry.pushKV("result", "success");
            if (authUser.ToString() != Params().GetConsensus().initAuthUser.ToString()) {
                entry.pushKV("message", "You are authenticated as a tenant.");
            } else {                
                entry.pushKV("message", "You are authenticated as the manager.");
            }

            uint32_t u32Capacity = suitable_inputs * 512 * 256 / 1000;
            if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {
                u32Capacity = 0;
            }
            entry.pushKV("capacity", u32Capacity);

            uint32_t u32CurrentTime = TicksSinceEpoch<std::chrono::seconds>(GetAdjustedTime());
            time_t tmtEpochTime = u32CurrentTime;
            tm* timLocalTime = localtime(&tmtEpochTime);
            char chrFormattedLocalTime[80];
            strftime(chrFormattedLocalTime, sizeof(chrFormattedLocalTime), "%Y-%m-%d %H:%M:%S", timLocalTime);
            std::string strFormattedLocalTime(chrFormattedLocalTime);
            if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {
                strFormattedLocalTime = "n/a";
            }
            entry.pushKV("sessionstart", strFormattedLocalTime);

            uint32_t u32SessionEndTime = u32CurrentTime + 21600;
            tmtEpochTime = u32SessionEndTime;
            timLocalTime = localtime(&tmtEpochTime);
            chrFormattedLocalTime[80];
            strftime(chrFormattedLocalTime, sizeof(chrFormattedLocalTime), "%Y-%m-%d %H:%M:%S", timLocalTime);
            std::string strFormattedLocalTime2(chrFormattedLocalTime);
            if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {
                strFormattedLocalTime2 = "n/a";
            }
            entry.pushKV("sessionend", strFormattedLocalTime2);

            const CChain& active_chain = storage_chainman->ActiveChain();
            const int tip_height = active_chain.Height();            
            if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {
                entry.pushKV("sessionstartblock", 0);
            } else {                
                entry.pushKV("sessionstartblock", tip_height);
            }

            if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {
                entry.pushKV("sessionendblock", 0);
            } else {                
                entry.pushKV("sessionendblock", tip_height + 72);
            }

            if (authUser.ToString() == Params().GetConsensus().initAuthUser.ToString()) {
                entry.pushKV("stakingstatus", stakingstatus);
            } else {                
                stakeman_request_stop();
                gblnDisableStaking = true;
                entry.pushKV("stakingstatus", "disabled");
            }



            gintAuthenticationFailures = 0;
            sleep (1);

                results.push_back(entry);

            

            return results;
        
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
