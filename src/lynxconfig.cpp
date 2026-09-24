#include <chainparams.h>
#include <opfile/src/util.h>
#include <storage/util.h>
#include <util/system.h>

#include <fstream>
#include <iostream>

void write_lynx_config(std::string& configpath, std::string passwordMain, std::string usernameMain)
{
    std::ofstream config(configpath);
    config << "# Changes to this file will take effect after the daemon is restarted" << std::endl;
    config << "# Lynx Documentation --> https://docs.getlynx.io/" << std::endl;
    config << "" << std::endl;
    config << "# Uncomment and change value to 0 to refuse connections from outside" << std::endl;
    config << "#listen=1" << std::endl;
    config << "" << std::endl;
    config << "# Accept command line and JSON-RPC commands" << std::endl;
    config << "server=1" << std::endl;
    config << "" << std::endl;
    config << "# Run in the background as a daemon and accept commands" << std::endl;
    config << "daemon=1" << std::endl;
    config << "" << std::endl;
    config << "# Uncomment and change value to 'pos' for detailed staking information or '0' for minimal" << std::endl;
    config << "#debug=0" << std::endl;
    config << "" << std::endl;
    config << "# Set value to 1 to disable staking or 0 to enable staking thread on startup" << std::endl;
    config << "disablestaking=0" << std::endl;
    config << "" << std::endl;
    config << "# Mainnet network" << std::endl;
    config << "main.rpcuser=" << usernameMain << std::endl;
    config << "main.rpcpassword=" << passwordMain << std::endl;
    config << "main.rpcbind=127.0.0.1" << std::endl;
    config << "main.rpcallowip=127.0.0.1" << std::endl;
    config << "main.rpcport=" << CurrentChainRPCPort() << std::endl;
    config << "" << std::endl;
    config << "# P2P port other nodes connect to. Open this TCP port in your firewall for" << std::endl;
    config << "# inbound peers. Uncomment and change only to run on a non-default port." << std::endl;
    config << "#main.port=" << CurrentChainP2PPort() << std::endl;

    config.close();
}

bool check_lynx_config(const ArgsManager& args)
{
    fs::path config_file_path = args.GetConfigFilePath();
    std::string configpath = fs::PathToString(config_file_path);

    if (!does_file_exist(configpath)) {
        std::string passwordMain = generate_uuid(16);
        std::string usernameMain = generate_uuid(16);
        write_lynx_config(configpath, passwordMain, usernameMain);
        return true;
    }
    return false;
}
