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
>   sections, title page, verbatim frames, empty titles, `$$…$$` → `\[…\]`).
> - `scripts/fix_frame_titles.py` — **must be run after `convert_deck.py`**; it catches the
>   nested-brace frame titles that `convert_deck.py` skips *silently* (C-FRAMETITLE-NESTED).
> - `scripts/alt_text_audit.py` / `scripts/alt_text_apply.py` — the alt-text worklist.
> - The sibling `latex-beamer` skill's `references/ltx-talk.md` has general ltx-talk syntax
>   (overlays, columns, templates). Use it for *how ltx-talk works*; use this skill for
>   *how to convert*.

> ### ⚠ Eight failures produce no usable error message
> "It compiled" means nothing for any of these. **`convert_deck.py --lint` greps for 1–4, 7
> and 8 — run it before every build.** 5 and 6 are alt-text findings: use `alt_text_audit.py`.
> Each ID has the full account in `compromises.md`.
>
> 1. **Nested-brace frame titles** left unconverted → the frame has no title and the text
>    renders as body text (C-FRAMETITLE-NESTED). Run `fix_frame_titles.py`, then grep.
> 2. **`\onslide<2>{…}`** → `\onslide` takes no argument, so this parses as a declaration plus
>    a stray group and blanks everything after it to the end of the frame (C-ONSLIDE-ARG). The
>    state is a *global* token list, so `tabular` cells do not contain the leak. Use
>    `\uncover<2>{…}` (reserves space) or `\only<2>{…}` (does not). Bare `\onslide<2->` as a
>    declaration is still valid.
> 3. **`\State<2>`** as an algorithm overlay spec → typeset as literal `<2>` on the slide; the
>    overlay never fires (C-OVERLAY-ALGO). Use `\State \uncover<2>{…}`.
> 4. **`\center{…}`** used as if it took an argument → it is a declaration; under tagging it
>    leaks an unclosed paragraph and the error is reported nowhere near the offending line
>    (C-CENTER-ARG). Cost a full day of bisection. Use `\begin{center}…\end{center}`.
> 5. **Images without `alt=`** → a screen reader reads out the filename.
> 6. **`tikzpicture` / `pgfplots` / `\input{…pdf_t}` figures** → untagged entirely, with no
>    warning, no `/Alt` and no checker complaint (A-TIKZ-ALT). Pass the latex-lab `alt` key on
>    the environment (`\begin{tikzpicture}[alt=…]`); inputted figures need
>    `\altinput{…}{fig.pdf_t}`.
> 7. **`\framesubtitle{…}`** → typesets nothing, and the page count is unchanged, so a
>    page-count check passes while the text is gone (C-FRAMESUBTITLE). Documented upstream, so
>    do not file it; fold both parts into `\frametitlesub{Title}{Subtitle}`.
> 8. **`$$…$$` display math** → every `\item` after the display loses its list indentation
>    (C-DISPLAY-DOLLAR). ltx-talk only. `convert_deck.py` rewrites these to `\[…\]`.
>
> Three rules that follow from the above:
>
> - **`Tagged: yes` is not a pass.** It says a tag tree exists, not that it is right. Four
>   failures survive a clean compile, `Tagged: yes`, 0 tagpdf errors *and* complete alt text:
>   orphan `H4` frame titles (A-HEADINGS), `tabular`s with no `TH` (A-TABLE-TH), sub-4.5:1
>   emphasis colours (A-CONTRAST), and untagged `tikzpicture`/inputted figures (A-TIKZ-ALT).
>   A real PDF/UA checker finds the first three; **nothing finds the fourth**. A-HEADINGS is a
>   one-line preamble fix — put it in at Step 1. See Step 6b.
>   ⚠ But a checker complaint is not automatically a defect: some apply a PDF/UA-**1** rule to
>   a ua-2 document. "Maths has no description" is the standard example, and the ua-2 answer is
>   MathML, not `/Alt`. Read **A-MATHALT** before fixing it.
> - **Verify overlays by rendering pages, never with `pdftotext`.** Hidden overlay content
>   stays in the PDF text layer, so extraction reports text that is invisible on the slide.
>   `pdftoppm -f N -l N -r 120 -png deck.pdf out`, then look at the image.
> - **Measure against a build that actually ran.** Beamer + `\DocumentMetadata` is fatal, so a
>   half-migrated repo leaves stale PDFs around and `pdfinfo` will read them and give you a
>   confident, wrong baseline.

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
(**C-THEOREM**), `\ifmmode`-guarded `\sc`/`\it`/`\bf` stubs (**C-OLDFONT**), and
`\frametitlesub{Title}{Subtitle}` (**C-FRAMESUBTITLE** — ltx-talk accepts `\framesubtitle`
and typesets nothing, so the subtitle has to ride along inside the frame title). Define it as
a *new* macro, never as a redefinition of `\framesubtitle`: that would need the class's
private title token list, and upstream says the frame-title interface is not yet settled.

**And this line, which costs nothing now and a full re-verification pass later:**
```latex
\tagpdfsetup{role/new-tag = frametitle / H2}  % else every frame title is an orphan H4
```
Without it a PDF/UA checker rejects **every** deck in the course for "headings do not begin
at level one" — even though the compile is clean and the output says `Tagged: yes`
(**A-HEADINGS**).

> ⚠ **Do not add `\tagpdfsetup{math/alt/use}`.** It is tempting, because a checker will report
> your maths as "images without a description" without it. It puts an `/Alt` on every
> `Formula`, which is *valid* under ua-2 — and much worse in practice, because a screen reader
> that finds `/Alt` is reported to read that string instead of the MathML. Both pass a
> validator; only one is usable. See **A-MATHALT**, including what is and is not verified.

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
one real course this one line fixed three otherwise-broken decks.

Keep the `\DocumentMetadata{…}` block (it must be the very first thing, before
`\documentclass`). **Prefer the modern `tagging=on` over the legacy `testphase={…}` list:**

```latex
\DocumentMetadata{ lang=en, pdfversion=2.0, pdfstandard={a-4,ua-2}, tagging=on }
```

**`ua-2` is not optional.** `a-4` is PDF/A-4 and emits *no* `pdfuaid:part`: the file makes no
PDF/UA claim, veraPDF fails it on ua2 clause 5, and a checker is then entitled to assess it
under PDF/UA-**1** — which is the very argument **A-MATHALT** rests on. `{a-4,ua-2}` emits
`pdfuaid:part=2, rev=2024` and also sets `/DisplayDocTitle true` (clause 8.11.2) for free.
`convert_deck.py` warns (`C-NO-UA2`) when it can see the block — it cannot follow an
`\input`-ed `tag-commands.tex`, so **check that file by hand** (**C-NO-UA2**).

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
| Frame options | `\begin{frame}[b]` | `\begin{frame}[vertical-alignment=bottom]` | C-FRAME-OPT — ltx-talk's `frame` takes a key-value list, so `b`/`t`/`c` are discarded whole and the frame renders centred. Also `allowframebreaks` → `auto-break=true` |
| Frame titles | `\begin{frame}[opts]{Title}` | `\begin{frame}[opts]` + `\frametitle{Title}` | braced titles otherwise render as **body text** |
| Empty titles | `\begin{frame}[c]{}` | `\begin{frame}[vertical-alignment=center]` | drops the stray group |
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
and friends (C-CENTER-ARG), `\State<n>` silent overlays (C-OVERLAY-ALGO), `\framesubtitle`
(C-FRAMESUBTITLE — accepted by the class and never typeset), raw `$$…$$`
(C-DISPLAY-DOLLAR — outdents every later `\item`), bare Beamer frame options
(C-FRAME-OPT — `[b]`/`[t]` discarded, so the frame renders centred), leftover
`\tableofcontents` (C-TOC), Beamer-only commands (C-NOBEAMER, C-BACKGROUND), `algpseudocodex`
(C-ALGO), and the `algorithm` float (C-ALGO-FLOAT).

---

## Step 3 — Compile, then fix by the catalogue

Build from inside the deck's directory so `../` inputs and `images/` resolve:
```sh
latexmk -C deck.tex && latexmk -lualatex -interaction=nonstopmode deck.tex
```
**Use `-lualatex`, not `-pdf`.** Under pdfTeX, ltx-talk falls back to `sansmathfonts` and every
comma in maths lands in the text layer as `;`, every period as `:` — the slides look right, so
only a text extraction catches it. LuaTeX is also the only engine that gets MathML on formulas;
XeTeX fixes the fonts but emits empty `/Formula` elements. See **C-PDFTEX-MATH**.

Then triage against `references/compromises.md`.

> **Fix it in the shared preamble where you can.** If a Beamer command is simply undefined,
> the first thing to try is defining it in `ltx-common.tex` to do the ltx-talk equivalent,
> leaving the decks untouched — that is how C-TOC and C-BACKGROUND work, and it is why the
> decks keep their original `\section{Title}` and `\usebackgroundtemplate{...}` lines.
> ltx-talk is moving: a shim in one file is deleted in one
> edit once the class catches up, and every deck is correct immediately. The same fix spread
> through deck bodies has to be undone deck by deck. Only reach for a deck-body edit when the
> right output needs a judgement the preamble cannot make.

The signatures you will most likely hit:

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

> ⚠ **Fix every `!` error, including the ones that look cosmetic.** Under
> `-interaction=nonstopmode` a non-halting error still makes `latexmk` stop after **one pass**
> (`Latexmk: Errors, so I did not complete making targets`), so everything that resolves on a
> later pass silently does not: cross-references render as `??`, `remember picture` anchors
> never resolve, MathML on formulas is absent. The damage surfaces far from the error, often
> in another file. `! Command \foo already defined` from a course preamble that predefines
> maths symbols is the usual culprit — use `\providecommand`. See **C-ONEPASS**.

---

## Step 4 — Verify (don't trust "it compiled")

For each converted deck confirm **all six** — the third, fourth and fifth have no error message
and are the ones people miss:
```sh
pdfinfo deck.pdf | grep -E 'Pages|Tagged'                  # Tagged: yes, pages == baseline
grep -c 'tagpdf Error' deck.log                            # must be 0 (Warnings are OK)
grep -nE '^\s*\\begin\{frame\}(<[^>]*>)?(\[[^]]*\])?\{' deck.tex     # must be EMPTY: title-less frames
pdftotext deck.pdf - | grep -n '[a-z]; [a-z]'              # must be EMPTY: pdfTeX maths corruption
grep -ciE 'Rerun to get|Label\(s\) may have changed' deck.log       # must be 0: build converged
grep -c 'Alternative text for graphic is missing' deck.log # -> 0 after Step 6
pdftoppm -png -r 70 -f 1 -l 4 deck.pdf /tmp/new            # eyeball title/heading/columns
```
- **Slide page count == baseline.** A mismatch means a frame dropped or split — investigate.
  But first make sure your **baseline build actually ran**: Beamer + `\DocumentMetadata` is
  fatal, so in a half-migrated repo `pdfinfo` may be reading a **stale PDF** and handing you a
  confident, wrong number.
- **`Tagged: yes`** and **0 tagpdf Errors**.
- **No corrupted maths in the text layer.** A hit on that `grep` means the deck was built with
  pdfTeX; rebuild with `-lualatex` (**C-PDFTEX-MATH**). `pdfinfo deck.pdf | grep Producer`
  confirms which engine produced a given PDF.
- **The build converged.** A surviving `Rerun to get…` / `Label(s) may have changed` means
  `latexmk` stopped early — almost always because a non-halting `!` error made it give up after
  one pass, leaving cross-references as `??` and `remember picture` anchors unresolved
  (**C-ONEPASS**). Page count and `Tagged: yes` both pass while this is true.
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

⚠ **That check is not enough — actually open the handout and look at it.** Page count and
`Tagged: yes` both stay green even when every `\only<n>{…}` in a frame stacks onto one page
instead of showing the intended single step (**C-HANDOUT-MODE**). Beamer's
`\begin{frame}<handout:2>` idiom does not carry over: under ltx-talk it suppresses every
`\only` in the frame rather than selecting overlay 2. Any deck with two-or-more
`\only<n>{...}` sites in one frame and no `handout:` qualifier needs this checked by eye, and
fixed per-frame with matched `handout:0`/`handout:1` pairs — see the entry for the exact
recipe and the trap (marking only the overlay to drop, not the one to keep, silently produces
a *blank* frame).

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
skips them by design: adding the `alt` key, or `\altinput`, is a source edit done by hand.

You need **both inputs**. The rendered image gives the figure's *content* (node labels, axis
labels); the LaTeX context gives its *role in the argument*. Context alone yields "a search
tree"; the image alone misses why the slide shows it. **Never write alt text from the
filename or the frame title without viewing the image.**

**Alt text is pedagogy, not metadata** — it decides what a blind student learns from the
slide. Generated alt text is a **draft for the author to review**, never a silent commit.

---

## Step 6b — The accessibility-checker pass (Steps 1-6 are not sufficient)

Alt text on the graphics is necessary and not sufficient. A course that passed every gate in
this skill — clean compile, `Tagged: yes`, 0 tagpdf errors, every image described — was still
rejected by a real PDF/UA checker on four counts. Each is catalogued with a verified fix in the
**A-\*** section of `references/compromises.md`; read the entry before acting.

| Checker complaint | Cause | Fix |
|---|---|---|
| "headings do not begin at level one" | ltx-talk roles `frametitle` to `H4`, and a title page has no heading at all | `role/new-tag = frametitle / H2`, plus the kernel's automatic paragraph tagger pointed at `H1` — **A-HEADINGS** |
| "images without a description", pointing at *maths* | the checker is applying a ua-**1** rule; under ua-2 maths is made accessible by MathML, not `/Alt` | **nothing** — do not set `math/alt/use`; verify the MathML is present and validate against ua-2 — **A-MATHALT** |
| "tables missing headers" | every `tabular` is tagged `Table`/`TR`/`TD`, never `TH` | classify each: `table/header-rows`/`header-columns`, or `table/tagging=div` for layout grids — **A-TABLE-TH** |
| "text with insufficient contrast" | saturated emphasis colours are <4.5:1 on white | darken the palette *and* the raw `\color{red}` sites — **A-CONTRAST** |
| *(no complaint at all)* | `tikzpicture`/`pgfplots`/`\input{…pdf_t}` figures are absent from the tag tree, so there is nothing to object to | `\begin{tikzpicture}[alt=…]`; `\altinput` for inputted figures — **A-TIKZ-ALT**, found by `alt_text_audit.py`, not by a checker |

A-HEADINGS and A-MATHALT are settled in the preamble and solve the whole course at once —
**apply them in Step 1 and save the round trip.** A-TABLE-TH and A-CONTRAST need per-deck work.

> ⚠ **Blackboard's checker is not the bar — PDF/UA-2 is.** It is a simplified checker; a deck
> can score near-perfect on it and still fail a real PDF/UA-2 validator. `verapdf` runs the
> full profile locally:
> ```sh
> verapdf -f ua2 --format text deck.pdf     # PASS/FAIL
> verapdf -f ua2 --format mrr  deck.pdf     # full report, per-check
> ```
> The `-f ua2` and the `ua-2` in `\DocumentMetadata` must agree: validating as ua2 a file that
> never declared ua-2 fails on clause 5 before anything else (**C-NO-UA2**). Run it before
> calling any A-\* fix done.

Three points of judgement the scripts cannot make for you:

- **Headings.** `role/new-tag = frametitle / H2` is one safe line. The title's `H1` is not:
  hand-writing `\tagstructbegin{tag=H1}` compiles clean, passes Blackboard, and **fails
  PDF/UA-2**. A-HEADINGS has the mechanism and the working code, already shipped in
  `assets/preamble-template.tex`. Use it rather than rederiving it.
- **Tables.** Classify by asking *"does a cell still make sense read aloud on its own, with no
  column name attached?"* Yes → layout grid, demote with `table/tagging=div` and do not invent
  a header row. No → data table, needs real `TH`, often on both axes. Do not trust a "first row
  is bold" heuristic: on a real course it misclassified 18 of the most important tables, whose
  header rows are not bold. Render the slide and look. ⚠ Two traps that leave the build green —
  the settings leak between tables, and a `tabular` inside a `frame*` is not tagged at all — are
  in A-TABLE-TH. **Build an oracle before you apply:** from the audit, write down the expected
  number of data tables per deck, then count them in the built PDF. Nothing else catches either
  trap.
- **Contrast.** Measure the rendered ink at **≥200 dpi**; at 70–90 dpi anti-aliasing invents
  intermediate colours and hides the real ones. Expect at least one false positive — a
  `\fcolorbox{black}{white}` gets reported although every pixel in it is ≥11:1.

Then re-verify against the PDF structure, not the log:
```sh
qpdf --qdf --object-streams=disable deck.pdf qdf.pdf
grep -aoE '/S\s*/[A-Za-z0-9]+' qdf.pdf | tr -s ' ' | sort | uniq -c | sort -rn
#   want: >= 1 /S /H1 ; frametitle roled one level below section ;
#         /S /TH present wherever data tables are
strings qdf.pdf | grep -c '<math'          # > 0 if the deck has maths (LuaLaTeX only)
verapdf -f ua2 --format text deck.pdf
```
The grep counts elements and cannot see nesting: an `H1` containing a stray `Part`/`P` still
reports `>= 1 /S /H1`. Only the validator catches that. It also cannot see MathML, hence the
separate `strings` check — and `/S /Formula` wants MathML, **not** `/Alt` (A-MATHALT).

⚠ When globbing for the PDF, **exclude handouts**: `deck-handout.pdf` sorts before `deck.pdf`
(`-` < `.`), so `ls week*/deck-*.pdf | head -1` hands you a stale handout. It cost a full
false-negative round here: a change that had worked was reported as having done nothing.

**Report contrast and table changes to the author.** Darkening a palette changes the look of
every slide, and adding a header row changes what is on one. Neither is a silent commit.

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
