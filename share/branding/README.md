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
