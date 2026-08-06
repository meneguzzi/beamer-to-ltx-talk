#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Felipe Meneguzzi
# Part of beamer-to-ltx-talk: https://github.com/meneguzzi/beamer-to-ltx-talk

"""
alt_text_audit.py — build an alt-text worklist for a deck (or a whole course).

Tagged PDF without alt text is not accessible. This finds every \\includegraphics
that has no alt=, gathers the two things needed to write good alt text, and renders
the image so the agent can actually LOOK at it:

  1. the image, rasterised to PNG  (the figure's *content* — node labels, axes, ...)
  2. its LaTeX context             (the figure's *role* — why it is on the slide)

Both are required. Context alone yields useless alt text ("a search tree"); the image
alone misses the argument it is making. See references/alt-text.md.

Usage:
    alt_text_audit.py DECK.tex [DECK2.tex ...] [--render-dir DIR] [--json OUT.json]
                      [--no-render]

Writes a JSON worklist (one entry per image, with an empty "alt" field to fill) and
prints a human-readable summary. Feed the filled JSON to alt_text_apply.py.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys

INCLUDE_RE = re.compile(r'\\includegraphics(?:\s*\[([^\]]*)\])?\s*\{([^}]+)\}')
FRAMEBEGIN_RE = re.compile(r'\\begin\{frame\*?\}')
FRAMEEND_RE = re.compile(r'\\end\{frame\*?\}')
FRAMETITLE_RE = re.compile(r'\\frametitle\{(.+)\}\s*$')
IMG_EXTS = ('', '.pdf', '.png', '.jpg', '.jpeg', '.eps')

# LaTeX noise to strip when harvesting prose context
STRIP_RE = re.compile(r'\\(begin|end)\{[^}]*\}|\\(item|centering|vspace|hspace|only|onslide|'
                      r'uncover|visible|textbf|textit|emph|small|large|Large|footnotesize)\b'
                      r'(<[^>]*>)?|[{}]|\$[^$]*\$')


def clean(line: str) -> str:
    return ' '.join(STRIP_RE.sub(' ', line).split())


def resolve(deck_dir: str, path: str):
    for ext in IMG_EXTS:
        p = os.path.join(deck_dir, path + ext)
        if os.path.isfile(p):
            return p
    return None


def render(src: str, out_dir: str, key: str):
    """Rasterise the image to a PNG the agent can view. Returns the PNG path or None."""
    os.makedirs(out_dir, exist_ok=True)
    dst = os.path.join(out_dir, key + '.png')
    ext = os.path.splitext(src)[1].lower()
    try:
        if ext == '.pdf':
            subprocess.run(['pdftoppm', '-png', '-r', '60', '-f', '1', '-l', '1',
                            '-singlefile', src, dst[:-4]],
                           check=True, capture_output=True)
        elif ext in ('.png', '.jpg', '.jpeg'):
            shutil.copyfile(src, dst)
        else:
            return None
        return dst if os.path.isfile(dst) else None
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return None


def audit(deck: str, render_dir: str, do_render: bool):
    deck_dir = os.path.dirname(os.path.abspath(deck)) or '.'
    lines = open(deck, encoding='utf-8').read().split('\n')

    # map each line -> (frame_start, frame_end) and the frame's \frametitle
    frame_of, title_of = {}, {}
    start = None
    for i, l in enumerate(lines):
        if FRAMEBEGIN_RE.search(l):
            start = i
        if FRAMEEND_RE.search(l) and start is not None:
            title = ''
            for j in range(start, i + 1):
                m = FRAMETITLE_RE.search(lines[j])
                if m:
                    title = m.group(1).strip()
                    break
            for j in range(start, i + 1):
                frame_of[j] = (start, i)
                title_of[j] = title
            start = None

    out = []
    for i, l in enumerate(lines):
        if l.lstrip().startswith('%'):
            continue
        for m in INCLUDE_RE.finditer(l):
            opts, path = (m.group(1) or ''), m.group(2).strip()
            if re.search(r'\balt\s*=', opts):
                continue                                   # already done
            fs, fe = frame_of.get(i, (max(0, i - 8), min(len(lines), i + 8)))
            prose = []
            for j in range(fs, fe + 1):
                if j == i or lines[j].lstrip().startswith('%'):
                    continue
                if '\\includegraphics' in lines[j]:
                    continue
                c = clean(lines[j])
                if len(c) > 3:
                    prose.append(c)
            src = resolve(deck_dir, path)
            key = f"{os.path.splitext(os.path.basename(deck))[0]}__{os.path.basename(path)}"
            key = re.sub(r'[^A-Za-z0-9_.-]', '_', key)
            png = render(src, render_dir, key) if (src and do_render) else None
            # sibling overlays of the same figure (\only<1>{a}\only<2>{b}) share a frame
            overlay = bool(re.search(r'\\(only|onslide|uncover|visible)\s*<', l))
            out.append({
                'deck': deck,
                'line': i + 1,
                'image': path,
                'resolved': src,
                'preview_png': png,
                'existing_options': opts,
                'frametitle': title_of.get(i, ''),
                'overlay_variant': overlay,
                'context': prose[:12],
                'alt': ''      # <-- agent fills this in, after VIEWING preview_png
            })
    return out


def main():
    ap = argparse.ArgumentParser(description='Build an alt-text worklist for ltx-talk decks.')
    ap.add_argument('decks', nargs='+')
    ap.add_argument('--render-dir', default='/tmp/alt-previews')
    ap.add_argument('--json', default='alt-worklist.json')
    ap.add_argument('--no-render', action='store_true')
    a = ap.parse_args()

    items = []
    for d in a.decks:
        items += audit(d, a.render_dir, not a.no_render)

    with open(a.json, 'w', encoding='utf-8') as f:
        json.dump(items, f, indent=2, ensure_ascii=False)

    print(f'{len(items)} image(s) missing alt text -> {a.json}', file=sys.stderr)
    for it in items:
        flag = '' if it['preview_png'] else '  [NO PREVIEW - resolve/render failed]'
        print(f"  {it['deck']}:{it['line']}  {it['image']}{flag}", file=sys.stderr)
        print(f"      frame: {it['frametitle']}", file=sys.stderr)
    print('\nNext: VIEW each preview_png, read its context, fill "alt", '
          'then run alt_text_apply.py.', file=sys.stderr)


if __name__ == '__main__':
    main()
