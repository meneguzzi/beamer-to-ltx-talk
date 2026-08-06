#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Felipe Meneguzzi
# Part of beamer-to-ltx-talk: https://github.com/meneguzzi/beamer-to-ltx-talk

"""
alt_text_apply.py — inject reviewed alt text back into the decks.

Reads the worklist produced by alt_text_audit.py (with the "alt" fields filled in)
and rewrites each \\includegraphics to carry alt={...}:

    \\includegraphics[width=.6\\linewidth]{x.pdf}
      -> \\includegraphics[width=.6\\linewidth,alt={A search tree ...}]{x.pdf}
    \\includegraphics{x.pdf}
      -> \\includegraphics[alt={A search tree ...}]{x.pdf}

Entries with an empty "alt" are skipped (and reported), so it is safe to fill the
worklist in batches. Never touches an \\includegraphics that already has alt=.
Idempotent. Use --decorative to emit alt={} for purely ornamental images.

Usage:
    alt_text_apply.py alt-worklist.json [--dry-run]
"""
import argparse
import json
import re
import sys
from collections import defaultdict

INCLUDE_RE = re.compile(r'(\\includegraphics)(?:\s*\[([^\]]*)\])?\s*\{([^}]+)\}')


def escape_alt(text: str) -> str:
    """alt={...} is read as LaTeX; keep it plain and balanced."""
    t = ' '.join(text.split())
    t = t.replace('\\', '/').replace('{', '(').replace('}', ')')
    for ch in ('&', '%', '#', '_', '$'):
        t = t.replace(ch, '\\' + ch)
    return t


def main():
    ap = argparse.ArgumentParser(description='Inject alt text into ltx-talk decks.')
    ap.add_argument('worklist')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    items = json.load(open(a.worklist, encoding='utf-8'))
    by_deck = defaultdict(list)
    skipped = 0
    for it in items:
        if not it.get('alt', '').strip():
            skipped += 1
            continue
        by_deck[it['deck']].append(it)

    total = 0
    for deck, entries in by_deck.items():
        lines = open(deck, encoding='utf-8').read().split('\n')
        for it in entries:
            i = it['line'] - 1
            if i >= len(lines):
                print(f'  ! {deck}:{it["line"]} out of range - re-run the audit', file=sys.stderr)
                continue
            target = it['image'].strip()
            alt = escape_alt(it['alt'])

            def repl(m):
                if m.group(3).strip() != target:
                    return m.group(0)
                opts = m.group(2) or ''
                if re.search(r'\balt\s*=', opts):
                    return m.group(0)                       # already has alt
                new = f'{opts},alt={{{alt}}}' if opts.strip() else f'alt={{{alt}}}'
                return f'{m.group(1)}[{new}]{{{m.group(3)}}}'

            new_line, n = INCLUDE_RE.subn(repl, lines[i])
            if new_line != lines[i]:
                lines[i] = new_line
                total += 1
            else:
                print(f'  ! {deck}:{it["line"]} no match for {target} '
                      f'(line moved?) - re-run the audit', file=sys.stderr)
        if not a.dry_run:
            open(deck, 'w', encoding='utf-8').write('\n'.join(lines))
        print(f'{"[dry-run] " if a.dry_run else ""}{deck}: {len(entries)} alt text(s)',
              file=sys.stderr)

    print(f'\n{total} \\includegraphics updated; {skipped} still without alt text.',
          file=sys.stderr)
    if skipped:
        print('Fill the remaining "alt" fields and re-run (safe: it is idempotent).',
              file=sys.stderr)


if __name__ == '__main__':
    main()
