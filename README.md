# beamer-to-ltx-talk

An [Agent Skill](https://agentskills.io) that converts existing LaTeX **Beamer** slide decks to the **ltx-talk** class, producing tagged, accessible PDF (PDF/UA, PDF/A).

The guiding principle is **faithful, minimal, scripted change**: keep body content and slide order identical, rewrite only what the class change forces, and report every compromise made.

Built and tested with [Claude Code](https://claude.ai/code), but `SKILL.md` is an open, cross-tool format — point any compliant agent at this repo, or ask any coding agent with file-read and shell access to follow it.

---

## Why ltx-talk?

Beamer is [incompatible with `\DocumentMetadata`](https://github.com/josephwright/beamer/issues/808), the LaTeX kernel's tagging activation hook. ltx-talk is a purpose-built replacement that supports:

- Tagged PDF output (PDF/UA-2, PDF/A-4) via the LaTeX tagging kernel
- Native handout mode without per-deck edits
- Clean `\EditInstance`-based theming instead of `\setbeamer*` commands

ltx-talk is still experimental, and most of its incompatibilities surface only under tagging. This skill encodes the fixes found converting two real courses, of 11 and 20 decks.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| **TeX Live 2026+** | Needs LaTeX kernel ≥ 2026-06-01; dev branch needs ≥ 2026-06-01 |
| **ltx-talk** installed | `kpsewhich ltx-talk.cls` should return a path |
| **latexmk** | For the Makefile targets |
| **Python 3.8+** | For `scripts/convert_deck.py` |

Check your setup:
```sh
kpsewhich ltx-talk.cls
pdftex --version
tlmgr info ltx-talk | grep -E 'cat-version|installed'
```

---

## What the skill does

When you give a compatible agent a Beamer `.tex` file and ask to convert it, the skill:

1. **Checks** the toolchain and surveys the deck for constructs that need attention.
2. **Generates** an ltx-talk shared preamble from `assets/preamble-template.tex`. Fill in the Identity block (author/institute) and ThemeAccent colour to match your original theme.
3. **Runs** `scripts/convert_deck.py` to handle the mechanical rewrites:
   - Switches `\documentclass{beamer}` → `\documentclass{ltx-talk}`
   - Converts braced frame titles to `\frametitle{…}`
   - Rewrites `\center{X}` → `\begin{center}X\end{center}` (a declaration, not a command, fatal under tagging)
   - Strips `\AtBeginSection` outline frames (the preamble's redefined `\section` emits a tagging-safe divider instead, so `\section{X}` lines stay untouched)
   - Rewrites title pages and verbatim frames
4. **Lints** with `convert_deck.py --lint` *before* compiling. See below.
5. **Compiles** and triages errors against the known-incompatibilities catalogue.
6. **Delivers** a conversion report listing the ltx-talk version targeted, page-count comparison, every compromise made, and outstanding manual follow-ups (especially missing alt text on images and untagged `tikzpicture`/`pgfplots` figures).

### Lint before you build

The two costliest bugs in a real 20-deck migration were invisible to the compiler: a braced frame title renders as body text with no error, and `\center{…}` corrupts the tag tree with the error reported nowhere near the cause. Both are source greps needing no build — see below.

---

## Repository layout

```
assets/
  preamble-template.tex   # Deployable ltx-talk preamble, copy to your project
  Makefile                # latexmk-based build for slide and handout targets

references/
  compromises.md          # Catalogue of Beamer→ltx-talk incompatibilities
                          # (symptom → cause → workaround → revisit when)

scripts/
  convert_deck.py         # Idempotent source transformer; also `--lint` (pre-build check)
  fix_frame_titles.py     # Second pass: brace-matched titles convert_deck.py can't see
  alt_text_audit.py       # Lists \includegraphics missing alt= text, plus tikzpicture/
                          # pgfplots/inputted figures untagged entirely (A-TIKZ-ALT)
  alt_text_apply.py       # Writes alt= text back into the source; skips A-TIKZ-ALT findings,
                          # which need an alt key set by hand at the call site
  table_audit.py          # Classifies every tabular: data table (needs TH) vs
                          # layout grid (needs table/tagging=div), see A-TABLE-TH

SKILL.md                  # Agent instructions (step-by-step protocol)
```

---

## Adapting the preamble template

Copy `assets/preamble-template.tex` next to your decks (e.g. as `ltx-common.tex`) and edit the two blocks at the top:

```latex
%% Theme accent — one colour name or RGB triple
\newcommand{\ThemeAccent}{bostonuniversityred}
\newcommand{\ThemeAccentText}{white}

%% Identity
\newcommand{\AuthorShort}{Smith and Jones}
\newcommand{\AuthorLong}{Alice Smith \and Bob Jones}
\newcommand{\AuthorEmails}{a.smith@uni.ac.uk \quad b.jones@uni.ac.uk}
\newcommand{\InstShort}{MyUni}
\newcommand{\InstLong}{University of Somewhere}
```

Common beamer theme → accent colour mapping is in the template comments.

⚠️ The template carries `columns`/`column`/`block` **stubs inside an `\iffalse` block; leave them disabled**. ltx-talk provides all of them *natively*; enabling the stubs clashes (`Command \columns already defined`). They exist only for a plain kernel-class setting. See **C-NATIVE-ENVS**.

---

## Known incompatibilities

Full details — error signatures, measurements, workarounds — are in
[`references/compromises.md`](references/compromises.md), one entry per ID. This is the short
orientation.

**The worst failures produce no error at the offending line.** They compile clean, keep the
right page count, report `Tagged: yes`, and are wrong on the slide. `--lint` catches the
greppable ones before you spend a build:

```sh
python3 scripts/convert_deck.py deck.tex --lint    # exit 1 if anything is flagged
```

The five that cost the most on a real migration:

| ID | Silent failure |
|---|---|
| **C-ONSLIDE-ARG** | `\onslide<n>{…}` takes no argument, so the declaration leaks and blanks everything after it to the end of the frame — 139 occurrences in one 11-deck course |
| **C-FRAMETITLE-NESTED** | nested-brace title left unconverted; the frame has no title and the text lands in the body |
| **C-CENTER-ARG** | `\center{…}` used as a command corrupts the tag tree, and the error lands far from the cause |
| **C-FRAME-OPT** | bare `[b]`/`[t]`/`[c]` frame options are discarded whole; every aligned frame renders centred |
| **A-TIKZ-ALT** | `tikzpicture`/`pgfplots`/`\input{…pdf_t}` figures are untagged entirely — no warning, and no checker complains, because they are missing from the tag tree rather than wrong within it |

⚠ **Verify overlays by rendering pages** (`pdftoppm -f N -l N -png`), never with `pdftotext`.
Hidden overlay content stays in the PDF text layer, so extraction reports content that is not
visible on the slide. That is how C-ONSLIDE-ARG and C-OVERLAY-ALGO were caught.

⚠ **A clean build is not a correct deck.** Four failures survive every gate in this skill —
clean compile, `Tagged: yes`, 0 tagpdf errors, every image described — and are found only by
running a real PDF/UA checker: A-HEADINGS, A-TABLE-TH, A-CONTRAST, and A-MATHALT. Read
A-MATHALT before acting on it: the checker is wrong there, and the obvious fix makes the maths
less accessible, not more.

The catalogue also covers the errors the compiler does report, which are the easy half: the
error text names the cause, and `compromises.md` opens with an error → cause → entry table.

Each entry records the ltx-talk version it was checked against. Before converting, check the
[ltx-talk changelog](https://github.com/josephwright/ltx-talk/blob/main/CHANGELOG.md) and
[open issues](https://github.com/josephwright/ltx-talk/issues) — some workarounds may no longer
be needed.

---

## Accessibility notes

The whole point of this conversion is tagged, accessible PDF. Things to check after conversion:

- **Alt text**: `tagpdf` warns for every `\includegraphics` without `alt={…}`. Surface the list and fill it; this is the main accessibility payload.
- **Non-`\includegraphics` figures**: a `tikzpicture`, a `pgfplots` `axis`, or an `\input{…}` of a generated `.pdf_t`/`.pgf` produces no warning at all and lands with no `/Alt` and no `Figure` tag (**A-TIKZ-ALT**). `alt_text_audit.py` finds these as `untagged_figure`; describe each by hand — the `alt` key on the environment for a `tikzpicture`/`axis`, `\altinput` for an inputted figure.
- **Reading order in columns**: content is tagged in source order (left column first, then right). Write columns so left-first is the correct reading order. For paired-row content, use `tabular` instead.
- **Block titles**: the `title=` argument of `block`/`alertblock`/`exampleblock` is tagged as plain text, not as a heading. For semantically important labels, use `\subsubsection*{}` inside the box body.
- **Verify tagging**: `pdfinfo deck.pdf | grep Tagged` should return `yes`; `grep 'tagpdf Error' deck.log` should return 0 matches.

---

## License

Licensed under the [GNU Affero General Public License v3.0](LICENSE) (or later), with an additional attribution term under §7(b): any redistributed or modified version (including one run as a network service) must keep a visible credit back to this project. See [`LICENSE`](LICENSE) for the exact wording.
