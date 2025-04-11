// Copyright (c) 2023 Lynx Core Developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef BITCOIN_STORAGE_AUTH_H
#define BITCOIN_STORAGE_AUTH_H

#include <key.h>
#include <key_io.h>

#include <opfile/src/decode.h>
#include <opfile/src/encode.h>
#include <opfile/src/protocol.h>
#include <opfile/src/util.h>
#include <storage/storage.h>
#include <storage/worker.h>

void add_auth_member(uint160 pubkeyhash);
void add_blockuuid_member(std::string uuid);
void add_blocktenant_member(std::string uuid);
void remove_auth_member(uint160 pubkeyhash);
void remove_blockuuid_member(std::string uuid);
void remove_blocktenant_member(std::string uuid);
void build_auth_list(const Consensus::Params& params);
void build_blockuuid_list(const Consensus::Params& params);
void build_blocktenant_list(const Consensus::Params& params);
bool is_auth_member(uint160 pubkeyhash);
bool is_blockuuid_member(std::string uuid);
bool set_auth_user(std::string& privatewif);
void copy_auth_list(std::vector<uint160>& tempList);
void copy_blockuuid_list(std::vector<std::string>& tempList);
void copy_blocktenant_list(std::vector<std::string>& tempList);
// bool is_signature_valid_chunk(std::string chunk);
bool is_signature_valid_chunk (std::string chunk, int pintOffset);
bool is_blockuuid_signature_valid_chunk (std::string chunk, int pintOffset);
bool is_blocktenant_signature_valid_chunk (std::string chunk, int pintOffset);
bool is_signature_valid_raw(std::vector<unsigned char>& signature, uint256& hash);
// bool check_contextual_auth(std::string& chunk, int& error_level);
bool check_contextual_blockuuid (std::string& chunk, int& error_level, int pintOffset);
bool check_contextual_blocktenant (std::string& chunk, int& error_level, int pintOffset);
bool check_contextual_auth (std::string& chunk, int& error_level, int pintOffset);
bool check_contextual_auth2 (std::string& chunk, int& error_level, int pintOffset);
// bool process_auth_chunk(std::string& chunk, int& error_level);
bool process_auth_chunk (std::string& chunk, int& error_level, int pintOffset);
bool process_blockuuid_chunk (std::string& chunk, int& error_level, int pintOffset);
bool process_blocktenant_chunk (std::string& chunk, int& error_level, int pintOffset);
bool compare_pubkey2 (std::string& chunk, int& error_level, int pintOffset, uint160 hash160);
bool is_opreturn_an_authdata(const CScript& script_data, int& error_level);
bool is_opreturn_a_blockuuiddata(const CScript& script_data, int& error_level);
bool is_opreturn_a_blocktenantdata(const CScript& script_data, int& error_level);
// bool is_opreturn_an_authdata2 (const CScript& script_data, int& error_level, int pintFlag);
// bool is_opreturn_an_authdata2 (const CScript& script_data, int& error_level);
bool found_opreturn_in_authdata(const CScript& script_data, int& error_level, bool test_accept = false);
bool found_opreturn_in_blockuuiddata(const CScript& script_data, int& error_level, bool test_accept = false);
bool found_opreturn_in_blocktenantdata(const CScript& script_data, int& error_level, bool test_accept = false);
bool compare_pubkey(const CScript& script_data, int& error_level, uint160 hash160);
//bool found_opreturn_in_authdata2 (const CScript& script_data, int& error_level, bool test_accept = false);
bool does_tx_have_authdata(const CTransaction& tx);
bool scan_blocks_for_authdata(ChainstateManager& chainman);
bool scan_blocks_for_blockuuiddata(ChainstateManager& chainman);
bool scan_blocks_for_blocktenantdata(ChainstateManager& chainman);
bool scan_blocks_for_specific_authdata(ChainstateManager& chainman, uint160 hash160);
bool check_mempool_for_authdata(const CTxMemPool& mempool);
bool generate_auth_payload(std::string& payload, int& type, uint32_t& time, std::string& hash);
bool generate_blockuuid_payload(std::string& payload, int& type, uint32_t& time, std::string& uuid);
bool generate_blocktenant_payload(std::string& payload, int& type, uint32_t& time, std::string& tenant);
bool generate_auth_transaction(WalletContext& wallet_context, CMutableTransaction& tx, std::string& opPayload);
bool generate_blockuuid_transaction(WalletContext& wallet_context, CMutableTransaction& tx, std::string& opPayload);
bool generate_blocktenant_transaction(WalletContext& wallet_context, CMutableTransaction& tx, std::string& opPayload);

#endif // BITCOIN_STORAGE_AUTH_H
