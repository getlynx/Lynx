#include <iomanip>

#include <logging.h>

#include "protocol.h"
#include "util.h"

#include <key_io.h>

#include <iostream>
#include <vector>
#include <cstring>  
#include "crypto/aes.h"
#include "crypto/sha256.h"  



extern std::string authUserKey;

bool file_to_hexchunks(std::string filepath, int& protocol, int& error_level, int& total_chunks, std::vector<std::string>& data_chunks) {

    std::string extension;
    if (extract_file_extension(filepath, extension)) {

        // we detected an extension we can store
        protocol = 1;
    }

    int filelen = read_file_size(filepath);
    if (filelen < 0) {
        error_level = ERR_FILESZ;
        return false;
    }

    // an inflated filelen (with extension bytes added)
    int filelenext = filelen;
    filelenext += (protocol == 1 ? OPENCODING_EXTENSION : 0);

    int estchunks = calculate_chunks_from_filesize(filelenext);
    // char* buffer = (char*)malloc(filelenext);
    char* buffer = (char*)malloc(filelenext + 1);
    if (!buffer) {
        error_level = ERR_MALLOC;
        free(buffer);
        return false;
    }

    if (!read_file_stream(filepath, buffer, filelen)) {
        error_level = ERR_FILEREAD;
        free(buffer);
        return false;
    }



    

    // Set asset length
    int intAssetLength = filelen;

    // Report asset in decimal
    LogPrint (BCLog::ALL, "Asset in decimal \n");
    for (int i = 0; i < intAssetLength; i++) {
        LogPrint (BCLog::ALL, "%d", buffer[i]);
    }
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "\n");

    // Report asset length
    LogPrint (BCLog::ALL, "Asset length %d \n", intAssetLength);
    LogPrint (BCLog::ALL, "\n");

    // Asset plaintext
    std::string strAssetPlaintext;

    // Snatch asset
    for (int i = 0; i < intAssetLength; i++) {
        strAssetPlaintext = strAssetPlaintext + buffer[i];
    }

    // Report asset plaintext
    LogPrint (BCLog::ALL, "Asset plaintext %s \n", strAssetPlaintext);

    // Report asset plaintext position 5 in decimal
    LogPrint (BCLog::ALL, "Asset plaintext position 5 in decimal %d \n", strAssetPlaintext[4]);

    // Report asset plaintext size
    LogPrint (BCLog::ALL, "Asset plaintext size %d \n", strAssetPlaintext.size());
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "\n");





    // Key (aes-256 rwquires 32-byte key)
    unsigned char key[32]; 

    // Prepare the IV (Initialization Vector) (aes block size is 16 bytes)
    unsigned char iv[16];  

    // Example key (use a secure key in practice)
    memset(key, 0x01, sizeof(key)); 

    // Example iv (should be random for each encryption)
    memset(iv, 0x02, sizeof(iv));   

    // Set plaintext
    // std::string plaintext = "Hello, Bitcoin AES Encryption!";

    // Report
    LogPrint (BCLog::ALL, "%s \n", strAssetPlaintext);

    // Vectorize
    std::vector<unsigned char> input(strAssetPlaintext.begin(), strAssetPlaintext.end());

    // Pad to a multiple of 16 bytes (aes block size)
    size_t pad_len = 16 - (input.size() % 16);
    input.insert(input.end(), pad_len, static_cast<unsigned char>(pad_len));

    // Encrypted output
    std::vector<unsigned char> encrypted(input.size());

    // Create a class instance, and initialize it with a key and a key size
    AES256Encrypt aes_encrypt(key);

    // Encrypt input
    for (size_t i = 0; i < input.size(); i += 16) {
        aes_encrypt.Encrypt(&encrypted[i], &input[i]);
    }

    // Report encrypted output
    // std::cout << "Encrypted Data: ";
    // print_hex(encrypted);
    for (unsigned char c : encrypted) {
        // printf("%02x", c);
        LogPrint (BCLog::ALL, "%02x", c);
    }
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "\n");
    

    // Decrypted output
    std::vector<unsigned char> decrypted(encrypted.size());

    // Create a class instance, and initialize it with a key
    AES256Decrypt aes_decrypt(key);

    // Decrypt
    for (size_t i = 0; i < encrypted.size(); i += 16) {
        aes_decrypt.Decrypt(&decrypted[i], &encrypted[i]);
    }

    // Remove padding 
    unsigned char pad_value = decrypted.back();
    decrypted.resize(decrypted.size() - pad_value);

    for (size_t i = 0; i < decrypted.size(); ++i) {
        LogPrint (BCLog::ALL, "%s",decrypted[i]);
        // printf("%u ", decrypted[i]);  // Print as unsigned int
    }
    LogPrint (BCLog::ALL, "%d \n", decrypted.size());
    LogPrint (BCLog::ALL, "%d \n", decrypted.size());
    LogPrint (BCLog::ALL, "%d \n", decrypted[4]);
    // printf("\n");





    // protocol 01 appends 4 byte extension to filestream
    if (protocol == 1) {

        sprintf(buffer+filelen, "%s", extension.c_str());

    }

    int chunk = 0;
    while (chunk * OPENCODING_CHUNKMAX < filelenext) {

        std::stringstream chunk_split;
        for (unsigned int i = (chunk * OPENCODING_CHUNKMAX); i < ((chunk + 1) * OPENCODING_CHUNKMAX); i++) {

            if (i >= filelenext) {
                break;
            }

            unsigned char byte = *(buffer + i);
            chunk_split << std::hex << std::setfill('0') << std::setw(2) << std::nouppercase << (int)byte;
        }

        data_chunks.push_back(chunk_split.str());
        chunk_split.clear();
        chunk++;

        if (debug) {
            printf("\r%d of %d chunks processed (parsing)", chunk, estchunks);
        }
    }

    total_chunks = chunk;
    free(buffer);

    if (debug) printf("\n");

    return true;
}

//bool build_chunks_auth_header(std::string header, std::vector<std::string>& encoded_chunks) {
bool build_chunks_auth_header(std::string header, std::vector<std::string>& encoded_chunks, int& error_level) {

    // we use chunknum 0 to store the authdata, signified by chunklen 0
    std::string authheader = header;
    authheader += "0000";

    char checkhash[OPENCODING_CHECKSUM*8];
    memset(checkhash, 0, sizeof(checkhash));
    sha256_hash_hex(authheader.c_str(), checkhash, authheader.size());
    checkhash[OPENCODING_CHECKSUM*4] = 0;

    CKey key = DecodeSecret(authUserKey);
    if (!key.IsValid()) {
        error_level = ERR_NOAUTHENTICATION;
        return false;
    }

    std::vector<unsigned char> signature;
    uint256 authhash = uint256S(std::string(checkhash));
    if (!key.SignCompact(authhash, signature)) {
        //error_level = ERR_BADSIG;
        return false;
    }

    authheader += HexStr(signature);

    LogPrint (BCLog::ALL, "HEADER CHUNK\n");
    LogPrint (BCLog::ALL, "magic protocol uuid chunk_length magic-protocol-uuid-chunk_length-hashed-signed\n");
    LogPrint (BCLog::ALL, "%s %s %s %s %s\n",
      authheader.substr( 0, OPENCODING_MAGICLEN*2),
      authheader.substr( OPENCODING_MAGICLEN*2, OPENCODING_VERSIONLEN*2),
      authheader.substr(OPENCODING_MAGICLEN*2+OPENCODING_VERSIONLEN*2, OPENCODING_UUID*2),
      authheader.substr(OPENCODING_MAGICLEN*2+OPENCODING_VERSIONLEN*2+OPENCODING_UUID*2, OPENCODING_CHUNKLEN*2),
      authheader.substr(OPENCODING_MAGICLEN*2+OPENCODING_VERSIONLEN*2+OPENCODING_UUID*2+OPENCODING_CHUNKLEN*2, header.length()-OPENCODING_MAGICLEN*2+OPENCODING_VERSIONLEN*2+OPENCODING_UUID*2+OPENCODING_CHUNKLEN*2));

    encoded_chunks.push_back(authheader);

    return true;
}

bool build_chunks_with_headers(std::pair<std::string, std::string>& putinfo, int& error_level, int& total_chunks, std::vector<std::string>& encoded_chunks) {

    int protocol;
    bool validcustom;
    std::vector<std::string> data_chunks;
    std::string authheader, header, header2, encoded_chunk, filepath, customuuid;

    filepath = putinfo.first;
    customuuid = putinfo.second;

    validcustom = customuuid.size() == OPENCODING_UUID*2;

    //! start off using protocol 00, unless we detect an extension
    protocol = 0;

    if (!file_to_hexchunks(filepath, protocol, error_level, total_chunks, data_chunks)) {

        // pass error_level through
        return false;
    }

    header = OPENCODING_MAGIC;
    header += protocol == 1 ? OPENCODING_VERSION[1] : OPENCODING_VERSION[0];
    header += validcustom ? customuuid : generate_uuid(OPENCODING_UUID);

    //if (!build_chunks_auth_header(header, encoded_chunks)) {
    if (!build_chunks_auth_header(header, encoded_chunks, error_level)) {
	    
        return false;
    }

    int chunknum = 1;
    for (auto& data_chunk : data_chunks) {

        int chunklen = data_chunk.size() / 2;
        header2 = get_len_as_hex(chunklen, OPENCODING_CHUNKLEN);

        char checkhash[OPENCODING_CHECKSUM*4];
        memset(checkhash, 0, sizeof(checkhash));
        sha256_hash_hex(data_chunk.c_str(), checkhash, data_chunk.size());

        checkhash[OPENCODING_CHECKSUM*2] = 0;

        header2 += std::string(checkhash);

        header2 += get_len_as_hex(chunknum, OPENCODING_CHUNKNUM);

        header2 += get_len_as_hex(total_chunks, OPENCODING_CHUNKTOTAL);

        LogPrint (BCLog::ALL, "\n");
        LogPrint (BCLog::ALL, "DATA CHUNK %d\n", chunknum);
        LogPrint (BCLog::ALL, "magic protocol uuid\n");
        LogPrint (BCLog::ALL, "%s %s %s\n",
          header.substr( 0, OPENCODING_MAGICLEN*2),
          header.substr( OPENCODING_MAGICLEN*2, OPENCODING_VERSIONLEN*2),
          header.substr( OPENCODING_MAGICLEN*2+OPENCODING_VERSIONLEN*2, OPENCODING_UUID*2));

        LogPrint (BCLog::ALL, "\n");
        LogPrint (BCLog::ALL, "length data_hash chunk_number total_chunks\n");
        LogPrint (BCLog::ALL, "%s %s %s %s\n",
          header2.substr( 0, OPENCODING_CHUNKLEN*2),
          header2.substr( OPENCODING_CHUNKLEN*2, OPENCODING_CHECKSUM*2),
          header2.substr( OPENCODING_CHUNKLEN*2+OPENCODING_CHECKSUM*2, OPENCODING_CHUNKNUM*2),
          header2.substr( OPENCODING_CHUNKLEN*2+OPENCODING_CHECKSUM*2+OPENCODING_CHUNKNUM*2, OPENCODING_CHUNKTOTAL*2));

        LogPrint (BCLog::ALL, "\n");
        LogPrint (BCLog::ALL, "data\n");
        LogPrint (BCLog::ALL, "%s\n", data_chunk);

        encoded_chunk = header + header2 + data_chunk;
        encoded_chunks.push_back(encoded_chunk);

        if (debug) {
            printf("\r%d of %d chunks processed (encoding)", chunknum, total_chunks);
        }

        ++chunknum;
    }

    if (debug) printf("\n");

    return true;
}

