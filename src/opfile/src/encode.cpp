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



extern int gintStoreAssetEncryptFlag;

extern std::string authUserKey;

extern std::string gstrAssetExtension;

extern std::string gstrAssetFilename;

bool file_to_hexchunks(std::string filepath, int& protocol, int& error_level, int& total_chunks, std::vector<std::string>& data_chunks, unsigned char* key) {

LogPrint (BCLog::ALL, "encrypt from file_to_hexchunks %d \n", gintStoreAssetEncryptFlag);
LogPrint (BCLog::ALL, "\n");

/*
    std::string extension;
    if (extract_file_extension(filepath, extension)) {

        // we detected an extension we can store
        protocol = 1;
    }
*/



    std::string extension;
    extension = gstrAssetExtension;

    if (extension.size() > 0) {

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
    // char* buffer = (char*)malloc(filelenext + 1);

    // Add 16 for, at most, 16 characters of padding.
    char* buffer = (char*)malloc(filelenext + 16 + 1);
    if (!buffer) {
        error_level = ERR_MALLOC;
        free(buffer);
        return false;
    }
    unsigned char* buffer2 = (unsigned char*)malloc(filelenext + 16 + 1);
    if (!buffer2) {
        error_level = ERR_MALLOC;
        free(buffer2);
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

/*

    LogPrint (BCLog::ALL, "Asset in decimal \n");
    for (int i = 0; i < intAssetLength; i++) {
        LogPrint (BCLog::ALL, "%d ", buffer[i]);
    }
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "\n");

*/

    // Report asset length
    LogPrint (BCLog::ALL, "Asset length %d \n", intAssetLength);
    LogPrint (BCLog::ALL, "\n");

    // Asset plaintext
    std::string strAssetPlaintext;

    // Key (aes-256 rwquires 32-byte key)
    // unsigned char chrKey[32]; 

    int intEncryptedAssetSize;

if (gintStoreAssetEncryptFlag == 1) {    

    strAssetPlaintext.reserve(intAssetLength); 

    // Snatch asset
    // for (int i = 0; i < intAssetLength; i++) {
        // strAssetPlaintext = strAssetPlaintext + buffer[i];
    // }

    std::copy(buffer, buffer + intAssetLength, std::back_inserter(strAssetPlaintext));

    LogPrint (BCLog::ALL, "Asset length %d \n", intAssetLength);
    LogPrint (BCLog::ALL, "\n");

/*


    // Report asset plaintext
    LogPrint (BCLog::ALL, "Asset plaintext %s \n", strAssetPlaintext);

    // Report asset plaintext position 5 in decimal
    LogPrint (BCLog::ALL, "Asset plaintext position 5 in decimal %d \n", strAssetPlaintext[4]);

    // Report asset plaintext size
    LogPrint (BCLog::ALL, "Asset plaintext size %d \n", strAssetPlaintext.size());
    LogPrint (BCLog::ALL, "\n");

*/

    // Vectorize asset plaintext
    std::vector<unsigned char> vctAssetPlaintext(strAssetPlaintext.begin(), strAssetPlaintext.end());

    LogPrint (BCLog::ALL, "Asset length %d \n", intAssetLength);
    LogPrint (BCLog::ALL, "\n");





    // IV (Initialization Vector) (aes block size is 16 bytes)
    // unsigned char chrIV[16];  

    // Example key (use a secure key in practice)
    // memset(chrKey, 0x01, sizeof(chrKey)); 

    // Example iv (should be random for each encryption)
    // memset(chrIV, 0x02, sizeof(chrIV));   

    // Pad to a multiple of 16 bytes (aes block size)
    size_t sztPadLength = 16 - (vctAssetPlaintext.size() % 16);
    vctAssetPlaintext.insert(vctAssetPlaintext.end(), sztPadLength, static_cast<unsigned char>(sztPadLength));

    // Encrypted asset
    std::vector<unsigned char> vctEncryptedAsset(vctAssetPlaintext.size());

    // Create a class instance, and initialize it with a key
    AES256Encrypt aes_encrypt(key);

    // Encrypt asset
    for (size_t i = 0; i < vctAssetPlaintext.size(); i += 16) {
        aes_encrypt.Encrypt(&vctEncryptedAsset[i], &vctAssetPlaintext[i]);
    }

    intEncryptedAssetSize = vctAssetPlaintext.size();





/*

// Report encrypted asset in decimal
LogPrint (BCLog::ALL, "Encrypted asset in decimal \n");
for (int i = 0; i < vctEncryptedAsset.size(); i++) {
    LogPrint (BCLog::ALL, "%d ", vctEncryptedAsset[i]);
}
LogPrint (BCLog::ALL, "\n");
LogPrint (BCLog::ALL, "\n");

*/

// Encrypted asset size
filelenext = vctEncryptedAsset.size();

// Report encrypted asset size
LogPrint (BCLog::ALL, "Encrypted asset size %d \n", vctEncryptedAsset.size());
LogPrint (BCLog::ALL, "\n");

// Extensiom
filelenext += (protocol == 1 ? OPENCODING_EXTENSION : 0);





// encrypted asset
// unsigned char* buffer2 = (unsigned char*)malloc(filelenext2 + 1);

// Snatch encrypted asset
for (int i = 0; i < vctEncryptedAsset.size(); i++) {
    buffer2[i] = vctEncryptedAsset[i];
}

LogPrint (BCLog::ALL, "Encrypted asset size %d \n", vctEncryptedAsset.size());
LogPrint (BCLog::ALL, "\n");

/*

// Report snatched encrypted asset in decimal
LogPrint (BCLog::ALL, "Snatched encrypted asset in decimal \n");
for (int i = 0; i < vctEncryptedAsset.size(); i++) {
    LogPrint (BCLog::ALL, "%d ", buffer2[i]);
}
LogPrint (BCLog::ALL, "\n");
LogPrint (BCLog::ALL, "\n");

*/





// Extension
if (protocol == 1) {
    for (int i = 0; i < 4; i++) {
        buffer2[vctEncryptedAsset.size() + i] = extension[i];
    }
    // sprintf(buffer2+vctEncryptedAsset.size(), "%s", extension.c_str());
}

/*

// Report snatched encrypted asset
LogPrint (BCLog::ALL, "Snatched encrypted asset \n");
for (int i = 0; i < filelenext; i++) {
    LogPrint (BCLog::ALL, "%02x", buffer2[i]);
}
LogPrint (BCLog::ALL, "\n");
LogPrint (BCLog::ALL, "\n");

*/

// Report snatched extension in decimal
if (protocol == 1) {
    LogPrint (BCLog::ALL, "Snatched extension in decimal \n");
    for (int i = 0; i < 4; i++) {
        LogPrint (BCLog::ALL, "%d ", buffer2[vctEncryptedAsset.size()+i]);
    }
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "\n");
}





/*

    // Report encrypted asset
    LogPrint (BCLog::ALL, "Encrypted asset \n");
    for (unsigned char c : vctEncryptedAsset) {
        LogPrint (BCLog::ALL, "%02x", c);
    }
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "\n");

*/

    // Decrypted asset
    std::vector<unsigned char> vctDecyptedAsset(vctEncryptedAsset.size());

    // Create a class instance, and initialize it with a key
    AES256Decrypt aes_decrypt(key);

    // Decrypt
    for (size_t i = 0; i < vctEncryptedAsset.size(); i += 16) {
        aes_decrypt.Decrypt(&vctDecyptedAsset[i], &vctEncryptedAsset[i]);
    }

    LogPrint (BCLog::ALL, "Encrypted asset size %d \n", vctEncryptedAsset.size());
    LogPrint (BCLog::ALL, "\n");
    
    // Remove padding 
    unsigned char chrPadValue = vctDecyptedAsset.back();
    vctDecyptedAsset.resize(vctDecyptedAsset.size() - chrPadValue);

/*

    // Report decrypted asset
    LogPrint (BCLog::ALL, "Decrypted asset in decumal \n");
    for (size_t i = 0; i < vctDecyptedAsset.size(); ++i) {
        LogPrint (BCLog::ALL, "%d ",vctDecyptedAsset[i]);
    }
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "Decrypted asset length %d \n", vctDecyptedAsset.size());
    LogPrint (BCLog::ALL, "Decrypted asset position 5 in decimal %d \n", vctDecyptedAsset[4]);
    LogPrint (BCLog::ALL, "\n");

*/

}





if (gintStoreAssetEncryptFlag == 0) {

    // protocol 01 appends 4 byte extension to filestream
    if (protocol == 1) {

        sprintf(buffer+filelen, "%s", extension.c_str());

    }

}





/*

// Report asset in decimal
LogPrint (BCLog::ALL, "Asset in decimal \n");
if (gintStoreAssetEncryptFlag == 0) {
    for (int i = 0; i < filelen; i++) {
        LogPrint (BCLog::ALL, "%d ", buffer[i]);
    }
} else {
    for (int i = 0; i <  intEncryptedAssetSize; i++) {
        LogPrint (BCLog::ALL, "%d ", buffer2[i]);
    }
}
LogPrint (BCLog::ALL, "\n");
LogPrint (BCLog::ALL, "\n");

*/

// Report extension in decimal
if (protocol == 1) {
    LogPrint (BCLog::ALL, "Extension in decimal \n");
    for (int i = 0; i < 4; i++) {
        if (gintStoreAssetEncryptFlag == 0) {
            LogPrint (BCLog::ALL, "%d ", buffer[filelen+i]);
        } else {
            LogPrint (BCLog::ALL, "%d ", buffer2[intEncryptedAssetSize+i]);
        }
    }
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "\n");
}





    int chunk = 0;
    // while (chunk * OPENCODING_CHUNKMAX < filelenext) {
    while (chunk * OPENCODING_CHUNKMAX < filelenext) {

        std::stringstream chunk_split;
        for (unsigned int i = (chunk * OPENCODING_CHUNKMAX); i < ((chunk + 1) * OPENCODING_CHUNKMAX); i++) {

            // if (i >= filelenext) {
            if (i >= filelenext) {
                    break;
            }

            unsigned char byte;
            // unsigned char byte = *(buffer + i);
            if (gintStoreAssetEncryptFlag == 0) {
                byte = *(buffer + i);
            } else {
                byte = *(buffer2 + i);
            }
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
    free(buffer2);

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

    // filepath = putinfo.first;
    filepath = gstrAssetFilename;
    customuuid = putinfo.second;

    validcustom = customuuid.size() == OPENCODING_UUID*2;



    std::string uuid = validcustom ? customuuid : generate_uuid(OPENCODING_UUID);

    LogPrint (BCLog::ALL, "uuid %s \n", uuid);
    LogPrint (BCLog::ALL, "\n");

    unsigned char key[32];

    for (size_t i = 0; i < 32; i++) {
        unsigned int byteValue;
        std::stringstream(uuid.substr(i * 2, 2)) >> std::hex >> byteValue;
        key[i] = static_cast<unsigned char>(byteValue);
    }

    LogPrint (BCLog::ALL, "key \n");
    for (int i = 0; i < 32; i++) {
        LogPrint (BCLog::ALL, "%d ", key[i]);
    }
    LogPrint (BCLog::ALL, "\n");
    LogPrint (BCLog::ALL, "\n");



    //! start off using protocol 00, unless we detect an extension
    protocol = 0;

    if (!file_to_hexchunks(filepath, protocol, error_level, total_chunks, data_chunks, key)) {

        // pass error_level through
        return false;
    }

    std::string strProtocol = "00";
    if ((protocol == 1) && (gintStoreAssetEncryptFlag == 0)) {
        strProtocol = "01";
    }
    if ((protocol == 0) && (gintStoreAssetEncryptFlag == 1)) {
        strProtocol = "02";
    }
    if ((protocol == 1) && (gintStoreAssetEncryptFlag == 1)) {
        strProtocol = "03";
    }

    header = OPENCODING_MAGIC;
    // header += protocol == 1 ? OPENCODING_VERSION[1] : OPENCODING_VERSION[0];
    header += strProtocol;
    // header += validcustom ? customuuid : generate_uuid(OPENCODING_UUID);
    header += uuid;

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

/*

        LogPrint (BCLog::ALL, "%s\n", data_chunk);

*/

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

