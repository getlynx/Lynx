# Lynx Core for the Lynx Data Storage Network

**Permanent, low-cost data storage on a public blockchain — built to outlive us.**

[Documentation](https://docs.getlynx.io/) · [Block Explorer](https://explorer.getlynx.io/) · [Store a File (Clevver)](https://clevver.org/) · [Discord](https://discord.getlynx.io/) · [Bluesky](https://bsky.app/profile/getlynx.io)

---

<p align="center">
  <img src="https://get.clevver.org/be9e1a4af03b57d1720cf37f3c044de59157d993626c44d10183b1c8bd0f41a4.png" alt="Lynx logo" width="300">
</p>

## What is Lynx?

Lynx is a blockchain designed to do one thing exceptionally well: store your most important digital files permanently, at low cost, in a way that stays accessible for generations.

When you store a file on Lynx, the **entire file** is written directly onto the blockchain — not a hash, not a pointer to a server or an IPFS node that someone has to keep paying for and maintaining. The file itself lives on-chain. That means no monthly fees, no subscriptions, and no single company whose survival your data depends on. As long as the network exists, your file is there, unchanged and independently verifiable by anyone.

Lynx is a fork of Bitcoin Core, hardened by more than a decade of real-world operation, but re-engineered around storage and sustainability rather than payments.

## Why it matters

Most "permanent" storage isn't. Cloud drives lapse when the bill goes unpaid. Links rot. Services shut down and take their data with them. IPFS and similar systems keep a file alive only as long as someone, somewhere, chooses to keep hosting it.

Lynx takes a different approach. By putting the whole file on a public, transparent, eleven-plus-year-old blockchain, it removes the ongoing dependencies that cause data to disappear. It's built for the things you can't afford to lose: family photos, legal and medical records, journalistic archives, and the research record itself — master's theses and dissertations, published papers and their underlying datasets, and long-term medical and climate research data that must stay verifiable for decades.

## How it works, in plain terms

Lynx treats its coin like a **commodity** — something that gets consumed to do useful work, the way gasoline is burned to move a ship.

- **Stakers** run nodes that secure the network and, in doing so, create new Lynx coins. This is done through **Proof of Stake**, which uses a tiny fraction of the energy of Bitcoin-style mining — no warehouses of power-hungry machines. While data-center computers can and do help maintain the global network, they aren't required: Lynx is [designed to be eco-friendly](https://docs.getlynx.io/lynx-core/sustainability) and can be run entirely by individual participants on inexpensive computers at home or in the office.
- **Storage users** acquire coins and "burn" (permanently destroy) them to pay for writing a file to the chain.

Coins are created to secure the network and destroyed to store data, completing the cycle. Because the coin has a genuine use, Lynx isn't chasing price speculation — it's a working utility.

This also makes running a node genuinely worthwhile: modest hardware like a Raspberry Pi can help secure the network and earn staking rewards while sipping electricity.

## Lynx and Clevver

The blockchain is the engine; **[Clevver](https://clevver.org/)** is the friendly front door.

Clevver is a web platform (and API) built on top of Lynx that makes permanent storage as easy as dragging and dropping a file into your browser. It handles all the blockchain complexity behind the scenes and hands you back a permanent, immutable web link to your file. It serves everyone from individuals preserving a single photo to enterprises integrating permanent storage into their own products.

If you just want to store something forever and don't care how the machinery works, **[start at clevver.org](https://clevver.org/)** — you can store your first file for free.

## Quick Start — Run a Node

Running a node secures the network and lets you earn staking rewards. Lynx offers **two installers**, both a single command, depending on the kind of experience you want. They connect to the same network and each can run more than one chain on a single machine.

### Spark — the simplest path

**Spark** is the fastest way from "I have a spare Linux machine" to "I'm running a node." Paste one line, come back in a few hours, and your node is live. It downloads the right binaries for your hardware, sets up the daemon, configures the firewall, tightens SSH, schedules automatic wallet backups, and gives you friendly short commands (`gba` for balance, `s` to toggle staking, `h` for help).

Spark is ideal for small, quiet hardware — a Raspberry Pi 4 (even a Pi Zero 2), a budget cloud server, or an old laptop in a closet.

👉 **[Spark Quick Start guide](https://docs.getlynx.io/lynx-administration/spark-the-simple-way-to-run-a-lynx-node)**

### Beacon — for hands-on operators

**Beacon** is a full terminal management console for the Lynx Data Storage Network. It's the better fit if you want a live dashboard you can leave open all day, wallet encryption, or a built-in ElectrumX server without assembling one yourself.

👉 See **[Spark vs. Beacon](https://docs.getlynx.io/lynx-administration/spark-the-simple-way-to-run-a-lynx-node)** in the docs to choose.

### Raspberry Pi ISO

Prefer to flash and go? A prebuilt Lynx ISO works with the standard Raspberry Pi Imager and sets everything up automatically on first boot.

👉 **[Raspberry Pi setup guide](https://docs.getlynx.io/raspberry-pi/raspberry-pi-complete-setup-and-management-guide)**

## The Bigger Strategy: Blockchain Recycling

Lynx doesn't just run its own chain — it gives abandoned blockchains a second life.

Across the crypto landscape are countless dead and orphaned chains: projects that were abandoned, ran their course, or never found a purpose, yet still carry real transaction history and coin holders. Rather than let them fade, Lynx **recycles** them: it preserves their existing history and coin ownership, migrates their consensus to Lynx's energy-efficient Proof of Stake, and adds permanent data-storage capability at the protocol layer.

Each recycled chain becomes another storage utility chain running on the same technology, and each one adds meaningful capacity to the network. It's a sustainability story on two levels — reusing what already exists, and doing it without the energy cost of Proof of Work.

## A Short History

- **2013** — The Lynx blockchain begins. Its history now stretches back over a decade, fully intact and preserved through every upgrade since.
- **Early years** — Lynx operates as a lightweight, low-fee cryptocurrency with an emphasis on accessibility and running on modest hardware.
- **2016–2024** — Lynx pivots decisively toward its true purpose: permanent, on-chain data storage. The storage architecture moves from an early API-based system to an advanced on-chain RPC design, with file sharding, authentication, and authorization all handled directly on the blockchain. Clevver launches as the consumer- and enterprise-facing storage platform.
- **2024** — A landmark release transitions Lynx from Hybrid Proof of Work to **LWMA Proof of Stake**, dramatically cutting energy use, and rebases the codebase on **Bitcoin Core v26**.
- **2025–2026** — The storage network expands from a single chain into a coordinated multi-chain network through the blockchain recycling strategy, unified deployment tooling arrives, and staking becomes possible from encrypted wallets.

## Two Years of Progress at a Glance

A summary of what the last two years of development delivered:

- **Consensus overhaul** — Completed the transition from Hybrid Proof of Work to LWMA Proof of Stake, making Lynx one of the more energy-efficient storage networks available while preserving the full multi-year blockchain history.
- **Bitcoin Core v26 rebase** — Brought the codebase current with upstream Bitcoin Core, ingesting ongoing security patches and networking improvements while maintaining Lynx's storage-specific features.
- **On-chain storage architecture** — Matured the RPC-based storage subsystem, with file sharding, message queuing, and on-chain authentication and authorization — no Layer 2 required.
- **Multi-chain storage network** — Grew from a single chain to a coordinated network of storage chains via blockchain recycling, multiplying total annual storage capacity available to Clevver and direct integrators.
- **Larger file support** — Increased the maximum single-asset upload size to accommodate bigger files in one operation.
- **Unified deployment** — Shipped the **Spark** one-line installer and the **Beacon** management console, covering the entire chain family across AMD and ARM hardware, plus a plug-and-play Raspberry Pi ISO.
- **Staking improvements** — Delivered staking from locked, encrypted wallets; a runtime staking toggle; and a critical fix to the stake-weighting math that ensures large holdings receive their correct staking weight.
- **Wallet accuracy** — Resolved long-standing balance-reporting issues tied to orphaned blocks and phantom UTXOs, so balances stay accurate through extended staking.
- **Reliability & diagnostics** — Hardcoded network seed nodes for faster, more dependable cold starts, and expanded logging and diagnostics for node operators.

For the full, version-by-version history, see the **[Releases page](https://github.com/getlynx/Lynx/releases)**.

## Get Involved

- **Store a file:** [clevver.org](https://clevver.org/)
- **Read the docs:** [docs.getlynx.io](https://docs.getlynx.io/)
- **Explore the chain:** [explorer.getlynx.io](https://explorer.getlynx.io/)
- **Run a node:** start with the [Spark Quick Start](https://docs.getlynx.io/lynx-administration/spark-the-simple-way-to-run-a-lynx-node)
- **Join the community:** the [Lynx Discord](https://discord.getlynx.io/) — active and happy to help
- **Report issues or contribute:** right here on GitHub

## Interface

Lynx Core is designed for command-line (CLI) operation. The Qt graphical interface is not included in current releases.

## License

Lynx Core is released under the [MIT License](LICENSE).

---

*Lynx is designed to make stored files accessible long after the creator is gone. Gone are the days of lost precious family photos. Lynx is designed to outlive us.*
