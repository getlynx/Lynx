// Copyright (c) 2011-2022 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef BITCOIN_NODE_BLOCKSTORAGE_H
#define BITCOIN_NODE_BLOCKSTORAGE_H

#include <attributes.h>
#include <chain.h>
#include <kernel/blockmanager_opts.h>
#include <kernel/chainparams.h>
#include <kernel/cs_main.h>
#include <protocol.h>
#include <sync.h>
#include <txdb.h>
#include <util/fs.h>

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <type_traits>
#include <unordered_map>
#include <vector>

class BlockValidationState;
class CBlock;
class CBlockFileInfo;
class CBlockUndo;
class CChain;
class CChainParams;
class Chainstate;
class ChainstateManager;
struct CCheckpointData;
struct FlatFilePos;
namespace Consensus {
struct Params;
}

namespace node {

/** The pre-allocation chunk size for blk?????.dat files (since 0.8) */
static const unsigned int BLOCKFILE_CHUNK_SIZE = 0x1000000; // 16 MiB
/** The pre-allocation chunk size for rev?????.dat files (since 0.8) */
static const unsigned int UNDOFILE_CHUNK_SIZE = 0x100000; // 1 MiB
/** The maximum size of a blk?????.dat file (since 0.8) */
static const unsigned int MAX_BLOCKFILE_SIZE = 0x8000000; // 128 MiB

/** Size of header written by WriteBlockToDisk before a serialized CBlock */
static constexpr size_t BLOCK_SERIALIZATION_HEADER_SIZE = CMessageHeader::MESSAGE_START_SIZE + sizeof(unsigned int);

extern std::atomic_bool fReindex;

// Bump allocator over one large file-backed mmap, used to hold the block index
// map nodes. The block index is loaded whole at startup but almost never touched
// away from the tip; backing it with a memory-mapped file lets the OS keep only
// the touched pages resident and page the cold history out to disk, instead of
// pinning every CBlockIndex in RAM. Entries are never erased, so deallocate is a
// no-op. On non-POSIX platforms Alloc falls back to plain heap allocation.
class BlockIndexArena
{
public:
    //! Allocate `bytes` from the arena, aligned to `align`. Opens/resets the
    //! backing file on first use. While staging is active (see BeginStaging),
    //! allocations come from an anonymous in-RAM region instead of the file.
    static void* Alloc(std::size_t bytes, std::size_t align);

    //! Route subsequent Alloc calls into an anonymous in-RAM staging region.
    //! Used to build the index cheaply before copying it into the file in
    //! height order. If the staging region can't be created, staging stays
    //! inactive and the index builds directly in the file (hash order).
    static void BeginStaging();
    //! Whether staging is currently active (BeginStaging succeeded).
    static bool StagingActive();
    //! Stop routing to staging; subsequent Alloc calls hit the file arena.
    //! The staging region stays mapped so its records can still be read/copied.
    static void EndStaging();
    //! Release the anonymous staging region back to the OS.
    static void ReleaseStaging();

    //! If the records live contiguously in the file arena (not heap fallback),
    //! report the arena base and the number of bytes used, so callers can walk
    //! the records in arena order (sequential reads) with stride sizeof(CBlockIndex).
    //! Returns false when records are on the heap and must be visited via the map.
    static bool FileGeometry(char*& base, std::size_t& used_bytes);
};

template <class T>
struct MmapAllocator {
    using value_type = T;
    // All instances share the one process-wide arena, so the allocator behaves
    // as stateless: the map treats it exactly like std::allocator.
    using is_always_equal = std::true_type;

    MmapAllocator() noexcept = default;
    template <class U>
    MmapAllocator(const MmapAllocator<U>&) noexcept {}

    T* allocate(std::size_t n) { return static_cast<T*>(BlockIndexArena::Alloc(n * sizeof(T), alignof(T))); }
    void deallocate(T*, std::size_t) noexcept {}

    template <class U> bool operator==(const MmapAllocator<U>&) const noexcept { return true; }
    template <class U> bool operator!=(const MmapAllocator<U>&) const noexcept { return false; }
};

// Lookup table from block hash to its CBlockIndex*, living in ordinary RAM while
// the records live in the file-backed arena. It is a flat open-addressing table:
// two parallel arrays (a 32-bit hash fragment and the record pointer) so each
// slot costs 12 bytes instead of an std::unordered_map node's ~56-64 B — ~0.2 GB
// for an 8.6M chain instead of ~0.6 GB. The full key is NOT stored per slot; it
// lives in the record (CBlockIndex::m_block_hash), read only to verify a fragment
// match. Records are never erased, so there are no tombstones. Pre-size with
// reserve() once before load so no rehashing happens during a sync.
class CBlockIndexMap
{
    std::vector<uint32_t> m_frag;   // 0 == empty slot marker is NOT used; see m_ptr
    std::vector<CBlockIndex*> m_ptr; // nullptr == empty slot
    std::size_t m_mask{0};
    std::size_t m_count{0};

    static uint32_t Frag(const uint256& h) { return static_cast<uint32_t>(h.GetUint64(0) >> 32); }
    std::size_t Home(const uint256& h) const { return static_cast<std::size_t>(h.GetUint64(0)) & m_mask; }

    void Allocate(std::size_t slots)
    {
        m_frag.assign(slots, 0);
        m_ptr.assign(slots, nullptr);
        m_mask = slots - 1;
    }
    void PlaceNoGrow(CBlockIndex* p)
    {
        const uint256& h = p->m_block_hash;
        std::size_t i = Home(h);
        while (m_ptr[i]) i = (i + 1) & m_mask;
        m_ptr[i] = p;
        m_frag[i] = Frag(h);
    }
    void Grow(std::size_t slots)
    {
        std::vector<CBlockIndex*> old = std::move(m_ptr);
        Allocate(slots);
        for (CBlockIndex* p : old) if (p) PlaceNoGrow(p);
    }

public:
    CBlockIndexMap() { Allocate(1u << 16); } // tiny start; reserve() sizes it before load

    // Size the table so n entries fit at <=~60% load, rounded up to a power of two.
    void reserve(std::size_t n)
    {
        std::size_t want = 1;
        while (want < n + n / 2) want <<= 1; // n * 1.5 headroom
        if (want > m_ptr.size()) Grow(want);
    }

    // Insert a fully-formed record (its m_block_hash must already be set).
    void insert(CBlockIndex* p)
    {
        if ((m_count + 1) * 4 > m_ptr.size() * 3) Grow(m_ptr.size() << 1); // keep load < 0.75
        PlaceNoGrow(p);
        ++m_count;
    }

    CBlockIndex* find(const uint256& h) const
    {
        std::size_t i = Home(h);
        const uint32_t f = Frag(h);
        while (CBlockIndex* p = m_ptr[i]) {
            if (m_frag[i] == f && p->m_block_hash == h) return p;
            i = (i + 1) & m_mask;
        }
        return nullptr;
    }
    CBlockIndex* operator[](const uint256& h) const { return find(h); }
    std::size_t count(const uint256& h) const { return find(h) ? 1 : 0; }
    std::size_t size() const { return m_count; }
    bool empty() const { return m_count == 0; }
    std::size_t bucket_count() const { return m_ptr.size(); }

    // Visit every record (unspecified order).
    template <typename Fn> void ForEach(Fn&& fn) const
    {
        for (CBlockIndex* p : m_ptr) if (p) fn(p);
    }
    // Remap every slot's pointer to fn(old) — used by the load-time height-order
    // copy to repoint the table at the moved records (the hashes, hence slot
    // positions and fragments, are unchanged).
    template <typename Fn> void RemapPointers(Fn&& fn)
    {
        for (CBlockIndex*& p : m_ptr) if (p) p = fn(p);
    }
};
using BlockMap = CBlockIndexMap;

// Allocate a CBlockIndex in the arena and construct it (from a header, or default).
CBlockIndex* NewBlockIndex(const CBlockHeader* header);

struct CBlockIndexWorkComparator {
    bool operator()(const CBlockIndex* pa, const CBlockIndex* pb) const;
};

struct CBlockIndexHeightOnlyComparator {
    /* Only compares the height of two block indices, doesn't try to tie-break */
    bool operator()(const CBlockIndex* pa, const CBlockIndex* pb) const;
};

struct PruneLockInfo {
    int height_first{std::numeric_limits<int>::max()}; //! Height of earliest block that should be kept and not pruned
};

/**
 * Maintains a tree of blocks (stored in `m_block_index`) which is consulted
 * to determine where the most-work tip is.
 *
 * This data is used mostly in `Chainstate` - information about, e.g.,
 * candidate tips is not maintained here.
 */
class BlockManager
{
    friend Chainstate;
    friend ChainstateManager;

private:
    const CChainParams& GetParams() const { return m_opts.chainparams; }
    const Consensus::Params& GetConsensus() const { return m_opts.chainparams.GetConsensus(); }
    /**
     * Load the blocktree off disk and into memory. Populate certain metadata
     * per index entry (nStatus, nChainWork, nTimeMax, etc.) as well as peripheral
     * collections like m_dirty_blockindex.
     */
    bool LoadBlockIndex()
        EXCLUSIVE_LOCKS_REQUIRED(cs_main);
    void FlushBlockFile(bool fFinalize = false, bool finalize_undo = false);
    void FlushUndoFile(int block_file, bool finalize = false);
    bool FindBlockPos(FlatFilePos& pos, unsigned int nAddSize, unsigned int nHeight, CChain& active_chain, uint64_t nTime, bool fKnown);
    bool FindUndoPos(BlockValidationState& state, int nFile, FlatFilePos& pos, unsigned int nAddSize);

    FlatFileSeq BlockFileSeq() const;
    FlatFileSeq UndoFileSeq() const;

    FILE* OpenUndoFile(const FlatFilePos& pos, bool fReadOnly = false) const;

    bool WriteBlockToDisk(const CBlock& block, FlatFilePos& pos, const CMessageHeader::MessageStartChars& messageStart) const;
    bool UndoWriteToDisk(const CBlockUndo& blockundo, FlatFilePos& pos, const uint256& hashBlock, const CMessageHeader::MessageStartChars& messageStart) const;

    /* Calculate the block/rev files to delete based on height specified by user with RPC command pruneblockchain */
    void FindFilesToPruneManual(std::set<int>& setFilesToPrune, int nManualPruneHeight, int chain_tip_height);

    /**
     * Prune block and undo files (blk???.dat and rev???.dat) so that the disk space used is less than a user-defined target.
     * The user sets the target (in MB) on the command line or in config file.  This will be run on startup and whenever new
     * space is allocated in a block or undo file, staying below the target. Changing back to unpruned requires a reindex
     * (which in this case means the blockchain must be re-downloaded.)
     *
     * Pruning functions are called from FlushStateToDisk when the m_check_for_pruning flag has been set.
     * Block and undo files are deleted in lock-step (when blk00003.dat is deleted, so is rev00003.dat.)
     * Pruning cannot take place until the longest chain is at least a certain length (CChainParams::nPruneAfterHeight).
     * Pruning will never delete a block within a defined distance (currently 288) from the active chain's tip.
     * The block index is updated by unsetting HAVE_DATA and HAVE_UNDO for any blocks that were stored in the deleted files.
     * A db flag records the fact that at least some block files have been pruned.
     *
     * @param[out]   setFilesToPrune   The set of file indices that can be unlinked will be returned
     */
    void FindFilesToPrune(std::set<int>& setFilesToPrune, uint64_t nPruneAfterHeight, int chain_tip_height, int prune_height, bool is_ibd);

    mutable RecursiveMutex cs_LastBlockFile;
    std::vector<CBlockFileInfo> m_blockfile_info;
    int m_last_blockfile = 0;
    //! Cached append handle for the current block file, so WriteBlockToDisk does not
    //! reopen the file for every block. Closed on rollover and in FlushBlockFile.
    mutable FILE* m_block_write_file GUARDED_BY(cs_LastBlockFile) {nullptr};
    mutable int m_block_write_file_num GUARDED_BY(cs_LastBlockFile) {-1};
    //! Cached append handle for the current undo (rev) file, same pattern as the block handle.
    mutable FILE* m_undo_write_file GUARDED_BY(cs_LastBlockFile) {nullptr};
    mutable int m_undo_write_file_num GUARDED_BY(cs_LastBlockFile) {-1};
    //! Cached read handle for the connect-thread block read (cached=true path only).
    mutable FILE* m_block_read_file GUARDED_BY(cs_LastBlockFile) {nullptr};
    mutable int m_block_read_file_num GUARDED_BY(cs_LastBlockFile) {-1};
    /** Global flag to indicate we should check to see if there are
     *  block/undo files that should be deleted.  Set on startup
     *  or if we allocate more file space when we're in prune mode
     */
    bool m_check_for_pruning = false;

    const bool m_prune_mode;

    /** Dirty block index entries. */
    std::set<CBlockIndex*> m_dirty_blockindex;

    /** Dirty block file entries. */
    std::set<int> m_dirty_fileinfo;

    /**
     * Map from external index name to oldest block that must not be pruned.
     *
     * @note Internally, only blocks at height (height_first - PRUNE_LOCK_BUFFER - 1) and
     * below will be pruned, but callers should avoid assuming any particular buffer size.
     */
    std::unordered_map<std::string, PruneLockInfo> m_prune_locks GUARDED_BY(::cs_main);

    const kernel::BlockManagerOpts m_opts;

public:
    using Options = kernel::BlockManagerOpts;

    explicit BlockManager(Options opts)
        : m_prune_mode{opts.prune_target > 0},
          m_opts{std::move(opts)} {};

    std::atomic<bool> m_importing{false};

    BlockMap m_block_index GUARDED_BY(cs_main);

    std::vector<CBlockIndex*> GetAllBlockIndices() EXCLUSIVE_LOCKS_REQUIRED(::cs_main);

    //! Visit every block index record. When the records are contiguous in the
    //! file arena this walks them in arena order (sequential disk reads, cheap on
    //! a cold index); otherwise it falls back to iterating the lookup map. Visit
    //! order is unspecified — use only where order doesn't matter.
    template <typename Fn>
    void ForEachBlockIndex(Fn&& fn) EXCLUSIVE_LOCKS_REQUIRED(::cs_main)
    {
        char* base = nullptr;
        std::size_t used = 0;
        if (BlockIndexArena::FileGeometry(base, used)) {
            for (std::size_t off = 0; off + sizeof(CBlockIndex) <= used; off += sizeof(CBlockIndex)) {
                fn(reinterpret_cast<CBlockIndex*>(base + off));
            }
        } else {
            m_block_index.ForEach([&](CBlockIndex* bi) { fn(bi); });
        }
    }

    /**
     * All pairs A->B, where A (or one of its ancestors) misses transactions, but B has transactions.
     * Pruned nodes may have entries where B is missing data.
     */
    std::multimap<CBlockIndex*, CBlockIndex*> m_blocks_unlinked;

    std::unique_ptr<CBlockTreeDB> m_block_tree_db GUARDED_BY(::cs_main);

    bool WriteBlockIndexDB() EXCLUSIVE_LOCKS_REQUIRED(::cs_main);
    bool LoadBlockIndexDB() EXCLUSIVE_LOCKS_REQUIRED(::cs_main);

    /**
     * Remove any pruned block & undo files that are still on disk.
     * This could happen on some systems if the file was still being read while unlinked,
     * or if we crash before unlinking.
     */
    void ScanAndUnlinkAlreadyPrunedFiles() EXCLUSIVE_LOCKS_REQUIRED(::cs_main);

    CBlockIndex* AddToBlockIndex(const CBlockHeader& block, CBlockIndex*& best_header) EXCLUSIVE_LOCKS_REQUIRED(cs_main);
    /** Create a new block index entry for a given block hash */
    CBlockIndex* InsertBlockIndex(const uint256& hash) EXCLUSIVE_LOCKS_REQUIRED(cs_main);

    //! Mark one block file as pruned (modify associated database entries)
    void PruneOneBlockFile(const int fileNumber) EXCLUSIVE_LOCKS_REQUIRED(cs_main);

    CBlockIndex* LookupBlockIndex(const uint256& hash) EXCLUSIVE_LOCKS_REQUIRED(cs_main);
    const CBlockIndex* LookupBlockIndex(const uint256& hash) const EXCLUSIVE_LOCKS_REQUIRED(cs_main);

    /** Get block file info entry for one block file */
    CBlockFileInfo* GetBlockFileInfo(size_t n);

    bool WriteUndoDataForBlock(const CBlockUndo& blockundo, BlockValidationState& state, CBlockIndex& block)
        EXCLUSIVE_LOCKS_REQUIRED(::cs_main);

    /** Store block on disk. If dbp is not nullptr, then it provides the known position of the block within a block file on disk. */
    FlatFilePos SaveBlockToDisk(const CBlock& block, int nHeight, CChain& active_chain, const FlatFilePos* dbp);

    /** Whether running in -prune mode. */
    [[nodiscard]] bool IsPruneMode() const { return m_prune_mode; }

    /** Attempt to stay below this number of bytes of block files. */
    [[nodiscard]] uint64_t GetPruneTarget() const { return m_opts.prune_target; }
    static constexpr auto PRUNE_TARGET_MANUAL{std::numeric_limits<uint64_t>::max()};

    [[nodiscard]] bool LoadingBlocks() const { return m_importing || fReindex; }

    [[nodiscard]] bool StopAfterBlockImport() const { return m_opts.stop_after_block_import; }

    /** Calculate the amount of disk space the block & undo files currently use */
    uint64_t CalculateCurrentUsage();

    //! Returns last CBlockIndex* that is a checkpoint
    const CBlockIndex* GetLastCheckpoint(const CCheckpointData& data) EXCLUSIVE_LOCKS_REQUIRED(cs_main);

    //! Find the first block that is not pruned
    const CBlockIndex* GetFirstStoredBlock(const CBlockIndex& start_block LIFETIMEBOUND) EXCLUSIVE_LOCKS_REQUIRED(::cs_main);

    /** True if any block files have ever been pruned. */
    bool m_have_pruned = false;

    //! Check whether the block associated with this index entry is pruned or not.
    bool IsBlockPruned(const CBlockIndex* pblockindex) EXCLUSIVE_LOCKS_REQUIRED(::cs_main);

    //! Create or update a prune lock identified by its name
    void UpdatePruneLock(const std::string& name, const PruneLockInfo& lock_info) EXCLUSIVE_LOCKS_REQUIRED(::cs_main);

    /** Open a block file (blk?????.dat) */
    FILE* OpenBlockFile(const FlatFilePos& pos, bool fReadOnly = false) const;

    /** Translation to a filesystem path */
    fs::path GetBlockPosFilename(const FlatFilePos& pos) const;

    /**
     *  Actually unlink the specified files
     */
    void UnlinkPrunedFiles(const std::set<int>& setFilesToPrune) const;

    /** Functions for disk access for blocks */
    bool ReadBlockFromDisk(CBlock& block, const FlatFilePos& pos, bool cached = false) const;
    bool ReadBlockFromDisk(CBlock& block, const CBlockIndex& index, bool cached = false) const;
    bool ReadRawBlockFromDisk(std::vector<uint8_t>& block, const FlatFilePos& pos, const CMessageHeader::MessageStartChars& message_start) const;

    bool UndoReadFromDisk(CBlockUndo& blockundo, const CBlockIndex& index) const;

    void CleanupBlockRevFiles() const;
};

void ThreadImport(ChainstateManager& chainman, std::vector<fs::path> vImportFiles, const fs::path& mempool_path);
} // namespace node

#endif // BITCOIN_NODE_BLOCKSTORAGE_H
