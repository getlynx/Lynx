#ifndef CHUNK_H
#define CHUNK_H

#include <string>
#include <vector>

// void get_magic_from_chunk(std::string chunk, std::string& magic);
void get_magic_from_chunk (std::string chunk, std::string& magic, int offset);

// void get_version_from_chunk(std::string chunk, std::string& version);
void get_version_from_chunk (std::string chunk, std::string& version, int offset);

// void get_uuid_from_chunk(std::string chunk, std::string& uuid);
void get_uuid_from_chunk (std::string chunk, std::string& uuid, int offset);

// void get_chunklen_from_chunk(std::string chunk, std::string& chunklen);
void get_chunklen_from_chunk (std::string chunk, std::string& chunklen, int offset);

// void get_signature_from_chunk(std::string chunk, std::string& signature);
void get_signature_from_chunk (std::string chunk, std::string& signature, int offset);

// void get_chunkhash_from_chunk(std::string chunk, std::string& chunkhash);
void get_chunkhash_from_chunk (std::string chunk, std::string& chunkhash, int offset);

// void get_chunknum_from_chunk(std::string chunk, std::string& chunknum);
void get_chunknum_from_chunk (std::string chunk, std::string& chunknum, int offset);

// void get_chunktotal_from_chunk(std::string chunk, std::string& chunktotal);
void get_chunktotal_from_chunk (std::string chunk, std::string& chunktotal, int offset);

void get_chunkdata_from_chunk(std::string chunk, std::string& chunkdata);

// void get_chunkdata_from_chunk(std::string chunk, std::string& chunkdata, int chunkdata_sz);
void get_chunkdata_from_chunk (std::string chunk, std::string& chunkdata, int chunkdata_sz, int offset);

#endif // CHUNK_H
