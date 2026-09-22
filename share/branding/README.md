# Per-chain branding

Artwork the Qt wallet is built with, one directory per chain id — the lowercase name used
in `src/kernel/chainparams.cpp` and in `make NAME=<chain>`:

```
share/branding/<chain>/
    icon.png      1024 x 1024 RGBA master
    icon.ico      multi-size Windows icon, derived from icon.png
```

Names and tickers are **not** kept here. They come from the `spec.*` block in
`src/kernel/chainparams.cpp` (`CurrentChainDisplayName()`, `CurrentCoinSymbol()`).

## How a chain's artwork is selected

`src/Makefile.qt.include` copies the right files into two generated, untracked outputs:

| generated file | fed to | shows up as |
| --- | --- | --- |
| `src/qt/res/icons/chain_icon.png` | `rcc`, via the `bitcoin` alias in `src/qt/bitcoin.qrc` | window, tray, splash, About dialog |
| `src/qt/res/icons/chain_icon.ico` | `windres`, via `src/qt/res/bitcoin-qt-res.rc` | the Windows `.exe`, taskbar, Explorer |

Both use the same three-step lookup:

1. `share/branding/$(NAME)/<file>`
2. `share/branding/lynx/<file>` — printed as a `FALLBACK` line in the build log
3. otherwise the build **fails**

Falling back to Lynx rather than to a stock Bitcoin asset is the point: it is what makes
it impossible to ship a Bitcoin-branded wallet by accident. The stock `bitcoin.png` /
`bitcoin.ico` / `bitcoin_testnet.ico` have been deleted for the same reason — with the
files gone, nothing can quietly reach for them. Step 3 is a repo-integrity check, so
`share/branding/lynx/` must always be complete.

The rules compare file contents on every `make` and copy only on a real change, so
`make NAME=<other>` re-brands an existing tree without a clean, and Qt resources are
regenerated exactly when the artwork actually changed.

## icon.png

- 1024 x 1024, PNG, RGBA, transparent background.
- Drawn on the splash at 430 x 430 and used as the tray/titlebar icon at 16 px, so it has
  to survive heavy downscaling. **Keep the mark simple** — fine internal detail turns to
  mush at 16 px, and no amount of source resolution fixes that.

The Lynx master is a solid disc carrying a knockout mark, with a ~4% white keyline around
it so the icon separates from dark desktop backgrounds. A shape that reads as a silhouette
is what makes it legible at tray size.

## icon.ico

16, 32, 48 and 256 px, all 32-bit. Committed rather than generated during the build, so no
build host needs image tooling and the build stays reproducible. Regenerate it with the
tool below whenever `icon.png` changes.

Entries are PNG-compressed at every size. Windows 7 and later read that fine, and the
tree targets `_WIN32_WINNT=0x0601`; if Explorer ever renders an icon wrongly, the small
sizes being PNG rather than BMP is the first thing to check.

## contrib/branding/branding.py

Maintainer tool. Needs Pillow (`apt install python3-pil`); nothing in the build does.

```
branding.py normalise <png> [dest]   crop to the circular content, scale to 1024 x 1024
branding.py derive                   recolour the lynx master into each chain's colour
branding.py ico [chain...]           rebuild icon.ico from icon.png
branding.py check                    report which chains still lack artwork
```

`derive` never touches a chain listed in `HAND_DRAWN` (`lynx`, `infiniloop`,
`digitalcoin`) — those carry their own artwork.

Derived chains get their disc recoloured to the colour Spark's chain selector already uses
for that chain: the tool reads `_CHAIN_PALETTE` and re-implements the djb2 hash from
`contrib/compiler/compile.sh`, rather than keeping a second copy of the palette that could
drift. The knockout mark is set to white or dark per chain, whichever contrasts better
against that disc colour, which keeps every chain at or above the WCAG AA ratio of 4.5:1 —
a fixed white mark would be near-invisible on the lighter palette entries.

The white keyline is left white on every chain. It is separated from the inner mark by
radius, because both are white in the master and a light/dark split alone cannot tell them
apart.

## Linux desktop integration

`make install` places `$(datadir)/pixmaps/<chain>.png` and
`$(datadir)/applications/<chain>.desktop`. The `.zip` archives this project ships do not
run `make install`, so that is groundwork for packagers — but the pixmap is also what the
`Icon=<chain>` key resolves against in the autostart file written by
`GUIUtil::SetStartOnSystemStartup()`.

The generated `.desktop` sets `Name=` to a plain capitalisation of the chain id, since
`CurrentChainDisplayName()` is a C++ function the build cannot call. That matches every
chain except `infiniloop`, which reads "InfiniLooP" in the wallet and "Infiniloop" in a
launcher.

## Not yet per-chain

- macOS `.icns` (`src/qt/res/icons/bitcoin.icns`) and the `Lynx-Qt.app` bundle name — there
  is no macOS build target.
- The six Android launcher icons under `src/qt/android/res/`.
- The NSIS installer art in `share/pixmaps/` — no installer is shipped.
- `src/qt/res/bitcoin-qt-res.rc` hardcodes `InternalName "lynx-qt"` and
  `OriginalFilename "lynx-qt.exe"` regardless of `NAME`, so a non-Lynx chain's Windows
  file-properties dialog reads "lynx-qt". Cosmetic.

Accent colours, if they are ever needed at run time, belong in the `spec.*` block in
`chainparams.cpp` rather than here — this directory is for build inputs.
