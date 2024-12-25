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

void ShowAverageSpans(const CBlockIndex* pindex)
{
    CBlockIndex* ppindex = (CBlockIndex*)pindex;

    char stringHour[24], stringDay[24], stringWeek[24], stringBiweek[24], stringMonth[24];
    uint32_t calcBlocksHour, calcBlocksDay, calcBlocksWeek, calcBlocksBiweek, calcBlocksMonth; 
    double calcAverageHour, calcAverageDay, calcAverageWeek, calcAverageBiweek, calcAverageMonth;

    if (!CalculateAverageBlocktime(ppindex, 60, calcBlocksHour, calcAverageHour)) {
        sprintf(stringHour, "n/a (n/a)");
    } else {
        sprintf(stringHour, "%.02fs (%d blk)", calcAverageHour, calcBlocksHour);
    }

    if (!CalculateAverageBlocktime(ppindex, 1440, calcBlocksDay, calcAverageDay)) {
        sprintf(stringDay, "n/a (n/a)");
    } else {
        sprintf(stringDay, "%.02fs (%d blk)", calcAverageDay, calcBlocksDay);
    }

    if (!CalculateAverageBlocktime(ppindex, 10080, calcBlocksWeek, calcAverageWeek)) {
        sprintf(stringWeek, "n/a (n/a)");
    } else {
        sprintf(stringWeek, "%.02fs (%d blk)", calcAverageWeek, calcBlocksWeek);
    }

    if (!CalculateAverageBlocktime(ppindex, 20160, calcBlocksBiweek, calcAverageBiweek)) {
        sprintf(stringBiweek, "n/a (n/a)");
    } else {
        sprintf(stringBiweek, "%.02fs (%d blk)", calcAverageBiweek, calcBlocksBiweek);
    }

    if (!CalculateAverageBlocktime(ppindex, 40320, calcBlocksMonth, calcAverageMonth)) {
        sprintf(stringMonth, "n/a (n/a)");
    } else {
        sprintf(stringMonth, "%.02fs (%d blk)", calcAverageMonth, calcBlocksMonth);
    }

    LogPrintAlways(BCLog::NONE, "Block Statistics - last hour: %s, day: %s, week: %s, fortnight: %s, month: %s\n",
        stringHour, stringDay, stringWeek, stringBiweek, stringMonth);

}
