#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Felipe Meneguzzi
# Part of beamer-to-ltx-talk: https://github.com/meneguzzi/beamer-to-ltx-talk

"""Audit every tabular in a course (A-TABLE-TH): where it is, what it looks
like, and a FIRST-PASS GUESS at whether it is a data table (needs TH) or a
layout grid (needs table/tagging=div).

    python3 table_audit.py <course-root> > tables.json

One record per live tabular: deck, line, frame title, column spec, a preview of
the first rows, and a `proposal` plus an empty `decision` field to fill in.

  THE `proposal` IS A HINT, NOT AN ANSWER. It keys off a bold first row or
  column, and on a real 20-deck course that misclassified 18 of the most
  important tables -- payoff matrices, joint probability tables and quiz grids
  whose header rows simply are not bold, and which need headers on BOTH axes.

  Render each slide and decide by the actual question:
      "does a cell still make sense read aloud on its own,
       with no column name attached?"
  No  -> data table:   table/header-rows={...}, table/header-columns={...}
         (multi-level headers work; the label column need not be column 1)
  Yes -> layout grid:  table/tagging=div  -- do NOT invent a header row

Comments are stripped before parsing: a plain `grep -c 'begin{tabular}'`
overcounts badly (36 of 83 hits on that course sat in commented-out slides).

When applying the decisions, two things bite and both leave the build green:
  * the settings LEAK between tables -- write all three keys every time,
    `table/tagging=true,table/header-rows={1},table/header-columns={}`;
  * a tabular inside a `frame*` is not tagged at all and the declaration is
    inert (C-FRAMESTAR-TAG suspends tagging for the whole environment).
Count `/S /Table` and `/S /TH` in the built PDF against an expected total.
"""
import json, re, sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".")

BEGIN = re.compile(r"\\begin\{tabular\*?\}(?:\{[^{}]*\})?(?:\[[^\]]*\])?\{")
END = re.compile(r"\\end\{tabular\}")
FRAMETITLE = re.compile(r"\\frametitle\{(.*)\}\s*$")
BOLDISH = re.compile(r"\\(textbf|bfseries|bf|emph|defn)\b")


def strip_comment(line):
    out, esc = [], False
    for ch in line:
        if esc:
            out.append(ch); esc = False; continue
        if ch == "\\":
            out.append(ch); esc = True; continue
        if ch == "%":
            break
        out.append(ch)
    return "".join(out)


def cells(row):
    """Split a tabular row on top-level &."""
    parts, depth, cur = [], 0, []
    for ch in row:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        if ch == "&" and depth == 0:
            parts.append("".join(cur)); cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    return [p.strip() for p in parts]


def audit(path):
    lines = path.read_text().splitlines()
    frames = {}  # line no -> current frame title
    title = None
    found = []
    i = 0
    while i < len(lines):
        raw = lines[i]
        code = strip_comment(raw)
        m = FRAMETITLE.search(code)
        if m:
            title = m.group(1).strip()
        m = BEGIN.search(code)
        if m:
            start = i
            # brace-match the colspec: p{.7\linewidth} nests, so [^}]* fails
            rest, depth_b, k = code[m.end():], 1, 0
            while k < len(rest) and depth_b:
                if rest[k] == "{":
                    depth_b += 1
                elif rest[k] == "}":
                    depth_b -= 1
                k += 1
            colspec, rest = rest[:k - 1], rest[k:]
            body, depth = [], 1
            j = i
            buf = rest
            while j < len(lines):
                if j > i:
                    buf = strip_comment(lines[j])
                depth += len(BEGIN.findall(buf)) if j > i else 0
                depth -= len(END.findall(buf))
                if depth <= 0:
                    body.append(END.split(buf)[0])
                    break
                body.append(buf)
                j += 1
            src = "\n".join(body)
            rows = [r.strip() for r in re.split(r"\\\\", src) if r.strip()]
            rows = [re.sub(r"\\hline|\\cline\{[^}]*\}", "", r).strip() for r in rows]
            rows = [r for r in rows if r]
            ncols = len([c for c in re.sub(r"[^lcrp@|]", "", colspec)
                         .replace("|", "").replace("@", "") ]) or len(cells(rows[0])) if rows else 0
            first = cells(rows[0]) if rows else []
            firstcol = [cells(r)[0] for r in rows if cells(r)]
            head_row = bool(rows) and all(BOLDISH.search(c) for c in first if c)
            head_col = bool(firstcol) and all(BOLDISH.search(c) for c in firstcol if c)
            found.append({
                "deck": str(path.relative_to(ROOT)),
                "line": start + 1,
                "frametitle": title,
                "colspec": colspec,
                "nrows": len(rows),
                "ncols": len(first),
                "bold_first_row": head_row,
                "bold_first_col": head_col,
                "first_row": first[:6],
                "rows_preview": [cells(r)[:6] for r in rows[:4]],
                "proposal": ("header-rows={1}" if head_row else
                             "header-columns={1}" if head_col else "div"),
                "reason": ("first row is entirely bold -> a real header row"
                           if head_row else
                           "first column is entirely bold -> row headers"
                           if head_col else
                           "no bold header row or column -> layout grid unless "
                           "a cell is meaningless without a column name"),
                "decision": "",
            })
            i = j
        i += 1
    return found


all_found = []
for f in sorted(ROOT.glob("week*/ai-lecture*.tex")):
    all_found += audit(f)

print(json.dumps(all_found, indent=1))
sys.stderr.write(f"{len(all_found)} tabular(s) across the course\n")
