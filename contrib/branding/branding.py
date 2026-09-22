#!/usr/bin/env python3
"""Per-chain branding artwork tool for the Lynx Qt wallet.

Maintainer tool, NOT part of the build. The build only ever copies committed files
(see the QT_CHAIN_ICON / QT_CHAIN_ICO rules in src/Makefile.qt.include), so no build
host needs this script or its dependencies.

Requires Pillow:  apt install python3-pil

Subcommands
  normalise <png>   crop a supplied master to its circular content and scale to 1024x1024
  derive            recolour the lynx master into each chain's Spark palette colour
  ico [chain...]    build the multi-size Windows icon.ico from icon.png
  check             report which chains in chainparams.cpp still lack artwork

The chain list and the per-chain colours are both READ FROM THE REPO rather than
duplicated here: chains come from src/kernel/chainparams.cpp (the same source
contrib/compiler/compile.sh reads) and colours are derived with the djb2 hash and
palette lifted from contrib/compiler/compile.sh, so a chain's icon colour always
matches the colour Spark's chain selector shows for it.
"""
import math
import os
import re
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
BRANDING = os.path.join(ROOT, 'share', 'branding')
CHAINPARAMS = os.path.join(ROOT, 'src', 'kernel', 'chainparams.cpp')
COMPILE_SH = os.path.join(ROOT, 'contrib', 'compiler', 'compile.sh')

CANVAS = 1024            # src/qt/splashscreen.cpp requests QSize(1024,1024)
ICO_SIZES = [16, 32, 48, 256]
WHITE = (255, 255, 255)
DARK = (3, 0, 0)         # the master's own near-black, reused for dark marks
# Chains whose artwork is supplied by hand and must never be overwritten by 'derive'.
HAND_DRAWN = {'lynx', 'infiniloop', 'digitalcoin'}


def chains():
    """Every chain defined in chainparams.cpp, alphabetically."""
    src = open(CHAINPARAMS, encoding='utf-8').read()
    return sorted(set(re.findall(r'spec\.[A-Za-z_]\w*\["([^"]+)"\]', src)))


def palette():
    """_CHAIN_PALETTE from compile.sh, so colours stay in lockstep with Spark."""
    src = open(COMPILE_SH, encoding='utf-8').read()
    m = re.search(r'_CHAIN_PALETTE=\(\n(.*?)\n\)', src, re.S)
    if not m:
        sys.exit('could not find _CHAIN_PALETTE in %s' % COMPILE_SH)
    return [int(x) for x in m.group(1).split()]


def djb2_mod100(s):
    h = 5381
    for ch in s:
        h = (h * 33 + ord(ch)) & 0x7fffffff
    return h % 100


def xterm_rgb(i):
    levels = [0, 95, 135, 175, 215, 255]
    if 16 <= i <= 231:
        i -= 16
        return (levels[i // 36], levels[(i // 6) % 6], levels[i % 6])
    if 232 <= i <= 255:
        v = 8 + (i - 232) * 10
        return (v, v, v)
    return (0, 0, 0)


def chain_colour(name):
    return xterm_rgb(palette()[djb2_mod100(name.lower())])


def _lin(c):
    c /= 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (_lin(x) for x in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def best_mark(disc):
    """White or dark for the knockout mark, whichever reads better on this disc."""
    cw, cb = contrast(WHITE, disc), contrast(DARK, disc)
    return (WHITE, 'white', cw) if cw >= cb else (DARK, 'dark', cb)


def measure_disc_radius(im):
    """Radius of the solid disc, i.e. where the body ends and the white keyline begins.

    Measured rather than hardcoded so the master can be replaced without editing code.
    Returns (disc_radius, opaque_radius).
    """
    w, h = im.size
    px = im.load()
    cx = cy = (w - 1) / 2.0
    dark, opaque = [], []
    for deg in range(0, 360, 10):
        t = math.radians(deg)
        d = o = None
        r = 0.0
        while r < max(w, h):
            x, y = int(round(cx + r * math.cos(t))), int(round(cy + r * math.sin(t)))
            if not (0 <= x < w and 0 <= y < h):
                break
            p = px[x, y]
            if p[3] > 128:
                o = r
                if luminance(p[:3]) < 0.18:
                    d = r
            r += 0.5
        if d:
            dark.append(d)
        if o:
            opaque.append(o)
    if not dark or not opaque:
        sys.exit('could not find a disc in the master - is it the expected artwork?')
    return sum(dark) / len(dark), sum(opaque) / len(opaque)


def normalise(path, dest):
    """Crop a master to its circular content and scale uniformly to CANVAS px."""
    im = Image.open(path).convert('RGBA')
    bb = im.getbbox()
    crop = im.crop(bb)
    if crop.width != crop.height:
        side = max(crop.width, crop.height)
        pad = Image.new('RGBA', (side, side), (0, 0, 0, 0))
        pad.paste(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
        crop = pad
        print('  padded to square %dx%d (content was %dx%d)'
              % (side, side, bb[2] - bb[0], bb[3] - bb[1]))
    out = crop.resize((CANVAS, CANVAS), Image.LANCZOS)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    out.save(dest)
    print('  %s -> %s  (%dx%d, uniform scale %.4f)'
          % (os.path.relpath(path, ROOT), os.path.relpath(dest, ROOT),
             CANVAS, CANVAS, CANVAS / crop.width))
    return out


def recolour(master, disc, mark, disc_r):
    """Three-region recolour: keyline stays white, disc body takes the chain colour,
    knockout mark takes `mark`.

    The artwork is a white keyline around a solid disc with a knockout mark inside it.
    A plain light/dark split cannot tell the outer keyline from the inner mark, so the
    keyline is separated geometrically by radius. Source luminance drives the blend
    between disc and mark colours, which keeps the antialiasing on that internal
    boundary smooth instead of jagged.
    """
    w, h = master.size
    mp = master.load()
    out = Image.new('RGBA', (w, h))
    op = out.load()
    cx = cy = (w - 1) / 2.0
    for y in range(h):
        dy = y - cy
        for x in range(w):
            r, g, b, a = mp[x, y]
            if a == 0:
                op[x, y] = (0, 0, 0, 0)
                continue
            t = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
            inner = [disc[i] * (1 - t) + mark[i] * t for i in range(3)]
            k = (math.hypot(x - cx, dy) - (disc_r - 1.0)) / 2.0
            k = 0.0 if k < 0 else (1.0 if k > 1 else k)
            op[x, y] = (round(inner[0] * (1 - k) + 255 * k),
                        round(inner[1] * (1 - k) + 255 * k),
                        round(inner[2] * (1 - k) + 255 * k), a)
    return out


def write_ico(src, dest):
    im = Image.open(src).convert('RGBA')
    if im.size != (CANVAS, CANVAS):
        sys.exit('%s is %dx%d, expected %dx%d - run "normalise" first'
                 % (src, im.width, im.height, CANVAS, CANVAS))
    im.save(dest, sizes=[(s, s) for s in ICO_SIZES])
    print('  %s  (%s)' % (os.path.relpath(dest, ROOT),
                          ', '.join('%dx%d' % (s, s) for s in ICO_SIZES)))


def cmd_normalise(args):
    if not args:
        sys.exit('usage: branding.py normalise <master.png> [dest]')
    dest = args[1] if len(args) > 1 else os.path.join(BRANDING, 'lynx', 'icon.png')
    normalise(args[0], dest)


def cmd_derive(_args):
    master_path = os.path.join(BRANDING, 'lynx', 'icon.png')
    if not os.path.isfile(master_path):
        sys.exit('missing %s - the Lynx master is the source for every derived chain'
                 % os.path.relpath(master_path, ROOT))
    master = Image.open(master_path).convert('RGBA')
    if master.size != (CANVAS, CANVAS):
        sys.exit('lynx master is %dx%d, expected %dx%d - run "normalise" first'
                 % (master.width, master.height, CANVAS, CANVAS))
    disc_r, opaque_r = measure_disc_radius(master)
    print('master: disc radius %.1f, opaque radius %.1f, keyline %.1fpx'
          % (disc_r, opaque_r, opaque_r - disc_r))
    print('%-13s %-9s %-6s %6s' % ('chain', 'disc', 'mark', 'ratio'))
    for name in chains():
        if name in HAND_DRAWN:
            print('%-13s %-9s %-6s %6s  (hand-drawn, skipped)' % (name, '-', '-', '-'))
            continue
        disc = chain_colour(name)
        mark, label, ratio = best_mark(disc)
        d = os.path.join(BRANDING, name)
        os.makedirs(d, exist_ok=True)
        recolour(master, disc, mark, disc_r).save(os.path.join(d, 'icon.png'))
        warn = '' if ratio >= 4.5 else '   <-- BELOW WCAG AA'
        print('%-13s #%02x%02x%02x   %-6s %6.2f%s' % (name, *disc, label, ratio, warn))


def cmd_ico(args):
    targets = args or [c for c in chains()
                       if os.path.isfile(os.path.join(BRANDING, c, 'icon.png'))]
    for name in targets:
        p = os.path.join(BRANDING, name, 'icon.png')
        if not os.path.isfile(p):
            print('  %-13s no icon.png, skipped' % name)
            continue
        write_ico(p, os.path.join(BRANDING, name, 'icon.ico'))


def cmd_check(_args):
    missing_png, missing_ico, stale = [], [], []
    for name in chains():
        png = os.path.join(BRANDING, name, 'icon.png')
        ico = os.path.join(BRANDING, name, 'icon.ico')
        if not os.path.isfile(png):
            missing_png.append(name)
            continue
        im = Image.open(png)
        note = '' if im.size == (CANVAS, CANVAS) else '  (WRONG SIZE %dx%d)' % im.size
        if not os.path.isfile(ico):
            missing_ico.append(name)
        elif os.path.getmtime(ico) < os.path.getmtime(png):
            stale.append(name)
        print('  %-13s icon.png %s%s' % (name, 'ok', note))
    print()
    if missing_png:
        print('no artwork (falls back to lynx): %s' % ', '.join(missing_png))
    if missing_ico:
        print('missing icon.ico            : %s' % ', '.join(missing_ico))
    if stale:
        print('icon.ico older than icon.png: %s' % ', '.join(stale))
    if not (missing_png or missing_ico or stale):
        print('all %d chains have complete, current artwork.' % len(chains()))
        return 0
    return 0


def main():
    cmds = {'normalise': cmd_normalise, 'derive': cmd_derive,
            'ico': cmd_ico, 'check': cmd_check}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        sys.exit(__doc__)
    sys.exit(cmds[sys.argv[1]](sys.argv[2:]) or 0)


if __name__ == '__main__':
    main()
