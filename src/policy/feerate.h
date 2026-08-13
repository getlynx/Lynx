// Copyright (c) 2009-2010 Satoshi Nakamoto
// Copyright (c) 2009-2022 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

// #define PANTHER

#ifndef BITCOIN_POLICY_FEERATE_H
#define BITCOIN_POLICY_FEERATE_H

#include <consensus/amount.h>
#include <serialize.h>


#include <cstdint>
#include <string>
#include <string_view>
#include <type_traits>

/*
#ifdef LYNX    
    const std::string CURRENCY_UNIT = "LYNX"; 
#elif defined(PANTHER)
    const std::string CURRENCY_UNIT = "PNTH"; 
#endif
*/

// Defined in kernel/chainparams.cpp, and declared here rather than including
// kernel/chainparams.h -- that header would drag the whole chain-params surface
// into every translation unit that only wants the currency label.
const std::string& CurrentCoinSymbol();

/**
 * Ticker used to label amounts and fee rates: "ALIO" on alioth, "IL8P" on a
 * chain whose ticker is not simply its first four letters. Read from the
 * spec.coinSymbol table in chainparams rather than derived from the chain name,
 * which got the ticker wrong whenever the two differ (alnitak is ANIK, not ALNI)
 * and produced a string with an embedded NUL for chain names under 4 characters.
 *
 * infiniloop keeps "InfiniLooP" as its unit, which is what that live chain has
 * always displayed -- its ticker is IL8P, but the unit label is deliberately the
 * chain name. Any other chain wanting that treatment gets a branch here.
 *
 * A function rather than a namespace-scope string on purpose: the initializer
 * reaches into the global ChainSpec in chainparams.cpp, so running it during
 * static init would be a static initialization order fiasco waiting to happen.
 * The local static defers it to first use, which is always after main() starts.
 */
inline const std::string& CurrencyUnit()
{
    static const std::string unit = (std::string_view(CURRENT_CHAIN) == "infiniloop")
                                        ? std::string{"InfiniLooP"}
                                        : CurrentCoinSymbol();
    return unit;
}

const std::string CURRENCY_ATOM = "sat"; // One indivisible minimum value unit

/* Used to determine type of fee estimation requested */
enum class FeeEstimateMode {
    UNSET,        //!< Use default settings based on other criteria
    ECONOMICAL,   //!< Force estimateSmartFee to use non-conservative estimates
    CONSERVATIVE, //!< Force estimateSmartFee to use conservative estimates
    BTC_KVB,      //!< Use BTC/kvB fee rate unit
    SAT_VB,       //!< Use sat/vB fee rate unit
};

/**
 * Fee rate in satoshis per kilovirtualbyte: CAmount / kvB
 */
class CFeeRate
{
private:
    /** Fee rate in sat/kvB (satoshis per 1000 virtualbytes) */
    CAmount nSatoshisPerK;

public:
    /** Fee rate of 0 satoshis per kvB */
    CFeeRate() : nSatoshisPerK(0) { }
    template<typename I>
    explicit CFeeRate(const I _nSatoshisPerK): nSatoshisPerK(_nSatoshisPerK) {
        // We've previously had bugs creep in from silent double->int conversion...
        static_assert(std::is_integral<I>::value, "CFeeRate should be used without floats");
    }

    /**
     * Construct a fee rate from a fee in satoshis and a vsize in vB.
     *
     * param@[in]   nFeePaid    The fee paid by a transaction, in satoshis
     * param@[in]   num_bytes   The vsize of a transaction, in vbytes
     */
    CFeeRate(const CAmount& nFeePaid, uint32_t num_bytes);

    /**
     * Return the fee in satoshis for the given vsize in vbytes.
     * If the calculated fee would have fractional satoshis, then the
     * returned fee will always be rounded up to the nearest satoshi.
     */
    CAmount GetFee(uint32_t num_bytes) const;

    /**
     * Return the fee in satoshis for a vsize of 1000 vbytes
     */
    CAmount GetFeePerK() const { return GetFee(1000); }
    friend bool operator<(const CFeeRate& a, const CFeeRate& b) { return a.nSatoshisPerK < b.nSatoshisPerK; }
    friend bool operator>(const CFeeRate& a, const CFeeRate& b) { return a.nSatoshisPerK > b.nSatoshisPerK; }
    friend bool operator==(const CFeeRate& a, const CFeeRate& b) { return a.nSatoshisPerK == b.nSatoshisPerK; }
    friend bool operator<=(const CFeeRate& a, const CFeeRate& b) { return a.nSatoshisPerK <= b.nSatoshisPerK; }
    friend bool operator>=(const CFeeRate& a, const CFeeRate& b) { return a.nSatoshisPerK >= b.nSatoshisPerK; }
    friend bool operator!=(const CFeeRate& a, const CFeeRate& b) { return a.nSatoshisPerK != b.nSatoshisPerK; }
    CFeeRate& operator+=(const CFeeRate& a) { nSatoshisPerK += a.nSatoshisPerK; return *this; }
    std::string ToString(const FeeEstimateMode& fee_estimate_mode = FeeEstimateMode::BTC_KVB) const;

    SERIALIZE_METHODS(CFeeRate, obj) { READWRITE(obj.nSatoshisPerK); }
};

#endif // BITCOIN_POLICY_FEERATE_H
