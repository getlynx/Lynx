#include <chainparams.h>
#include <opfile/src/util.h>
#include <storage/util.h>
#include <util/system.h>

#include <fstream>
#include <iostream>

void write_lynx_config(std::string& configpath, std::string passwordMain, std::string usernameMain, std::string passwordTest, std::string usernameTest)
{
    std::ofstream config(configpath);
    config << "# Changes to this file will take effect after the Lynx daemon is restarted" << std::endl;
    config << "# Lynx Documentation --> https://docs.getlynx.io/" << std::endl;
    config << "" << std::endl;
    config << "# Accept connections from outside" << std::endl;
    config << "listen=1" << std::endl;
    config << "" << std::endl;
    config << "# Accept command line and JSON-RPC commands" << std::endl;
    config << "server=1" << std::endl;
    config << "" << std::endl;
    config << "# Run in the background as a daemon and accept commands" << std::endl;
    config << "daemon=1" << std::endl;
    config << "" << std::endl;
    config << "# Set value to 0 for Mainnet or 1 for Testnet" << std::endl;
    config << "testnet=0" << std::endl;
    config << "" << std::endl;
    config << "# Change value to 'pos' for detailed staking information or '0' for minimal" << std::endl;
    config << "debug=0" << std::endl;
    config << "" << std::endl;
    config << "# Set value to 1 to disable staking or 0 to enable staking thread on startup" << std::endl;
    config << "disablestaking=0" << std::endl;
    config << "" << std::endl;
    config << "# Mainnet network" << std::endl;
    config << "main.rpcuser=" << usernameMain << std::endl;
    config << "main.rpcpassword=" << passwordMain << std::endl;
    config << "main.rpcbind=127.0.0.1" << std::endl;
    config << "main.rpcallowip=127.0.0.1" << std::endl;
    config << "" << std::endl;
    config << "# Testnet network" << std::endl;
    config << "test.rpcuser=" << usernameTest << std::endl;
    config << "test.rpcpassword=" << passwordTest << std::endl;
    config << "test.rpcbind=127.0.0.1" << std::endl;
    config << "test.rpcallowip=127.0.0.1" << std::endl;

    config.close();
}

void check_lynx_config(const ArgsManager& args)
{
    fs::path config_file_path = args.GetConfigFilePath();
    std::string configpath = fs::PathToString(config_file_path);

    if (!does_file_exist(configpath)) {
        std::string passwordMain = generate_uuid(16);
        std::string usernameMain = generate_uuid(16);
        std::string passwordTest = generate_uuid(16);
        std::string usernameTest = generate_uuid(16);
        write_lynx_config(configpath, passwordMain, usernameMain, passwordTest, usernameTest);
    }
}
