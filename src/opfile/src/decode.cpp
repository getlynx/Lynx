#include "chunk.h"
#include "protocol.h"
#include "util.h"

#include <storage/auth.h>

#include <logging.h>

#include <key_io.h>

#include <time.h>

#include <iostream>
#include <vector>
#include <cstring>  
#include "crypto/aes.h"
#include "crypto/sha256.h"  

// #define TIMING 1

extern ChainstateManager* storage_chainman;

extern uint32_t authTime;

extern uint160 ghshAuthenticatetenantPubkey;

extern int gintFetchDone;

/*
bool check_chunk_contextual(std::string chunk, int& protocol, int& error_level)
{
    bool valid;
    std::string magic, version;

    // check lynx magic
    get_magic_from_chunk(chunk, magic);
    if (magic != OPENCODING_MAGIC) {
        error_level = ERR_CHUNKMAGIC;
        return false;
    }

    // check version byte
    valid = false;
    get_version_from_chunk(chunk, version);
    for (auto& l : OPENCODING_VERSION) {
        if (version == l) {
            valid = true;
        }
    }

    // bail on unknown protocol types
    if (!valid) {
        error_level = ERR_CHUNKVERSION;
        return false;
    }

    // pass protocol back
    protocol = std::stoul(version, nullptr, 16);

    return true;
}
*/

// Check for chunk data, check for valid protocal, return protocol
bool check_chunk_contextual (std::string chunk, int& protocol, int& error_level, int offset)
{
    bool valid;
    std::string magic, version;

    // Check for chunkdata magic instead of authdata magic
    get_magic_from_chunk (chunk, magic, offset);
    if (magic != OPENCODING_MAGIC) {
        error_level = ERR_CHUNKMAGIC;
        return false;
    }

    // Check version byte
    valid = false;
    get_version_from_chunk (chunk, version, offset);
    for (auto& l : OPENCODING_VERSION) {
        if (version == l) {
            valid = true;
        }
    }

    // Bail on unknown protocol types
    if (!valid) {
        error_level = ERR_CHUNKVERSION;
        return false;
    }

    // pass protocol back
    protocol = std::stoul(version, nullptr, 16);

    return true;
}

//bool is_valid_authchunk(std::string& chunk, int& error_level)
bool is_valid_authchunk (std::string& chunk, int& error_level, int offset)
{
    // extract signature
    std::string signature;
    std::vector<unsigned char> vchsig;
    //get_signature_from_chunk(chunk, signature);
    get_signature_from_chunk (chunk, signature, offset);
    vchsig = ParseHex(signature);

    // calculate hash
    char checkhash[OPENCODING_CHECKSUM*8];
    memset(checkhash, 0, sizeof(checkhash));

//LogPrint (BCLog::ALL, "chunk.c_str() %s\n", chunk.c_str());
//LogPrint (BCLog::ALL, "opdata.c_str() %s\n", opdata.c_str());
//LogPrint (BCLog::ALL, "&opdata.c_str()[6] %s\n", &opdata.c_str()[6]);
//LogPrint (BCLog::ALL, "\n");

    //sha256_hash_hex(chunk.c_str(), checkhash, (OPENCODING_MAGICLEN*2) + (OPENCODING_VERSIONLEN*2) + (OPENCODING_UUID*2) + (OPENCODING_CHUNKLEN*2));
    sha256_hash_hex(&chunk.c_str()[offset], checkhash, (OPENCODING_MAGICLEN*2) + (OPENCODING_VERSIONLEN*2) + (OPENCODING_UUID*2) + (OPENCODING_CHUNKLEN*2));
    checkhash[OPENCODING_CHECKSUM*4] = 0;
    uint256 authhash = uint256S(std::string(checkhash));

    // extract pubkey
    CPubKey pubkey;
    if (!pubkey.RecoverCompact(authhash, vchsig)) {
        error_level = ERR_CHUNKAUTHSIG;
        return false;
    }

    // test pubkey
    uint160 hash160(Hash160(pubkey));

    LogPrint (BCLog::ALL, "pubKey from header chunk signature %s\n", hash160.ToString());
    LogPrint (BCLog::ALL, "\n");

ghshAuthenticatetenantPubkey = hash160;    

// LogPrint (BCLog::ALL, "initAuthTime %d\n", Params().GetConsensus().initAuthTime);

// authTime = Params().GetConsensus().initAuthTime;

// if (!scan_blocks_for_specific_authdata (*storage_chainman, hash160)) {
    // error_level = ERR_CHUNKAUTHUNK;
    // return false;
// }

    // Remove constraint that storeasset tenant be authorized at fetchasset time
    // if (!is_auth_member(hash160)) {
        // error_level = ERR_CHUNKAUTHUNK;
        // return false;
    // }

    return true;
}

bool extract_pubkey_from_signature (std::string& chunk, int offset) {

    std::string signature;
    std::vector<unsigned char> vchsig;

    get_signature_from_chunk (chunk, signature, offset);
    vchsig = ParseHex(signature);

    char checkhash[OPENCODING_CHECKSUM*8];
    memset(checkhash, 0, sizeof(checkhash));

    sha256_hash_hex(&chunk.c_str()[offset], checkhash, (OPENCODING_MAGICLEN*2) + (OPENCODING_VERSIONLEN*2) + (OPENCODING_UUID*2) + (OPENCODING_CHUNKLEN*2));
    checkhash[OPENCODING_CHECKSUM*4] = 0;
    uint256 authhash = uint256S(std::string(checkhash));

    // extract pubkey
    CPubKey pubkey;
    pubkey.RecoverCompact(authhash, vchsig);

    ghshAuthenticatetenantPubkey = Hash160(pubkey);

// ghshAuthenticatetenantPubkey = hash160;    

    return true;

}

//bool build_file_from_chunks(std::pair<std::string, std::string> get_info, int& error_level, int& total_chunks, std::vector<std::string>& encoded_chunks) {
bool build_file_from_chunks(std::pair<std::string, std::string> get_info, int& error_level, int& total_chunks, std::vector<std::string>& encoded_chunks, int offset) {

    clock_t start, end;

    double t_gufc = 0.0;

    double t_gclfc = 0.0;

    double t_gchfc = 0.0;

    double t_gcdfc = 0.0;

    double t_shh = 0.0;

    double t_gcnfc = 0.0;

    double t_gctfc = 0.0;

    double t_bfh = 0.0;

    error_level = NO_ERROR;

    bool lastchunk;
    char checkhash[OPENCODING_CHECKSUM*4];
    unsigned char buffer[OPENCODING_CHUNKMAX*2];
    //int protocol, offset, thischunk, chunknum2, chunklen2, chunktotal2, extskip;
    int protocol, thischunk, chunknum2, chunklen2, chunktotal2, extskip;
    std::string chunklen, uuid, uuid2, chunkhash, checksum, chunknum, chunktotal, chunkdata, filepath;

    //offset = 0;
    extskip = 0;
    protocol = 0;
    thischunk = 1;
    lastchunk = false;
    filepath = strip_trailing_slash(get_info.second) + "/" + get_info.first;

    FILE* in = fopen(filepath.c_str(), "wb");
    if (!in) {
        error_level = ERR_FILEOPEN;
        return false;
    }

    for (auto& chunk : encoded_chunks) {

        // note the last chunk
        if (chunk == encoded_chunks.back()) {
            lastchunk = true;
        }

//    start = clock ();    

        // perform contextual checks
        if (!check_chunk_contextual (chunk, protocol, error_level, offset)) {
            // pass error_level back
            return false;
        }

//    end = clock ();    
//    t_ccc = t_ccc + (double) (end - start) / CLOCKS_PER_SEC;

#ifdef TIMING
    start = clock ();    
#endif

        // ensure uuid is uniform
        get_uuid_from_chunk (chunk, uuid, offset);
        if (uuid2.size() > 0) {
            if (uuid != uuid2) {
                error_level = ERR_CHUNKUUID;
                return false;
            }
        } else {
            uuid2 = uuid;
        }

#ifdef TIMING
    end = clock ();    
    t_gufc = t_gufc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

#ifdef TIMING
    start = clock ();    
#endif

        // ensure chunklen is uniform (besides last chunk)
        //get_chunklen_from_chunk(chunk, chunklen);
        get_chunklen_from_chunk (chunk, chunklen, offset);
        chunklen2 = std::stoul(chunklen, nullptr, 16);

        if (chunklen2 == 0) {
            continue;
        }

        // ... if datachunk
        if (lastchunk == false && (chunklen2 != OPENCODING_CHUNKMAX)) {
            error_level = ERR_CHUNKLEN;
            return false;
        }

#ifdef TIMING
    end = clock ();    
    t_gclfc = t_gclfc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

#ifdef TIMING
    start = clock ();    
#endif

        // test chunkdata hash to calculated chunkdata hash
        get_chunkhash_from_chunk (chunk, chunkhash, offset);

#ifdef TIMING
    end = clock ();    
    t_gchfc = t_gchfc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

#ifdef TIMING
    start = clock ();    
#endif

        get_chunkdata_from_chunk (chunk, chunkdata, chunklen2, offset);

#ifdef TIMING
    end = clock ();    
    t_gcdfc = t_gcdfc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

#ifdef TIMING
    start = clock ();    
#endif

        sha256_hash_hex(chunkdata.c_str(), checkhash, chunklen2*2);
    
        checkhash[OPENCODING_CHECKSUM*2] = 0;
        if (chunkhash != std::string(checkhash)) {
            error_level = ERR_CHUNKHASH;
            return false;
        }

#ifdef TIMING
    end = clock ();    
    t_shh = t_shh + (double) (end - start) / CLOCKS_PER_SEC;
#endif

#ifdef TIMING
    start = clock ();    
#endif

        // check chunknum is uniform
        get_chunknum_from_chunk (chunk, chunknum, offset);
        chunknum2 = std::stoul(chunknum, nullptr, 16);
        if (thischunk != chunknum2) {
            error_level = ERR_CHUNKNUM;
            return false;
        }

#ifdef TIMING
    end = clock ();    
    t_gcnfc = t_gcnfc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

#ifdef TIMING
    start = clock ();    
#endif

        // check chunktotal is correct
        get_chunktotal_from_chunk (chunk, chunktotal, offset);
        chunktotal2 = std::stoul(chunktotal, nullptr, 16);
        if (encoded_chunks.size() != chunktotal2) {
            error_level = ERR_CHUNKTOTAL;
            return false;
        }

#ifdef TIMING
    end = clock ();    
    t_gctfc = t_gctfc + (double) (end - start) / CLOCKS_PER_SEC;
#endif

        // if protocol is 01 and lastchunk is true (extensiondata)
        if (lastchunk == true && protocol == 1) {
            extskip = OPENCODING_EXTENSION;
        }

#ifdef TIMING
    start = clock ();    
#endif

unsigned char buffer2[16];
buffer2[0] = 249;
buffer2[1] = 240;
buffer2[2] = 16; 
buffer2[3] = 149; 
buffer2[4] = 253; 
buffer2[5] = 112; 
buffer2[6] = 118; 
buffer2[7] = 243; 
buffer2[8] = 21; 
buffer2[9] = 63; 
buffer2[10] = 185; 
buffer2[11] = 165; 
buffer2[12] = 55; 
buffer2[13] = 136; 
buffer2[14] = 244; 
buffer2[15] = 124;

// Key (aes-256 rwquires 32-byte key)
unsigned char chrKey[32]; 

// Example key (use a secure key in practice)
memset(chrKey, 0x01, sizeof(chrKey)); 

// Encrypted asset
std::vector<unsigned char> vctEncryptedAsset(16);

// Decrypted asset
std::vector<unsigned char> vctDecyptedAsset(16);

// Create a class instance, and initialize it with a key
AES256Decrypt aes_decrypt(chrKey);

for (int i = 0; i < 16; i++) {
    vctEncryptedAsset[i] = buffer2[i];
}

// Decrypt
for (size_t i = 0; i < vctDecyptedAsset.size(); i += 16) {
    aes_decrypt.Decrypt(&vctDecyptedAsset[i], &vctEncryptedAsset[i]);
}

// Remove padding 
unsigned char chrPadValue = vctDecyptedAsset.back();
vctDecyptedAsset.resize(vctDecyptedAsset.size() - chrPadValue);

// Report decrypted asset
LogPrint (BCLog::ALL, "Decrypted asset \n");
for (size_t i = 0; i < vctDecyptedAsset.size(); ++i) {
    LogPrint (BCLog::ALL, "%s",vctDecyptedAsset[i]);
}
LogPrint (BCLog::ALL, "\n");
LogPrint (BCLog::ALL, "Decrypted asset length %d \n", vctDecyptedAsset.size());
LogPrint (BCLog::ALL, "Decrypted asset position 5 in decimal %d \n", vctDecyptedAsset[4]);
LogPrint (BCLog::ALL, "\n");





        // write to buffer
        binlify_from_hex(&buffer[0], chunkdata.c_str(), chunkdata.size());
        if (!write_partial_stream(in, (char*)buffer, (chunkdata.size() / 2) - extskip)) {
            error_level = ERR_FILEWRITE;
            return false;
        }

#ifdef TIMING
    end = clock ();    
    t_bfh = t_bfh + (double) (end - start) / CLOCKS_PER_SEC;
#endif

        if (debug) {
            printf("\r%d of %d chunks processed (decoding)", thischunk, chunktotal2);
        }

        ++thischunk;
    }

    fclose(in);

    LogPrint (BCLog::ALL, "(build_file_from_chunks)\n");

    //! if protocol 01, rename file with extension
    if (protocol == 1) {

        std::string extension;
        int extoffset = (chunkdata.size() / 2) - extskip;
        for (int extwrite = extoffset; extwrite < extoffset + OPENCODING_EXTENSION; extwrite++) {
            extension += buffer[extwrite];
        }

        LogPrint (BCLog::ALL, "Extension found: %s\n", extension);
        LogPrint (BCLog::ALL, "\n");

        std::string newfilepath = filepath + "." + extension;

        if (std::rename(filepath.c_str(), newfilepath.c_str())) {
            error_level = ERR_EXTENSION;
            return false;
        }
    } else {
        LogPrint (BCLog::ALL, "No extension found.\n");
        LogPrint (BCLog::ALL, "\n");
    }

    if (debug) printf("\n");

#ifdef TIMING
    LogPrint (BCLog::ALL, "elapsed get_uuid_from_chunk %ld \n", t_gufc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed get_chunklen_from_chunk %ld \n", t_gclfc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed get_chunkhash_from_chunk %ld \n", t_gchfc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed get_chunkdata_from_chunk %ld \n", t_gcdfc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed sha256_hash_hex %ld \n", t_shh);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed get_chunknumber_from_chunk %ld \n", t_gcnfc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed get_chunktotal_from_chunk %ld \n", t_gctfc);
    LogPrint (BCLog::ALL, "\n");

    LogPrint (BCLog::ALL, "elapsed binlify_from_hex %ld \n", t_bfh);
    LogPrint (BCLog::ALL, "\n");
#endif

    gintFetchDone = 1;   

    return true;
}
