# beamer-to-ltx-talk

A [Claude Code](https://claude.ai/code) skill that converts existing LaTeX **Beamer** slide decks to the **ltx-talk** class, producing tagged, accessible PDF (PDF/UA, PDF/A).

The guiding principle is **faithful, minimal, scripted change**: keep body content and slide order identical, rewrite only what the class change forces, and report every compromise made.

---

## Why ltx-talk?

Beamer is [incompatible with `\DocumentMetadata`](https://github.com/josephwright/beamer/issues/808), the LaTeX kernel's tagging activation hook. ltx-talk is a purpose-built replacement that supports:

- Tagged PDF output (PDF/UA-2, PDF/A-4) via the LaTeX tagging kernel
- Native handout mode without per-deck edits
- Clean `\EditInstance`-based theming instead of `\setbeamer*` commands

The trade-off is that ltx-talk is still experimental and has known incompatibilities — most of which only surface under tagging. This skill encodes the fixes discovered converting a real 11-deck course.

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

When you give Claude Code a Beamer `.tex` file and ask to convert it, the skill:

1. **Checks** the toolchain and surveys the deck for constructs that need attention.
2. **Generates** an ltx-talk shared preamble from `assets/preamble-template.tex` — fill in the Identity block (author/institute) and ThemeAccent colour to match your original theme.
3. **Runs** `scripts/convert_deck.py` to handle the mechanical rewrites:
   - Switches `\documentclass{beamer}` → `\documentclass{ltx-talk}`
   - Converts braced frame titles to `\frametitle{…}`
   - Replaces `\section{X}` with `\heading{X}` (tagging-safe section divider)
   - Rewrites title pages and verbatim frames
4. **Compiles** and triages errors against the known-incompatibilities catalogue.
5. **Delivers** a conversion report listing the ltx-talk version targeted, page-count comparison, every compromise made, and outstanding manual follow-ups (especially missing alt text on images).

---

## Repository layout

```
assets/
  preamble-template.tex   # Deployable ltx-talk preamble — copy to your project
  Makefile                # latexmk-based build for slide and handout targets

references/
  compromises.md          # Catalogue of Beamer→ltx-talk incompatibilities
                          # (symptom → cause → workaround → revisit when)

scripts/
  convert_deck.py         # Idempotent source transformer; run with --help

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

The template also includes **beamer-compatibility stubs** for constructs ltx-talk does not yet offer natively: `columns`/`column`, `block`/`alertblock`/`exampleblock`, and `\note{}`.

---

## Known incompatibilities (summary)

Full details — including error signatures and workarounds — are in [`references/compromises.md`](references/compromises.md).

| ID | Issue | Workaround |
|---|---|---|
| **C-ALGO** ⚠️ | `algpseudocodex` hangs/errors under tagging | Switch to classic `algorithmicx`/`algpseudocode` |
| **C-TOC** | `\tableofcontents` corrupts the tag tree | Replace with `\heading{X}` section dividers |
| **C-BLOCK-ALGO** ⚠️ | `\begin{block}` conflicts with `algorithmicx` | Define theorem-like envs with `tcolorbox` |
| **C-FRAMETITLE** | Braced frame titles render as body text | Use `\frametitle{…}` explicitly |
| **C-MAKETITLE** | `frame-title-arg` breaks `\maketitle` | Don't use `frame-title-arg`; use `\frametitle` |
| **C-TITLEPAGE** | `\maketitle` fills frame; trailing text overlaps | Use `\coursetitlepage{}{}{}`|
| **C-VERBATIM** | `containsverbatim`/`lstlisting` fail in `frame` | Use `frame*` environment |
| **C-NOBEAMER** | All `\usetheme`/`\setbeamer*` are undefined | Rebuild styling with `\EditInstance` |
| **C-OVERLAY-ALIGN** | Overlay tokens inside `tabular`/`align*` break `&` | Wrap only the cell content, not the `&`/`\\` |
| **C-OVERLAY-ALGO** | `\onslide{\State…}` corrupts algorithmicx tracking | Use native overlay-spec: `\State<2> …` |
| **C-DISPMATH-NEWLINE** | `\\` after display math errors | Replace with `\vspace{…}` or blank line |
| **C-FONTS** | Maths is sans-serif by default | Load a serif maths font if needed |

The catalogue is version-pinned to **ltx-talk 0.5.0**. Before converting, check the [ltx-talk changelog](https://github.com/josephwright/ltx-talk/blob/main/CHANGELOG.md) and [open issues](https://github.com/josephwright/ltx-talk/issues) — some workarounds may no longer be needed.

---

## Accessibility notes

The whole point of this conversion is tagged, accessible PDF. Things to check after conversion:

- **Alt text**: `tagpdf` warns for every `\includegraphics` without `alt={…}`. Surface the list and fill it — this is the main accessibility payload.
- **Reading order in columns**: content is tagged in source order (left column first, then right). Write columns so left-first is the correct reading order. For paired-row content, use `tabular` instead.
- **Block titles**: the `title=` argument of `block`/`alertblock`/`exampleblock` is tagged as plain text, not as a heading. For semantically important labels, use `\subsubsection*{}` inside the box body.
- **Verify tagging**: `pdfinfo deck.pdf | grep Tagged` should return `yes`; `grep 'tagpdf Error' deck.log` should return 0 matches.
