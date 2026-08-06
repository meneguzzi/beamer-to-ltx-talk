# Beamer → ltx-talk: compromises & incompatibilities

Catalogue of problems found converting a real course to **ltx-talk v0.5.0** (released
2026-04-30; dev branch needs LaTeX kernel 2026-06-01). Each entry: **symptom → cause →
workaround → revisit when**. Most only appear under tagging (`\DocumentMetadata`), which is
why they are absent from the upstream quick-start docs.

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
  `\DocumentMetadata{…}`) as the very first line, before `\documentclass`. On the CS3033
  course this single-line change took three "totally broken" decks straight to
  `Tagged: yes`, page counts matching baseline.
- **Detect before compiling:** `convert_deck.py` warns (`C-NO-DOCMETA`) during both `--lint`
  and conversion when no `\DocumentMetadata` is reachable before `\documentclass`.
- **Revisit when:** ltx-talk starts erroring clearly on a missing `\DocumentMetadata` instead
  of half-loading.

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

## C-OVERLAY-ALIGN — overlay tokens inside `tabular`/`align*` break alignment

- **Symptom:** `! Misplaced alignment tab character &` or `! Improper \halign inside $'s` when
  an overlay command (`\onslide`, `\visible`, `\only`) wraps an entire row including `&` or
  `\\`: e.g. `\onslide<2>{& = formula \\}` or `\onslide<+->{cell1 & cell2 \\}`.
- **Cause:** `&` and `\\` must be at the **top level** of a `tabular`/`align*` environment
  (they are active inside the `\halign`). Wrapping them in a group (even a non-expanded one)
  removes them from that top level and TeX errors out.
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
  frames that use `\begin{algorithmic}` AND wrap `\State` in an overlay command:
  `\onslide<2>{\State formula}`. In practice this only bites when the wrapped `\State` sits
  **nested inside** `\If`/`\ForAll`/`\Loop`; a top-level `\only<1>{\State …}` is harmless,
  and an overlay inside a `\Function` *name* is fine.
- **Cause:** algorithmicx tracks nesting depth with `\csname`-based counters
  (`\ALG@b@N@EndFor`, `\ALG@currentblock`). Wrapping `\State` in a group (`\onslide{…}`)
  scopes the push but not the pop of those counters, leaving them permanently mismatched.
  `\end{frame}` then sees unbalanced `\endcsname` pairs.
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
  every "builds clean" report. The mechanical fix is
  `\onslide<spec>{` → `\uncover<spec>{` (skip commented-out lines); page counts should be
  **unchanged** afterwards, which is a good invariant to assert.
- **Revisit when:** ltx-talk gives `\onslide` a `+m` argument form for Beamer compatibility.
  Track against `\NewDocumentCommand \onslide` in `ltx-talk.cls`.

## C-DISPMATH-NEWLINE — `\\` after display math is invalid

- **Symptom:** `! There's no line here to end.` at a `\\` or `\\*[Ncm]` that follows a display
  math block (`$…$`, `\[…\]`, `equation`, etc.).
- **Cause:** display math ends in vertical mode; `\\` (a line-break command) is only valid in
  horizontal/paragraph mode.
- **Workaround:** replace `\\[Ncm]` with `\vspace{Ncm}` and bare `\\` with a blank line
  (paragraph break).
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

## C-NATIVE-ENVS — ltx-talk *already* provides `columns`/`column`/`block`/`frame*`

- **Symptom:** `Command \columns already defined` (or silently worse behaviour) if you paste
  in this skill's own preamble stubs.
- **Cause:** `assets/preamble-template.tex` defines minipage/tcolorbox **stubs** for
  `columns`, `column` and `block`. Under ltx-talk 0.5.1 these are **native**
  (`ltx-talk.cls` lines 1074, 1141, 2134, 997) and the stubs clash.
- **Workaround:** use the native environments; **do not copy those stubs in**. The template's
  stub block is only for a kernel-class setting where they genuinely don't exist.
- **Revisit when:** the template is fixed.

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

## C-BACKGROUND — no `\usebackgroundtemplate`

- **Symptom:** `Undefined control sequence` at `\usebackgroundtemplate`.
- **Cause:** ltx-talk has no equivalent.
- **Workaround:** an overlay tikz node. ⚠ **A no-op stub is dangerous**: these frames
  typically carry *white text over a dark image*, so silently dropping the background makes
  the text invisible rather than merely unstyled.
  ```latex
  \begin{tikzpicture}[remember picture,overlay]
    \node at (current page.center) {\includegraphics[width=\paperwidth]{img.pdf}};
  \end{tikzpicture}
  ```

## C-EDITINSTANCE-EXPAND — template colour keys don't expand macros

- **Symptom:** `LaTeX Error: Unknown color '\ThemeAccent'` — repeated once per frame.
- **Cause:** `\EditInstance{header}{std}{background-color=\ThemeAccent}` — the kernel template
  colour keys want a literal colour **name** and do not expand a macro.
- **Workaround:** write the colour name out. (An *empty* `background-color=` draws no bar at
  all — that is how you get a minimalist, Pittsburgh-like bar-less header.)

---

# A-* — accessibility-checker findings (compile clean, tag clean, still fail)

> These four are a **different class** from everything above. The deck compiles, `pdfinfo`
> says `Tagged: yes`, the log has zero tagpdf errors — and a PDF/UA checker still rejects it.
> `Tagged: yes` means *a tag tree exists*, not that it is correct. Found by running a real
> checker over a course that had passed every gate in this skill.
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
  and make the deck title the document's `H1` by hand — it is plain text inside a frame, not
  a sectioning command, so nothing tags it for you:
  ```latex
  {\Huge\bfseries \tagstructbegin{tag=H1}\tagmcbegin{}#1\tagmcend\tagstructend}
  ```
  Verified on a 20-deck course: no visual change, page counts unchanged, 0 tagpdf errors.
- **Check:** `grep -aoE '/S\s*/H[0-9]' qdf.pdf | sort | uniq -c` — there must be ≥1 `H1`, and
  `frametitle` must role to exactly one level below the section.
- **Revisit when:** ltx-talk makes the frametitle level configurable, or roles it relative to
  the sectioning depth actually in use.

---

## A-MATHALT — inline maths is reported as an undescribed image

- **Symptom:** the checker lists *"images without a description"* and points at slides whose
  only "images" are `$x^2$`, `$\approx$`, a `$$…$$`. Confusing, because every
  `\includegraphics` already has `alt=`.
- **Cause:** each maths group becomes a `/S /Formula` element, and PDF/UA wants `/Alt` on it.
  `latex-lab` will supply one from the TeX source, but the switch is off by default:
  `math/alt/use` is auto-enabled for `pdfstandard=ua-1` **only**, and stays off for `ua-2`
  (`latex-lab-math.ltx`, the `begindocument/end` hook).
- **Workaround:** `\tagpdfsetup{math/alt/use}` in the shared preamble. Every `Formula` then
  carries an `/Alt` derived from the source ("LaTeX formula starts \begin {math} A \end
  {math} LaTeX formula ends"). Verbose, but valid, and it costs one line.
- **Caveat:** this is a *floor*, not good alt text. For a deck built around a handful of
  important equations, write real descriptions; the auto text is right for the long tail
  of stray `$n$`s.
- **Check:** `grep -c 'Alternative text for graphic is missing' deck.log` covers **graphics
  only** and will not catch this. Look for `/Alt` on `/S /Formula` in the PDF instead.

---

## A-TABLE-TH — every `tabular` is a data table with no header cells

- **Symptom:** *"this PDF contains tables that are missing headers"*, one report per
  `tabular` in the deck — including the ones that are not tables at all.
- **Cause:** `latex-lab` tags every `tabular` as `Table`/`TR`/`TD` and never guesses which
  row or column is the header. Slide decks make this worse than papers do, because `tabular`
  is routinely used for pure *layout*: a 2×2 quadrant of prose, a key/value list, a row of
  images.
- **Workaround:** classify each table, then declare it. The test is
  **"does a cell still make sense read aloud on its own, with no column name attached?"**
  - *No* → data table. Declare the headers **immediately before** `\begin{tabular}`:
    ```latex
    \tagpdfsetup{table/header-rows={1}}                              % header row
    \tagpdfsetup{table/header-rows={1,2},table/header-columns={1,2}} % both axes
    ```
    Multi-level headers work, and the label column need not be column 1
    (`header-columns={4}` is fine). `\multicolumn`/`\multirow` spans are honoured: the
    emitted `/TH` carry correct `/TH-col`, `/TH-row`, `/TH-both` and `colspan-N`.
  - *Yes* → layout grid. **Do not invent a header row.** Demote it out of the tree:
    ```latex
    \tagpdfsetup{table/tagging=div}
    ```
    which retags `Table`→`Div`, `TR`→`NonStruct`, `TD`→ a text block. The grid leaves the
    semantic tree entirely and the cells are simply read in visual order.
    (`table/tagging=presentation` keeps `Table`/`TR`/`TD` plus an ARIA presentation
    attribute — weaker, and some checkers still complain. Prefer `div`.)
- ⚠ **Every declaration must state all three keys — these settings leak.** Nothing resets
  them at `\end{tabular}`:
  - `table/tagging=div` swaps the tag names and **nothing swaps them back**. The
    `header-rows`/`header-columns` keys do *not* restore them, so one layout table silently
    demotes every later table in the same group to `Div`.
  - `table/tagging=true` restores the names but does **not** clear the header lists, so the
    previous table's `header-rows={1,2}` leaks into the next one.

  So write every data table as order-independent, with empty lists where not wanted:
  ```latex
  \tagpdfsetup{table/tagging=true,table/header-rows={1},table/header-columns={}}
  ```
  (`div` clears both lists itself, so it needs no extra keys.) Getting this wrong cost 7
  mis-tagged tables across two decks on the course above, and **the build stays green**:
  clean compile, `Tagged: yes`, 0 tagpdf errors. Only counting the structure elements
  catches it.
- ⚠ **A `tabular` inside a `frame*` is not tagged at all** — no `Table`, no `TD`, no `TH`,
  and your `\tagpdfsetup` there is inert. The `frame*` tagging hooks (C-FRAMESTAR-TAG) wrap
  the whole environment in `\tag_stop:`, so *everything* on a listing slide is invisible to a
  screen reader, tables included. Don't chase it as a table bug; it is the known cost of
  C-FRAMESTAR-TAG. Either leave the declaration in place (it becomes correct the moment
  `frame*` tagging is fixed — say so in the comment) or move the table out of the `frame*`.
- **Scale, and a warning:** on a 20-deck course, 47 live tabulars — 9 layout, 35 taggable
  data tables, 3 stranded inside `frame*` — and **18 of the data ones needed *both* axes**
  (payoff matrices, joint probability tables, quiz grids). A "first row is bold" heuristic
  classified most of those 18 wrongly. Render the slide and look at it; the header rows that
  matter most are often not bold.
  Also: a plain `grep -c 'begin{tabular}'` badly overcounts — on that course 36 of 83 hits
  were inside commented-out slides. Strip comments before auditing.
- **Check — build an oracle *before* you apply.** From the audit, write down the expected
  number of data tables per deck; after the build, count what is actually in the PDF and
  compare. Nothing else catches the leak above.
  ```sh
  qpdf --qdf --object-streams=disable deck.pdf qdf.pdf
  grep -acE '/S /Table' qdf.pdf ; grep -acE '/S /TH' qdf.pdf
  ```
  ⚠ When globbing for the PDF, **exclude handouts**: `deck-handout.pdf` sorts *before*
  `deck.pdf` (`-` < `.`), so `ls week*/deck-*.pdf | head -1` hands you a stale handout and a
  confidently wrong answer. This is the "measure against a build that actually ran" trap
  wearing a different hat.

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

## Quick error → cause map

> ⚠ **The worst failures in this catalogue produce NO error at the offending line.**
> Run **`convert_deck.py --lint`** before every build — it greps for all of these:
> | Silent failure | Symptom | Entry |
> |---|---|---|
> | Nested-brace frame title left unconverted | frame has **no title**; text lands in the body | C-FRAMETITLE-NESTED |
> | `\onslide<n>{…}` (braced) | blanks **everything after it to end of frame** on early overlays | C-ONSLIDE-ARG |
> | `\State<2>` used as an overlay spec | overlay never fires; literal **`<2>` printed on the slide** | C-OVERLAY-ALGO |
> | `\center{…}` used as a command | tag tree corrupts; error lands **far away**, or in another frame | C-CENTER-ARG |
> | `\includegraphics` without `alt=` | screen reader reads out **the filename** | see `alt-text.md` |
>
> And four more that survive *every* check in this skill — clean compile, `Tagged: yes`,
> 0 tagpdf errors — and are only caught by an actual PDF/UA checker:
> | Silent failure | Symptom | Entry |
> |---|---|---|
> | frame titles roled `H4` by the class | "headings do not begin at level one" | A-HEADINGS |
> | `Formula` elements with no `/Alt` | "images without a description", pointing at maths | A-MATHALT |
> | every `tabular` is a `Table` with no `TH` | "tables missing headers", including layout grids | A-TABLE-TH |
> | saturated emphasis colours | "text with insufficient contrast" | A-CONTRAST |
>
> Three of these are invisible to `pdftotext` as well as to the compiler: hidden overlay
> content stays in the PDF text layer. **Render the page** (`pdftoppm -f N -l N -png`) to
> judge an overlay.

| Error text | Cause | Entry |
|---|---|---|
| `Improper \halign inside $$'s` | algpseudocodex algorithm | C-ALGO |
| `tagpdf Error: no open structure on the stack` at `\end{frame*}` | `frame*` + `listings` under tagging | C-FRAMESTAR-TAG |
| `Argument of \equal has an extra }` | nested `\Call` (classic algpseudocode) | C-CALL-NEST |
| `Undefined control sequence \l__tag_name_float/algorithm_tl` | `algorithm` **float** | C-ALGO-FLOAT |
| `Environment definition undefined` at `\begin{definition}` | no theorem envs | C-THEOREM |
| Many `Undefined control sequence` (`\institute`, `\hypersetup`) + `\normalsize not defined` + `frame* undefined`; stub 2–8pp PDF | `\DocumentMetadata` never set (commented-out input) | C-NO-DOCMETA |
| `Paragraph ended before \lst@next was complete` | `lstlisting` in a plain frame (verbatim frame not `frame*`, e.g. empty-title one missed) | C-VERBATIM |
| `Undefined control sequence \sc` / `\scshape invalid in math mode` | obsolete font commands | C-OLDFONT |
| `Undefined control sequence \usebackgroundtemplate` | no background templates | C-BACKGROUND |
| `Unknown color '\ThemeAccent'` (once per frame) | template key won't expand a macro | C-EDITINSTANCE-EXPAND |
| `Command \columns already defined` | pasted the template's stubs; they're native | C-NATIVE-ENVS |
| `Improper \halign inside $'s` | overlay around `&`/`\\` in `tabular`/`align*` | C-OVERLAY-ALIGN |
| `Misplaced alignment tab character &` | overlay around `&` in `tabular` | C-OVERLAY-ALIGN |
| `You can't use \halign in math mode` | multi-line `\State{…\\…}` (algpseudocodex) | C-ALGO |
| `Missing \endcsname` / `Extra \endcsname` at `\end{frame}` | `\begin{block}`+algorithmic | C-BLOCK-ALGO |
| `Missing \endcsname` / `Extra \endcsname` at `\end{frame}` | `\onslide{\State…}` in algorithmic | C-OVERLAY-ALGO |
| `There's no line here to end` | `\\` after display math | C-DISPMATH-NEWLINE |
| `tagpdf Error: … begin/end … differ` / `Sect can not be closed` | `\tableofcontents` | C-TOC |
| `tagpdf Error: … begin/end text-unit para hooks differ` (line looks innocent) | `\center{…}` as a command | C-CENTER-ARG |
| `Misplaced \crcr` in `\tbl_crcr:n` + `Missing }` (~100 errors, none at the title page) | `\and` typeset outside `\author` | C-AND-TITLE |
| `Not allowed in LR mode` at `\maketitle` | `frame-title-arg` option set | C-MAKETITLE |
| frame title appears as body text | braced title, no `\frametitle` | C-FRAMETITLE |
| `not compatible with \DocumentMetadata` | class still `beamer` | switch class |
| `Paragraph ended before \lst@next…` | verbatim in normal frame | C-VERBATIM |
| `Undefined control sequence \setbeamer…` | Beamer styling command | C-NOBEAMER |
