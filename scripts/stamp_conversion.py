#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Felipe Meneguzzi
# Part of beamer-to-ltx-talk: https://github.com/meneguzzi/beamer-to-ltx-talk

r"""
stamp_conversion.py — record how a course was converted, in the converted repo.

A converted repo otherwise records NOTHING about its own conversion. When a catalogue
entry is retired, or a converter bug is fixed, or advice is RETRACTED, there is no way to
tell which decks predate the change short of re-reading every source. #7 retracted
C-TITLEPAGE's advice outright: every course converted before it carries a hand-rolled
title frame that is now dead weight, and nothing in those repos says so.

    stamp_conversion.py COURSE_DIR [--engine lualatex] [--dry-run]

Writes COURSE_DIR/ltx-talk-conversion.toml.

WHAT THIS RECORDS, AND WHY ONLY THIS
------------------------------------
Only the WRITE-ONCE facts: the things that cannot be reconstructed later. The ltx-talk
version that was installed on the day, and the converter revision that ran, are gone the
moment either is upgraded. Everything derivable from the sources later -- which
constructs a deck uses, what lint says today -- is deliberately NOT here, because a stale
copy of a derivable fact is worse than no copy.

Which entries were applied, which by hand, and which lint hits were knowingly skipped
belong to #12's upgrade task, not here: they need the advice to have settled, and they
want building alongside #18's assertion layer rather than twice.

WHY A SEPARATE FILE AND NOT THE SHARED PREAMBLE
-----------------------------------------------
assets/preamble-template.tex is copied by hand and then hand-edited forever. Measured on
the two copied preambles available: one still carries 8 unfilled <<placeholder>> markers
long after conversion. A stamp reading "ltx-talk version: <<VERSION>>" is worse than no
stamp, because a later reader would trust it. This file is written by a script, is not
meant to be hand-edited, and says so at the top.

It also must not go into the deck .tex files: convert_deck.py is text-in/text-out and
tests/run_converter_idempotence.sh enforces convert(x) == x, which a per-deck stamp
breaks on the second run.

HONEST DEGRADATION
------------------
Every value that cannot be determined is written as `unknown = [...]` with a reason,
rather than guessed or silently omitted. A missing key and a key that could not be
determined are different facts, and the upgrade task has to tell them apart.

⚠ ltx-talk's version comes from \ProvidesExplClass in the class file itself, NEVER from
`tlmgr info`: that reports cat-version 0.6.1 against an installed 0.6.2 and lags CTAN.
See references/compromises.md.

The path to that class file is deliberately NOT recorded. This file is committed to the
course repo, and an absolute path leaks the converting machine's layout while adding
nothing the version and date do not already say.
"""
import argparse
import datetime
import os
import re
import subprocess
import sys

STAMP_NAME = 'ltx-talk-conversion.toml'
SCHEMA = 1


def _run(cmd, cwd=None):
    """Return stripped stdout, or None if the command is missing or fails."""
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() or None if r.returncode == 0 else None


def ltx_talk_class_path():
    return _run(['kpsewhich', 'ltx-talk.cls'])


def ltx_talk_version(path):
    r"""(version, date) from \ProvidesExplClass {ltx-talk} {DATE} {VERSION}.

    The class file is the only honest source. `tlmgr info ltx-talk` reports the CTAN
    catalogue version, which lags: 0.6.1 while 0.6.2 was installed and in use.
    """
    if not path or not os.path.exists(path):
        return None, None
    try:
        with open(path, encoding='utf-8', errors='replace') as fh:
            head = fh.read(20000)
    except OSError:
        return None, None
    m = re.search(r'\\ProvidesExplClass\s*\{\s*ltx-talk\s*\}\s*'
                  r'\{\s*([^}]*?)\s*\}\s*\{\s*([^}]*?)\s*\}', head)
    if not m:
        return None, None
    return m.group(2), m.group(1)


def texlive_year():
    v = _run(['tex', '--version'])
    if not v:
        return None
    m = re.search(r'TeX Live (\d{4})', v)
    return m.group(1) if m else None


def skill_version():
    """git describe of THIS repo -- which converter ran."""
    here = os.path.dirname(os.path.abspath(__file__))
    return (_run(['git', 'describe', '--tags', '--always', '--dirty'], cwd=here)
            or _run(['git', 'rev-parse', '--short', 'HEAD'], cwd=here))


_DOCMETA_RE = re.compile(r'\\DocumentMetadata\s*\{', re.S)


def _strip_comments(text):
    r"""Blank out LaTeX comments, preserving offsets so indices stay valid.

    Needed before brace matching: these files routinely carry a commented-out variant of
    the very block being read (a pre-tagging \DocumentMetadata kept for reference), and a
    lone unbalanced brace inside a comment would otherwise throw the depth count off and
    swallow the rest of the file.
    """
    out, i, n = [], 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '\\' and i + 1 < n:
            out.append(text[i:i + 2])
            i += 2
            continue
        if ch == '%':
            j = text.find('\n', i)
            j = n if j == -1 else j
            out.append(' ' * (j - i))
            i = j
            continue
        out.append(ch)
        i += 1
    return ''.join(out)


def _balanced(text, open_idx):
    """Return the EFFECTIVE contents of the brace group whose '{' is at open_idx.

    Both the matching and the returned slice come from the comment-stripped copy. That
    matters twice over. Matching, because these files keep a commented-out variant of the
    block around and a lone unbalanced brace in one would run the depth count off the end.
    The slice, because what belongs in a provenance record is the settings that were IN
    FORCE -- a commented-out `testphase={` line recorded as if it were live is worse than
    not recording the block at all.
    """
    scan = _strip_comments(text)
    depth = 0
    for i in range(open_idx, len(scan)):
        if scan[i] == '{':
            depth += 1
        elif scan[i] == '}':
            depth -= 1
            if depth == 0:
                return scan[open_idx + 1:i]
    return None


def find_documentmetadata(course_dir):
    r"""The \DocumentMetadata argument actually in force, and the file it came from.

    Real courses keep it in a shared tag-commands.tex rather than in each deck, so search
    the tree rather than a single file. Commented-out occurrences are skipped: a deck
    shipping `% \DocumentMetadata{...}` is the C-NO-DOCMETA trap, and recording it as
    active would be a lie.
    """
    for root, dirs, files in os.walk(course_dir):
        dirs[:] = [d for d in dirs if d not in ('.git', 'build', '_build')]
        for name in sorted(files):
            if not name.endswith('.tex'):
                continue
            path = os.path.join(root, name)
            try:
                with open(path, encoding='utf-8', errors='replace') as fh:
                    text = fh.read()
            except OSError:
                continue
            for m in _DOCMETA_RE.finditer(text):
                line_start = text.rfind('\n', 0, m.start()) + 1
                if '%' in text[line_start:m.start()]:
                    continue
                body = _balanced(text, m.end() - 1)
                if body is not None:
                    rel = os.path.relpath(path, course_dir)
                    return ' '.join(body.split()), rel
    return None, None


def _toml_str(s):
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'


def render(fields, unknown, previous=None):
    lines = [
        '# Conversion provenance -- written by beamer-to-ltx-talk, not by hand.',
        '#',
        '# It records the versions this course was converted AGAINST, so a later upgrade can',
        '# tell what has changed since. Only write-once facts are here: things that cannot be',
        '# reconstructed once ltx-talk or the skill is upgraded. Anything derivable from the',
        '# sources is deliberately absent, because a stale copy of a derivable fact is worse',
        '# than no copy.',
        '#',
        '# Re-running stamp_conversion.py updates this file in place.',
        '',
        f'schema = {SCHEMA}',
        '',
        '[conversion]',
    ]
    for k, v in fields['conversion'].items():
        lines.append(f'{k} = {_toml_str(v)}')
    lines += ['', '[ltx_talk]']
    for k, v in fields['ltx_talk'].items():
        lines.append(f'{k} = {_toml_str(v)}')
    lines += ['', '[skill]']
    for k, v in fields['skill'].items():
        lines.append(f'{k} = {_toml_str(v)}')

    lines += ['', '# Values that could not be determined at stamp time, and why. A key listed',
              '# here is NOT the same as a key that was never asked for: do not treat an',
              '# undetermined value as a default.', '[unknown]']
    for k, why in unknown.items():
        lines.append(f'{k} = {_toml_str(why)}')

    if previous:
        lines += ['', '# Previous stamps, oldest last. Kept so an upgrade can see what a repo',
                  '# was converted against before it was re-stamped.']
        for p in previous:
            lines += ['', '[[superseded]]']
            for k, v in p.items():
                lines.append(f'{k} = {_toml_str(v)}')
    return '\n'.join(lines) + '\n'


_KV_RE = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"(.*)"\s*$')


def read_existing(path):
    """Flat {section.key: value} of an existing stamp. Tolerant on purpose: this file may
    have been written by an older schema, and failing to parse it must not stop a
    re-stamp."""
    out, section = {}, None
    try:
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                line = line.rstrip('\n')
                if line.startswith('[['):
                    section = None
                    continue
                if line.startswith('['):
                    section = line.strip('[]')
                    continue
                m = _KV_RE.match(line)
                if m and section:
                    out[f'{section}.{m.group(1)}'] = m.group(2)
    except OSError:
        return {}
    return out


def build(course_dir, engine):
    """Gather the stamp. Returns (fields, unknown)."""
    unknown = {}

    cls = ltx_talk_class_path()
    version, cls_date = ltx_talk_version(cls)
    if version is None:
        unknown['ltx_talk.version'] = (
            'kpsewhich could not find ltx-talk.cls, or it carries no \\ProvidesExplClass '
            'line. Do NOT fall back to `tlmgr info`: it reports the CTAN catalogue '
            'version, which lags the installed class.')

    tl = texlive_year()
    if tl is None:
        unknown['ltx_talk.texlive_year'] = 'tex --version did not report a TeX Live year'

    skill = skill_version()
    if skill is None:
        unknown['skill.version'] = (
            'git describe failed in the skill checkout -- the skill may have been '
            'installed as a zip, which carries no git history')

    docmeta, docmeta_src = find_documentmetadata(course_dir)
    if docmeta is None:
        unknown['conversion.documentmetadata'] = (
            'no uncommented \\DocumentMetadata found anywhere under the course '
            'directory. ltx-talk half-loads without one (C-NO-DOCMETA), so this is '
            'worth investigating rather than accepting')

    fields = {
        'conversion': {
            'date': datetime.date.today().isoformat(),
            'engine': engine,
        },
        'ltx_talk': {},
        'skill': {},
    }
    if docmeta is not None:
        fields['conversion']['documentmetadata'] = docmeta
        fields['conversion']['documentmetadata_source'] = docmeta_src
    if version is not None:
        fields['ltx_talk']['version'] = version
        fields['ltx_talk']['class_date'] = cls_date
    if tl is not None:
        fields['ltx_talk']['texlive_year'] = tl
    if skill is not None:
        fields['skill']['version'] = skill
    fields['skill']['stamped_by'] = 'stamp_conversion.py'
    return fields, unknown


def main():
    ap = argparse.ArgumentParser(
        description='Record ltx-talk and skill provenance in a converted course repo.')
    ap.add_argument('course_dir', help='root of the converted course')
    ap.add_argument('--engine', default='lualatex',
                    help='build engine the course uses (default: lualatex; LuaLaTeX is '
                         'required for tagged maths -- see A-MATHALT)')
    ap.add_argument('--dry-run', action='store_true',
                    help='print the stamp instead of writing it')
    args = ap.parse_args()

    if not os.path.isdir(args.course_dir):
        sys.exit(f'stamp_conversion.py: not a directory: {args.course_dir}')

    fields, unknown = build(args.course_dir, args.engine)
    path = os.path.join(args.course_dir, STAMP_NAME)

    previous, changes = [], []
    old = read_existing(path) if os.path.exists(path) else {}
    if old:
        prev = {k.replace('.', '_'): v for k, v in old.items()
                if k.split('.')[0] in ('conversion', 'ltx_talk', 'skill')}
        if prev:
            previous.append(prev)
        for sect, keys in (('ltx_talk', ('version',)), ('skill', ('version',))):
            for k in keys:
                was, now = old.get(f'{sect}.{k}'), fields[sect].get(k)
                if was and now and was != now:
                    changes.append(f'{sect}.{k}: {was} -> {now}')

    text = render(fields, unknown, previous)

    if args.dry_run:
        sys.stdout.write(text)
    else:
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(text)

    where = f'{path}{" (dry run, not written)" if args.dry_run else ""}'
    print(f'\n=== stamp_conversion.py: {where} ===', file=sys.stderr)
    for sect in ('conversion', 'ltx_talk', 'skill'):
        for k, v in fields[sect].items():
            print(f'  {sect}.{k} = {v}', file=sys.stderr)
    if changes:
        print('  --- changed since the previous stamp ---', file=sys.stderr)
        for c in changes:
            print(f'  {c}', file=sys.stderr)
        print('  This repo was converted against an older toolchain. #12 tracks the '
              'upgrade task that acts on that.', file=sys.stderr)
    if unknown:
        print('  --- COULD NOT DETERMINE ---', file=sys.stderr)
        for k, why in unknown.items():
            print(f'  {k}: {why}', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
