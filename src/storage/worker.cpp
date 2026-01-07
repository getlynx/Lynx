// Copyright (c) 2023 Lynx Core Developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <time.h>

#include <opfile/src/decode.h>
#include <opfile/src/encode.h>
#include <opfile/src/protocol.h>
#include <opfile/src/util.h>
#include <storage/storage.h>
#include <storage/worker.h>

int workerStatus;
RecursiveMutex workQueueLock, workResultLock;

std::vector<std::pair<std::string, std::string>> workQueuePut;
std::vector<std::pair<std::string, std::string>> workQueueGet;
std::vector<std::pair<std::string, std::string>> workQueueResult;

extern ChainstateManager* storage_chainman;
extern wallet::WalletContext* storage_context;

extern int gintFetchDone;

extern std::string gstrAssetFilename;

extern int gintJSONAssetStore;

extern std::string gstrJSONAssetStoreCharacters;

void add_put_task(std::string put_info, std::string put_uuid)
{
    LOCK(workQueueLock);
    add_result_entry();
    workQueuePut.push_back(std::make_pair(put_info, put_uuid));
}

void add_get_task(std::pair<std::string, std::string> get_info)
{
    LOCK(workQueueLock);
    add_result_entry();
    workQueueGet.push_back(get_info);
}

void add_result_entry()
{
    LOCK(workResultLock);
    workQueueResult.push_back(std::pair(generate_uuid(8), std::string("")));
}

std::string get_result_hash()
{
    LOCK(workResultLock);
    return workQueueResult.back().first;
}

void add_result_text(std::string& result)
{
    LOCK(workResultLock);
    workQueueResult.back().second = result;
}

void get_storage_worker_status(int& status)
{
    LOCK(workQueueLock);
    status = workerStatus;
}

void set_storage_worker_status(int status)
{
    LOCK(workQueueLock);
    workerStatus = status;
}

void perform_put_task(std::pair<std::string, std::string>& put_info, int& error_level)
{
    // get wallet handle
    auto vpwallets = GetWallets(*storage_context);
    size_t nWallets = vpwallets.size();
    if (nWallets < 1) {
        error_level = ERR_NOWALLET;
        return;
    }

    // see if there are enough inputs
    int usable_inputs;
    // int filelen = read_file_size(put_info.first);
    int filelen;

LogPrint (BCLog::STORAGE, "json 3 \n");

    if (gintJSONAssetStore == 0) {
        filelen = read_file_size(gstrAssetFilename);
    } else {
        filelen = gstrJSONAssetStoreCharacters.size();
    }

LogPrint (BCLog::STORAGE, "json 4 %d \n", filelen);

    // check file length
    int maxfilelength = 25 * 1024 * 1024;
    if (filelen > maxfilelength) {
        LogPrint (BCLog::STORAGE, "File length exceeds max file length. filelen: %d maxfilelength: %d\n", filelen, maxfilelength);
        error_level = ERR_FILELENGTH;
        return;
    }

    int est_chunks = calculate_chunks_from_filesize(filelen);
    estimate_coins_for_opreturn(vpwallets.front().get(), usable_inputs);

    LogPrint (BCLog::STORAGE, "File length: %d\n", filelen);
    LogPrint (BCLog::STORAGE, "\n");

    LogPrint (BCLog::STORAGE, "Number of chunks per transactuion: %d\n", OPRETURN_PER_TX);
    LogPrint (BCLog::STORAGE, "\n");

    LogPrint (BCLog::STORAGE, "Number of groups of %d chunks %d\n", OPRETURN_PER_TX, (est_chunks+(OPRETURN_PER_TX-1))/OPRETURN_PER_TX);
    LogPrint (BCLog::STORAGE, "\n");

    // one usable input per batch of 256 chunks
    if (usable_inputs < ((est_chunks+(OPRETURN_PER_TX-1))/OPRETURN_PER_TX)) {
        error_level = ERR_LOWINPUTS;
        return;
    }

LogPrint (BCLog::STORAGE, "json 5 \n");

    // build chunks from file
    int total_chunks;
    std::vector<std::string> encoded_chunks;
    if (!build_chunks_with_headers(put_info, error_level, total_chunks, encoded_chunks)) {
        //pass error_level back
        return;
    }

LogPrint (BCLog::STORAGE, "json 6 \n");

//LogPrintf ("harness return\n");
//error_level = ERR_LOWINPUTS;
//return;    

    LogPrint (BCLog::STORAGE, "\n");
    LogPrint (BCLog::STORAGE, "CREATE AND SUBMIT CHUNK TRANSACTIONS (perform_put_task)\n");
    LogPrint (BCLog::STORAGE, "For each group of 256 chunks, there will be one putfile transaction\n");
    LogPrint (BCLog::STORAGE, "For each putfile transaction, there will be one input, used to pay for the transaction.\n");
    LogPrint (BCLog::STORAGE, "For each putfile transaction, the first output will be the change from the input.\n");
    LogPrint (BCLog::STORAGE, "The change from the input is the value of the input minus the cost of chunk storage.\n");
    LogPrint (BCLog::STORAGE, "The cost of chunk storage is one satoshi per byte of transaction.\n");
    LogPrint (BCLog::STORAGE, "For each putfile transaction, there will be one output per chunk.\n");
    LogPrint (BCLog::STORAGE, "A chunk output output-script is the chunk prepended with 106 as a single byte.\n");
    LogPrint (BCLog::STORAGE, "Chunk outputs have a value of zero satoshis\n");
    LogPrint (BCLog::STORAGE, "\n");
    LogPrint (BCLog::STORAGE, "For each putfile transaction, the value of the input is given.\n");
    LogPrint (BCLog::STORAGE, "Next, the number of transaction bytes is given.\n");
    LogPrint (BCLog::STORAGE, "Next, the number of satoshis used to pay for the storage is given.\n");
    LogPrint (BCLog::STORAGE, "Finally, the amount of change from the input is given.\n");
    LogPrint (BCLog::STORAGE, "\n");

    // create tx, sign and submit for each chunk
    CMutableTransaction txChunk;
    std::vector<std::string> batch_chunks;
    if (encoded_chunks.size() <= OPRETURN_PER_TX) {
        batch_chunks = encoded_chunks;
        if (!generate_selfsend_transaction(*storage_context, txChunk, batch_chunks)) {
            error_level = ERR_TXGENERATE;
            return;
        }
        return;
    } else {
        for (auto &l : encoded_chunks) {
             batch_chunks.push_back(l);
             if (batch_chunks.size() == OPRETURN_PER_TX) {
                 if (!generate_selfsend_transaction(*storage_context, txChunk, batch_chunks)) {
                     error_level = ERR_TXGENERATE;
                     return;
                 }
                 batch_chunks.clear();
                 txChunk = CMutableTransaction();
             }
        }

        // when the number of chunks is evenly divisible by the nummber of chunks 
        // per transaction, this final transaction is unnecessary
        if (batch_chunks.size() > 0) {
            txChunk = CMutableTransaction();
            if (!generate_selfsend_transaction(*storage_context, txChunk, batch_chunks)) {
                error_level = ERR_TXGENERATE;
                return;
            }
            batch_chunks.clear();
        }    
    }
}

void perform_get_task(std::pair<std::string, std::string> get_info, int& error_level)
{

    LogPrint (BCLog::STORAGE, "\n");
    LogPrint (BCLog::STORAGE, "FETCHASSET (perform_get_task)\n");
    LogPrint (BCLog::STORAGE, "\n");
    LogPrint (BCLog::STORAGE, "fetchasset does two things:\n");
    LogPrint (BCLog::STORAGE, "1) Scan blockchain for chunks given uuid.\n");
    LogPrint (BCLog::STORAGE, "The chunks are placed in order, regardless of blockchain chunk order.\n");
    LogPrint (BCLog::STORAGE, "(scan_blocks_for_specific_uuid)\n");
    LogPrint (BCLog::STORAGE, "2) Store file on disc.\n");
    LogPrint (BCLog::STORAGE, "The filename will be the uuid, and will be created in the given path.\n");
    LogPrint (BCLog::STORAGE, "(build_file_from_chunks)\n");
    LogPrint (BCLog::STORAGE, "\n");
    LogPrint (BCLog::STORAGE, "uuid: %s\n", get_info.first);
    LogPrint (BCLog::STORAGE, "path: %s\n", get_info.second);
    LogPrint (BCLog::STORAGE, "\n");
    //LogPrint (BCLog::STORAGE, "\n");
    //LogPrint (BCLog::STORAGE, "\n");

    clock_t start, end;
    double build_time_taken, scan_time_taken;

    start = clock ();    

    int offset;

    std::vector<std::string> chunks;
    if (!scan_blocks_for_specific_uuid(*storage_chainman, get_info.first, error_level, chunks, offset)) {

        gintFetchDone = 1;

        return;
    }

    end = clock ();    
    scan_time_taken = (double) (end - start) / CLOCKS_PER_SEC;

    start = clock ();    

    int total_chunks = chunks.size();
    if (!build_file_from_chunks (get_info, error_level, total_chunks, chunks, offset)) {

        gintFetchDone = 1;

        return;
    }

    end = clock ();    
    build_time_taken = (double) (end - start) / CLOCKS_PER_SEC;

    // LogPrint (BCLog::STORAGE, "elapsed time perform_get_task scan %ld build %ld\n", scan_time_taken, build_time_taken);

    LogPrint (BCLog::STORAGE, "elapsed time perform_get_task scan %f build %f\n", scan_time_taken, build_time_taken);

}

void thread_storage_worker()
{
    
    const char* error_level_string[] = {
    
     "NO_ERROR",
     //internal
     "ERR_FILESZ",
     "ERR_MALLOC",
     //encoding
     "ERR_CHUNKMAGIC",
     "ERR_CHUNKVERSION",
     "ERR_CHUNKUUID",
     "ERR_CHUNKLEN",
     "ERR_CHUNKHASH",
     "ERR_CHUNKNUM",
     "ERR_CHUNKTOTAL",
     "ERR_CHUNKFAIL",
     //fileop
     "ERR_FILEOPEN",
     "ERR_FILEREAD",
     "ERR_FILEWRITE",
     //wallet
     "ERR_NOAUTHENTICATION",
     "ERR_BADSIG",
     "ERR_NOWALLET",
     "ERR_LOWINPUTS",
     "ERR_TXGENERATE",
     "ERR_FILELENGTH",
     //auth
     "ERR_CHUNKAUTHNONE",
     "ERR_NOTALLDATACHUNKS",
     "ERR_CHUNKAUTHSIG",
     "ERR_CHUNKAUTHUNK",
     //feature
     "ERR_EXTENSION"
    
    };

    int error_level;
    set_storage_worker_status(WORKER_IDLE);

    while (!ShutdownRequested()) {

        UninterruptibleSleep(500ms);

        // check queues under lock
        int putqueue_sz, getqueue_sz;
        {
            LOCK(workQueueLock);
            putqueue_sz = workQueuePut.size();
            getqueue_sz = workQueueGet.size();
        }

        // buffer for sprintf result
        char buffer[128];
        // char buffer[1024];
        memset(buffer, 0, sizeof(buffer));

        // perform putqueue tasks
        if (putqueue_sz > 0) {
            std::pair<std::string, std::string> putTask;
            error_level = NO_ERROR;
            set_storage_worker_status(WORKER_BUSY);
            {
                LOCK(workQueueLock);
                putTask = workQueuePut.back();
            }
            perform_put_task(putTask, error_level);
            if (error_level != NO_ERROR) {
                //sprintf(buffer, "putTask %s had error_level %d", putTask.first.c_str(), error_level);
                sprintf(buffer, "putTask %s had error_level %s", putTask.first.c_str(), error_level_string[error_level]);
                std::string stringbuf = std::string(buffer);
                add_result_text(stringbuf);
            } else {
                //sprintf(buffer, "putTask %s completed successfully", putTask.first.c_str());
                sprintf(buffer, "putTask %s %s completed successfully", putTask.first.c_str(), putTask.second.c_str());
                std::string stringbuf = std::string(buffer);
                add_result_text(stringbuf);
            }
            {
                LOCK(workQueueLock);
                workQueuePut.pop_back();
            }
            set_storage_worker_status(WORKER_IDLE);
        }

        // perform getqueue tasks
        if (getqueue_sz > 0) {
            std::pair<std::string, std::string> getTask;
            error_level = NO_ERROR;
            set_storage_worker_status(WORKER_BUSY);
            {
                LOCK(workQueueLock);
                getTask = workQueueGet.back();
            }
            perform_get_task(getTask, error_level);

            if (error_level != NO_ERROR) {

                sprintf(buffer, "getTask %s, %s had error_level %s", getTask.first.c_str(), getTask.second.c_str(), error_level_string[error_level]);
                std::string stringbuf = std::string(buffer);
                add_result_text(stringbuf);
            } else {

                // sprintf(buffer, "getTask %s, %s completed successfully", getTask.first.c_str(), getTask.second.c_str());

                // std::string stringbuf = std::string(buffer);

                std::string stringbuf = "getTask " + getTask.first + ", " + getTask.second + " completed successfully";

                add_result_text(stringbuf);

            }

            {
                LOCK(workQueueLock);
                workQueueGet.pop_back();
            }

            set_storage_worker_status(WORKER_IDLE);

        }

        if (ShutdownRequested()) {
            return;
        }
    }
}
