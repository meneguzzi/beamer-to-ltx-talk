# Beamer → ltx-talk: compromises & incompatibilities

Catalogue of problems found converting two real courses (11 decks, then 20) to **ltx-talk,
verified across 0.5.0–0.5.2** (0.5.0 released 2026-04-30; dev branch needs LaTeX kernel
2026-06-01). Each entry notes the specific version it was verified against. Each entry: **symptom → cause →
workaround → revisit when**. Most only appear under tagging (`\DocumentMetadata`), which is
why they are absent from the upstream quick-start docs.

**Where a workaround lives matters as much as what it is.** ltx-talk is experimental and
moving, so every entry here is temporary by design. A workaround that sits in the shared
preamble (`assets/preamble-template.tex`, deployed as `ltx-common.tex`) is deleted in one edit
when the class catches up, and every converted deck is correct the moment it is. A workaround
spread through deck bodies has to be found and undone deck by deck. So, in order of preference:

1. **A command or setting in the shared preamble.** Deck source unchanged. C-TOC and
   C-BACKGROUND are the worked examples — the decks keep their original `\section{Title}` and
   `\usebackgroundtemplate{...}` lines, and the preamble defines what they mean.
2. **A `convert_deck.py` rewrite.** Deck source changes once, mechanically.
3. **A lint rule plus a hand fix.** Only where the correct output needs judgement the script
   cannot make — C-ONSLIDE-ARG, where automating it corrupted a real deck.

Entries that use 2 or 3 should say why 1 was not possible. **Revisit when** is where an entry
records what would let it move up, or disappear.

**Before relying on this, re-check upstream** — these are version-pinned:
- Changelog: https://github.com/josephwright/ltx-talk/blob/main/CHANGELOG.md
- Issues: https://github.com/josephwright/ltx-talk/issues

---

## C-ALGO — `algpseudocodex` cannot be typeset under tagging  ⚠️ highest impact

- **Symptom:** `! Improper \halign inside $$'s.` (and, with multi-line `\State{…\\…}`,
  `! You can't use \halign in math mode`) — emitted at `\end{frame}`. The frame cannot be
  produced at all. Triggered by `\Comment` and/or `\Function` inside `\begin{algorithmic}`.
- **Cause (verified 2026-06-27, ltx-talk 0.5.0):** `algpseudocodex` typesets every code
  line inside a **`varwidth`** box (it `\RequirePackage{varwidth}`; see algpseudocodex.sty
  lines 28, 185, 470, 854 — varwidth is what powers its `indLines` guide rules and aligned
  comments). `varwidth` is two-pass: it sets the body to measure it, then *reprocesses* it
  via an internal `\halign`. Under tagging that reprocessing runs in a display-math (`$$`)
  context, where `\halign` is illegal → "Improper `\halign` inside `$$`'s" plus
  `varwidth: Failed to reprocess entire contents`. **Independent of the `math` tagging
  phase** — reproduces under `testphase={phase-I,…}` with no math phase at all. Box-wrapping
  (minipage/parbox/varwidth) does **not** help. `\SuspendTagging`/`\ResumeTagging` around
  the env makes pdflatex **hang** (and would un-tag the algorithm anyway) — do not use it.
- **Workaround:** switch the engine to the **classic `algorithmicx`/`algpseudocode`**:
  ```latex
  \usepackage{algorithmicx}
  \usepackage[noend]{algpseudocode}   % [noend] mimics algpseudocodex's noEnd look
  ```
  Syntax is ~identical (`\State`, `\Function`, `\Comment`, `\Call`, `\If`, `\While`,
  `\Statex`). The exact same algorithm source then compiles tagged and clean. Drop the
  `algpseudocodex` options `noEnd,indLines=false` (not valid here). Cosmetic differences:
  classic prints "end function" unless `[noend]`; no indent guide lines.
- **Revisit when:** **ltx-talk may fix this later** — the real fix is for the tagged output
  path to tolerate a `\halign` produced by boxed two-pass reprocessing (varwidth), so re-test
  `algpseudocodex` against each new ltx-talk release and drop the engine swap once it works.
  It could equally be fixed from the `algpseudocodex` side (a varwidth-free mode). No upstream
  issue is filed against either yet — consider filing one citing the varwidth reprocessing
  mechanism above. **This blocks most algorithm-bearing decks, so check it first.**

## C-TOC — `\tableofcontents` corrupts the tag tree

- **Symptom:** `Package tagpdf Error: The number of automatic begin (N) and end (M) … para
  hooks differ!` and `structure Sect can not be closed`. PDF is emitted but invalid as tagged.
- **Cause:** ltx-talk's `\tableofcontents` (as used in `\AtBeginSection` outline frames)
  opens/closes tagging structures unevenly. `\tagpdfsetup{activate=off}`, `\tagpdfparaOff`,
  Artifact-wrapping, and `frame*` all fail to fix it.
- **Workaround:** drop the auto-outline, and **redefine `\section` itself** so the decks need
  no edit at all. Snapshot ltx-talk's own `\section` with `\NewCommandCopy` (so the
  redefinition delegates instead of recursing), then have it emit the section **and** a plain
  section-divider frame showing the title (tagging-clean, verified):
  ```latex
  \NewCommandCopy{\ltxtalkorigsection}{\section}
  \RenewDocumentCommand{\section}{s o m}{%
    \IfBooleanTF{#1}{\ltxtalkorigsection*{#3}}{%        % \section*  -> silent, no divider
      \IfValueTF{#2}{\ltxtalkorigsection[#2]{#3}}{\ltxtalkorigsection{#3}}%
      \sectiondividerframe{#3}%
    }%
  }
  ```
  `\section{X}` and `\section[Short]{X}` keep working verbatim; `\section*{X}` is the escape
  hatch for a section with no divider. You lose the "contents list with current section
  highlighted". A hand-built, tagging-safe contents frame is possible but more work — offer it
  as an option.
- **Revisit when:** issue **#223** ("repeated TOC causes Link annotations…") and the 0.5.0
  section/TOC improvements land a tagging-safe `\tableofcontents`. The non-tagged docs claim
  current-section dimming already works — so this is specifically a *tagging* regression.

## C-FRAMETITLE — braced frame titles render as body text

- **Symptom:** `\begin{frame}[c]{Objectives}` prints "Objectives" as ordinary body text; the
  header bar stays empty.
- **Cause:** without the `frame-title-arg` class option, ltx-talk does not treat the first
  braced group as the title.
- **Workaround:** convert to `\frametitle{…}`:
  `\begin{frame}[c]` then `\frametitle{Objectives}`. Renders correctly in the header.
- **Do NOT** "fix" this by loading `frame-title-arg` → see C-MAKETITLE.
- ⚠ **A leading `<overlayspec>` before `[opts]`** (`\begin{frame}<3>[c]{Title}` — legal
  Beamer, overlay spec ahead of the options bracket) was, until found on a real course,
  invisible to **both** `convert_deck.py` **and** the Step-4 verification grep — it fell
  through every regex (`^...\\begin\{frame\}(\[...\])?\{`) and reported as a false-clean
  "no orphan titles" while the frame was still unconverted. Both regexes now accept an
  optional `(<[^>]*>)?` ahead of the options group. Only 2 instances found in one course,
  but they cost nothing to miss silently — always spot-check.
- **Revisit when:** n/a — `\frametitle` is the documented primary form; keep using it.

## C-FRAMETITLE-NESTED — the convert script silently skips nested-brace titles  ⚠ silent

- **Symptom: none.** No error, no warning. The frame simply has **no title**: the text renders
  as body text and the header stays empty. This is the nastiest failure mode in the whole
  catalogue precisely because nothing tells you.
- **Cause:** `scripts/convert_deck.py` matches frame titles with `[^{}]*`, which cannot see
  **nested braces**. So it silently leaves behind both forms:
  ```latex
  \begin{frame}[c]{\only<1>{Example}\only<2>{Find a plan for}}   % single, nested
  \begin{frame}[c]{Arc consistency}{{\sc Inference}}             % double, nested
  ```
  This shipped 10 title-less frames across three decks that had already been signed off as
  "clean" — caught only later, by accident.
- **Workaround:** run **`scripts/fix_frame_titles.py`** (a real brace matcher) after
  `convert_deck.py`. It handles both the single and double forms.
- **Always verify afterwards** — this must return nothing:
  ```sh
  grep -nE '^\s*\\begin\{frame\}(\[[^]]*\])?\{' deck.tex
  ```
- **Revisit when:** `convert_deck.py` grows a brace matcher of its own.

## C-FRAME-OPT — bare Beamer frame options are discarded  ⚠ silent; `[b]`/`[t]` render centred

- **Symptom:** none. `\begin{frame}[b]` compiles, page count matches, `Tagged: yes`, and the
  frame renders centred. `pdftotext` does not see it: identical on an MWE, and on a real deck
  the same words come back regrouped, which reads as extraction noise.
- **Cause:** ltx-talk's `frame` takes a key–value list, not Beamer's positional letters:
  `\keys_set:nn { talk / frame } {#2}`. Keys are `action-spec`, `auto-break`,
  `auto-break-coverage`, `label`, `name`, `supplementary-frame`, `tag-slides` and
  `vertical-alignment` (`bottom`/`center`/`stretch`/`top`, default `center`).
  Observed, not traced through the code: **the list is parsed only if it contains an `=`**.
  The word is irrelevant — bare `auto-break`, a real key, is discarded like bare `b`
  (over-long frame: `[auto-break]` 2 pages, `[auto-break=true]` 1).
- **Workaround:** name the key. The mapping is total, so `convert_deck.py` applies it.

  | Beamer | ltx-talk | note |
  |---|---|---|
  | `[b]` | `vertical-alignment=bottom` | measured |
  | `[t]` | `vertical-alignment=top` | measured |
  | `[c]` | `vertical-alignment=center` | inert; rewritten so the source says what the class reads |
  | `[allowframebreaks]` | `auto-break=true` | not bare `auto-break` |
  | `[label=x]` | `label=x` | the one Beamer option that survives untouched |
  | `[containsverbatim]`, `[fragile]` | — | verbatim goes through `frame*` (**C-VERBATIM**) |
  | `[plain]`, `[shrink]`, `[squeeze]`, `[noframenumbering]` | — | no key; delete or reimplement |

- **Measured** (ltx-talk 0.6.0, TeX Live 2026, lualatex; `pdftotext -bbox` `yMin` of the body
  text, one-frame MWE):

  | frame options | `yMin` |
  |---|---|
  | none, `[b]`, `[t]` | 135.76 — all identical, i.e. centred |
  | `[vertical-alignment=bottom]` | 247.96 |
  | `[vertical-alignment=top]`, `[…=stretch]` | 23.57 |

- **The silence is conditional.** A list of nothing but bare words is discarded. Add any
  `key=value` to the same list and every bare word becomes
  `! LaTeX Error: The key 'talk/frame/b' is unknown` and stops the build. `[b]` is silent,
  `[b,label=x]` is loud, and converting `[t,fragile]` turns a working deck into a failing
  one. `convert_deck.py` warns when it leaves such a word behind.
- **No preamble fix exists.** Defining the missing key in the class's own family does not
  work:

  ```latex
  \ExplSyntaxOn
  \keys_define:nn { talk / frame }
    { b .meta:n = { vertical-alignment = bottom } , b .value_forbidden:n = true }
  \ExplSyntaxOff
  ```

  `[b]` still gives `yMin` 135.76; `[b,name=zz]` gives 247.96. The key exists and is ignored,
  because the list is never parsed. `\let` cannot help — `\begin{frame}`'s own argument spec
  grabs the list. The only preamble-side fix is `\RenewDocumentEnvironment{frame}`, which
  means reimplementing a definition that branches on `frame-title-arg` and calls the private
  `\__talk_frame_process:nn`, and redoing it every ltx-talk release. Rewrite the source.
- **Not backwards compatible with Beamer, but loudly so.**
  `\begin{frame}[vertical-alignment=bottom]` under `\documentclass{beamer}` gives
  `! Package keyval Error: vertical-alignment undefined` and exit 1. Beamer parses frame
  options with `keyval` unconditionally, so unlike ltx-talk it can be taught the key. A deck
  that must build both ways needs four lines on the Beamer side:

  ```latex
  \makeatletter
  \define@key{beamerframe}{vertical-alignment}[center]{\setkeys{beamerframe}{\csname beamer@va@#1\endcsname}}
  \def\beamer@va@bottom{b}\def\beamer@va@top{t}\def\beamer@va@center{c}\def\beamer@va@stretch{s}
  \define@key{beamerframe}{auto-break}[true]{\setkeys{beamerframe}{allowframebreaks}}
  \makeatother
  ```

  Measured under beamer, same MWE: `vertical-alignment=bottom` `yMin` 255.31 = native `[b]`;
  `top` 29.43; `center` 116.38 = the default; `auto-break=true` 2 pages, same as
  `allowframebreaks`. `stretch`→`s` is written by analogy and not measured.
- **On real decks** (a 28-deck course, ltx-talk 0.6.0, lualatex). Every deck converted with no
  leftover bare option. Two rebuilt against their pre-rewrite build:

  | deck | options rewritten | pages | result |
  |---|---|---|---|
  | the one with the `[b]` frame | 23 | 72 → 72 | exit 0, `Tagged: yes`, same words; that frame's body moved from `yMin` 128.32 to 185.08 |
  | the one with 3 `[t]` frames | 39 | 60 → 60 | exit 0, `Tagged: yes` |

- **Frequency:** across the two courses the Beamer originals used only `c` (456 and 776),
  `t` (1 and 43), `b` (0 and 1) and `containsverbatim` (13 and 16).
- **Detect before compiling:** `convert_deck.py --lint` reports `C-FRAME-OPT` for any option
  list holding a bare item. Hand-written frames keep reintroducing them.
- **Revisit when:** ltx-talk parses the list unconditionally, or errors on an unknown bare
  word. 0.6.1's *"Refine implementation of frame property storage"* (upstream #241) touches
  this machinery but does not change the behaviour — checked before it reached TeX Live here.

## C-FRAMESUBTITLE — `\framesubtitle` typesets nothing  ⚠ silent, and documented upstream

- **Symptom:** none. `\framesubtitle{…}` parses, absorbs its argument and prints nothing. Frame
  title, layout, page count and tag tree are all unchanged, and the compiler says nothing at
  any log level. Every fidelity check in this skill passes while the text is gone; a
  `pdftotext` diff catches it only against the Beamer build. One lecture on a live course
  shipped with six `\framesubtitle{Quiz}` and the word "Quiz" appearing zero times in the PDF.
- **Cause** (ltx-talk 0.5.3): the class declares the token list, sets it and clears it, but
  never reads it. Three mentions in `ltx-talk.cls`:
  ```
   623:  \tl_gclear:N \g__talk_frame_subtitle_tl        % cleared at slide start
  1801:  \tl_new:N    \g__talk_frame_subtitle_tl        % declared
  1810:  \tl_gset:Nn  \g__talk_frame_subtitle_tl {#3}   % set by \framesubtitle
  ```
  `\g__talk_frame_title_tl` is additionally read at 811 (typeset by the `frametitle` template)
  and 1855 (PDF bookmark). Both commands share a signature and both store their argument; only
  the title is consumed.
- ✅ **Intended, and documented.** Do not file an issue. `ltx-talk.pdf`, §"Components of a frame
  → The frame title": *"Currently, the ⟨frame subtitle⟩ is not used in output: this will be
  addressed in later releases. The ⟨options⟩ for both commands are currently unused."*
- **Workaround:** fold both parts into one `\frametitle` via a macro in the shared preamble:
  ```latex
  \newcommand{\frametitlesub}[2]{\frametitle{#1 --- {\normalsize #2}}}
  ```
  then rewrite each adjacent `\frametitle{A}` + `\framesubtitle{B}` pair to
  `\frametitlesub{A}{B}`. The Beamer-side preamble can define the same macro as a real
  `\frametitle` plus `\framesubtitle`, so converted decks stay exportable back to Beamer.
- ⚠ **Do not redefine the class's `\framesubtitle` to append to the title.** That needs either
  the private `\g__talk_frame_title_tl` or a wrapper mirroring `\frametitle`'s
  `D<>{all} O{#3} m` signature; both couple the deck to internals the manual explicitly calls
  unsettled.
- **Detect before compiling:** invisible to the compiler and to `pdftotext`, so this is a
  source-only check. `convert_deck.py --lint` (rule `C-FRAMESUBTITLE`) strips comments first;
  by hand, do the same or commented-out frames give false hits:
  ```sh
  grep -nE '^[^%]*\\framesubtitle' deck.tex
  ```
  The lint does not fire on the line defining a `\frametitlesub` dual-compile shim, whose
  Beamer-side body legitimately contains `\framesubtitle`.
- **Revisit when:** a later release typesets the subtitle; `\frametitlesub` can then be retired.

## C-CENTER-ARG — `\center{…}` used as if it took an argument  ⚠ diagnosed nowhere near the fault

- **Symptom:**
  ```
  tagpdf Error: number of automatic begin (N) and end (N-1) text-unit para hooks differ
  ```
  reported at `\end{frame}`, `\end{document}`, or some *unrelated later frame* — **never at the
  offending line**. Cost a full day of bisection on one deck.
- **Cause:** `\center`, `\centering`, `\raggedright` and `\raggedleft` are **declarations**
  (`\center` is the internal *begin* of the `center` environment), not commands taking an
  argument. Beamer tolerated `\center{X}` silently. Under tagging the stray group leaves a
  paragraph opened and never closed, so the para-hook begin/end counts drift — and the error
  surfaces wherever the imbalance is finally noticed.
- **Workaround:** use the environment.
  ```latex
  \center{Some text}                      % WRONG — silent in beamer, fatal under tagging
  \begin{center}Some text\end{center}     % right
  ```
  `scripts/convert_deck.py` rewrites `\center{…}` automatically (brace-matched, skips
  comments) and warns if the braces are unbalanced.
- **Detect before compiling** — `convert_deck.py --lint` flags it, or grep directly:
  ```sh
  grep -nE '\\(center|centering|raggedright|raggedleft)\{' deck.tex
  ```
- **Revisit when:** n/a — this was always a LaTeX misuse; tagging merely makes it fatal.

## C-MAKETITLE — `frame-title-arg` breaks `\maketitle`

- **Symptom:** `! LaTeX Error: Not allowed in LR mode.` at `\maketitle` (inside or outside a
  frame) once the `frame-title-arg` option is set.
- **Cause:** with `frame-title-arg`, every frame demands a mandatory braced title, which
  collides with `\maketitle`.
- **Workaround:** do not use `frame-title-arg` at all. Convert titles to `\frametitle`
  (C-FRAMETITLE) and the conflict disappears.
- **Revisit when:** n/a.

## C-TITLEPAGE — `\maketitle` fills the frame; trailing content overlaps

- **Symptom:** the "Material adapted from …" block that Beamer decks add after `\maketitle`
  prints **on top of** the title.
- **Cause:** ltx-talk's `\maketitle` produces a full, vertically-centred frame; anything
  after it in the same frame overlaps. The stock title is also bare (limited styling).
- **Workaround:** use a custom title frame — `\coursetitlepage{title}{subtitle}{attribution}`
  (see `preamble-template.tex`) — that lays out title, authors, institute and an attribution
  slot. Keep `\title`/`\author` as metadata for the footer/PDF info.
- **Revisit when:** a full title-page template ships (known limitation in 0.5.0).

## C-NO-DOCMETA — a deck that never sets `\DocumentMetadata` half-loads ltx-talk  ⚠ cascade of "undefined"

- **Symptom:** dozens of `! Undefined control sequence` on ordinary commands (`\institute`,
  `\hypersetup`, `\frametitle`), `! LaTeX Error: The font size command \normalsize is not
  defined`, `! Environment frame* undefined`, `\begin{document} ended by \end{frame*}`. The
  deck emits a stub PDF (2–8 pages). Nothing names the real cause.
- **Cause:** ltx-talk **requires** `\DocumentMetadata` (set before `\documentclass`). Real
  decks sometimes ship it commented out — e.g. `% \input{../tag-commands.tex}` — from a
  pre-tagging build. Without it the class only half-initialises, so huge swathes of it
  (including its own `frame*` and font machinery) are never defined.
- **Workaround:** activate it. Uncomment the metadata input (or add a literal
  `\DocumentMetadata{…}`) as the very first line, before `\documentclass`. On one real
  course this single-line change took three "totally broken" decks straight to
  `Tagged: yes`, page counts matching baseline.
- **Detect before compiling:** `convert_deck.py` warns (`C-NO-DOCMETA`) during both `--lint`
  and conversion when no `\DocumentMetadata` is reachable before `\documentclass`.
- **Revisit when:** ltx-talk starts erroring clearly on a missing `\DocumentMetadata` instead
  of half-loading.

## C-NO-UA2 — `pdfstandard=a-4` alone declares no PDF/UA conformance  ⚠ silent, and it undermines A-MATHALT

- **Symptom:** the deck compiles, is `Tagged: yes`, and looks accessible — but
  `verapdf -f ua2` fails it on **clause 5** ("the PDF/UA version of a file shall be specified
  … using the PDF/UA identification schema") and on clause 8.11.2 (`DisplayDocTitle`). Nothing
  in the log mentions either. Worse, an institutional checker that sees no ua-2 declaration is
  entitled to assess the file under PDF/UA-**1** — under which the (correct) MathML-only maths
  of **A-MATHALT** *is* a failure.
- **Cause:** `pdfstandard=a-4` is PDF/**A**-4, a preservation profile. It emits the `pdfuaid`
  XMP namespace but no `pdfuaid:part`, so the file makes no PDF/UA claim at all. The two are
  independent: you must ask for `ua-2` explicitly.
- **Workaround:** `\DocumentMetadata{lang=en, pdfversion=2.0, pdfstandard={a-4,ua-2},
  tagging=on}`. Adding `ua-2` also makes the kernel set `ViewerPreferences /DisplayDocTitle
  true`, clearing clause 8.11.2 as a side effect.
- **Measured** (ltx-talk 0.6.0, TeX Live 2026, veraPDF 1.28, `article` MWE, lualatex):

  | `pdfstandard=` | `pdfuaid:part` in XMP | `verapdf -f ua2` failing clauses |
  |---|---|---|
  | `a-4` | *absent* | **5**, 8.11.2, 8.11.1 |
  | `{a-4,ua-2}` | `part=2, rev=2024` | 8.11.1 only |

  The residual 8.11.1 is `dc:title` — the MWE has no `\title`. Adding `\title{T}` gives a clean
  `PASS`, and `\title` alone is enough: it does **not** need `\maketitle`, so a deck using the
  hand-rolled **C-TITLEPAGE** frame still satisfies it as long as `\title` is kept.
- **Detect before compiling:** `convert_deck.py` warns (`C-NO-UA2`) during both `--lint` and
  conversion when a literal `\DocumentMetadata` in *this file* sets `pdfstandard=` without
  `ua-2`. ⚠ It cannot follow `\input`, so the common layout — metadata in a shared
  `tag-commands.tex` — is invisible to it. Check that file by hand, or check the artefact:

  ```sh
  qpdf --qdf --object-streams=disable deck.pdf - | strings | grep -c 'pdfuaid:part'   # want >= 1
  ```
- **Revisit when:** ltx-talk or latex-lab starts defaulting `pdfstandard` to include a PDF/UA
  level, or warns when tagging is on but no PDF/UA conformance is declared.

## C-ONEPASS — a non-halting error caps the build at one pass  ⚠ silent, damage shows up elsewhere

- **Symptom:** an error that looks cosmetic — most often
  `! LaTeX Error: Command \foo already defined.` — costs every construct that needs a converged
  multi-pass build. Cross-references render as `??`, `remember picture` anchors never resolve,
  TOC data stays stale, MathML on formulas is absent. The damage appears nowhere near the
  error, often in a different file.
- **Cause:** `-interaction=nonstopmode` keeps TeX going, so the run "succeeds", but `latexmk`
  sees a non-zero outcome and stops:
  ```
  Latexmk: Errors, so I did not complete making targets
  ```
  One pass. Everything that resolves on pass 2 or 3 is left unresolved.
- **Reproduction** (ltx-talk 0.6.0, TeX Live 2026):
  ```latex
  \DocumentMetadata{lang=en, pdfversion=2.0, tagging=on}
  \documentclass{ltx-talk}
  \newcommand\mapsfrom{\mathrel{\reflectbox{\ensuremath{\mapsto}}}}
  \begin{document}
  \begin{frame}\frametitle{Clash}
  Ref to a later page: \pageref{last}.
  \end{frame}
  \begin{frame}\frametitle{Second}\label{last}
  Second.
  \end{frame}
  \end{document}
  ```

  | | `latexmk` exit | passes | `\pageref` renders |
  |---|---|---|---|
  | `\newcommand\mapsfrom` | 12 | **1** | **`??`** |
  | `\providecommand\mapsfrom` | 0 | 3 | `2` |

  Nothing else changed; the maths renders identically in both.
- **Why converted decks hit this:** a course preamble that predefines maths symbols
  (`\newcommand\mapsfrom{…}` in a shared symbols file) is fine under Beamer/pdfTeX, where
  nothing defines them. Under ltx-talk with LuaTeX, `unicode-math` already provides them and
  `\newcommand` refuses. On one 20-deck course this fired in **20 of 20 decks**, and 0 of 20
  Beamer baselines.
- **Workaround:** `\providecommand` for any symbol a full `unicode-math` stack might supply.
  Otherwise, fix the error — there is no error worth leaving in a deck you intend to verify.
- **Detect:** the deck's own `.log` says whether the build converged.
  ```sh
  grep -ciE 'Rerun to get|Label\(s\) may have changed' deck.log   # PRIMARY: did NOT converge
  grep -c 'Latexmk: Errors' build.log                            # latexmk gave up
  grep -c 'There were undefined references' deck.log
  ```
  All three must be 0, but ⚠ **check the first** — they are not interchangeable. A deck with no
  forward references produces no undefined-reference warning while still capped at one pass.
  Measured on a 98-page deck with the clash present: `Rerun to get… = 1`,
  `There were undefined references = 0`. **Not lint-detectable:** the offending `\newcommand`
  usually lives in an `\input`-ed shared preamble, which `--lint` does not read.
- ⚠ **A correct page count is not evidence of a sound build.** The broken build above emits a
  correct-looking, correctly paginated, `Tagged: yes` PDF.
- **Revisit when:** n/a — `latexmk` is behaving correctly. The fix is to have no errors.

## C-AND-TITLE — `\and` in a custom title page detonates  ⚠ 101 errors, none near the fault

- **Symptom:** `! Misplaced \crcr.` (inside `\tbl_crcr:n`), `! Missing } inserted`,
  `! Extra }, or forgotten \endgroup` — **101 errors on one real deck**, every one reported at
  `\end{frame}` or `\end{document}`, none of them at the title page that actually caused it.
  Removing the attribution text, the `\\` line breaks, even emptying the argument entirely,
  changes nothing — which sends you hunting in the wrong file for hours.
- **Cause:** `\author{A \and B}` is idiomatic, so `\AuthorLong` naturally holds `A \and B`.
  But **`\and` is not a separator** — LaTeX defines it as
  `\end{tabular}\hskip 1em \plus.17fil \begin{tabular}[t]{c}`. It is only legal *inside*
  `\author`/`\maketitle`, where a `tabular` is already open. A custom title frame that
  typesets `\AuthorLong` in running text therefore **closes a tabular that was never opened**,
  ripping an alignment apart. The tagging table module (`\tbl_crcr:n`) is what finally
  reports it, which is why the error looks like a tagging bug and is not one.
- **Workaround:** rebind `\and` for the duration of the title frame:
  ```latex
  \newcommand{\coursetitlepage}[3]{%
    \begingroup
    \renewcommand{\and}{\qquad}%   <-- without this, 101 errors
    \begin{frame} ... {\large \AuthorLong} ... \end{frame}%
    \endgroup
  }
  ```
  Verified: same deck, same everything else — 101 errors → **0 errors, page count identical,
  `Tagged: yes`**. `assets/preamble-template.tex` now does this.
- **Also:** the stock template avoids `\\` as a line break in that frame (`\par` + `\vspace`
  instead). `\\` is not what breaks here, but `\par`/`\vspace` is the tagging-safe idiom for
  stacking centred lines.
- **Revisit when:** n/a — `\and` outside `\author` was always invalid; tagging just makes the
  diagnosis maximally confusing.

## C-VERBATIM — `containsverbatim` / `lstlisting` need `frame*`

- **Symptom:** `! Paragraph ended before \lst@next was complete` / runaway argument with
  `listings` or `verbatim` in a normal `frame`.
- **Cause:** ltx-talk frames don't catch-code-protect verbatim; the Beamer `containsverbatim`/
  `fragile` options don't exist.
- **Workaround:** use the `frame*` environment (`\begin{frame*} … \frametitle{…} …
  \end{frame*}`). It handles `\verb`/verbatim/`lstlisting` without external files.
- ⚠ **`frame*` is necessary but NOT sufficient under tagging** — on its own it corrupts the
  tag tree. See **C-FRAMESTAR-TAG** below; you must also suspend tagging around it.
- `scripts/convert_deck.py` now rewrites the `\begin` **and** walks the file to pair every
  `\end{frame}` → `\end{frame*}` automatically. It also converts verbatim frames with an
  **empty or absent title** (`\begin{frame}[c,containsverbatim]{}` or `…]` with no `{}`) —
  an earlier version let the empty-title rule strip the `{}` and leave a plain frame, so the
  listing still broke with `\lst@next`. The containsverbatim check now runs first.
- **Revisit when:** n/a — `frame*` is the documented mechanism.

## C-FRAMESTAR-TAG — `frame*` + `listings` corrupts the tag tree  ⚠ highest impact

- **Symptom:** `Package tagpdf Error: there is no open structure on the stack` at
  `\end{frame*}`; `The number of automatic begin (N) and end (M) … differ`; poppler reports
  `Mismatched EMC operator`; and downstream `Use of \??? doesn't match its definition` /
  "Access to an entry beyond an array's bounds" at `\end{document}`. **70 errors** on one
  real 68-page deck with 13 PDDL listings.
- **Cause:** ltx-talk's `frame*` **re-tokenises its body** (`\tl_retokenize:n`, ltx-talk.cls
  ~line 599) in order to handle verbatim. Under `\DocumentMetadata` that re-processing emits
  unbalanced tagging structures, and `listings` — which is not tag-aware — cannot survive it.
  Reproduces with `frame*` + `lstlisting` and *nothing else*.
- **Workaround (verified: 0 errors, 0 warnings):** suspend tagging around the **entire
  `frame*`**, via order-independent hooks in the preamble:
  ```latex
  \ExplSyntaxOn
  \AddToHook{env/frame*/before}{\tag_stop:}
  \AddToHook{env/frame*/after}{\tag_start:}
  \ExplSyntaxOff
  ```
  Things that do **not** work, all tried:
  - suspending only the `lstlisting` (rather than the whole `frame*`) — errors remain;
  - `\SuspendTagging`/`\ResumeTagging` instead of `\tag_stop:`/`\tag_start:` — leaves a
    nested/dangling marked-content unit at the frame boundary ("nested marked content",
    "no mc to end", `Mismatched EMC`) and *re-introduces* structure errors when two `frame*`
    are adjacent;
  - adding tagging phases (`block`, phase-II, phase-III) — no effect;
  - `\lstinputlisting` from an external file in a normal `frame` — still 2 errors.
- **Trade-off — larger than it looks:** the hooks suspend tagging for the **whole
  environment**, so *everything* on that slide becomes an artifact, not just the listing. The
  prose, the itemize, any `tabular`, any figure — none of it is in the screen-reader reading
  order, and any `\tagpdfsetup` you write inside the frame is **inert**. This surfaces later
  as a phantom bug ("why does this table have no `TH`?"); it is this compromise, not a table
  problem. Keep a `frame*` down to the listing plus the minimum around it, put anything that
  matters pedagogically *outside* the frame as tagged content, and audit how much of the
  course is inside `frame*`: `grep -c 'begin{frame\*}' week*/*.tex`.
- **Revisit when:** ltx-talk's `frame*` stops re-tokenising, or `listings` becomes tag-aware.

## C-NOBEAMER — all `\usetheme`/`\setbeamer*`/`\usebeamerfont` are undefined

- **Symptom:** `Undefined control sequence` for any `\setbeamercolor`, `\setbeamertemplate`,
  `\usetheme`, `\usebeamerfont`, `\beamercolorbox`, etc.
- **Cause:** ltx-talk intentionally has no `beamer`-named commands.
- **Workaround:** rebuild styling with the kernel template/instance system:
  `\EditInstance{header}{std}{background-color=…,color=…}`, `\EditInstance{footer}{std}{…}`.
  Named visual themes (Madrid/Warsaw/CambridgeUS) have **no equivalent** — the look is
  approximate, not identical. Warn the user; agree on fidelity vs. clean-accessible style.
- **Revisit when:** ltx-talk grows themeing (none planned short-term; design is low priority
  per the class description).

## C-FONTS — maths is sans-serif by default

- **Symptom:** maths looks different (sans) from Beamer's `\usefonttheme[onlymath]{serif}`.
- **Cause:** ltx-talk defaults to all-sans, including `\mathrm`/`\textrm`.
- **Workaround:** decide per project. XeLaTeX is **not** supported; LuaTeX needs Unicode maths
  setup. To restore the Beamer `\usefonttheme[onlymath]{serif}` look under **pdfLaTeX** (sans
  body text, serif maths), re-point the four core maths symbol fonts back to Latin Modern
  *after* `amssymb`. ltx-talk's pdfLaTeX path loads `sansmathfonts` + `lmodern[nomath]` and
  sets `\rmdefault=\sfdefault`, which is what makes maths sans:
  ```latex
  \DeclareSymbolFont{operators}   {OT1}{lmr} {m}{n}
  \DeclareSymbolFont{letters}     {OML}{lmm} {m}{it}
  \DeclareSymbolFont{symbols}     {OMS}{lmsy}{m}{n}
  \DeclareSymbolFont{largesymbols}{OMX}{lmex}{m}{n}
  \SetSymbolFont{operators}{bold}{OT1}{lmr} {bx}{n}
  \SetSymbolFont{letters}  {bold}{OML}{lmm} {b}{it}
  \SetSymbolFont{symbols}  {bold}{OMS}{lmsy}{b}{n}
  ```
  Verified tagging-clean on a 20-deck course.
- **Revisit when:** n/a — design choice.

## C-IMMATURE — blocks, theorems, media

- **Blocks:** `\begin{block}{}…\end{block}` *works* but is undocumented/under development
  (issue #205). Usable for simple callouts; don't build elaborate styling on it.
  **CRITICAL:** also see C-BLOCK-ALGO below — `block` conflicts with `algorithmic`.
- **Theorems:** `\newtheorem*` is incomplete (issue #219). Use tcolorbox instead — see C-BLOCK-ALGO.
- **Media:** `media9 \includemedia`, `\movie`, `\animategraphics` are untested under tagging —
  verify case-by-case or fall back to a static image + hyperlink.
  ⚠ **If you drop `media9` from the preamble** (the template does not load it by default)
  **but a deck still has `\includemedia{...}` in the body**, the failure is a multi-error
  cascade — `Undefined control sequence`, `Illegal unit of measure`, `Misplaced alignment tab
  character &` (from the unparsed `flashvars` string) — none of which names the missing
  package. Step 0.4's survey grep (`\includemedia|\movie|\animategraphics`) exists precisely
  to catch this before it happens: if it hits, either keep `media9` loaded in that deck's
  preamble, or remove the `\includemedia` call and use the deck's own fallback link/image
  (most `\includemedia` sites already carry one, e.g. a YouTube URL in the same frame).
- **Revisit when:** the cited issues close.

## C-BLOCK-ALGO — `\begin{block}` conflicts with algorithmicx  ⚠️ non-obvious

- **Symptom:** `! Missing \endcsname inserted` / `! Extra \endcsname` at `\end{frame}` in any
  frame that uses `\begin{algorithmic}`, even if no theorem environment appears in that frame.
  Occurs as soon as a `\newenvironment{definition}{\begin{block}{…}}{…}` (or similar) is
  **defined anywhere in the preamble** — using it is not required.
- **Cause:** ltx-talk's `\begin{block}` resets or reuses an internal name that collides with
  algorithmicx's `\csname`-based block-depth stack
  (`\ALG@b@N@EndFor`, `\ALG@currentblock`, `\ALG@makebeginrepeat`). The `\csname` push/pop
  tracking gets mismatched, and `\end{frame}` sees unbalanced `\endcsname` pairs.
- **Workaround:** define all theorem-like environments (`definition`, `theorem`, `corollary`,
  `example`) using **tcolorbox** instead of `\begin{block}`:
  ```latex
  \usepackage[most]{tcolorbox}
  \tcbset{theoremstyle/.style={
    colback=aliceblue, colframe=bostonuniversityred,
    fonttitle=\bfseries, sharp corners, boxrule=0.4pt,
    left=4pt, right=4pt, top=2pt, bottom=2pt,
  }}
  \newenvironment{definition}{\begin{tcolorbox}[theoremstyle, title=Definition]}{\end{tcolorbox}}
  ```
  tcolorbox does not touch algorithmicx's internal counters — tagging-safe and conflict-free.
- **Revisit when:** ltx-talk issue #205 / #219 land a stable `\newtheorem` / block environment
  that does not interfere with `algorithmicx`.

## C-OVERLAY-ALIGN — `\onslide` inside `tabular`/`align*` breaks alignment

- **Symptom:** `! Misplaced alignment tab character &` or `! Improper \halign inside $'s` when
  `\onslide<n>{…}` wraps an entire row including `&` or `\\`: e.g. `\onslide<2>{& = formula
  \\}` or `\onslide<+->{cell1 & cell2 \\}`.
- **Cause:** `&` and `\\` must be at the **top level** of a `tabular`/`align*` environment
  (they are active inside the `\halign`). `\onslide<n>{…}` expands to a genuine brace group
  around its content (C-ONSLIDE-ARG's leak is a side effect of the same mechanism), so
  wrapping `&`/`\\` in it removes them from that top level and TeX errors out.
- ⚠ **This is specific to `\onslide`.** An earlier version of this entry named
  `\visible`/`\only` as equally hazardous. Verified false on a real course (20+ instances of
  `\uncover<+->{cell & cell \\ \hline}` and `\only<2->{1 & 0 & 0\\}`, all compiling with 0
  errors and rendering correctly across the full overlay sequence): `\only` fully includes or
  fully omits its content (`ltx-talk.cls`'s `\__talk_if_overlay:nT`), and `\uncover` typesets
  the content unconditionally and only toggles opacity — neither mechanism exposes `&`/`\\`
  to `\halign` mid-group the way `\onslide`'s stray-group-plus-leaking-declaration does.
  `\uncover`/`\only` around a full row are safe; only `\onslide` needs the workaround below.
- **Workaround:** keep `&` and `\\` at the top level; wrap only the **content**:
  ```latex
  % tabular — use <.-> on cols 2+ to share the same overlay step
  \uncover<+->{cell1} & \uncover<.->{cell2} & \uncover<.->{cell3} \\
  % align* — wrap the formula, not the alignment token
  & \uncover<4->{= \frac{1}{n}(R_n + (n-1)Q_n)} \\
  ```
  ⚠ Use `\uncover`, **not** `\onslide` — see C-ONSLIDE-ARG. `\onslide` takes no argument, so
  `\onslide<+->{cell1}` leaks past the cell and blanks the rest of the table.
  `<.->` on subsequent cells reuses the current step counter without incrementing, so all
  cells in a row appear and disappear together. `<+->` on the first cell increments the step.
- **Revisit when:** n/a — this is a fundamental TeX alignment mechanism constraint.

## C-OVERLAY-ALGO — `\onslide{\State…}` corrupts algorithmicx block tracking

- **Symptom:** `! Missing \endcsname inserted` / `! Extra \endcsname` at `\end{frame}` in
  frames that use `\begin{algorithmic}` AND wrap `\State` in **any** overlay command —
  `\onslide<2>{\State formula}`, `\uncover<2>{\State formula}`, and `\only<2>{\State formula}`
  all trigger it identically; this is not specific to `\onslide`. In practice this only bites
  when the wrapped `\State` sits **nested inside** `\If`/`\ForAll`/`\Loop`; a top-level
  `\only<1>{\State …}` (not nested in a block) is harmless, and an overlay inside a
  `\Function` *name* is fine.
- **Cause:** algorithmicx tracks nesting depth with `\csname`-based counters
  (`\ALG@b@N@EndFor`, `\ALG@currentblock`). Wrapping `\State` in **any** brace group —
  regardless of which overlay macro opens it — scopes the push but not the pop of those
  counters, leaving them permanently mismatched. `\end{frame}` then sees unbalanced
  `\endcsname` pairs. (The lint rule already matches `onslide|only|visible|uncover`; this is
  a documentation fix, not a detection gap.)
- **Workaround:** keep the **structural token at the top level** and wrap only its
  *content* — the same principle as C-OVERLAY-ALIGN:
  ```latex
  % Instead of: \onslide<2>{\State $x \gets y$ \Comment{note}}
  \State \uncover<2>{$x \gets y$ \Comment{note}}   % 0 errors, overlay preserved
  ```
  `\State` is then always executed (so push/pop stay balanced) and only the text appears or
  disappears. Wrapping a **balanced** `\If{…}\EndIf` pair is also safe, because both push and
  pop are hidden together — but it must be `\uncover<2>{\If…\EndIf}`, **never**
  `\onslide<2>{…}` (C-ONSLIDE-ARG).
- ⚠ **Do NOT use `\State<2> …`.** An earlier version of this entry recommended the
  "native overlay-spec syntax". **It does not work** under classic `algpseudocode` (the engine
  C-ALGO forces you onto): the `<2>` is typeset as **literal `<2>` text on the slide** and the
  overlay never fires, so the line renders on every slide *and* carries visible junk. Verified
  2026-07-22 by rendering the page — note that `pdftotext` shows the `<2>` too, but only the
  image proves it is *visible*. Classic `algpseudocode` is simply not overlay-aware; only
  beamer patched it to be.
- ⚠ **`\onslide` is not the fix either** — earlier revisions of this entry said
  `\State \onslide<2>{…}`. That leaks (C-ONSLIDE-ARG) and in a real deck blanked the entire
  remainder of a two-function algorithm. Always `\State \uncover<2>{…}`.
- **Revisit when:** ltx-talk (or algorithmicx) grows real overlay-spec support on `\State`.

## C-ONSLIDE-ARG — `\onslide<n>{…}` takes no argument and leaks to end of frame

- **Symptom:** none at compile time. Zero errors, zero warnings, correct page count. On the
  *early* overlays of a frame, everything after the `\onslide` is simply blank — the rest of a
  table row, all following rows, subsequent body text, even the other column of a `columns`
  environment. Found only by rendering an early overlay and looking at it.
- **Cause:** ltx-talk declares
  ```latex
  \NewDocumentCommand \onslide { D <> { all } }     % ltx-talk.cls:1486 — spec only, no +m
  ```
  so `\onslide<2>{X}` is the *declaration* `\onslide<2>` followed by an ordinary brace group.
  The declaration then applies to the rest of the frame. It is stored in a **global** token
  list (`\g__talk_onslide_tl`, ltx-talk.cls:1502), so ordinary grouping — including `tabular`
  cells, which are their own TeX group — does **not** contain it. This is a genuine Beamer
  incompatibility: Beamer's `\onslide` *does* accept a braced argument, so the pattern
  survives conversion untouched and looks right.
- **Workaround:** use the commands that really do take an argument:
  ```latex
  \uncover<2>{X}    % hides but RESERVES space  — the Beamer \onslide{...} equivalent
  \only<2>{X}       % omits entirely, no space reserved
  ```
  `\uncover` is the right default when converting Beamer's `\onslide<n>{…}`; it keeps the
  layout stable across overlays. Bare `\onslide<2->` with no group remains valid ltx-talk and
  should be left alone.
- **Scale:** in one 11-deck course this pattern appeared **139 times** and was invisible in
  every "builds clean" report; a 20-deck course had 204 more. The mechanical fix is
  `\onslide<spec>{` → `\uncover<spec>{` (skip commented-out lines); page counts should be
  **unchanged** afterwards, which is a good invariant to assert.
  ⚠ **That mechanical fix breaks if the group being rewritten wraps a whole
  `tabular`/`align*`/`cases`/`matrix` environment**, not just a cell's content — the `&`/`\\`
  inside belong to that environment's own alignment, and a blind regex swap can leave you
  with a corrupted brace count (mismatched `\begin`/`\end` inside the new `\uncover{…}`).
  Caught in practice on a real course. Anyone scripting this fix beyond `convert_deck.py`'s
  `--lint`-only stance (see the note under Step 2 in `SKILL.md` — this rewrite is deliberately
  left manual, not automated, precisely because it needs this kind of judgement) should
  first check the group doesn't contain a `\begin{tabular}`/`\begin{align*}`/etc.
- **Revisit when:** ltx-talk gives `\onslide` a `+m` argument form for Beamer compatibility.
  Track against `\NewDocumentCommand \onslide` in `ltx-talk.cls`.

## C-OVERLAY-MULTIPASS — `\only` rows relying on Beamer's per-page re-typesetting need a `\\` ltx-talk doesn't

- **Symptom:** `! Extra alignment tab has been changed to \cr.` (repeated, once per row) in a
  `tabular` built from consecutive `\only<N>{cell1 & cell2 & cell3}` rows **with no trailing
  `\\`** on any of them.
- **Cause:** Beamer *re-typesets the frame once per overlay page*, so on overlay page N only
  the matching `\only<N>{…}` branch is ever expanded — every other row vanishes from the
  source entirely, and whichever row survives is always the table's last, so it needs no row
  terminator. ltx-talk instead typesets the frame **once**, expands **every** overlay branch
  into the same `\halign`, and toggles visibility afterwards via PDF OCG layers (see
  C-ONSLIDE-ARG/C-OVERLAY-ALIGN for the same single-pass model). Under that model all N rows
  genuinely coexist in one alignment, and every row but the last needs its own `\\` — a
  Beamer deck written assuming re-typesetting silently violates that.
- **Workaround:** add the missing `\\` to every row but the last:
  ```latex
  \only<1>{a & b & c} \\
  \only<2>{d & e & f} \\
  \only<3>{g & h & i}     % last row: no trailing \\
  ```
- **Detect:** not caught by `--lint` (it is a missing token, not a hazardous pattern) — only
  surfaces at compile as `Extra alignment tab`. If a table built from stacked `\only<N>{row}`
  lines fails this way, check for a missing `\\` before chasing anything else.
- **Revisit when:** n/a — this is the same single-pass-vs-multi-pass model difference behind
  C-ONSLIDE-ARG and C-OVERLAY-ALIGN, just manifesting as a missing token instead of a leak.

## C-HANDOUT-MODE — mode-qualified overlay specs are only half implemented, so handouts stack every overlay

- **Symptom:** nothing in the slides. The **handout** build prints every overlay of a frame
  stacked on one page, so a step-through built from `\only<1>{img1}` … `\only<4>{img4}` hands
  the reader four images on top of one another. Build green, page count the expected
  one-per-frame, handout tag-soundness check passes. Found converting a 20-deck course: 120
  live sites across 13 decks.
- **Cause:** `ltx-talk.cls` parses Beamer's mode syntax (`article`/`handout`/`projector`) but
  implements only part of the semantics. Beamer's `\begin{frame}<handout:2>` means *hand out
  slide 2 of this frame*; ltx-talk keeps the frame and suppresses every `\only` inside it,
  leaving only the non-overlay text. Measured on a two-overlay frame (`\only<1>{BLANK}` /
  `\only<2>{FILLED}`, built with `\PassOptionsToClass{handout}{ltx-talk}`, ltx-talk 0.5.3):

  | Source | Handout output |
  |---|---|
  | nothing | **both**, stacked |
  | `\begin{frame}<handout:0>` | frame dropped ✅ |
  | `\begin{frame}<handout:2>` | frame kept, all `\only` suppressed, only plain text survives |
  | `\only<1\| handout:0>` alone | frame kept, **nothing** rendered |
  | `\only<1\| handout:0>` **and** `\only<2\| handout:1>` | second overlay only ✅ |

  Projector output is correct in all five. Frame-level `<handout:0>` is the one frame-scoped
  form that behaves, and it drops the whole frame.
- **Workaround:** mark overlays in **matched pairs** — `handout:0` on the ones to drop *and*
  `handout:1` on the ones to keep:
  ```latex
  \only<1| handout:0>{\includegraphics[...]{environments-blank.pdf}}
  \only<2| handout:1>{\includegraphics[...]{environments-full.pdf}}
  ```
  Whitespace around `|` is trimmed. ⚠ **Marking only the overlays to drop produces a blank
  frame** — silently worse than doing nothing. This is a per-frame judgement, not a mechanical
  rewrite: a genuine progressive build often should show every step in the handout. Unlike most
  of this catalogue, `<handout:N>` works natively under Beamer, so a deck keeping Beamer as an
  export target needs different source for the two backends.
- **Detect:** `convert_deck.py --lint` flags every frame with 2+ `\only<n>{...}` sites and no
  `handout:` qualifier anywhere in the frame. Advisory, not a rewrite: a genuine progressive
  build is a legitimate reason for the finding to be a no-op, so it names candidate frames for
  a human rather than auto-annotating them. It cannot confirm the bug — **build the handout and
  look at it**, since a tag-soundness check on the handout passes regardless.
- **Revisit when:** ltx-talk implements frame-level `<handout:N>` selection, not just
  suppression.

## C-PDFTEX-MATH — pdfTeX corrupts every comma and period in the maths text layer  ⚠ silent, engine-dependent

- **Symptom:** the slides render correctly, but the PDF text layer is wrong wherever there is
  maths: every comma extracts as `;`, every period as `:`, `\ldots` as `": : :"`, `\checkmark`
  as `X`. Clean compile, correct page count, `Tagged: yes`, 0 tagpdf errors. Copy-paste,
  full-text search, and any assistive technology reading the text layer rather than tagged
  `/ActualText` get the corrupted version.
- **Measured** (ltx-talk 0.6.0, TeX Live 2026) — one frame, source
  `Inline: $g(a, b, c)$ and $x.y$ and $p \ldots q$.`:

  | engine | `pdftotext` output |
  |---|---|
  | **pdfLaTeX** | `Inline: g (a; b; c) and x:y and p : : : q.` |
  | XeLaTeX | `Inline: 𝑔(𝑎, 𝑏, 𝑐) and 𝑥.𝑦 and 𝑝 … 𝑞.` |
  | LuaLaTeX | `Inline: 𝑔(𝑎, 𝑏, 𝑐) and 𝑥.𝑦 and 𝑝 … 𝑞.` |

  The Beamer original of the same source extracts correctly under pdfTeX, so the corruption
  arrives with the class, not the engine alone.
- **Cause:** `ltx-talk.cls` picks its maths font by engine. Under LuaTeX/XeTeX it loads
  `NewCMSansMath-Regular.otf` via `\setmathfont`; otherwise it falls back to
  `\RequirePackage{sansmathfonts}`, whose OML-encoded sans maths has wrong ToUnicode maps.
- **Workaround:** build with **LuaLaTeX** — `latexmk -lualatex`, which `assets/Makefile` does.
  No source change: an already-converted deck is repaired by rebuilding.
- ⚠ **Not XeLaTeX.** XeTeX takes the same OpenType branch and fixes the text layer, but MathML
  generation is LuaTeX-only:
  ```latex
  \sys_if_engine_luatex:TF
    { \RequirePackage { lua-unicode-math }
      \tagpdfsetup { math / mathml / luamml / load = true } }
    { \RequirePackage { unicode-math } }
  ```
  Measured on the MWE above plus `\[ f(x) = \sum_{i=1}^{n} a_i x^i \]`, after three passes
  (`qpdf --qdf --object-streams=disable`, then `grep -ao '<math'`): LuaLaTeX emits **4**
  `<math>` payloads, XeLaTeX **0** — `/Formula` elements with nothing inside them. XeTeX also
  warns `tagpdf ... xetex doesn't support interword`. For tagged maths, LuaLaTeX is the only
  correct choice.
- ⚠ **Count passes before concluding anything here.** On a single pass both engines emit 0
  payloads; the MathML appears only once the build converges, so a one-pass build makes
  LuaLaTeX look no better than XeTeX. A non-halting `!` error is enough to cap the build at one
  pass — see **C-ONEPASS**.
- **Cost of the switch:** LuaLaTeX is slower, and font metrics shift slightly (a probe moved a
  measured x-position from 50.041 to 50.165), so a deck can reflow. Re-check page counts against
  the pre-switch build.
- **Detect:** extract the text layer and look for corrupted maths punctuation.
  ```sh
  pdftotext deck.pdf - | grep -n '[a-z]; [a-z]'
  ```
  `pdfinfo deck.pdf | grep Producer` says which engine actually built a given PDF.
- **Revisit when:** ltx-talk gives the pdfTeX path a maths font with correct ToUnicode maps, or
  drops the pdfTeX fallback. Verified present on 0.6.0.

## C-DISPLAY-DOLLAR — `$$…$$` silently outdents every list item after it  ⚠ silent, ltx-talk only

- **Symptom:** in an `itemize`, every `\item` after a `$$…$$` display loses its indentation and
  renders flush with the frame margin, so the list visibly splits in two. Clean compile,
  correct page count, sound tag tree, `Tagged: yes`, and `pdftotext` returns the same words in
  the same order. **Render the page to catch this.** `$$` also selects the wrong display skips,
  making vertical gaps uneven — cosmetic, unlike the outdent.
- **Scale:** one 20-lecture course had this in **16 of 24 decks across 164 sites** (worst decks
  44, 23, 20, 16). It passed every gate and was found by eye, months after conversion.
- **Measured** (ltx-talk 0.5.3, TeX Live 2026) — x-position of the item text in points via
  `pdftotext -bbox`, same three-item list in each class:

  | class | `$$…$$` | `\[…\]` |
  |---|---|---|
  | `article` | 158.7 / 158.7 / 158.7 | 158.7 / 158.7 / 158.7 |
  | `beamer` | 50.2 / 50.2 / 50.2 | 50.2 / 50.2 / 50.2 |
  | **`ltx-talk`** | **50.0 / 28.3 / 28.3** | 50.0 / 50.0 / 50.0 |

  Items 2 and 3 lose 21.7pt — exactly the `itemize` indent — and land on the frame margin.
- **Cause: not pinned down.** Presumably ltx-talk applies its list indentation in a way raw
  `$$` bypasses and `\[…\]` does not. What is established: not the tagging (reproduces under
  `\DocumentMetadata{tagging=off}`), and not a local preamble (reproduces with the bare class, no packages).
  ⚠ It is also **not** generic LaTeX `list` behaviour: the `\parshape` explanation is the first
  thing that comes to mind and survives casual checking, but `article` uses the same `list`
  machinery and is unaffected. Do not repeat it.
- **Workaround:** spell display math `\[…\]`. `convert_deck.py` rewrites this automatically,
  alternating `\[` and `\]` over the `$$` occurrences in file order, skipping comments and
  verbatim bodies, and refusing to rewrite at all if the total count is odd. Pure LaTeX, so the
  deck stays exportable back to Beamer. There is no reason to keep `$$` in any deck.
- **Detect before compiling:** `convert_deck.py --lint` (rule `C-DISPLAY-DOLLAR`) flags any
  unescaped `$$` outside comments and verbatim bodies.
  ```sh
  grep -nE '^[^%]*(^|[^\\])\$\$' deck.tex
  ```
- ⚠ **Check the overfull-vbox count after converting.** The corrected display skips are
  slightly larger than what `$$` produced, so an already-tight frame can tip over. Compare
  against the same deck before the rewrite, not against zero.
- **Limitation of any lexical pass:** `$a$$b$` — two adjacent inline maths with no space —
  reads as a `$$` to the converter, the lint and the grep. Rare; the converter reports its pair
  count so it can be eyeballed.
- **Revisit when:** filed upstream. Best-evidenced item in the catalogue, with a clean MWE;
  issue #5 puts it first in the filing order. Not reported to ltx-talk as of 2026-08-27.

## C-DISPMATH-NEWLINE — `\\` after display math is invalid

- **Symptom:** `! There's no line here to end.` at a `\\` or `\\*[Ncm]` that follows a display
  math block (`$…$`, `\[…\]`, `equation`, etc.).
- **Cause:** display math ends in vertical mode; `\\` (a line-break command) is only valid in
  horizontal/paragraph mode.
- **Workaround:** replace `\\[Ncm]` with `\vspace{Ncm}` and bare `\\` with a blank line
  (paragraph break).
- ⚠ **The `--lint` pattern only matches `\\` directly after `$$…$$`/`\]`** — it misses the
  identical failure when the `\\` follows the **closing `}` of an overlay group** whose
  content ends in display math or an image (`\only<n>{$$…$$} \\`, `\uncover<n>{...}\\`): the
  group doesn't change TeX's mode, so the math inside still leaves it in vertical mode, and
  the error is the same "no line here to end" — but now reported after a `}`, not a `$$`, so
  the grep-based lint doesn't fire. Found 11 such instances across 3 decks on a real course,
  none flagged. If you hit this error and the preceding token is `}` rather than math or
  `\]`, look *inside* the group for display math/an image before assuming the lint missed
  nothing.
- **Revisit when:** n/a — this is a fundamental LaTeX constraint.

## C-CALL-NEST — classic `\Call` cannot nest  (bites *after* the C-ALGO engine swap)

- **Symptom:** `! Argument of \equal has an extra }` / `! Paragraph ended before \equal was
  complete`, raised at `\end{frame}`. Nothing in your source mentions `\equal`.
- **Cause:** classic `algpseudocode` defines
  `\Call{#1}{#2}` as `\textproc{#1}\ifthenelse{\equal{#2}{}}{}{(#2)}`. A **nested `\Call`
  inside `#2`** breaks the `\equal` test:
  `\Call{Or-Search}{$p.\Call{Initial-State}{}$}`. `algpseudocodex`'s `\Call` nests fine — so
  this only appears *because* C-ALGO forced you onto the classic engine.
- **Workaround:** drop the emptiness test; always emit parentheses (this is also what
  algpseudocodex renders, e.g. `Initial-State()`):
  ```latex
  \algrenewcommand\Call[2]{\textproc{#1}(#2)}
  ```
- **Revisit when:** n/a.

## C-ALGO-FLOAT — the `algorithm` float is not registered for tagging

- **Symptom:** `! Undefined control sequence … \l__tag_name_float/algorithm_tl`.
- **Cause:** `\begin{algorithm}` (the float from the `algorithm` package) is not known to the
  tagging float module. Bare `algorithmic` — the common case — is unaffected.
- **Workaround:** **remove the float wrapper**, keeping the pseudocode as bare (still tagged)
  `algorithmic` with a bold caption line. Suspending tagging around the float
  (`\AddToHook{env/algorithm/before}{\tag_stop:}`) also compiles, but makes the pseudocode an
  artifact *and* did not clear the error in practice — prefer removal.
- **Revisit when:** the float tagging module learns custom float types.

## C-ALGO-CENTER — `algorithmic` inside `center` loses all its indentation  ⚠ silent, and not ltx-talk's fault

- **Symptom:** the pseudocode compiles cleanly, tags cleanly, and comes out **centred line by
  line**. Every `\State`, `\If` and `\For` indent is gone, so the block reads as a ragged column
  of prose rather than as code. No error, no warning, and `pdftotext` returns the same words in
  the same order, so a text-layer check cannot see it either. **Render the page to catch this.**
- **Cause:** `algorithmic` sets its lines as ordinary paragraph material, and indentation is
  leading horizontal glue. `\begin{center}` applies `\centering` to *each* line, which absorbs
  that glue into the surrounding stretch. This is plain LaTeX behaviour, **not** an ltx-talk
  regression, and it bites under Beamer too. It shows up during conversion only because
  `center`-wrapped algorithms are a common Beamer-deck habit and the conversion is when someone
  finally looks at the rendered page.
- **Workaround:** keep the `center` to place the block horizontally, and restore left alignment
  inside it with a `minipage` plus `flushleft`:
  ```latex
  \begin{center}
    \begin{minipage}[t]{.9\linewidth}
    \begin{flushleft}
    \begin{algorithmic}
      ...
    \end{algorithmic}
    \end{flushleft}
    \end{minipage}
  \end{center}
  ```
  Size the `minipage` so the longest line fits; `.7` to `.9\linewidth` covered every case on this
  course. The construction is class-independent, so it survives an export back to Beamer.
- **Simpler alternative:** drop the `center` entirely. An `algorithmic` block left at the frame
  margin needs no wrapper at all, and most algorithm frames want the full width anyway.
- **Finding them:** grep for a `\begin{algorithmic}` whose enclosing environment stack contains
  `center` but neither `minipage` nor `flushleft`. Whole-line comments must be stripped first, or
  commented-out frames produce false hits.
- **Revisit when:** n/a. This is how `center` works.

## C-NATIVE-ENVS — ltx-talk *already* provides `columns`/`column`/`block`/`frame*`

- **Symptom:** `Command \columns already defined` (or silently worse behaviour) if you paste
  in this skill's own preamble stubs.
- **Cause:** `assets/preamble-template.tex` defines minipage/tcolorbox **stubs** for
  `columns`, `column` and `block`. Under ltx-talk 0.5.1 these are **native**
  (`ltx-talk.cls` lines 1074, 1141, 2134, 997) and the stubs clash.
- **Workaround:** use the native environments; **do not copy those stubs in**. The template's
  stub block is only for a kernel-class setting where they genuinely don't exist.
- **Revisit when:** the template is fixed.
- **Don't over-generalise this to `alertblock`/`exampleblock`** — those are *not* native
  (nothing to clash with), and still need defining. See **C-ALERTBLOCK**.

## C-ALERTBLOCK — `alertblock`/`exampleblock` are NOT native, unlike `block`

- **Symptom:** `LaTeX Error: Environment alertblock undefined` (or `exampleblock`) — or,
  worse, a box that compiles clean but shows a lone `[` as its title with the intended text
  leaking into the body.
- **Cause:** it's easy to over-generalise C-NATIVE-ENVS above: ltx-talk 0.5.3 provides
  `block` natively, but has **no** native `alertblock`/`exampleblock` at all (nothing to
  clash with, nothing to fall back on). A model or contributor who reads "don't paste in the
  block stub, it's native" can reasonably (but wrongly) conclude the same about
  alertblock/exampleblock, find nothing else in the skill telling it what to do with them,
  and improvise. One observed improvisation: preserve beamer's `\begin{alertblock}<2->{Title}`
  call signature with an xparse `d<>m` wrapper that forwards the title into the new
  environment as `[{#2}]` —
  ```latex
  \NewDocumentEnvironment{alertblock}{d<>m}{\begin{ltxalertblock}[{#2}]}{\end{ltxalertblock}}
  ```
  `[...]` is tcolorbox's **key=value options** argument, not a positional slot — passing a
  bare braced title there is a category error. It doesn't raise a compile error; tcolorbox
  just doesn't find a title key, so the title area renders the literal `[` and the actual
  title text spills into the box body as ordinary text.
- **Workaround:** define `alertblock`/`exampleblock` with tcolorbox, called with a plain
  **mandatory** brace argument — same as beamer's own call syntax minus the overlay spec:
  ```latex
  \newtcolorbox{alertblock}[1]{title={#1}, fonttitle=\bfseries,
    colback=red!8!white, colframe=red!70!black, left=4pt, right=4pt, top=2pt, bottom=2pt}
  \newtcolorbox{exampleblock}[1]{title={#1}, fonttitle=\bfseries,
    colback=cadmiumgreen!8!white, colframe=cadmiumgreen, left=4pt, right=4pt, top=2pt, bottom=2pt}
  ```
  (Shipped active in `assets/preamble-template.tex`, outside the disabled C-NATIVE-ENVS
  stub block — only `block`/`columns`/`column` moved inside that `\iffalse`.) If a deck's
  `\begin{alertblock}<2->{Title}` genuinely needs the overlay, don't reinvent the environment
  signature to swallow `<...>` — wrap the whole box instead:
  `\onslide<2->{\begin{alertblock}{Title}...\end{alertblock}}`.
- **Revisit when:** ltx-talk grows native `alertblock`/`exampleblock` (tracked alongside the
  same issues as C-IMMATURE's block/theorem status).

## C-THEOREM — no theorem environments

- **Symptom:** `LaTeX Error: Environment definition undefined` at `\begin{definition}`.
- **Cause:** Beamer's *theme* supplied `definition`/`theorem`/`example`/…; ltx-talk does not,
  and its `\newtheorem` is incomplete (issue #219).
- **Workaround:** build them with **tcolorbox** — not ltx-talk's native `\block` (which
  collides with algorithmicx's csname stack, C-BLOCK-ALGO). `[auto counter]` keeps
  `\label`/`\ref` working:
  ```latex
  \usepackage{tcolorbox}
  \newtcolorbox[auto counter]{definition}[1][]{title=Definition~\thetcbcounter, ...}
  ```

## C-OLDFONT — `\sc`, `\it`, `\bf` … are undefined (and may sit inside maths)

- **Symptom:** `Undefined control sequence` on `\sc`; or, once stubbed naively,
  `LaTeX Error: Command \scshape invalid in math mode`.
- **Cause:** the standard classes still define the obsolete two-letter font commands;
  **ltx-talk does not**. Old decks use them freely — including *inside maths*
  (`$X_i.{\sc Neighbors}$`), where a text-shape switch is illegal.
- **Workaround:** `\ifmmode`-guarded stubs (no-op in maths):
  ```latex
  \providecommand{\sc}{\ifmmode\else\scshape\fi}   % likewise \it \bf \rm \sf \tt \sl
  ```

## C-BACKGROUND — no `\usebackgroundtemplate`  ⚠ every automated check passes while the slide is wrong

- **Symptom:** `Undefined control sequence` at `\usebackgroundtemplate`. The error is the easy
  part. These frames carry white text over a dark image, so a no-op stub gives white text on a
  white page — clean compile, right page count, `Tagged: yes`, matching `pdftotext`. Measured
  on the fixture: stubbed, the background page is **99% white**.
- **Cause:** ltx-talk has no equivalent. It does its own page colour through the kernel's
  `shipout/background` hook (`\__talk_pagecolor:n`), which is the right layer for this.
- **Workaround: define the command in the shared preamble; the decks are not edited at all.**
  Shipped in `assets/preamble-template.tex`:
  ```latex
  \ExplSyntaxOn
  \newcommand{\ltxtalkbgartifact}{\keys_set:nn{tag/graphic}{artifact}}
  \ExplSyntaxOff
  \newcommand{\ltxtalkbgoff}{\RemoveFromHook{shipout/background}[talkbg]}
  \newcommand{\usebackgroundtemplate}[1]{%
    \AddToHook{shipout/background}[talkbg]{%
      \put(0cm,-\paperheight){%
        \begingroup\ltxtalkbgartifact\setkeys{Gin}{height=\paperheight}#1\endgroup}%
    }%
    \aftergroup\ltxtalkbgoff
  }
  ```
  The deck keeps its `{ ... }` group, its `\usebackgroundtemplate` line and its own
  `\includegraphics` call verbatim; Beamer's `\usebackgroundtemplate{}` reset idiom works too.
  When ltx-talk grows a background interface, delete the block and every converted deck is
  already correct. Same shape as C-TOC.
- ⚠ **Do not use an overlay tikz node.**
  ```latex
  \begin{tikzpicture}[remember picture,overlay]     % <- do not do this
    \node at (current page.center) {\includegraphics[width=\paperwidth]{img.pdf}};
  \end{tikzpicture}
  ```
  That is not a background. It is content that draws outside its own bounding box, so it
  paints in document order — over the header, which is where ltx-talk puts the frame title.
  `remember picture` + `current page` also resolves through the `.aux`, so any error that
  stops latexmk converging leaves a misplaced image and body text on white, silently.
- **Measured** (ltx-talk 0.6.0, themed deck with header and footer bars, 60 dpi):

  | recipe | header band still theme colour | frame title | needs a converged build |
  |---|---|---|---|
  | tikz `remember picture` node | **0%** | painted over | **yes**, silently |
  | `shipout/background` hook | 98% | visible | no |
  | ordinary frame (control) | 98% | visible | — |

  Page area covered by the image, against the Beamer original: Beamer 81%, hook 77%, tikz 87%.
  Beamer draws its background under the chrome; the hook matches, the tikz node does not. On
  the fixture, white area per page — Beamer 0 / 0 / 95%, converted 0 / 0 / 96%.
- **Three things the shim adds that the deck's own graphics call does not have.**
  - `artifact`. Without it the background enters the structure tree as a `/Figure` whose
    `/Alt` is the filename, once per shipped page — a two-overlay frame gets two. Fixture: 2
    `/S /Figure` and 2 `/Alt` without it, **0 and 0** with it, renders byte-identical. It is
    set through a macro defined at top level because `\ExplSyntaxOn` does not survive being
    stored in hook code, so `\keys_set:nn` cannot go inline inside `\AddToHook` (10 errors).
  - `height=\paperheight`. Beamer scaled by width and cropped the overflow; under `\put` there
    is no crop, so `width` alone leaves an image wider than the page short — **13% of the page
    white** (21:9 image on a 16:9 page), under white text. A mismatched image is stretched
    rather than cropped, which is the accepted cost.
  - `\aftergroup`. Hook code is global, so without it the background leaks onto every later
    frame. It covers every overlay page of the frame; `\AddToHookNext` would cover only the
    first.
- **Detect before compiling:** `convert_deck.py --lint` reports `C-BACKGROUND` on any
  `\usebackgroundtemplate`, to say the shim must be in the common preamble. It does not
  rewrite the deck, because with the shim there is nothing to rewrite.
- **Revisit when:** ltx-talk gains a background-image interface of its own; the shim block is
  then deleted and nothing else changes.

## C-EDITINSTANCE-EXPAND — template colour keys don't expand macros

- **Symptom:** `LaTeX Error: Unknown color '\ThemeAccent'` — repeated once per frame.
- **Cause:** `\EditInstance{header}{std}{background-color=\ThemeAccent}` — the kernel template
  colour keys want a literal colour **name** and do not expand a macro.
- **Workaround:** write the colour name out. (An *empty* `background-color=` draws no bar at
  all — that is how you get a minimalist, Pittsburgh-like bar-less header.)

---

# A-* — accessibility-checker findings (compile clean, tag clean, still fail)

> These five are a **different class** from everything above. The deck compiles, `pdfinfo`
> says `Tagged: yes`, the log has zero tagpdf errors — and a PDF/UA checker still rejects it.
> `Tagged: yes` means *a tag tree exists*, not that it is correct. The first four were found
> by running a real checker over a course that had passed every gate in this skill.
> **A-TIKZ-ALT is worse:** no checker reported it either, because the affected figures are
> absent from the tag tree rather than wrong within it.
>
> **Do a checker pass before declaring a conversion done** (SKILL.md Step 6b).

---

## A-HEADINGS — every frame title is an orphan `H4`  ⚠ affects every deck

- **Symptom:** the checker reports *"the headings in this PDF do not begin at level one"*,
  usually naming the first content slide.
- **Cause:** `ltx-talk.cls` hard-codes `role/new-tag = frametitle / H4` (v0.5.2, line 192).
  Meanwhile `\section` is `H1`. So the heading tree of a typical deck runs `H4, H1, H4, H4,
  …`: the document opens on an H4 with no H1 above it, and H1→H4 skips two levels. Nothing
  on a title page is a heading at all — `\title` maps to `/Title`, roled to `P`.
- **Workaround:** two changes, both in the shared preamble:
  ```latex
  \tagpdfsetup{role/new-tag = frametitle / H2}   % sits directly under the section H1
  ```
  and make the deck title the document's `H1` — it is plain text inside a frame, not a
  sectioning command, so nothing tags it for you. **Do not reach for a manual struct here:**
  ```latex
  {\Huge\bfseries \tagstructbegin{tag=H1}\tagmcbegin{}#1\tagmcend\tagstructend}   % WRONG
  ```
  This compiles clean, `check-ltx.sh` is green, the `H1` is *present* — and it still fails a
  real PDF/UA-2 checker (veraPDF; Blackboard's simplified checker does not catch it):
  `<Hn> shall not contain <Part>` / `<Hn> shall not contain <P>`. The title-page body is one
  LaTeX paragraph (the `\\`s are line breaks, not `\par`s), and the kernel's *automatic*
  per-paragraph tagger fires on the first character actually typeset — the title's first
  letter, which sits **inside** the manual struct. The automatic tagger doesn't check what's
  already open; it wraps its own `Part → P` as a child of whatever struct is current, landing
  it inside the hand-written `H1`. Same trap family as C-CENTER-ARG: a declaration with
  paragraph-scale side effects, colliding with something written locally. Reaching for
  `\tagpdfsetup{para/tagging=false}` to suppress the automatic tagger makes it **worse** —
  that key is meant to be set once at `\begin{document}` (`documentmetadata-support.ltx:357`),
  and toggling it mid-paragraph desyncs the kernel's own begin/end counters (12 new tagpdf
  errors on a course this was tried on, dwarfing the original 2-clause failure).

  **Correct fix — let the automatic tagger do the job instead of fighting it:**
  ```latex
  \begingroup
    \tagpdfsetup{para/tag=H1,para/flattened}%
    {\Huge\bfseries #1\par}%
  \endgroup
  ```
  Force the title onto its own real paragraph (`\par`, not `\\`), then point the kernel's own
  per-paragraph machinery at it with the two keys built for exactly this (`latex.ltx`,
  `\NewTaggingSocketPlug{para/semantic/begin}`/`{para/textblock/begin}`): `para/tag` sets what
  tag the automatic tagger uses instead of its default `P`; `para/flattened` skips the outer
  `Part` wrapper it would otherwise add. One clean `H1`, produced by the mechanism that was
  always going to fire — no manual struct, nothing to keep balanced by hand. Verified on a
  20-deck course: title page renders pixel-identical, page counts unchanged, `check-ltx.sh`
  green, and the `Hn-Part`/`Hn-P` veraPDF failures are gone.
- **Check:** `grep -aoE '/S\s*/H[0-9]' qdf.pdf | sort | uniq -c` — there must be ≥1 `H1`, and
  `frametitle` must role to exactly one level below the section. That check alone is not
  enough to catch this specific trap — run `verapdf -f ua2 deck.pdf` (PDF/UA-2; Blackboard's
  checker does not catch it) to confirm the `H1` doesn't contain `Part`/`P`.
- **Revisit when:** ltx-talk makes the frametitle level configurable, or roles it relative to
  the sectioning depth actually in use.

---

## A-MATHALT — a checker calls maths "an undescribed image"; do NOT add `/Alt`  ⚠ the obvious fix is harmful

- **Symptom:** the checker lists *"images without a description"* and points at slides whose
  only "images" are `$x^2$`, `$\approx$`, a display. Every `\includegraphics` already has
  `alt=`.
- **Cause: the checker, not the PDF.** Each maths group becomes a `/S /Formula`. PDF/UA-**1**
  wants `/Alt` on it; PDF/UA-**2** also accepts **MathML**, which is what LaTeX emits. A
  validator reporting this against a ua-2 document is applying a ua-1 rule.
- ⚠ **Do NOT set `\tagpdfsetup{math/alt/use}`.** It is valid — ua-2 permits `/Alt` on a
  `Formula` — but a screen reader that finds `/Alt` reads that string instead of parsing the
  MathML with MathCat, so a navigable formula becomes
  `"LaTeX formula starts \begin {math} A \end {math} LaTeX formula ends"`. Both routes pass a
  validator; only one is usable. `latex-lab` auto-enables the switch for `ua-1` and leaves it
  off for `ua-2` (`latex-lab-math.ltx`, the `begindocument/end` hook), which is correct.
- **Measured (ltx-talk 0.6.0, TeX Live 2026)** — one frame, `\[ f(x)=\sum_{i=1}^{n}a_ix^i \]`,
  three passes, `qpdf --qdf` then grep:

  | | `<math>` | `/Alt` | `/AF` |
  |---|---|---|---|
  | default (correct) | 1 | 0 | 6 |
  | `math/alt/use` | 1 | **1** | 6 |

  The switch does not remove the MathML; both files contain it. The harm is in consumption.
- **The shadowing claim is upstream's, not ours.** MathML taking precedence over `/Alt` is the
  published position of the PDF Association's *Best Practice Guide: Math in PDF* (v1.0,
  written by the LaTeX Project Liaison Working Group), and LaTeX Project members test the
  combination with NVDA + MathCat; confirmed by ltx-talk on PR #21 and issue #17. Not
  reproduced here: screen-reader support for maths is Windows-only at present. The
  measurements above are ours and stand on their own.
- ⚠ **MathML is LuaTeX-only.** Under XeTeX and pdfTeX there is no MathML and, with this switch
  correctly off, no `/Alt` either — the `Formula` elements are empty and the maths has **no
  accessible representation at all**. That makes LuaLaTeX a hard requirement, not a
  preference. See **C-PDFTEX-MATH**.
- **What to do:** nothing in the source. Verify the MathML is present and validate against
  ua-2 rather than ua-1.
- **Check:** `grep -c 'Alternative text for graphic is missing' deck.log` covers graphics only
  and catches nothing here. Look for `<math` in `qpdf --qdf` output instead.
- **Revisit when:** validators catch up to PDF/UA-2. The document is already right.

---

## A-TABLE-TH — every `tabular` is a data table with no header cells

- **Symptom:** *"this PDF contains tables that are missing headers"*, one report per `tabular`,
  including the ones that are not tables.
- **Cause:** `latex-lab` tags every `tabular` as `Table`/`TR`/`TD` and never guesses which row
  or column is the header. Decks make this worse than papers do, because `tabular` is routinely
  used for layout: a 2×2 quadrant of prose, a key/value list, a row of images.
- **Workaround:** classify each table, then declare it. The test: *does a cell still make sense
  read aloud on its own, with no column name attached?*
  - **No → data table.** Declare the headers immediately before `\begin{tabular}`:
    ```latex
    \tagpdfsetup{table/header-rows={1}}                              % header row
    \tagpdfsetup{table/header-rows={1,2},table/header-columns={1,2}} % both axes
    ```
    Multi-level headers work and the label column need not be column 1
    (`header-columns={4}` is fine). `\multicolumn`/`\multirow` spans are honoured: the emitted
    `/TH` carry correct `/TH-col`, `/TH-row`, `/TH-both` and `colspan-N`.
  - **Yes → layout grid.** Do not invent a header row. Demote it out of the tree:
    ```latex
    \tagpdfsetup{table/tagging=div}
    ```
    which retags `Table`→`Div`, `TR`→`NonStruct`, `TD`→ a text block; the cells are then read
    in visual order. (`table/tagging=presentation` keeps `Table`/`TR`/`TD` plus an ARIA
    presentation attribute — weaker, and some checkers still complain. Prefer `div`.)
- ⚠ **These settings leak; every declaration must state all three keys.** Nothing resets them
  at `\end{tabular}`. `table/tagging=div` swaps the tag names and nothing swaps them back, so
  one layout table demotes every later table in the same group. `table/tagging=true` restores
  the names but does not clear the header lists, so the previous table's `header-rows={1,2}`
  leaks into the next. Write every data table order-independently:
  ```latex
  \tagpdfsetup{table/tagging=true,table/header-rows={1},table/header-columns={}}
  ```
  (`div` clears both lists itself.) Getting this wrong cost 7 mis-tagged tables across two
  decks, and the build stays green: clean compile, `Tagged: yes`, 0 tagpdf errors. Only
  counting structure elements catches it.
- ⚠ **A `tabular` inside a `frame*` is not tagged at all** — no `Table`, no `TD`, no `TH`, and
  `\tagpdfsetup` there is inert. The `frame*` hooks (C-FRAMESTAR-TAG) wrap the environment in
  `\tag_stop:`, so everything on a listing slide is invisible to a screen reader, tables
  included. This is the known cost of C-FRAMESTAR-TAG, not a table bug. Either leave the
  declaration in place, with a comment saying it becomes correct when `frame*` tagging is
  fixed, or move the table out of the `frame*`.
- **Scale:** on a 20-deck course, 47 live tabulars — 9 layout, 35 taggable data tables, 3
  stranded inside `frame*` — and **18 of the data ones needed both axes** (payoff matrices,
  joint probability tables, quiz grids). A "first row is bold" heuristic classified most of
  those 18 wrongly; the header rows that matter most are often not bold, so render the slide
  and look. A plain `grep -c 'begin{tabular}'` also overcounts badly — 36 of 83 hits on that
  course were inside commented-out slides. Strip comments before auditing.
- **Check — build an oracle before you apply.** From the audit, write down the expected number
  of data tables per deck; after the build, count what is in the PDF and compare. Nothing else
  catches the leak above.
  ```sh
  qpdf --qdf --object-streams=disable deck.pdf qdf.pdf
  grep -acE '/S /Table' qdf.pdf ; grep -acE '/S /TH' qdf.pdf
  ```
  ⚠ When globbing for the PDF, exclude handouts: `deck-handout.pdf` sorts before `deck.pdf`
  (`-` < `.`), so `ls week*/deck-*.pdf | head -1` hands you a stale handout and a confidently
  wrong answer.

---

## A-CONTRAST — the emphasis palette fails WCAG AA

- **Symptom:** *"this PDF contains text with insufficient contrast"*, naming slides with
  coloured emphasis.
- **Cause:** the saturated colours decks inherit from Beamer habits look fine on a projector
  and fail the 4.5:1 body-text threshold on white. Measured, against white:
  `red` 4.00, `teal!80` 3.41, `orange` 2.53, `green` 2.15, `dkgreen` 3.78 — all fail.
- **Workaround:** darken, keeping the hue. 5-7:1 leaves headroom and stays distinguishable:
  ```latex
  \definecolor{aired}{rgb}{0.75,0,0}          % 6.52  (was red,     4.00)
  \definecolor{aiteal}{rgb}{0.05,0.40,0.40}   % 6.75  (was teal!80, 3.41)
  \definecolor{aiorange}{rgb}{0.68,0.33,0}    % 5.17  (was orange,  2.53)
  \definecolor{aigreen}{rgb}{0,0.50,0}        % 5.17  (was dkgreen, 3.78)
  ```
- **Do not stop at the `\textred`-style macros.** Decks also write `{\color{red}…}` inline —
  on the course above, 46 times, bypassing every macro. If (and only if) no figure or tikz
  picture uses the colour *graphically*, redefining the standard name once in the preamble
  fixes every site at a stroke:
  ```latex
  \definecolor{red}{rgb}{0.75,0,0}
  ```
  Check that precondition first:
  `grep -hoE '(draw|fill|text|color)\s*=\s*red[^,;}]*|red![0-9]+' week*/*.tex`
- **Check:** render at **≥200 dpi** and measure the actual ink. Anti-aliasing at 70-90 dpi
  invents intermediate colours and buries the real ones in the histogram.
  ```python
  def lum(c):
      f = lambda v: v/12.92 if v <= 0.03928 else ((v+0.055)/1.055)**2.4
      r, g, b = [x/255 for x in c[:3]]
      return 0.2126*f(r) + 0.7152*f(g) + 0.0722*f(b)
  contrast_vs_white = 1.05 / (lum(rgb) + 0.05)      # want >= 4.5
  ```
- **False positive to expect:** a `\fcolorbox{black}{white}{…}` may be reported as a contrast
  failure although every pixel in it measures ≥11:1 — the checker appears to compare the
  box's white *fill* against the white page. Measure before you chase it.

---

## A-TIKZ-ALT — figures that are not `\includegraphics` are silently untagged  ⚠ invisible to every alt-text tool

- **Symptom:** none. No warning, no checker complaint naming the figure, and it never appears
  in an alt-text audit, because every alt tool in this skill matches `\includegraphics`. A
  screen reader encounters nothing where the diagram is.
- **Affects:** `tikzpicture`, `pgfplots` `axis`, and `\input{…}` of a generated figure (xfig
  `.pdf_t`, `.pspdftex`, `.pgf`). On one 20-deck course, 23 figures across 5 decks that no
  gate could see, against zero missing `alt=` on `\includegraphics`.
- **Worse than a missing `alt=`.** tagpdf warns for a bare `\includegraphics` and then
  falsely satisfies validators by using the filename as `/Alt` (see `alt-text.md`). A
  `tikzpicture` produces no warning and no `/Alt`, so there is nothing to grep for in the log
  and nothing to find in the PDF.
- **Inputted figures are the nastiest case.** An xfig `.pdf_t` is an `\includegraphics`
  wrapped in a `picture` overlay, in a separate file. A linter grepping deck sources never
  sees it, so the figure is absent from the alt-text debt rather than listed as missing.
- **`tikzpicture` and `pgfplots` need no wrapper.** `latex-lab` provides an `alt` key on the
  environment:
  ```latex
  \begin{tikzpicture}[alt=A square joined to a circle by an arrow.]
  ```
  This sets the `graphic/begin` socket to the `alt` plug
  (`latex-lab-testphase-graphic.sty`); the default plug is `text`, which tags node content as
  marked content and produces no description. Verified on ltx-talk 0.6.0: `/S /Figure` with
  the exact `/Alt`, 0 errors.
- **Inputted figures take the same key at the call site**, which the `\includegraphics` inside
  the generated file picks up:
  ```latex
  \ExplSyntaxOn
  \NewDocumentCommand{\altinput}{ m m }
    { \group_begin: \keys_set:nn { tag / graphic } { alt = {#1} } \input{#2} \group_end: }
  \ExplSyntaxOff
  ```
  ```latex
  \altinput{A generated diagram showing a labelled box.}{fig.pdf_t}
  ```
  Do **not** add `alt=` inside the `.pdf_t` — xfig regenerates it.
- **Decks that already use an `altfigure` wrapper: change the definition, not the call sites.**
  The environment groups, so `\end{altfigure}` scopes the key:
  ```latex
  \ExplSyntaxOn
  \NewDocumentEnvironment{altfigure}{ m }
    { \keys_set:nn { tag / graphic } { alt = {#1} } }
    { }
  \ExplSyntaxOff
  ```
  Byte-identical to `\altinput` on the same figure: 4 `/Figure`, 2 `/Alt`, no junk. One edit
  in the shared preamble fixes every `\begin{altfigure}` in a course. Remove the wrapper from
  `tikzpicture`/`pgfplots` call sites — those take the key directly.
- ⚠ **Do not hand-roll tag structure.** Where `latex-lab` already tags a construct, configure
  it through its keys. `\tagstructbegin{tag=Figure,alt={…}}` builds a `Figure` around content
  that already has one, and the inner `picture` environments then claim a placeholder `/Alt`
  of `"picture environment"`. The same mistake on the title page is marked WRONG in
  **A-HEADINGS**.
- **Beamer side:** `\altinput` is ltx-talk-only; give the Beamer preamble
  `\newcommand{\altinput}[2]{\input{#2}}`. Beamer ignores the `alt` key on `tikzpicture`
  harmlessly.
- **Check:** `alt_text_audit.py` reports these as `untagged_figure`. They cannot be auto-fixed
  the way an optional argument can, so they belong on the manual worklist.

---

## Quick error → cause map

⚠ **The worst failures here produce no error at the offending line.** Run
`convert_deck.py --lint` before every build; it greps for all of the silent ones.

**Silent — compiles clean, page count right, `Tagged: yes`.**

| Silent failure | Symptom | Caught by | Entry |
|---|---|---|---|
| Nested-brace frame title left unconverted | frame has no title; text lands in the body | `--lint` | C-FRAMETITLE-NESTED |
| `\onslide<n>{…}` (braced) | blanks everything after it to end of frame on early overlays | `--lint` | C-ONSLIDE-ARG |
| `\State<2>` as an overlay spec | overlay never fires; literal `<2>` printed on the slide | `--lint` | C-OVERLAY-ALGO |
| `\center{…}` as a command | tag tree corrupts; error lands far away, or in another frame | `--lint` | C-CENTER-ARG |
| `\framesubtitle{…}` | text never typeset | `--lint` | C-FRAMESUBTITLE |
| `$$…$$` display math | every `\item` after it loses its list indent | `--lint` | C-DISPLAY-DOLLAR |
| bare `[b]`/`[t]`/`[c]` frame option | discarded whole; aligned frames render centred | `--lint` | C-FRAME-OPT |
| `pdfstandard=` without `ua-2` | PDF declares no PDF/UA conformance | `--lint` | C-NO-UA2 |
| `\includegraphics` without `alt=` | screen reader reads out the filename | log warning | `alt-text.md` |
| frame titles roled `H4` by the class | "headings do not begin at level one" | PDF/UA checker | A-HEADINGS |
| every `tabular` is a `Table` with no `TH` | "tables missing headers", including layout grids | PDF/UA checker | A-TABLE-TH |
| saturated emphasis colours | "text with insufficient contrast" | PDF/UA checker | A-CONTRAST |
| `tikzpicture` / `\input{…pdf_t}` figures | absent from the reading order | **nothing** | A-TIKZ-ALT |
| `algorithmic` wrapped in `center` | pseudocode centred line by line, all indentation lost | **nothing** | C-ALGO-CENTER |

Two cautions on that table. **A-MATHALT is not in it**: a ua-1 checker reports maths as
"images without a description", but the file is correct and the fix is harmful — read the
entry before acting on that report. And `pdftotext` cannot see four of these: hidden overlay
content stays in the PDF text layer, and centred pseudocode keeps its word order. **Render the
page** (`pdftoppm -f N -l N -png`) to judge an overlay or an algorithm.

**Loud — the error text names the cause, once you know the mapping.**

| Error text | Cause | Entry |
|---|---|---|
| `Improper \halign inside $$'s` | algpseudocodex algorithm | C-ALGO |
| `You can't use \halign in math mode` | multi-line `\State{…\\…}` (algpseudocodex) | C-ALGO |
| `tagpdf Error: no open structure on the stack` at `\end{frame*}` | `frame*` + `listings` under tagging | C-FRAMESTAR-TAG |
| `Argument of \equal has an extra }` | nested `\Call` (classic algpseudocode) | C-CALL-NEST |
| `Undefined control sequence \l__tag_name_float/algorithm_tl` | `algorithm` float | C-ALGO-FLOAT |
| `Environment definition undefined` at `\begin{definition}` | no theorem envs | C-THEOREM |
| Many `Undefined control sequence` (`\institute`, `\hypersetup`) + `\normalsize not defined` + `frame* undefined`; stub 2–8pp PDF | `\DocumentMetadata` never set | C-NO-DOCMETA |
| `Paragraph ended before \lst@next was complete` | verbatim in a plain frame, not `frame*` | C-VERBATIM |
| `Undefined control sequence \sc` / `\scshape invalid in math mode` | obsolete font commands | C-OLDFONT |
| `Undefined control sequence \usebackgroundtemplate` | no background templates | C-BACKGROUND |
| `Unknown color '\ThemeAccent'` (once per frame) | template key won't expand a macro | C-EDITINSTANCE-EXPAND |
| `Command \columns already defined` | pasted the template's stubs; they are native | C-NATIVE-ENVS |
| `Improper \halign inside $'s` | overlay around `&`/`\\` in `tabular`/`align*` | C-OVERLAY-ALIGN |
| `Misplaced alignment tab character &` | overlay around `&` in `tabular` | C-OVERLAY-ALIGN |
| `Extra alignment tab has been changed to \cr` | stacked `\only<N>{row}` table with no `\\` | C-OVERLAY-MULTIPASS |
| `Missing \endcsname` / `Extra \endcsname` at `\end{frame}` | `\begin{block}` + algorithmic | C-BLOCK-ALGO |
| `Missing \endcsname` / `Extra \endcsname` at `\end{frame}` | `\onslide{\State…}` in algorithmic | C-OVERLAY-ALGO |
| `There's no line here to end` | `\\` after display math | C-DISPMATH-NEWLINE |
| `tagpdf Error: … begin/end … differ` / `Sect can not be closed` | `\tableofcontents` | C-TOC |
| `tagpdf Error: … begin/end text-unit para hooks differ` (innocent-looking line) | `\center{…}` as a command | C-CENTER-ARG |
| `Misplaced \crcr` in `\tbl_crcr:n` + `Missing }` (~100 errors, none at the title page) | `\and` outside `\author` | C-AND-TITLE |
| `Not allowed in LR mode` at `\maketitle` | `frame-title-arg` option set | C-MAKETITLE |
| frame title appears as body text | braced title, no `\frametitle` | C-FRAMETITLE |
| `not compatible with \DocumentMetadata` | class still `beamer` | switch the class |
| `Undefined control sequence \setbeamer…` | Beamer styling command | C-NOBEAMER |

