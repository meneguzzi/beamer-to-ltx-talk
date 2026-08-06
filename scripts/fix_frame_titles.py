#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Felipe Meneguzzi
# Part of beamer-to-ltx-talk: https://github.com/meneguzzi/beamer-to-ltx-talk

"""
fix_frame_titles.py — brace-matching frame-title fixer. Run AFTER convert_deck.py.

convert_deck.py folds braced frame titles with a regex that cannot see nested braces
([^{}]*), so it silently leaves behind anything like:

    \\begin{frame}[c]{\\only<1>{Example}\\only<2>{Find a plan for}}     % single, nested
    \\begin{frame}[c]{Arc consistency}{{\\sc Inference}}                % double, nested

Under ltx-talk a braced title is NOT a title: it renders as ordinary BODY TEXT and the
header stays empty (C-FRAMETITLE). This compiles with no error or warning, so it is easy
to ship a deck full of title-less frames without noticing.

This script re-scans with a real brace matcher and rewrites:

    \\begin{frame}[opts]{A}      -> \\begin{frame}[opts]  +  \\frametitle{A}
    \\begin{frame}[opts]{A}{B}   -> \\begin{frame}[opts]  +  \\frametitle{A --- B}

Single-line frame headers only; never touches comments; idempotent.

Usage:  fix_frame_titles.py DECK.tex [DECK2.tex ...] [--dry-run]
"""
import argparse
import re
import sys

HEAD_RE = re.compile(r'^(\s*)\\begin\{frame\}(\[[^\]]*\])?\{')


def match_group(s: str, i: int):
    """s[i] == '{'; return (content, index_after_closing_brace) or None."""
    if i >= len(s) or s[i] != '{':
        return None
    depth, j = 1, i + 1
    while j < len(s) and depth:
        c = s[j]
        if c == '\\':
            j += 2
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
        j += 1
    return (s[i + 1:j - 1], j) if depth == 0 else None


def fix(path: str, dry: bool) -> int:
    lines = open(path, encoding='utf-8').read().split('\n')
    out, n = [], 0
    for line in lines:
        if line.lstrip().startswith('%'):
            out.append(line)
            continue
        m = HEAD_RE.match(line)
        if not m:
            out.append(line)
            continue
        indent, opt = m.group(1), m.group(2) or ''
        first = match_group(line, m.end() - 1)
        if not first:
            out.append(line)
            continue
        a, k = first
        title, end = a, k
        second = match_group(line, k) if k < len(line) and line[k] == '{' else None
        if second:
            b, k2 = second
            title, end = f'{a} --- {b}', k2
        if line[end:].strip():        # trailing junk -> leave it for a human
            out.append(line)
            continue
        out.append(f'{indent}\\begin{{frame}}{opt}')
        out.append(f'{indent}\\frametitle{{{title}}}')
        n += 1
    if n and not dry:
        open(path, 'w', encoding='utf-8').write('\n'.join(out))
    return n


def main():
    ap = argparse.ArgumentParser(description='Brace-matching frame-title fixer.')
    ap.add_argument('decks', nargs='+')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    total = 0
    for d in a.decks:
        n = fix(d, a.dry_run)
        total += n
        if n:
            print(f'{"[dry-run] " if a.dry_run else ""}{d}: folded {n} braced title(s)',
                  file=sys.stderr)
    print(f'{total} frame title(s) fixed.', file=sys.stderr)


if __name__ == '__main__':
    main()
