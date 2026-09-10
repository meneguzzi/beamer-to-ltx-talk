#!/usr/bin/env python3
"""Measure a rendered PDF page, given as a Netpbm file from pdftoppm.

Some catalogue entries fail in a way that leaves no trace in the text layer, the
log, or the structure tree: the page compiles, is tagged, extracts the right
words, and renders WRONG. C-BACKGROUND is the worked case -- stub out
\\usebackgroundtemplate and the frame still has the right page count and the
right text, rendered white on white. Nothing short of looking at the pixels sees
it.

So: pdftoppm renders the page, this reads the raster. Netpbm is parsed here
directly rather than through Pillow, because the test rig must not grow a Python
dependency for three fixtures -- P5/P6 is a header and a byte block.

  pixelprobe.py FILE pixel    X Y            -> "R G B" at that point
  pixelprobe.py FILE mean     X0 Y0 X1 Y1    -> "R G B" mean over the region
  pixelprobe.py FILE nonwhite X0 Y0 X1 Y1    -> fraction of pixels not near-white

All coordinates are FRACTIONS of page width/height in [0,1], with y measured
from the TOP of the page. That matches `pdftotext -bbox`, which the geometry
assertions in assert.sh already use; two conventions in one rig would be a trap.

A pixel is "near-white" when every channel is >= PIXEL_WHITE_MIN (default 250 of
255). Antialiasing of a glyph edge against white produces channel values in the
230s, so a threshold at 255 would count the blank margin of any rendered page as
painted.
"""
import os
import sys


def read_netpbm(path):
    """(width, height, channels, bytes) for a binary P5/P6 file."""
    with open(path, 'rb') as fh:
        data = fh.read()
    if data[:2] not in (b'P5', b'P6'):
        sys.exit(f"pixelprobe: {path} is not a binary P5/P6 Netpbm file "
                 f"(magic {data[:2]!r}); pdftoppm writes P6, or P5 with -gray")
    channels = 1 if data[:2] == b'P5' else 3
    # Header: three whitespace-separated integers after the magic, with #
    # comments legal anywhere in between.
    vals, i = [], 2
    while len(vals) < 3:
        if i >= len(data):
            sys.exit(f"pixelprobe: {path} has a truncated header")
        c = data[i:i + 1]
        if c == b'#':
            while i < len(data) and data[i:i + 1] not in (b'\n', b'\r'):
                i += 1
        elif c.isspace():
            i += 1
        elif c.isdigit():
            j = i
            while j < len(data) and data[j:j + 1].isdigit():
                j += 1
            vals.append(int(data[i:j]))
            i = j
        else:
            sys.exit(f"pixelprobe: unexpected byte {c!r} in the header of {path}")
    i += 1  # exactly one whitespace byte separates the header from the raster
    w, h, maxval = vals
    if maxval != 255:
        sys.exit(f"pixelprobe: {path} has maxval {maxval}; only 8-bit (255) is "
                 f"handled, and pdftoppm writes 255")
    want = w * h * channels
    raster = data[i:i + want]
    if len(raster) != want:
        sys.exit(f"pixelprobe: {path} claims {w}x{h}x{channels} = {want} bytes "
                 f"of raster, has {len(raster)}")
    return w, h, channels, raster


def box(w, h, x0, y0, x1, y1):
    """Fractional region -> half-open pixel box, clamped, never empty."""
    if not (0.0 <= x0 <= x1 <= 1.0) or not (0.0 <= y0 <= y1 <= 1.0):
        sys.exit(f"pixelprobe: region {x0},{y0},{x1},{y1} is not an ordered "
                 f"pair of fractions in [0,1]")
    px0, px1 = int(x0 * w), int(round(x1 * w))
    py0, py1 = int(y0 * h), int(round(y1 * h))
    px0, py0 = min(px0, w - 1), min(py0, h - 1)
    return px0, py0, max(px1, px0 + 1), max(py1, py0 + 1)


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    path, op = argv[1], argv[2]
    args = [float(a) for a in argv[3:]]
    w, h, ch, raster = read_netpbm(path)
    white_min = int(os.environ.get('PIXEL_WHITE_MIN', '250'))

    def rgb(px, py):
        o = (py * w + px) * ch
        return (raster[o],) * 3 if ch == 1 else tuple(raster[o:o + 3])

    if op == 'pixel':
        if len(args) != 2:
            sys.exit("pixelprobe: pixel takes X Y")
        px, py, _, _ = box(w, h, args[0], args[1], args[0], args[1])
        print('%d %d %d' % rgb(px, py))
        return

    if len(args) != 4:
        sys.exit(f"pixelprobe: {op} takes X0 Y0 X1 Y1")
    px0, py0, px1, py1 = box(w, h, *args)
    n = (px1 - px0) * (py1 - py0)

    if op == 'mean':
        sums = [0, 0, 0]
        for py in range(py0, py1):
            for px in range(px0, px1):
                p = rgb(px, py)
                sums[0] += p[0]; sums[1] += p[1]; sums[2] += p[2]
        print('%.1f %.1f %.1f' % (sums[0] / n, sums[1] / n, sums[2] / n))
    elif op == 'nonwhite':
        painted = 0
        for py in range(py0, py1):
            for px in range(px0, px1):
                if min(rgb(px, py)) < white_min:
                    painted += 1
        print('%.4f' % (painted / n))
    else:
        sys.exit(f"pixelprobe: unknown operation '{op}'")


if __name__ == '__main__':
    main(sys.argv)
