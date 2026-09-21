# Per-chain branding

Artwork the Qt wallet is built with, one directory per chain id (the lowercase name used
in `src/kernel/chainparams.cpp` and in `make NAME=<chain>`):

```
share/branding/<chain>/icon.png
```

Names and tickers are **not** kept here. They come from the `spec.*` block in
`src/kernel/chainparams.cpp` (`CurrentChainDisplayName()`, `CurrentCoinSymbol()`), so a
chain needs nothing in this directory to build; it only needs a directory here to look
different from the default.

## icon.png

- 1024 × 1024 pixels, PNG, RGBA with a transparent background.
- Used as the window and tray icon and drawn on the splash screen at 430 × 430, so it
  must read well when scaled down to 16 px.

At build time `src/Makefile.qt.include` copies `share/branding/$(NAME)/icon.png` to the
untracked `src/qt/res/icons/chain_icon.png` (the `bitcoin` alias in `src/qt/bitcoin.qrc`).
When a chain has no directory here, the stock `src/qt/res/icons/bitcoin.png` is used
instead, so replace that file to change the default for every chain at once.

The build only reads the icon when Qt resources are regenerated. Adding or changing a
chain's `icon.png` is enough: the rule compares the file contents on every `make` and
rebuilds the resources only when they differ.

## Later

Windows `.ico`, macOS `.icns` and `share/pixmaps/*` will be derived from the same
`icon.png`. Accent colours, when added, will live in `share/branding/<chain>/brand.json`
and never carry names or tickers.

### Windows, as it stands today

The compiler cross-compiles a Windows `.exe` for every chain (see
`contrib/compiler/README.md`), and that `.exe` does **not** go through this directory. Its
embedded icon comes from the tracked, chain-independent `src/qt/res/icons/bitcoin.ico`,
named by `src/qt/res/bitcoin-qt-res.rc`, so every chain's Windows build currently wears the
stock Lynx icon no matter what `share/branding/<chain>/icon.png` contains.

Closing that gap means generating a multi-size `.ico` from `icon.png` and pointing the
`.rc` at the generated file — mirroring what `src/Makefile.qt.include` already does for
`chain_icon.png`. Note this is a genuinely separate step rather than a path substitution:
the window/tray icon is a Qt resource loaded at run time, whereas the `.exe` icon is a
PE resource compiled in by `windres`, which needs real `.ico` container format.

The same `.rc` files also hardcode `InternalName "lynx-qt"` / `OriginalFilename
"lynx-qt.exe"` regardless of `make NAME=`, so a non-Lynx chain's file-properties dialog
reads "lynx-qt". Cosmetic, but it lives here too.
