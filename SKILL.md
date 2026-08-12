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

This skill encodes problems discovered converting two real courses (11 decks, then 20).
Most are not in the upstream docs because they only surface under *tagging*
(`\DocumentMetadata`).

> **Companion references (read before doing anything):**
> - `references/compromises.md` — the catalogue of incompatibilities, with symptom, cause,
>   workaround, and "revisit when". **This is the heart of the skill.**
> - `references/alt-text.md` — how to write the alt text (Step 6). Tagging without alt text
>   is not accessibility. And alt text alone is not enough either — see the **A-\*** entries
>   in `compromises.md` for the four things a PDF/UA checker still rejects (Step 6b).
> - `scripts/table_audit.py` — classifies every `tabular` in a course as data table or layout
>   grid, the input to the A-TABLE-TH work.
> - `assets/preamble-template.tex` — the deployable ltx-talk shared preamble (copy to the project and fill in the Identity and ThemeAccent blocks at the top).
> - `scripts/convert_deck.py` — the pattern-based source transformer (frametitles,
>   sections, title page, verbatim frames, empty titles).
> - `scripts/fix_frame_titles.py` — **must be run after `convert_deck.py`**; it catches the
>   nested-brace frame titles that `convert_deck.py` skips *silently* (C-FRAMETITLE-NESTED).
> - `scripts/alt_text_audit.py` / `scripts/alt_text_apply.py` — the alt-text worklist.
> - The sibling `latex-beamer` skill's `references/ltx-talk.md` has general ltx-talk syntax
>   (overlays, columns, templates). Use it for *how ltx-talk works*; use this skill for
>   *how to convert*.

> ### ⚠ Five failures in this skill produce NO usable error message
> They will not show up in a log (or point anywhere near the fault), and "it compiled" means
> nothing. **`convert_deck.py --lint` greps for all five — run it before every build.**
> 1. **Nested-brace frame titles** left unconverted → the frame has *no title*; the text
>    renders as body text (C-FRAMETITLE-NESTED). Run `fix_frame_titles.py`, then grep.
> 2. **`\onslide<2>{…}`** → ltx-talk's `\onslide` takes **no argument**, so this parses as a
>    *declaration* plus a stray group and blanks **everything after it to the end of the
>    frame** (C-ONSLIDE-ARG). The state lives in a *global* token list, so `tabular` cells and
>    other groups do **not** contain the leak. Use `\uncover<2>{…}` (reserves space) or
>    `\only<2>{…}` (does not). Bare `\onslide<2->` as a declaration is still valid.
> 3. **`\State<2>`** used as an algorithm overlay spec → classic `algpseudocode` does not
>    accept it; the spec is typeset as **literal `<2>` text on the slide** and the overlay
>    never fires (C-OVERLAY-ALGO). Use `\State \uncover<2>{…}`.
> 4. **`\center{…}`** used as if it took an argument → it is a *declaration*; under tagging it
>    leaks an unclosed paragraph and the error is reported **nowhere near** the offending line
>    (C-CENTER-ARG). Cost a full day of bisection. Use `\begin{center}…\end{center}`.
> 5. **Images without `alt=`** → a screen reader reads out *the filename*.
> 6. **`tikzpicture` / `pgfplots` / `\input{…pdf_t}` figures** → untagged entirely, with **no
>    warning, no `/Alt`, and no checker complaint** (A-TIKZ-ALT). Wrap each in `altfigure`.
>
> Also: **measure against a build that actually ran.** Beamer + `\DocumentMetadata` is fatal,
> so a half-migrated repo can leave stale PDFs lying around, and `pdfinfo` will happily read
> them and give you a confident, wrong baseline.
>
> And: **`Tagged: yes` is not a pass.** It says a tag tree exists, not that it is right. Five
> further failures survive a clean compile, `Tagged: yes`, 0 tagpdf errors *and* complete alt
> text — orphan `H4` frame titles, `Formula` elements with no `/Alt`, `tabular`s with no `TH`,
> sub-4.5:1 emphasis colours, and untagged `tikzpicture`/inputted figures. Only a real PDF/UA
> checker finds the first four; **nothing at all finds the fifth**, because those figures are
> missing from the tag tree rather than wrong inside it. Two are one-line preamble fixes:
> **put them in at Step 1** (A-HEADINGS, A-MATHALT). See Step 6b.
>
> And **verify overlays by rendering pages, never with `pdftotext`** — hidden overlay content
> stays in the PDF text layer, so extraction reports text that is invisible on the slide.
> Use `pdftoppm -f N -l N -r 120 -png deck.pdf out` and look at the image.

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
   grep -cE '\\begin\{tikzpicture\}|\\input\{[^}]*(pdf_t|images/)' deck.tex      # A-TIKZ-ALT
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

`alertblock`/`exampleblock` are the opposite case: ltx-talk has **no native version of
either**, so the template's tcolorbox stub for them stays active (not inside that `\iffalse`).
Call them with a plain mandatory brace argument, `\begin{alertblock}{Title}…`, same as beamer.
Do not invent a `d<>m`-style wrapper to preserve beamer's optional overlay spec — that's how
`[{#2}]` gets passed to tcolorbox's *options* argument instead of the title, and the title
silently renders as a literal `[` (**C-ALERTBLOCK**). Wrap the whole box in `\onslide<n->{…}`
instead if the overlay is genuinely needed.

Also add, up front, the things every real deck turns out to need (all catalogued):
the `frame*` tagging hooks (**C-FRAMESTAR-TAG** — without these, listings destroy the tag
tree), the nesting-safe `\Call` (**C-CALL-NEST**), tcolorbox theorem environments
(**C-THEOREM**), and `\ifmmode`-guarded `\sc`/`\it`/`\bf` stubs (**C-OLDFONT**).

**And these two lines, which cost nothing now and a full re-verification pass later:**
```latex
\tagpdfsetup{role/new-tag = frametitle / H2}  % else every frame title is an orphan H4
\tagpdfsetup{math/alt/use}                    % else Formula elements carry no /Alt
```
Without them a PDF/UA checker rejects **every** deck in the course for "headings do not begin
at level one" and "images without a description" — even though the compile is clean, the
output says `Tagged: yes`, and every graphic has `alt=` (**A-HEADINGS**, **A-MATHALT**).
While you are in `\coursetitlepage`, tag the deck title as the document's `H1`; nothing else
in a deck is one. See Step 6b.

The ltx-talk preamble **requires** `\DocumentMetadata` (it uses `\tag_stop:`, `\EditInstance`).
It is a **one-for-one replacement** for the Beamer preamble — load one or the other, never
both, or you get `Undefined control sequence` at `\usetheme`.

⚠ **Check that each deck actually activates `\DocumentMetadata`.** Real decks ship it
commented out (`% \input{../tag-commands.tex}`) from a pre-tagging build. Without it ltx-talk
**half-loads** — a cascade of `Undefined control sequence` (`\institute`, `\hypersetup`,
`frame*`) plus `\normalsize not defined`, and a 2–8-page stub PDF, none of it naming the
cause (**C-NO-DOCMETA**). `convert_deck.py` warns when it is missing; uncomment the input. On
CS3033 this one line fixed three otherwise-broken decks.

Keep the `\DocumentMetadata{…}` block (it must be the very first thing, before
`\documentclass`). **Prefer the modern `tagging=on` over the legacy `testphase={…}` list:**

```latex
\DocumentMetadata{ lang=en, pdfversion=2.0, pdfstandard=a-4, tagging=on }
```

`testphase={phase-I,…}` is the old experimental opt-in and enables only the weakest phase.
On TeX Live 2026 `tagging=on` is the supported spelling and gives fuller tagging. Verified
head-to-head on a real course: identical page counts, `Tagged: yes`, 0 errors under both — so
there is no reason to stay on `testphase`.

⚠ If `tagging=on` appears to explode with ~100 alignment errors, **do not blame the tagging
mode** — check `\and` in your title page first (**C-AND-TITLE**). That misdiagnosis cost real
time; the tagging setting was innocent.

The embedded HTML/CSS files tagpdf attaches may force a `PDF/A-4F` validation note; harmless.

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
hand (because they need judgement): the title-page content, folding double titles, anything
inside a frame body, **and every C-ONSLIDE-ARG / C-OVERLAY-ALGO / C-OVERLAY-ALIGN fix**
(`\onslide<n>{…}` → `\uncover<n>{…}`/`\only<n>{…}`). `--lint` finds all of them; the script
does not rewrite them. An earlier version of this skill auto-rewrote `\onslide<spec>{` →
`\uncover<spec>{` mechanically and it corrupted a group that wrapped a whole `tabular`
environment (the fix needs to know whether the group's `&`/`\\` belong to an *outer*
alignment or are the overlay's own content) — reverted in favour of a lint-then-hand-fix
workflow. At course scale (100-200+ hits) this is real, tedious work; budget time for it.

**Then run the second pass — it is not optional:**
```sh
python3 scripts/fix_frame_titles.py deck.tex
```
`convert_deck.py` matches titles with `[^{}]*`, so it **silently skips** any title containing
nested braces (`{\only<1>{A}\only<2>{B}}`, `{Title}{{\sc Sub}}`). Those frames then render
with **no title at all**, with no error and no warning (C-FRAMETITLE-NESTED). Verify:
```sh
grep -nE '^\s*\\begin\{frame\}(<[^>]*>)?(\[[^]]*\])?\{' deck.tex     # must return nothing
```

**One more thing the script does not do**, and you must:
- **The title page.** Replace the `\maketitle` frame with `\coursetitlepage{…}{…}{…}`.
  Strip any `%` comments out of the attribution text as you fold it into the third argument —
  a stray `%` swallows the closing brace and you get `File ended while scanning use of
  \coursetitlepage`.

(`\end{frame}` → `\end{frame*}` pairing **is** now automatic — `convert_deck.py` walks the
file after the line rewrites and closes every `frame*` properly.)

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
grep -nE '^\s*\\begin\{frame\}(<[^>]*>)?(\[[^]]*\])?\{' deck.tex     # must be EMPTY: title-less frames
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

> ⚠ **`Tagged: yes` means a tag tree exists, not that it is correct.** A deck can pass every
> line above and still be rejected by a PDF/UA checker — for four reasons that produce no
> compiler output at all. Do **Step 6b** before calling a conversion done.

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

The audit reports a second finding type, `untagged_figure`: `tikzpicture`, `pgfplots` and
`\input{…pdf_t}` figures that are absent from the tag tree altogether (**A-TIKZ-ALT**). Step 4
proves nothing about them — the warning it counts only ever fires for `\includegraphics`, so a
deck full of undescribed plots reports `0`. They have no `preview_png` either, because the
figure does not exist until TeX draws it; read the built PDF page instead. `alt_text_apply.py`
skips them by design: wrapping in `altfigure` is a structural edit, done by hand.

You need **both inputs**. The rendered image gives the figure's *content* (node labels, axis
labels); the LaTeX context gives its *role in the argument*. Context alone yields "a search
tree"; the image alone misses why the slide shows it. **Never write alt text from the
filename or the frame title without viewing the image.**

**Alt text is pedagogy, not metadata** — it decides what a blind student learns from the
slide. Generated alt text is a **draft for the author to review**, never a silent commit.

---

## Step 6b — The accessibility-checker pass (Steps 1-6 are not sufficient)

Alt text on the graphics is necessary and **not sufficient**. A course that passed every gate
in this skill — clean compile, `Tagged: yes`, 0 tagpdf errors, every image described — was
still rejected by a real PDF/UA checker on four counts. Read the **A-\*** section of
`references/compromises.md`; all four are catalogued with verified fixes.

| Checker complaint | Cause | Fix |
|---|---|---|
| "headings do not begin at level one" | ltx-talk roles `frametitle` to `H4`, and a title page has no heading at all | `role/new-tag = frametitle / H2` + point the kernel's automatic paragraph tagger at `H1` — **A-HEADINGS**, do NOT hand-write `\tagstructbegin{tag=H1}` |
| "images without a description", pointing at *maths* | `Formula` elements get no `/Alt`; the switch is auto-on for ua-**1** only | `\tagpdfsetup{math/alt/use}` — **A-MATHALT** |
| "tables missing headers" | every `tabular` is tagged `Table`/`TR`/`TD`, never `TH` | classify each: `table/header-rows`/`header-columns`, or `table/tagging=div` for layout grids — **A-TABLE-TH** |
| "text with insufficient contrast" | saturated emphasis colours are <4.5:1 on white | darken the palette *and* the raw `\color{red}` sites — **A-CONTRAST** |
| *(no complaint at all)* | `tikzpicture`/`pgfplots`/`\input{…pdf_t}` figures are absent from the tag tree, so there is nothing for a checker to object to | wrap each in `altfigure` — **A-TIKZ-ALT**, found by `alt_text_audit.py`, not by a checker |

The first two are one-line preamble fixes that solve the whole course at once — **apply them
in Step 1 and save yourself the round trip.** The last two need per-deck work.

> ⚠ **Blackboard's checker is not the bar — PDF/UA-2 is.** It is a *simplified* checker; a
> deck can score near-perfect on it and still fail a real PDF/UA-2 validator. `verapdf`
> (Homebrew: `verapdf`) runs the full profile locally:
> ```sh
> verapdf -f ua2 --format text deck.pdf     # PASS/FAIL
> verapdf -f ua2 --format mrr  deck.pdf     # full report, per-check
> ```
> Run it before calling any A-\* fix done — Blackboard passing a deck does not mean it passes
> `ua2`. This is how the A-HEADINGS title-tagging bug below was actually found.

Three of these are structural rather than cosmetic, and all three need judgement you cannot
fully script:

- **Headings.** `role/new-tag = frametitle / H2` is genuinely one line and safe. The title's
  `H1` is not: the obvious approach, hand-writing `\tagstructbegin{tag=H1}` around the title
  text, compiles clean and passes Blackboard but **fails PDF/UA-2** (`Hn shall not contain
  Part`/`P`). The title-page body is typically one long LaTeX paragraph, and the kernel's
  *automatic* per-paragraph tagger fires on the first character actually typeset — landing its
  own `Part → P` wrapper **inside** whatever manual struct is open, regardless of it. Do not
  try to suppress the automatic tagger with `\tagpdfsetup{para/tagging=false}` either — that
  key is meant to be set once at `\begin{document}`, and toggling it mid-paragraph desyncs the
  kernel's own begin/end counters (worse: a dozen new tagpdf errors, not zero). The fix is to
  let the automatic tagger produce the `H1` itself: force the title onto its own real
  paragraph (`\par`, not `\\`) and set `\tagpdfsetup{para/tag=H1,para/flattened}` for exactly
  that paragraph's lifetime. See A-HEADINGS in `references/compromises.md` for the full
  mechanism and the working code, already in `assets/preamble-template.tex`.
- **Tables.** The classifying question is *"does a cell still make sense read aloud on its
  own, with no column name attached?"* If yes it is a layout grid — demote it with
  `table/tagging=div` and **do not invent a header row**. If no it is a data table and needs
  real `TH`, often on *both* axes. Do not trust a "first row is bold" heuristic: on a real
  course it misclassified 18 of the most important tables (payoff matrices, joint probability
  tables), whose header rows are not bold. Render the slide and look.

  Two traps when you apply it, both of which leave the build **green**:
  1. **The settings leak.** Nothing resets them at `\end{tabular}`, and the keys only
     partially reset each other, so one `table/tagging=div` silently demotes every later
     table in the group. Write each data table with all three keys —
     `table/tagging=true,table/header-rows={1},table/header-columns={}` — so it is
     order-independent.
  2. **A `tabular` inside a `frame*` is not tagged at all**, and your `\tagpdfsetup` there is
     inert — C-FRAMESTAR-TAG suspends tagging for the whole environment. Don't debug it as a
     table problem.

  So **build an oracle before you apply**: from the audit, write down the expected number of
  data tables per deck, then count `/S /Table` and `/S /TH` in the built PDF and compare.
  Nothing else catches either trap.
- **Contrast.** Measure the rendered ink at **≥200 dpi** — at 70-90 dpi anti-aliasing invents
  intermediate colours and hides the real ones. And expect at least one false positive: a
  `\fcolorbox{black}{white}` gets reported although every pixel in it is ≥11:1.

Then re-verify against the PDF structure itself, not the log:
```sh
qpdf --qdf --object-streams=disable deck.pdf qdf.pdf
grep -aoE '/S\s*/[A-Za-z0-9]+' qdf.pdf | tr -s ' ' | sort | uniq -c | sort -rn
#   want: >= 1 /S /H1 ; frametitle roled one level below section ;
#         /S /TH present wherever data tables are ; /Alt on /S /Formula
verapdf -f ua2 --format text deck.pdf
#   the qpdf/grep check above counts elements but can't see nesting —
#   an H1 containing a stray Part/P (the A-HEADINGS manual-struct trap)
#   still shows ">= 1 /S /H1" and passes it. Only a real validator catches that.
```
⚠ When globbing for the PDF to check, **exclude handouts**: `deck-handout.pdf` sorts *before*
`deck.pdf` (`-` < `.`), so `ls week*/deck-*.pdf | head -1` quietly hands you a stale handout —
the "measure against a build that actually ran" trap in a new disguise. It cost a full
false-negative round here: a change that had worked was reported as having done nothing.

**Report contrast and table changes to the author.** Darkening a palette changes the look of
every slide, and adding a header row changes what is *on* one — neither is a silent commit.

## Step 7 — Conversion report (always deliver this)

End with a short report per deck:
- ltx-talk version targeted, and any upstream fixes you adopted because of Step 0.2.
- Page count: baseline vs converted (slides) and handout.
- **Compromises made** (cite `references/compromises.md` IDs), e.g. "section outlines →
  dividers (C-TOC)", "algorithm engine swapped (C-ALGO)".
- **Manual follow-ups**: title-page wording, folded double titles, images still missing
  `alt=` (list them — this is the accessibility payload, not optional), any frame that needed
  hand-tuning.
- **Accessibility state (Step 6b)**: whether the A-\* fixes are in, tables still unclassified,
  and any colour change you made — a darkened palette alters the look of every slide and an
  added header row alters what is *on* one, so both are the author's call, not yours.
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
