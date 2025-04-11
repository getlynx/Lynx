#include <opfile/src/util.h>
#include <storage/chunk.h>

/*
void get_magic_from_auth(std::string chunk, std::string& magic) {
    magic = get_hex_from_offset(chunk, 0, OPAUTH_MAGICLEN*2);
}
*/

void get_magic_from_auth (std::string chunk, std::string& magic, int pintOffset) {
    magic = get_hex_from_offset(chunk, pintOffset, OPAUTH_MAGICLEN*2);
}

void get_magic_from_blockuuid (std::string chunk, std::string& magic, int pintOffset) {
    magic = get_hex_from_offset(chunk, pintOffset, OPBLOCKUUID_MAGICLEN*2);
}

void get_magic_from_blocktenant (std::string chunk, std::string& magic, int pintOffset) {
    magic = get_hex_from_offset(chunk, pintOffset, OPBLOCKTENANT_MAGICLEN*2);
}

/*
void get_operation_from_auth(std::string chunk, std::string& operation) {
    operation = get_hex_from_offset(chunk, OPAUTH_MAGICLEN*2, OPAUTH_OPERATIONLEN*2);
}
*/

void get_operation_from_auth (std::string chunk, std::string& operation, int pintOffset) {
    operation = get_hex_from_offset(chunk, pintOffset + OPAUTH_MAGICLEN*2, OPAUTH_OPERATIONLEN*2);
}

void get_operation_from_blockuuid (std::string chunk, std::string& operation, int pintOffset) {
    operation = get_hex_from_offset(chunk, pintOffset + OPBLOCKUUID_MAGICLEN*2, OPBLOCKUUID_OPERATIONLEN*2);
}

void get_operation_from_blocktenant (std::string chunk, std::string& operation, int pintOffset) {
    operation = get_hex_from_offset(chunk, pintOffset + OPBLOCKTENANT_MAGICLEN*2, OPBLOCKTENANT_OPERATIONLEN*2);
}

/*
void get_time_from_auth(std::string chunk, std::string& time) {
    time = get_hex_from_offset(chunk, (OPAUTH_MAGICLEN*2) + (OPAUTH_OPERATIONLEN*2), OPAUTH_TIMELEN*2);
}
*/

void get_time_from_auth (std::string chunk, std::string& time, int pintOffset) {
    time = get_hex_from_offset(chunk, pintOffset + (OPAUTH_MAGICLEN*2) + (OPAUTH_OPERATIONLEN*2), OPAUTH_TIMELEN*2);
}

void get_time_from_blockuuid (std::string chunk, std::string& time, int pintOffset) {
    time = get_hex_from_offset(chunk, pintOffset + (OPBLOCKUUID_MAGICLEN*2) + (OPBLOCKUUID_OPERATIONLEN*2), OPBLOCKUUID_TIMELEN*2);
}

void get_time_from_blocktenant (std::string chunk, std::string& time, int pintOffset) {
    time = get_hex_from_offset(chunk, pintOffset + (OPBLOCKTENANT_MAGICLEN*2) + (OPBLOCKTENANT_OPERATIONLEN*2), OPBLOCKTENANT_TIMELEN*2);
}

/*
void get_hash_from_auth(std::string chunk, std::string& hash) {
    hash = get_hex_from_offset(chunk, (OPAUTH_MAGICLEN*2) + (OPAUTH_OPERATIONLEN*2) + (OPAUTH_TIMELEN*2), OPAUTH_HASHLEN*2);
}
*/

void get_hash_from_auth (std::string chunk, std::string& hash, int pintOffset) {
    hash = get_hex_from_offset(chunk, pintOffset + (OPAUTH_MAGICLEN*2) + (OPAUTH_OPERATIONLEN*2) + (OPAUTH_TIMELEN*2), OPAUTH_HASHLEN*2);
}

void get_uuid_from_blockuuid (std::string chunk, std::string& uuid, int pintOffset) {
    uuid = get_hex_from_offset(chunk, pintOffset + (OPBLOCKUUID_MAGICLEN*2) + (OPBLOCKUUID_OPERATIONLEN*2) + (OPBLOCKUUID_TIMELEN*2), OPBLOCKUUID_UUIDLEN*2);
}

void get_tenant_from_blocktenant (std::string chunk, std::string& tenant, int pintOffset) {
    tenant = get_hex_from_offset(chunk, pintOffset + (OPBLOCKTENANT_MAGICLEN*2) + (OPBLOCKTENANT_OPERATIONLEN*2) + (OPBLOCKTENANT_TIMELEN*2), OPBLOCKTENANT_TENANTLEN*2);
}

/*
void get_signature_from_auth(std::string chunk, std::string& sig) {
    sig = get_hex_from_offset(chunk, (OPAUTH_MAGICLEN*2) + (OPAUTH_OPERATIONLEN*2) + (OPAUTH_TIMELEN*2) + (OPAUTH_HASHLEN*2), 0);
}
*/

void get_signature_from_auth (std::string chunk, std::string& sig, int pintOffset) {
    sig = get_hex_from_offset(chunk, pintOffset + (OPAUTH_MAGICLEN*2) + (OPAUTH_OPERATIONLEN*2) + (OPAUTH_TIMELEN*2) + (OPAUTH_HASHLEN*2), 0);
}

void get_signature_from_blockuuid (std::string chunk, std::string& sig, int pintOffset) {
    sig = get_hex_from_offset(chunk, pintOffset + (OPBLOCKUUID_MAGICLEN*2) + (OPBLOCKUUID_OPERATIONLEN*2) + (OPBLOCKUUID_TIMELEN*2) + (OPBLOCKUUID_UUIDLEN*2), 0);
}

void get_signature_from_blocktenant (std::string chunk, std::string& sig, int pintOffset) {
    sig = get_hex_from_offset(chunk, pintOffset + (OPBLOCKTENANT_MAGICLEN*2) + (OPBLOCKTENANT_OPERATIONLEN*2) + (OPBLOCKTENANT_TIMELEN*2) + (OPBLOCKTENANT_TENANTLEN*2), 0);
}

