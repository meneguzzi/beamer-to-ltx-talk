#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Felipe Meneguzzi
# Part of beamer-to-ltx-talk: https://github.com/meneguzzi/beamer-to-ltx-talk

r"""
convert_deck.py — pattern-based Beamer -> ltx-talk source transformer.

Faithful and minimal: rewrites only the constructs the class change forces, never
touches commented-out lines, preserves indentation, and reports every change and every
compromise. Idempotent: safe to re-run.

It does the mechanical 80%. It deliberately does NOT auto-rewrite things that need human
judgement (the title-page content, folding double titles, anything inside a frame body) —
it warns about those instead.

Usage:
    convert_deck.py DECK.tex [--in-place]
                    [--old-preamble common-packages.tex] [--new-preamble ltx-common.tex]
    convert_deck.py DECK.tex --lint      # report only, rewrite nothing; exit 1 if issues

\section is left alone on purpose: the shared preamble redefines \section to emit the
section divider frame, so the decks need no edit (see C-TOC in references/compromises.md).

--lint catches the failures the COMPILER never reports: a braced frame title renders as
body text, and \center{...} corrupts the tag tree from nowhere near the offending line.
Run it before every build.

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


def match_brace(text: str, open_idx: int):
    """Index just past the '}' matching the '{' at open_idx, or None if unbalanced."""
    depth, j, n = 1, open_idx + 1, len(text)
    while j < n and depth:
        if text[j] == '\\':                 # skip an escaped char
            j += 2
            continue
        if text[j] == '{':
            depth += 1
        elif text[j] == '}':
            depth -= 1
        j += 1
    return j if depth == 0 else None


def fix_center_arg(text: str):
    r"""C-CENTER-ARG: \center{X} -> \begin{center}X\end{center}.

    \center is a DECLARATION (the internal begin of the center env), not a command taking
    an argument. Beamer tolerated the misuse silently; under tagging it leaks an unclosed
    paragraph and yields "number of automatic begin/end text-unit para hooks differ",
    reported nowhere near the offending line.
    """
    out, i, n, fixed = [], 0, len(text), 0
    pat = re.compile(r'\\center\s*\{')
    while i < n:
        m = pat.search(text, i)
        if not m:
            out.append(text[i:])
            break
        # don't touch commented-out lines
        bol = text.rfind('\n', 0, m.start()) + 1
        if text[bol:m.start()].lstrip().startswith('%'):
            out.append(text[i:m.end()])
            i = m.end()
            continue
        end = match_brace(text, m.end() - 1)
        if end is None:                      # unbalanced: leave it, but shout
            line_no = text.count('\n', 0, m.start()) + 1
            WARN.append(('C-CENTER-ARG',
                         f'line {line_no}: \\center{{...}} with unbalanced braces — could not '
                         'rewrite. Fix by hand: \\center is a declaration, not a command.'))
            out.append(text[i:m.end()])
            i = m.end()
            continue
        inner = text[m.end():end - 1]
        out.append(text[i:m.start()])
        out.append(f'\\begin{{center}}{inner}\\end{{center}}')
        i = end
        fixed += 1
    if fixed:
        NOTE.append(f'\\center{{...}} -> center env ({fixed})')
        WARN.append(('C-CENTER-ARG',
                     f'Rewrote {fixed} \\center{{...}} misuse(s). \\center is a declaration, '
                     'not a command taking an argument; under tagging it leaks an unclosed '
                     'paragraph ("begin/end text-unit para hooks differ") far from the line.'))
    return ''.join(out)


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
                     'ltx-talk \\tableofcontents corrupts the tag tree. The preamble\'s '
                     'redefined \\section emits a divider frame instead (\\section* to opt out).'))
    return ''.join(out)


def pair_framestar_ends(text: str) -> str:
    r"""C-VERBATIM: close every \begin{frame*} with \end{frame*}, not \end{frame}.

    convert_deck rewrites the \begin of a verbatim frame but cannot see its matching
    \end from a line-local rewrite, so we walk the file afterwards. frame* cannot
    nest, so a simple in/out flag is enough.
    """
    out, inside, fixed = [], False, 0
    for line in text.split('\n'):
        if not is_comment(line):
            if '\\begin{frame*}' in line:
                inside = True
            elif inside and '\\end{frame}' in line:
                line = line.replace('\\end{frame}', '\\end{frame*}')
                inside, fixed = False, fixed + 1
        out.append(line)
    if fixed:
        NOTE.append(f'\\end{{frame}} -> \\end{{frame*}} ({fixed})')
    return '\n'.join(out)


def convert_line(line: str, old_pre: str, new_pre: str) -> str:
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

    # verbatim frame: [...,containsverbatim]{T} -> frame* + frametitle  (C-VERBATIM)
    # MUST run before the double/empty/normal-title branches below: a verbatim frame with
    # an empty title (\begin{frame}[c,containsverbatim]{}) would otherwise be caught by the
    # empty-title rule, which drops the {} but leaves a PLAIN frame — and the listing then
    # breaks with "Paragraph ended before \lst@next". The title group is OPTIONAL here so
    # title-less verbatim frames convert too.
    # NOTE: all five regexes below accept an optional leading <overlayspec> (e.g.
    # \begin{frame}<3>[c]{Title}) before the [opts] group. Beamer allows the overlay
    # spec ahead of the options bracket, and a deck that has one there was, until this
    # was found on a real course, silently invisible to both this script AND the
    # Step-4 verification grep in SKILL.md — a title-less/unconverted frame reported
    # as "clean". See C-FRAMETITLE in compromises.md.
    m = re.match(r'^(\s*)\\begin\{frame\}(<[^>]*>)?\[([^\]]*)\](\{([^{}]*)\})?\s*$', body)
    if m and 'containsverbatim' in m.group(3):
        overlay = m.group(2) or ''
        opts = ','.join(o for o in (x.strip() for x in m.group(3).split(','))
                        if o and o != 'containsverbatim')
        titletext = m.group(5)          # None (no group) or '' (empty {}) -> no \frametitle
        WARN.append(('C-VERBATIM',
                     f'Verbatim frame "{titletext or "(untitled)"}" -> frame* (drop '
                     'containsverbatim). Ensure the matching \\end{frame} becomes '
                     '\\end{frame*}.'))
        NOTE.append('containsverbatim frame -> frame*')
        title = f'{m.group(1)}\\frametitle{{{titletext}}}\n' if titletext else ''
        head = f'{m.group(1)}\\begin{{frame*}}{overlay}[{opts}]\n' if opts else \
               f'{m.group(1)}\\begin{{frame*}}{overlay}\n'
        return head + title

    # double braced title {A}{B}  -> \frametitle{A --- B}  (warn: Beamer subtitle)
    m = re.match(r'^(\s*)\\begin\{frame\}(<[^>]*>)?(\[[^\]]*\])?\{([^{}]*)\}\{([^{}]*)\}\s*$', body)
    if m:
        overlay = m.group(2) or ''
        opt = m.group(3) or ''
        WARN.append(('C-FRAMETITLE',
                     f'Double title folded: {{{m.group(4)}}}{{{m.group(5)}}} -> '
                     f'"{m.group(4)} --- {m.group(5)}" (ltx-talk has no frame subtitle in '
                     'output). Review wording.'))
        NOTE.append('double-title frame -> frametitle')
        return f'{m.group(1)}\\begin{{frame}}{overlay}{opt} {comment}\n{m.group(1)}\\frametitle{{{m.group(4)} --- {m.group(5)}}}\n'

    # empty title {} -> drop the group (keep trailing comment, e.g. activity slides)
    m = re.match(r'^(\s*)\\begin\{frame\}(<[^>]*>)?(\[[^\]]*\])?\{\}\s*$', body)
    if m:
        overlay = m.group(2) or ''
        opt = m.group(3) or ''
        NOTE.append('empty-title frame cleaned')
        return f'{m.group(1)}\\begin{{frame}}{overlay}{opt}{(" " + comment) if comment else ""}\n'

    # normal braced title  [opts]{T}  or  {T}  ->  \frametitle{T}
    m = re.match(r'^(\s*)\\begin\{frame\}(<[^>]*>)?(\[[^\]]*\])?\{([^{}]+)\}\s*$', body)
    if m:
        overlay = m.group(2) or ''
        opt = m.group(3) or ''
        NOTE.append('frame title -> frametitle')
        tail = (' ' + comment) if comment else ''
        return f'{m.group(1)}\\begin{{frame}}{overlay}{opt}{tail}\n{m.group(1)}\\frametitle{{{m.group(4)}}}\n'

    # frame title with a trailing comment after the brace
    m = re.match(r'^(\s*)\\begin\{frame\}(<[^>]*>)?(\[[^\]]*\])?\{([^{}]+)\}\s*$', body) if comment else None
    if m:
        overlay = m.group(2) or ''
        opt = m.group(3) or ''
        NOTE.append('frame title (w/ comment) -> frametitle')
        return f'{m.group(1)}\\begin{{frame}}{overlay}{opt} {comment}\n{m.group(1)}\\frametitle{{{m.group(4)}}}\n'

    # \section is deliberately NOT rewritten: the shared preamble redefines \section
    # itself to emit the divider frame (C-TOC), so the decks keep their original lines.
    return line


#: (compromise-id, compiled regex, message) — pure source greps, no build needed.
#: Each entry is a failure the LaTeX compiler will NOT report.
LINTS = [
    ('C-FRAMETITLE',
     re.compile(r'^\s*\\begin\{frame\}(?:<[^>]*>)?(?:\[[^\]]*\])?\{'),
     'braced frame title left unconverted — this renders as BODY TEXT with no error and '
     'no title in the header. Convert to \\frametitle{...} (nested braces: run '
     'scripts/fix_frame_titles.py).'),
    ('C-CENTER-ARG',
     re.compile(r'\\center\s*\{'),
     '\\center{...} takes no argument — it is a declaration. Under tagging this leaks an '
     'unclosed paragraph ("begin/end text-unit para hooks differ") reported far from here. '
     'Use \\begin{center}...\\end{center}.'),
    ('C-CENTER-ARG',
     re.compile(r'\\(?:centering|raggedright|raggedleft)\s*\{'),
     'declaration used as if it took an argument — same tag-tree hazard as \\center{...}. '
     'Use the matching environment, or drop the braces so it acts as a declaration.'),
    ('C-ONSLIDE-ARG',
     re.compile(r'\\onslide\s*<[^>]*>\s*\{'),
     '\\onslide takes NO braced argument in ltx-talk (\\NewDocumentCommand \\onslide '
     '{ D <> { all } }), so \\onslide<n>{...} is a DECLARATION plus a stray group: it blanks '
     'everything after it to the end of the frame. The state is a GLOBAL token list, so '
     'tabular cells and other groups do not contain the leak. Compiles clean; visible only '
     'by rendering an early overlay. Use \\uncover<n>{...} (reserves space) or \\only<n>{...} '
     '(does not). Bare \\onslide<n> as a declaration is fine.'),
    ('C-OVERLAY-ALGO',
     re.compile(r'\\State\s*<'),
     '\\State<n> is NOT supported by classic algpseudocode: the spec is typeset as LITERAL '
     '"<n>" text on the slide and the overlay never fires. Use \\State \\uncover<n>{...}.'),
    ('C-OVERLAY-ALGO',
     re.compile(r'\\(?:onslide|only|visible|uncover)\s*<[^>]*>\s*\{\s*\\(?:State|Comment)\b'),
     'overlay wrapping \\State/\\Comment corrupts algorithmicx\'s csname block stack '
     '("Missing/Extra \\endcsname" at \\end{frame}). Keep \\State at the top level and '
     'overlay only its content: \\State \\uncover<n>{...}.'),
    ('C-OVERLAY-ALIGN',
     re.compile(r'\\onslide\s*<[^>]*>\s*\{\s*&'),
     'overlay wrapping the & of a tabular/align row ("Misplaced alignment tab character &"). '
     '& must stay at the top level: write  & \\uncover<n>{content}. (Only \\onslide leaks '
     'this way — \\only/\\uncover either omit or opacity-toggle their whole group and are '
     'safe around & and \\\\; verified on a real course, see C-OVERLAY-ALIGN in compromises.md.)'),
    ('C-OVERLAY-ALIGN',
     re.compile(r'\\onslide\s*<[^>]*>\s*\{[^{}]*\\\\\s*\}'),
     'overlay group swallows the row-ending \\\\ ("Misplaced alignment tab" / "Improper '
     '\\halign"). \\\\ must stay at the top level: \\uncover<n>{content} \\\\.'),
    ('C-DISPMATH-NEWLINE',
     re.compile(r'(?:\$\$|\\\])\s*\\\\'),
     '\\\\ immediately after display math ("There\'s no line here to end"): display math ends '
     'in vertical mode. Use \\vspace{...} or a blank line instead.'),
    ('C-TOC',
     re.compile(r'\\tableofcontents'),
     '\\tableofcontents corrupts the tag tree under ltx-talk. Remove it; the redefined '
     '\\section already emits a divider frame per section.'),
    ('C-NOBEAMER',
     re.compile(r'\\(?:usetheme|usecolortheme|usefonttheme|setbeamer\w*|usebeamer\w*|'
                r'beamercolorbox)\b'),
     'Beamer-only command; undefined in ltx-talk. Restyle via \\EditInstance.'),
    ('C-BACKGROUND',
     re.compile(r'\\usebackgroundtemplate'),
     'no equivalent in ltx-talk. Use an overlay tikz node — do NOT no-op stub it: these '
     'frames usually hold white text over a dark image, which would become invisible.'),
    ('C-ALGO',
     re.compile(r'\\usepackage(?:\[[^\]]*\])?\{algpseudocodex\}'),
     'algpseudocodex cannot be typeset under tagging at all. Swap to classic '
     'algorithmicx + algpseudocode[noend].'),
    ('C-ALGO-FLOAT',
     re.compile(r'\\begin\{algorithm\}'),
     'the `algorithm` FLOAT is not registered for tagging. Drop the float wrapper and keep '
     'bare (still tagged) `algorithmic`.'),
]


def missing_documentmetadata(text: str) -> bool:
    r"""True if the deck never activates \DocumentMetadata before \documentclass.

    ltx-talk REQUIRES \DocumentMetadata: without it the class half-loads and you get a
    cascade of "Undefined control sequence" (\institute, \hypersetup, frame*) plus
    "\normalsize is not defined" — none of which name the real cause. A deck satisfies
    the requirement either with a literal \DocumentMetadata or with a NON-commented
    \input of a file that sets it (conventionally tag-commands.tex). A commented-out
    \input (`% \input{../tag-commands.tex}`) is the trap this catches.
    """
    for line in text.split('\n'):
        code = line.split('%', 1)[0] if not line.lstrip().startswith('%') else ''
        if '\\documentclass' in code:
            return True                                  # reached class first -> missing
        if '\\DocumentMetadata' in code:
            return False
        if '\\input' in code and 'tag-commands' in code:
            return False
    return True


def lint(text: str, path: str) -> int:
    """Report source-level failures the compiler stays silent about. Returns issue count."""
    hits = []
    if missing_documentmetadata(text):
        hits.append((1, 'C-NO-DOCMETA',
                     'no \\DocumentMetadata reached before \\documentclass (is '
                     '\\input{...tag-commands...} commented out?). ltx-talk half-loads '
                     'without it: \\institute/\\hypersetup/frame*/\\normalsize all come '
                     'up "undefined", none naming the cause.', '\\documentclass{ltx-talk}'))
    for lineno, line in enumerate(text.split('\n'), 1):
        if is_comment(line):
            continue
        code = re.sub(r'(?<!\\)%.*$', '', line)     # ignore trailing comments
        for cid, pat, msg in LINTS:
            if pat.search(code):
                hits.append((lineno, cid, msg, line.strip()))

    print(f'\n=== convert_deck.py --lint: {path} ===', file=sys.stderr)
    if not hits:
        print('  clean — no silent-failure patterns found.', file=sys.stderr)
        return 0

    for lineno, cid, msg, src in hits:
        print(f'  {path}:{lineno}: [{cid}] {msg}', file=sys.stderr)
        print(f'      | {src}', file=sys.stderr)

    by_id = {}
    for _, cid, _, _ in hits:
        by_id[cid] = by_id.get(cid, 0) + 1
    summary = ', '.join(f'{c}x {i}' for i, c in sorted(by_id.items()))
    print(f'  --- {len(hits)} issue(s): {summary}', file=sys.stderr)
    print('  See references/compromises.md for each ID.', file=sys.stderr)
    return len(hits)


def main():
    ap = argparse.ArgumentParser(description='Beamer -> ltx-talk source transformer.')
    ap.add_argument('deck')
    ap.add_argument('--in-place', action='store_true')
    ap.add_argument('--lint', action='store_true',
                    help='report silent-failure patterns and exit 1 if any; rewrite nothing')
    ap.add_argument('--old-preamble', default='common-packages.tex')
    ap.add_argument('--new-preamble', default='ltx-common.tex')
    args = ap.parse_args()

    if args.lint:
        text = open(args.deck, encoding='utf-8').read()
        sys.exit(1 if lint(text, args.deck) else 0)

    text = open(args.deck, encoding='utf-8').read()
    text = strip_atbeginsection(text)
    text = fix_center_arg(text)

    out_lines = [convert_line(ln + '\n', args.old_preamble, args.new_preamble)
                 for ln in text.split('\n')]
    result = ''.join(out_lines)
    if result.endswith('\n\n'):
        result = result[:-1]
    result = pair_framestar_ends(result)      # C-VERBATIM: close frame* properly

    # blanket warnings worth raising regardless of what was rewritten
    if missing_documentmetadata(text):
        WARN.append(('C-NO-DOCMETA', 'This deck does not activate \\DocumentMetadata before '
                     '\\documentclass (a commented-out \\input{...tag-commands...}?). ltx-talk '
                     'half-loads without it — expect "undefined" \\institute/\\hypersetup/'
                     'frame*/\\normalsize. Uncomment the metadata input.'))
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
