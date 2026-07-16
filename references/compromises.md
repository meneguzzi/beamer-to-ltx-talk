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
- **Trade-off:** the code/verbatim slide becomes an **artifact** — it is not in the
  screen-reader reading order. If the code matters pedagogically, put an explanatory tagged
  line *outside* the `frame*`.
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
  \onslide<+->{cell1} & \onslide<.->{cell2} & \onslide<.->{cell3} \\
  % align* — wrap the formula, not the alignment token
  & \onslide<4->{= \frac{1}{n}(R_n + (n-1)Q_n)} \\
  ```
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
  \State \onslide<2>{$x \gets y$ \Comment{note}}   % 0 errors, overlay preserved
  ```
  `\State` is then always executed (so push/pop stay balanced) and only the text appears or
  disappears. Wrapping a **balanced** `\If{…}\EndIf` pair in `\onslide{…}` is also safe,
  because both push and pop are hidden together.
- ⚠ **Do NOT use `\State<2> …`.** An earlier version of this entry recommended the
  "native overlay-spec syntax". **It does not work** under ltx-talk 0.5.1 + classic
  `algpseudocode` (the engine C-ALGO forces you onto): the `<2>` is *silently swallowed* —
  it compiles with zero errors and zero warnings, and the line then renders on **every**
  slide, destroying the progressive reveal. Verified: `\State<2>` → 1 page (no overlay);
  `\onslide<2>{\State}` → 2 pages but 30 `\endcsname` errors; `\State \onslide<2>{…}` →
  2 pages, 0 errors. Classic `algpseudocode` is simply not overlay-aware; only beamer
  patched it to be.
- **Revisit when:** ltx-talk (or algorithmicx) grows real overlay-spec support on `\State`.

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

## Quick error → cause map

> ⚠ **The worst failures in this catalogue produce NO error at the offending line.**
> Run **`convert_deck.py --lint`** before every build — it greps for all of these:
> | Silent failure | Symptom | Entry |
> |---|---|---|
> | Nested-brace frame title left unconverted | frame has **no title**; text lands in the body | C-FRAMETITLE-NESTED |
> | `\State<2>` used as an overlay spec | overlay **silently dropped**; line shows on every slide | C-OVERLAY-ALGO |
> | `\center{…}` used as a command | tag tree corrupts; error lands **far away**, or in another frame | C-CENTER-ARG |
> | `\includegraphics` without `alt=` | screen reader reads out **the filename** | see `alt-text.md` |

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
