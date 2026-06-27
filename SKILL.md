---
name: beamer-to-ltx-talk
description: >
  Convert an existing LaTeX Beamer slide deck (or a whole course of decks) into the
  ltx-talk class for tagged / accessible PDF output, preserving the original content and
  structure as faithfully as possible. Use this skill whenever the user wants to port,
  migrate, or convert Beamer slides to ltx-talk, make existing slides accessible/tagged
  PDF (PDF/UA, PDF/A), or escape Beamer's incompatibility with `\DocumentMetadata`.
  Trigger on phrases like "convert my beamer deck to ltx-talk", "port these slides to
  ltx-talk", "make my beamer slides tagged/accessible", "migrate the lectures to
  ltx-talk", "beamer to ltx-talk", or any time a `.tex` Beamer deck is provided and the
  user wants it rebuilt under ltx-talk. This is the *conversion* counterpart to the
  `latex-beamer` skill (which generates new decks from papers); prefer this one when the
  input is already a Beamer deck.
---

# Beamer → ltx-talk Conversion Skill

Convert an existing **Beamer** deck to **ltx-talk** so it produces tagged, accessible PDF.
The guiding principle is **faithful, minimal, scripted change**: keep the body content and
slide order identical, rewrite only what the class change forces, and **tell the user
every time a compromise is made**.

This skill encodes problems discovered converting a real 11-deck course. Most are not in
the upstream docs because they only surface under *tagging* (`\DocumentMetadata`).

> **Companion references (read before doing anything):**
> - `references/compromises.md` — the catalogue of incompatibilities, with symptom, cause,
>   workaround, and "revisit when". **This is the heart of the skill.**
> - `references/preamble-template.tex` — a ready-made ltx-talk shared preamble.
> - `scripts/convert_deck.py` — the pattern-based source transformer (frametitles,
>   sections, title page, verbatim frames, empty titles).
> - The sibling `latex-beamer` skill's `references/ltx-talk.md` has general ltx-talk syntax
>   (overlays, columns, templates). Use it for *how ltx-talk works*; use this skill for
>   *how to convert*.

---

## Step 0 — Preflight (always, before touching any file)

1. **Check the toolchain.**
   ```sh
   kpsewhich ltx-talk.cls          # must exist
   pdftex --version                 # TeX Live 2026+ / LaTeX kernel 2025-11-01 or newer
   tlmgr info ltx-talk | grep -E 'cat-version|installed'
   ```
   ltx-talk is **experimental**; the dev branch tracks the latest kernel. If `ltx-talk.cls`
   is missing or LaTeX is old, stop and tell the user to update TeX Live.

2. **Check upstream for change since this skill was written.** ltx-talk moves fast and the
   compromises below are version-specific. Fetch and skim:
   - https://github.com/josephwright/ltx-talk/blob/main/CHANGELOG.md
   - https://github.com/josephwright/ltx-talk/issues (look for: tableofcontents/TOC tagging
     #223, blocks #205, theorems #219, frame titles, sections)

   For each compromise you are about to apply (see `references/compromises.md`), check
   whether a newer release has fixed it. If so, prefer the now-working native feature and
   note it to the user. Record the ltx-talk version you targeted in the conversion report.

3. **Establish a baseline & a safety net.**
   - Work on a branch (`git switch -c refactor-ltx-talk`) or otherwise keep the originals.
   - Compile each original Beamer deck and record its **page count** and a couple of
     rendered pages (`pdftoppm -png -r 70 deck.pdf /tmp/ref`). This is your fidelity oracle —
     after conversion the *slide* page count should match (the *handout* count will be lower
     because overlays flatten).

4. **Survey the deck(s)** so you can warn early. Count the constructs that matter:
   ```sh
   grep -cE '\\usetheme|\\setbeamer|\\begin\{frame\}|\\AtBeginSection|\\tableofcontents' deck.tex
   grep -cE '\\begin\{algorithmic\}|\\Comment|\\Function' deck.tex     # algpseudocodex risk
   grep -cE 'containsverbatim|lstlisting|verbatim'        deck.tex     # frame* needed
   grep -cE '\\includemedia|\\movie|\\animategraphics'    deck.tex     # media risk
   grep -cE '\\includegraphics(\[[^]]*\])?\{' deck.tex; grep -c 'alt=' deck.tex  # alt-text gap
   ```
   Report the blast radius to the user before mass-editing, and confirm the scope (one deck,
   or all — pilot one first if a course).

---

## Step 1 — The shared preamble

If the deck `\input`s a shared preamble (common in courses), create a **parallel** ltx-talk
preamble (e.g. `ltx-common.tex`) rather than editing the Beamer one in place — the other
unconverted decks still need the Beamer version. For a standalone deck, inline the preamble.

Start from `references/preamble-template.tex`. It already:
- loads no Beamer commands (there is **no** `\usetheme`/`\setbeamercolor`/`\setbeamertemplate`/
  `\usebeamerfont` in ltx-talk — they do not exist);
- rebuilds the visual style via the kernel template system (`\EditInstance{header}{std}{…}`,
  `{footer}{std}{…}`);
- uses the **classic `algpseudocode`** engine, never `algpseudocodex` (see compromises);
- defines `\heading{…}` (section + tagging-safe divider) and `\coursetitlepage{…}{…}{…}`.

Port from the old preamble: colour definitions, `\definecolor`s, custom math macros, the
`\emph` redefinition, `hyperref` metadata, author/institute. **Drop**: `\usetheme`, every
`\setbeamer*`, `\usefonttheme` (decide on maths fonts — ltx-talk maths is sans by default),
`media9`/`multimedia` unless needed, and any Beamer-internal patch files.

Keep the `\DocumentMetadata{…}` block (it must be the very first thing, before
`\documentclass`). Tagging works with `pdfstandard=a-4` and a `testphase` of `phase-I`
upward — but the embedded HTML/CSS files tagpdf attaches may force a `PDF/A-4F` validation
note; that is harmless.

---

## Step 2 — Scripted source transforms

Run `scripts/convert_deck.py` (see its `--help`). It is **idempotent** and only rewrites
patterns, never content. It performs:

| Transform | From | To | Note |
|---|---|---|---|
| Class line | `\documentclass[…]{beamer}` | `\documentclass[…]{ltx-talk}` | |
| Frame titles | `\begin{frame}[opts]{Title}` | `\begin{frame}[opts]` + `\frametitle{Title}` | braced titles otherwise render as **body text** |
| Empty titles | `\begin{frame}[c]{}` | `\begin{frame}[c]` | drops the stray group |
| Double titles | `\begin{frame}{A}{B}` | `\frametitle{A --- B}` | Beamer subtitle → folded in; **warns** |
| Sections | `\section{X}` | `\heading{X}` | divider frame; **warns** TOC outline is lost |
| Verbatim frames | `[…,containsverbatim]{T}` | `\begin{frame*}` + `\frametitle{T}` | |
| Title frame | `\maketitle` + trailing centred text | `\coursetitlepage{…}{…}{…}` | usually needs a **manual** finish |

The script **never edits commented-out lines** and preserves indentation. It prints a
summary of every change and every warning. Things it deliberately leaves for you to do by
hand (because they need judgement): the title-page content, folding double titles, and
anything inside a frame body.

After scripting, also swap the preamble `\input` (`common-packages.tex` → `ltx-common.tex`)
and remove the now-invalid `\AtBeginSection` block and Beamer patch inputs.

---

## Step 3 — Compile, then fix by the catalogue

Build from inside the deck's directory so `../` inputs and `images/` resolve:
```sh
latexmk -C deck.tex && latexmk -pdf -interaction=nonstopmode deck.tex
```
Then triage against `references/compromises.md`. The signatures you will most likely hit:

- **`Improper \halign inside $$'s`** → an `algpseudocodex` algorithm. Confirm the preamble
  uses classic `algpseudocode`; that alone fixes it. (Do **not** chase `varwidth`/minipage/
  SuspendTagging rabbit holes — they do not work; the engine swap does.)
- **`tagpdf Error: number of automatic begin/end … differ` / `structure Sect can not be
  closed`** → a `\tableofcontents`. Replace with `\heading` dividers (the script does this
  for sections; remove any standalone outline frames).
- **`Not allowed in LR mode` at `\maketitle`** → the `frame-title-arg` class option is set.
  Remove it; braced titles still work once converted to `\frametitle`.
- **`Class beamer Error: not compatible with \DocumentMetadata`** → the class line wasn't
  switched, or a stray `{beamer}` remains.

Iterate until `latexmk` exits 0.

---

## Step 4 — Verify (don't trust "it compiled")

For each converted deck confirm:
```sh
pdfinfo deck.pdf | grep -E 'Pages|Tagged'        # Tagged: yes, pages == baseline
grep -c 'tagpdf Error'  deck.log                  # must be 0 (Warnings are OK)
grep -c 'tagpdf Warning' deck.log                 # mostly "missing alt text" — list them
pdftoppm -png -r 70 -f 1 -l 4 deck.pdf /tmp/new    # eyeball title, a heading, a columns frame
```
- **Slide page count == baseline.** A mismatch means a frame dropped or split — investigate.
- **`Tagged: yes`** and **0 tagpdf Errors**.
- Spot-check the title page, a section divider, a columns/figure frame, and an algorithm
  frame against the reference renders.

---

## Step 5 — Handout build wiring

ltx-talk has native handout mode (`\documentclass[handout]{ltx-talk}`) that flattens overlays
to one page per frame. Wire it **without per-deck edits** by passing the option on the command
line, and add a Makefile if converting a course. Copy `assets/Makefile` (targets:
`make slides`, `make handout`, `make <day>`, `make clean`). The handout rule injects
`\PassOptionsToClass{handout}{ltx-talk}` via `latexmk -usepretex`, writing `deck-handout.pdf`
beside `deck.pdf`. Verify a deck with overlays collapses (handout page count < slide count)
and stays `Tagged: yes`.

---

## Step 6 — Conversion report (always deliver this)

End with a short report per deck:
- ltx-talk version targeted, and any upstream fixes you adopted because of Step 0.2.
- Page count: baseline vs converted (slides) and handout.
- **Compromises made** (cite `references/compromises.md` IDs), e.g. "section outlines →
  dividers (C-TOC)", "algorithm engine swapped (C-ALGO)".
- **Manual follow-ups**: title-page wording, folded double titles, images still missing
  `alt=` (list them — this is the accessibility payload, not optional), any frame that needed
  hand-tuning.
- Anything that compiled but looked wrong, for the user to judge.

---

## Things people forget (check these)

- **Alt text.** Tagging warns `Using 'images/x.pdf' instead` for every `\includegraphics`
  without `alt={…}`. Converting *for accessibility* and leaving images unlabelled defeats the
  purpose — surface the list and offer to fill it.
- **`\emph` is often redefined** in these decks to bold/coloured (and decks may `\let\emph\textbf`
  after `\begin{document}`). Preserve that; don't assume italic `\emph`.
- **Maths fonts change** (sans by default in ltx-talk). If the deck relied on
  `\usefonttheme[onlymath]{serif}`, decide whether to restore serif maths and tell the user.
- **`\only<1>{img}\only<2>{img}` overlay image toggles work** unchanged — keep them.
- **Speaker notes**: a `\pdfpcnote` no-op stub keeps sources compiling; real note export is
  out of scope.
- **Tables/`tabular` are fine**, but `\\`-heavy alignments inside ltx-talk `column`s
  (varwidth) can be fragile — if one errors, render it full width or as its own frame.
- **Idempotency**: the script is safe to re-run, but re-running after manual edits may
  re-warn; commit between the scripted pass and manual fixes so diffs stay legible.
- **One deck first.** For a course, pilot a single representative deck (one with a title
  page, sections, columns, and an algorithm), get sign-off on the *look*, then batch the rest.
