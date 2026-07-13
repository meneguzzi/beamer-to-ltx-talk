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
> - `references/alt-text.md` — how to write the alt text (Step 6). Tagging without alt text
>   is not accessibility.
> - `assets/preamble-template.tex` — the deployable ltx-talk shared preamble (copy to the project and fill in the Identity and ThemeAccent blocks at the top).
> - `scripts/convert_deck.py` — the pattern-based source transformer (frametitles,
>   sections, title page, verbatim frames, empty titles).
> - `scripts/fix_frame_titles.py` — **must be run after `convert_deck.py`**; it catches the
>   nested-brace frame titles that `convert_deck.py` skips *silently* (C-FRAMETITLE-NESTED).
> - `scripts/alt_text_audit.py` / `scripts/alt_text_apply.py` — the alt-text worklist.
> - The sibling `latex-beamer` skill's `references/ltx-talk.md` has general ltx-talk syntax
>   (overlays, columns, templates). Use it for *how ltx-talk works*; use this skill for
>   *how to convert*.

> ### ⚠ Four failures in this skill produce NO usable error message
> They will not show up in a log (or point anywhere near the fault), and "it compiled" means
> nothing. **`convert_deck.py --lint` greps for all four — run it before every build.**
> 1. **Nested-brace frame titles** left unconverted → the frame has *no title*; the text
>    renders as body text (C-FRAMETITLE-NESTED). Run `fix_frame_titles.py`, then grep.
> 2. **`\State<2>`** used as an algorithm overlay spec → the overlay is *silently dropped*
>    and the line shows on every slide (C-OVERLAY-ALGO). Use `\State \onslide<2>{…}`.
> 3. **`\center{…}`** used as if it took an argument → it is a *declaration*; under tagging it
>    leaks an unclosed paragraph and the error is reported **nowhere near** the offending line
>    (C-CENTER-ARG). Cost a full day of bisection. Use `\begin{center}…\end{center}`.
> 4. **Images without `alt=`** → a screen reader reads out *the filename*.
>
> Also: **measure against a build that actually ran.** Beamer + `\DocumentMetadata` is fatal,
> so a half-migrated repo can leave stale PDFs lying around, and `pdfinfo` will happily read
> them and give you a confident, wrong baseline.

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

Start from `assets/preamble-template.tex`. It already:
- loads no Beamer commands (there is **no** `\usetheme`/`\setbeamercolor`/`\setbeamertemplate`/
  `\usebeamerfont` in ltx-talk — they do not exist);
- rebuilds the visual style via the kernel template system (`\EditInstance{header}{std}{…}`,
  `{footer}{std}{…}`);
- uses the **classic `algpseudocode`** engine, never `algpseudocodex` (see compromises);
- **redefines `\section`** so it emits the section *and* a tagging-safe divider frame — the
  decks keep their original `\section{…}` lines untouched (`\section*{…}` opts out of the
  divider); and defines `\coursetitlepage{…}{…}{…}`.

Port from the old preamble: colour definitions, `\definecolor`s, custom math macros, the
`\emph` redefinition, `hyperref` metadata, author/institute. **Drop**: `\usetheme`, every
`\setbeamer*`, `\usefonttheme` (decide on maths fonts — ltx-talk maths is sans by default;
`references/compromises.md` C-FONTS has a working serif recipe), `media9`/`multimedia` unless
needed, and any Beamer-internal patch files.

⚠ **Do not paste in the template's `columns`/`column`/`block` stubs.** ltx-talk provides all
of them **natively** — the stubs clash (C-NATIVE-ENVS). They are in the template only for a
kernel-class setting where they genuinely don't exist.

Also add, up front, the things every real deck turns out to need (all catalogued):
the `frame*` tagging hooks (**C-FRAMESTAR-TAG** — without these, listings destroy the tag
tree), the nesting-safe `\Call` (**C-CALL-NEST**), tcolorbox theorem environments
(**C-THEOREM**), and `\ifmmode`-guarded `\sc`/`\it`/`\bf` stubs (**C-OLDFONT**).

The ltx-talk preamble **requires** `\DocumentMetadata` (it uses `\tag_stop:`, `\EditInstance`).
It is a **one-for-one replacement** for the Beamer preamble — load one or the other, never
both, or you get `Undefined control sequence` at `\usetheme`.

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
| Sections | *(left as-is)* | *(left as-is)* | the preamble's redefined `\section` emits the divider; the script only strips `\AtBeginSection` and **warns** the TOC outline is lost |
| Centring | `\center{X}` | `\begin{center}X\end{center}` | C-CENTER-ARG — a declaration, not a command; fatal under tagging |
| Verbatim frames | `[…,containsverbatim]{T}` | `\begin{frame*}` + `\frametitle{T}` | |
| Title frame | `\maketitle` + trailing centred text | `\coursetitlepage{…}{…}{…}` | usually needs a **manual** finish |

The script **never edits commented-out lines** and preserves indentation. It prints a
summary of every change and every warning. Things it deliberately leaves for you to do by
hand (because they need judgement): the title-page content, folding double titles, and
anything inside a frame body.

**Then run the second pass — it is not optional:**
```sh
python3 scripts/fix_frame_titles.py deck.tex
```
`convert_deck.py` matches titles with `[^{}]*`, so it **silently skips** any title containing
nested braces (`{\only<1>{A}\only<2>{B}}`, `{Title}{{\sc Sub}}`). Those frames then render
with **no title at all**, with no error and no warning (C-FRAMETITLE-NESTED). Verify:
```sh
grep -nE '^\s*\\begin\{frame\}(\[[^]]*\])?\{' deck.tex     # must return nothing
```

**Two more things the script does not do**, and you must:
- **`\end{frame}` → `\end{frame*}`.** It rewrites the `\begin` of a verbatim frame but not
  its matching `\end`. Pair them up (count: `grep -c` each — they must match).
- **The title page.** Replace the `\maketitle` frame with `\coursetitlepage{…}{…}{…}`.

After scripting, also swap the preamble `\input` (`common-packages.tex` → `ltx-common.tex`)
and remove the now-invalid `\AtBeginSection` block and Beamer patch inputs.

---

## Step 2b — Lint BEFORE you compile (cheap; catches what the compiler cannot)

```sh
python3 scripts/convert_deck.py deck.tex --lint     # exit 1 if anything is flagged
```
The two costliest bugs in a real 20-deck migration were **invisible to the compiler**: a
braced frame title renders as body text with no error at all, and `\center{…}` corrupts the
tag tree with an error reported *nowhere near* the offending line (a full day of bisection).
Both are pure source greps needing no build — so run this on every deck, every time, and get
to zero before spending a compile.

It flags: unconverted braced frame titles (C-FRAMETITLE / C-FRAMETITLE-NESTED), `\center{…}`
and friends (C-CENTER-ARG), `\State<n>` silent overlays (C-OVERLAY-ALGO), leftover
`\tableofcontents` (C-TOC), Beamer-only commands (C-NOBEAMER, C-BACKGROUND), `algpseudocodex`
(C-ALGO), and the `algorithm` float (C-ALGO-FLOAT).

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
  closed`** → a `\tableofcontents`. Remove it; the preamble's redefined `\section` already
  emits a divider frame per section (the script strips `\AtBeginSection`, but delete any
  standalone outline frames by hand).
- **`Not allowed in LR mode` at `\maketitle`** → the `frame-title-arg` class option is set.
  Remove it; braced titles still work once converted to `\frametitle`.
- **`Class beamer Error: not compatible with \DocumentMetadata`** → the class line wasn't
  switched, or a stray `{beamer}` remains.

Iterate until `latexmk` exits 0.

---

## Step 4 — Verify (don't trust "it compiled")

For each converted deck confirm **all four** — the third one has no error message and is the
one people miss:
```sh
pdfinfo deck.pdf | grep -E 'Pages|Tagged'                  # Tagged: yes, pages == baseline
grep -c 'tagpdf Error' deck.log                            # must be 0 (Warnings are OK)
grep -nE '^\s*\\begin\{frame\}(\[[^]]*\])?\{' deck.tex     # must be EMPTY: title-less frames
grep -c 'Alternative text for graphic is missing' deck.log # -> 0 after Step 6
pdftoppm -png -r 70 -f 1 -l 4 deck.pdf /tmp/new            # eyeball title/heading/columns
```
- **Slide page count == baseline.** A mismatch means a frame dropped or split — investigate.
  But first make sure your **baseline build actually ran**: Beamer + `\DocumentMetadata` is
  fatal, so in a half-migrated repo `pdfinfo` may be reading a **stale PDF** and handing you a
  confident, wrong number.
- **`Tagged: yes`** and **0 tagpdf Errors**.
- Spot-check the title page, a section divider, a columns/figure frame, and an algorithm
  frame against the reference renders.

For a course, wire this into a `check` build target so it fails on *unsound* output, not just
on a failed compile.

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

## Step 6 — Alt text (this is the point of the migration)

A tagged PDF whose figures are unlabelled is **not accessible**. `tagpdf` warns once per bare
`\includegraphics` — "Alternative text for graphic is missing … Using 'images/x.pdf' instead"
— which means a screen reader reads out **the filename**. Do not stop at `Tagged: yes`.

Read `references/alt-text.md`. In short:

```sh
# 1. collect: find unlabelled images, RENDER each one, harvest its LaTeX context
python3 scripts/alt_text_audit.py week*/deck*.tex --render-dir /tmp/alt --json alt.json

# 2. for each entry: LOOK at preview_png, read its context, fill the "alt" field

# 3. inject (idempotent; skips entries still empty, so you can work in batches)
python3 scripts/alt_text_apply.py alt.json

# 4. verify
grep -c 'Alternative text for graphic is missing' deck.log     # -> 0
```

You need **both inputs**. The rendered image gives the figure's *content* (node labels, axis
labels); the LaTeX context gives its *role in the argument*. Context alone yields "a search
tree"; the image alone misses why the slide shows it. **Never write alt text from the
filename or the frame title without viewing the image.**

**Alt text is pedagogy, not metadata** — it decides what a blind student learns from the
slide. Generated alt text is a **draft for the author to review**, never a silent commit.

## Step 7 — Conversion report (always deliver this)

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
