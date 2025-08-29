// Copyright (c) 2023 Lynx Core Developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <pos/manager.h>

bool fStakerRunning{false};
bool fStakerRequestStart{false};
bool fStakerRequestStop{false};

// signal stake thread start
// Bens comment
void stakeman_request_start() {
    LogPrint(BCLog::POS, "PoS Manager: Stake thread start requested - setting fStakerRequestStart flag to true\n");
    fStakerRequestStart = true;
    LogPrint(BCLog::POS, "PoS Manager: Stake thread will be started in next manager loop iteration\n");
}

// signal stake thread stop
void stakeman_request_stop() {
    LogPrint(BCLog::POS, "PoS Manager: Stake thread stop requested - setting fStakerRequestStop flag to true\n");
    fStakerRequestStop = true;
    LogPrint(BCLog::POS, "PoS Manager: Stake thread will be stopped in next manager loop iteration\n");
}

// stake thread handler
void *stakeman_handler(wallet::WalletContext& wallet_context, ChainstateManager& chainman, CConnman* connman)
{
    LogPrint(BCLog::POS, "PoS Manager: Initializing stake manager handler - this manages the lifecycle of the staking thread\n");
    LogPrint(BCLog::POS, "PoS Manager: Setting initial request to start staking (fStakerRequestStart = true)\n");
    fStakerRequestStart = true;

    while (!ShutdownRequested())
    {
        bool printed_running = false;
        while (fStakerRunning)
        {
            if (!printed_running) {
                LogPrint(BCLog::POS, "PoS Manager: Staker is currently RUNNING - checking for stop requests\n");
                printed_running = true;
            }
            fStakerRequestStart = false;
            if (fStakerRequestStop)
            {
                LogPrint(BCLog::POS, "PoS Manager: Stop request detected - initiating staking thread shutdown\n");
                StopThreadStakeMiner();
                LogPrint(BCLog::POS, "PoS Manager: StopThreadStakeMiner() called - thread termination signaled\n");
                fStakerRunning = false;
                fStakerRequestStop = false;
                LogPrint(BCLog::POS, "PoS Manager: Staking thread STOPPED - flags reset (fStakerRunning=false, fStakerRequestStop=false)\n");
            }
            UninterruptibleSleep(std::chrono::milliseconds{250});
        }

        while (!fStakerRunning)
        {
            LogPrint(BCLog::POS, "PoS Manager: Staker is currently STOPPED - checking for start requests\n");
            fStakerRequestStop = false;
            if (fStakerRequestStart)
            {
                LogPrint(BCLog::POS, "PoS Manager: Start request detected - initiating staking thread startup\n");
                LogPrint(BCLog::POS, "PoS Manager: Calling StartThreadStakeMiner() with wallet context, chainstate manager, and connection manager\n");
                StartThreadStakeMiner(wallet_context, chainman, connman);
                LogPrint(BCLog::POS, "PoS Manager: StartThreadStakeMiner() completed - new staking thread launched\n");
                fStakerRunning = true;
                fStakerRequestStart = false;
                LogPrint(BCLog::POS, "PoS Manager: Staking thread STARTED - flags set (fStakerRunning=true, fStakerRequestStart=false)\n");
            }
            UninterruptibleSleep(std::chrono::milliseconds{250});
        }

        UninterruptibleSleep(std::chrono::milliseconds{250});
    }

    LogPrint(BCLog::POS, "PoS Manager: Shutdown requested - exiting stake manager handler\n");
    LogPrint(BCLog::POS, "PoS Manager: Ensuring staking thread is stopped before exit\n");
    if (fStakerRunning) {
        StopThreadStakeMiner();
        LogPrint(BCLog::POS, "PoS Manager: Final staking thread shutdown completed\n");
    }
    return (void*)0;
}
