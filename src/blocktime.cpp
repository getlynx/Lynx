// Copyright (c) 2023 Lynx Core Developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <chainparams.h>
#include <logging.h>
#include <validation.h>

bool CalculateAverageBlocktime(CBlockIndex* pindex, uint32_t timeSpan, uint32_t& blocks, double& calcAverage)
{
    blocks = 0;
    uint32_t gapAverage = 0;
    uint32_t nowTime = pindex->nTime;
    uint32_t beginTime = pindex->nTime;

    while (pindex && ((beginTime - nowTime) / 60) < timeSpan) {
        blocks += 1;
        pindex = pindex->pprev;
        if (!pindex) return false;
        gapAverage = gapAverage + (nowTime - pindex->nTime);
        nowTime = pindex->nTime;
    }

    calcAverage = (double)gapAverage / blocks;
    return pindex->nHeight >= blocks;
}

/**
 * Displays average block time statistics for different time periods
 * Calculates and logs the average block times for the last hour, day, week, fortnight, and month
 * @param pindex Pointer to the current block index
 */
void ShowAverageSpans(const CBlockIndex* pindex)
{
    // Cast away const-ness
    CBlockIndex* ppindex = (CBlockIndex*)pindex;

    // Buffers to store formatted strings for each time period
    char stringHour[24], stringDay[24], stringWeek[24], stringBiweek[24], stringMonth[24];

    // Variables to store calculation results for each time period
    // blocks = number of blocks in the period, average = average time between blocks
    uint32_t calcBlocksHour, calcBlocksDay, calcBlocksWeek, calcBlocksBiweek, calcBlocksMonth; 
    double calcAverageHour, calcAverageDay, calcAverageWeek, calcAverageBiweek, calcAverageMonth;

    // Calculate hourly average (60 minutes)
    if (!CalculateAverageBlocktime(ppindex, 60, calcBlocksHour, calcAverageHour)) {
        sprintf(stringHour, "n/a (n/a)");
    } else {
        sprintf(stringHour, "%.0fs (%d blocks)", calcAverageHour, calcBlocksHour);
    }

    // Calculate daily average (1440 minutes = 24 hours)
    if (!CalculateAverageBlocktime(ppindex, 1440, calcBlocksDay, calcAverageDay)) {
        sprintf(stringDay, "n/a (n/a)");
    } else {
        sprintf(stringDay, "%.0fs (%d blocks)", calcAverageDay, calcBlocksDay);
    }

    // Calculate weekly average (10080 minutes = 7 days)
    if (!CalculateAverageBlocktime(ppindex, 10080, calcBlocksWeek, calcAverageWeek)) {
        sprintf(stringWeek, "n/a (n/a)");
    } else {
        sprintf(stringWeek, "%.0fs (%d blocks)", calcAverageWeek, calcBlocksWeek);
    }

    // Calculate fortnightly average (20160 minutes = 14 days)
    if (!CalculateAverageBlocktime(ppindex, 20160, calcBlocksBiweek, calcAverageBiweek)) {
        sprintf(stringBiweek, "n/a (n/a)");
    } else {
        sprintf(stringBiweek, "%.0fs (%d blocks)", calcAverageBiweek, calcBlocksBiweek);
    }

    // Calculate monthly average (40320 minutes = 28 days)
    if (!CalculateAverageBlocktime(ppindex, 40320, calcBlocksMonth, calcAverageMonth)) {
        sprintf(stringMonth, "n/a (n/a)");
    } else {
        sprintf(stringMonth, "%.0fs (%d blocks)", calcAverageMonth, calcBlocksMonth);
    }

    // Log all statistics
    LogPrintAlways(BCLog::NONE, "Block Statistics - last hour: %s, day: %s, week: %s, fortnight: %s, month: %s\n",
        stringHour, stringDay, stringWeek, stringBiweek, stringMonth);
    LogPrintAlways(BCLog::POS, "Block Statistics - https://docs.getlynx.io/lynx-core/understanding-the-lynx-blockchain-statistics-report");
}
