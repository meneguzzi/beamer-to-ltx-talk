#!/usr/bin/env python3
"""
convert_deck.py — pattern-based Beamer -> ltx-talk source transformer.

Faithful and minimal: rewrites only the constructs the class change forces, never
touches commented-out lines, preserves indentation, and reports every change and every
compromise. Idempotent: safe to re-run.

It does the mechanical 80%. It deliberately does NOT auto-rewrite things that need human
judgement (the title-page content, folding double titles, anything inside a frame body) —
it warns about those instead.

Usage:
    convert_deck.py DECK.tex [--in-place] [--sections {heading,keep}]
                    [--old-preamble common-packages.tex] [--new-preamble ltx-common.tex]

Without --in-place it prints the converted source to stdout and the report to stderr.
See references/compromises.md for the IDs cited in warnings (C-ALGO, C-TOC, ...).
"""
import argparse
import re
import sys

WARN = []          # (id, message)
NOTE = []          # informational change counts


def is_comment(line: str) -> bool:
    return line.lstrip().startswith('%')


def strip_atbeginsection(text: str):
    """Remove a \\AtBeginSection[...]{ ... } block by brace matching (multi-line)."""
    out = []
    i, n, removed = 0, len(text), 0
    while i < n:
        m = re.compile(r'\\AtBeginSection\b\s*(\[[^\]]*\])?\s*\{').match(text, i)
        if not m:
            out.append(text[i])
            i += 1
            continue
        # found the opening brace of the body; walk to its match
        depth, j = 1, m.end()
        while j < n and depth:
            if text[j] == '\\':           # skip escaped char
                j += 2
                continue
            if text[j] == '{':
                depth += 1
            elif text[j] == '}':
                depth -= 1
            j += 1
        removed += 1
        i = j
        # swallow a single trailing newline left behind
        if i < n and text[i] == '\n':
            i += 1
    if removed:
        NOTE.append(f'removed {removed} \\AtBeginSection block(s)')
        WARN.append(('C-TOC',
                     'Auto-outline frames (\\AtBeginSection + \\tableofcontents) removed: '
                     'ltx-talk \\tableofcontents corrupts the tag tree. Section dividers '
                     'from \\heading{} substitute for them.'))
    return ''.join(out)


def convert_line(line: str, sections_mode: str, old_pre: str, new_pre: str) -> str:
    if is_comment(line):
        return line

    # class line
    new, k = re.subn(r'(\\documentclass(?:\[[^\]]*\])?\{)beamer(\})', r'\1ltx-talk\2', line)
    if k:
        NOTE.append('class -> ltx-talk')
        return new

    # preamble input swap
    if old_pre and old_pre in line and '\\input' in line:
        return line.replace(old_pre, new_pre)

    # --- frame title transforms (single line, no nested braces in the title) ---
    body, comment = line, ''
    cm = re.search(r'(?<!\\)%.*$', line)
    if cm:
        body, comment = line[:cm.start()], line[cm.start():]

    # double braced title {A}{B}  -> \frametitle{A --- B}  (warn: Beamer subtitle)
    m = re.match(r'^(\s*)\\begin\{frame\}(\[[^\]]*\])?\{([^{}]*)\}\{([^{}]*)\}\s*$', body)
    if m:
        opt = m.group(2) or ''
        WARN.append(('C-FRAMETITLE',
                     f'Double title folded: {{{m.group(3)}}}{{{m.group(4)}}} -> '
                     f'"{m.group(3)} --- {m.group(4)}" (ltx-talk has no frame subtitle in '
                     'output). Review wording.'))
        NOTE.append('double-title frame -> frametitle')
        return f'{m.group(1)}\\begin{{frame}}{opt} {comment}\n{m.group(1)}\\frametitle{{{m.group(3)} --- {m.group(4)}}}\n'

    # empty title {} -> drop the group (keep trailing comment, e.g. activity slides)
    m = re.match(r'^(\s*)\\begin\{frame\}(\[[^\]]*\])?\{\}\s*$', body)
    if m:
        opt = m.group(2) or ''
        NOTE.append('empty-title frame cleaned')
        return f'{m.group(1)}\\begin{{frame}}{opt}{(" " + comment) if comment else ""}\n'

    # verbatim frame: [...,containsverbatim]{T} -> frame* + frametitle  (C-VERBATIM)
    m = re.match(r'^(\s*)\\begin\{frame\}\[([^\]]*)\]\{([^{}]*)\}\s*$', body)
    if m and 'containsverbatim' in m.group(2):
        opts = ','.join(o for o in (x.strip() for x in m.group(2).split(','))
                        if o and o != 'containsverbatim')
        WARN.append(('C-VERBATIM',
                     f'Verbatim frame "{m.group(3)}" -> frame* (drop containsverbatim). '
                     'Ensure the matching \\end{frame} becomes \\end{frame*}.'))
        NOTE.append('containsverbatim frame -> frame*')
        title = f'{m.group(1)}\\frametitle{{{m.group(3)}}}\n'
        if opts:
            return f'{m.group(1)}\\begin{{frame*}}[{opts}]\n{title}'
        return f'{m.group(1)}\\begin{{frame*}}\n{title}'

    # normal braced title  [opts]{T}  or  {T}  ->  \frametitle{T}
    m = re.match(r'^(\s*)\\begin\{frame\}(\[[^\]]*\])?\{([^{}]+)\}\s*$', body)
    if m:
        opt = m.group(2) or ''
        NOTE.append('frame title -> frametitle')
        tail = (' ' + comment) if comment else ''
        return f'{m.group(1)}\\begin{{frame}}{opt}{tail}\n{m.group(1)}\\frametitle{{{m.group(3)}}}\n'

    # frame title with a trailing comment after the brace
    m = re.match(r'^(\s*)\\begin\{frame\}(\[[^\]]*\])?\{([^{}]+)\}\s*$', body) if comment else None
    if m:
        opt = m.group(2) or ''
        NOTE.append('frame title (w/ comment) -> frametitle')
        return f'{m.group(1)}\\begin{{frame}}{opt} {comment}\n{m.group(1)}\\frametitle{{{m.group(3)}}}\n'

    # sections -> headings (divider). Plain \section is silent under ltx-talk otherwise.
    m = re.match(r'^(\s*)\\section\{([^{}]*)\}\s*$', body)
    if m and sections_mode == 'heading':
        NOTE.append('section -> heading')
        return f'{m.group(1)}\\heading{{{m.group(2)}}}\n'

    return line


def main():
    ap = argparse.ArgumentParser(description='Beamer -> ltx-talk source transformer.')
    ap.add_argument('deck')
    ap.add_argument('--in-place', action='store_true')
    ap.add_argument('--sections', choices=['heading', 'keep'], default='heading')
    ap.add_argument('--old-preamble', default='common-packages.tex')
    ap.add_argument('--new-preamble', default='ltx-common.tex')
    args = ap.parse_args()

    text = open(args.deck, encoding='utf-8').read()
    text = strip_atbeginsection(text)

    out_lines = [convert_line(ln + '\n', args.sections, args.old_preamble, args.new_preamble)
                 for ln in text.split('\n')]
    result = ''.join(out_lines)
    if result.endswith('\n\n'):
        result = result[:-1]

    # blanket warnings worth raising regardless of what was rewritten
    if re.search(r'\\begin\{algorithmic\}', text):
        WARN.append(('C-ALGO', 'Deck contains algorithms: the preamble MUST use classic '
                     'algorithmicx + algpseudocode[noend], NOT algpseudocodex, or every '
                     'algorithm frame fails under tagging ("Improper \\halign inside $$\'s"). '
                     'Confirm the shared preamble (it is loaded via \\input, not this file).'))
    if '\\maketitle' in text:
        WARN.append(('C-TITLEPAGE', 'A \\maketitle title frame remains: replace with '
                     '\\coursetitlepage{title}{subtitle}{attribution} by hand (stock '
                     '\\maketitle fills the frame and any trailing text overlaps).'))
    if re.search(r'\\includegraphics(\[[^\]]*\])?\{', text):
        imgs = len(re.findall(r'\\includegraphics(?:\[[^\]]*\])?\{', text))
        alts = len(re.findall(r'\balt\s*=', text))
        if alts < imgs:
            WARN.append(('ALT', f'{imgs - alts} of {imgs} \\includegraphics lack alt= text; '
                         'add it for accessible tagged output.'))

    if args.in_place:
        open(args.deck, 'w', encoding='utf-8').write(result)
    else:
        sys.stdout.write(result)

    # report -> stderr
    from collections import Counter
    print('\n=== convert_deck.py report ===', file=sys.stderr)
    for change, c in Counter(NOTE).items():
        print(f'  [{c:>3}] {change}', file=sys.stderr)
    if WARN:
        print('  --- WARNINGS / compromises (see references/compromises.md) ---', file=sys.stderr)
        seen = set()
        for cid, msg in WARN:
            key = (cid, msg)
            if key in seen:
                continue
            seen.add(key)
            print(f'  ⚠ [{cid}] {msg}', file=sys.stderr)
    print('  Manual follow-ups: title page, double titles, frame* \\end tags, alt text.',
          file=sys.stderr)


if __name__ == '__main__':
    main()
