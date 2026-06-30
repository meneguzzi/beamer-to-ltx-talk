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
- **Workaround:** drop the auto-outline. Replace `\section{X}` with a `\heading{X}` macro that
  emits the section **and** a plain section-divider frame showing the title (tagging-clean,
  verified). You lose the "contents list with current section highlighted". A hand-built,
  tagging-safe contents frame is possible but more work — offer it as an option.
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

## C-VERBATIM — `containsverbatim` / `lstlisting` need `frame*`

- **Symptom:** `! Paragraph ended before \lst@next was complete` / runaway argument with
  `listings` or `verbatim` in a normal `frame`.
- **Cause:** ltx-talk frames don't catch-code-protect verbatim; the Beamer `containsverbatim`/
  `fragile` options don't exist.
- **Workaround:** use the `frame*` environment (`\begin{frame*} … \frametitle{…} …
  \end{frame*}`). It handles `\verb`/verbatim/`lstlisting` without external files.
- **Revisit when:** n/a — `frame*` is the documented mechanism.

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
- **Workaround:** decide per project. To restore serif maths, load an appropriate maths font
  package (pdfLaTeX) — test under tagging. XeLaTeX is **not** supported; LuaTeX needs Unicode
  maths setup.
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
  frames that use `\begin{algorithmic}` AND wrap `\State` (or `\Comment`) in an overlay
  command: `\onslide<2>{\State formula}`.
- **Cause:** algorithmicx tracks nesting depth with `\csname`-based counters
  (`\ALG@b@N@EndFor`, `\ALG@currentblock`). Wrapping `\State` in a group (`\onslide{…}`)
  scopes the push but not the pop of those counters, leaving them permanently mismatched.
  `\end{frame}` then sees unbalanced `\endcsname` pairs.
- **Workaround:** use algorithmicx's **native overlay-spec syntax** — the `<spec>` argument
  goes directly after the command name, with no braces around the full statement:
  ```latex
  % Instead of: \onslide<2>{\State $x \gets y$  \Comment{note}}
  \State<2> $x \gets y$      % shows \State on step 2+
  \Comment<2>{note}          % shows \Comment on step 2+
  ```
  Wrapping a **balanced** `\If{…}\EndIf` pair (both the begin and end hidden together) in
  `\onslide{…}` is safe because both push and pop are hidden together. Only wrapping a single
  `\State` (or one side of a matching pair) is unsafe.
- **Revisit when:** n/a — the native overlay-spec syntax is the intended API.

## C-DISPMATH-NEWLINE — `\\` after display math is invalid

- **Symptom:** `! There's no line here to end.` at a `\\` or `\\*[Ncm]` that follows a display
  math block (`$…$`, `\[…\]`, `equation`, etc.).
- **Cause:** display math ends in vertical mode; `\\` (a line-break command) is only valid in
  horizontal/paragraph mode.
- **Workaround:** replace `\\[Ncm]` with `\vspace{Ncm}` and bare `\\` with a blank line
  (paragraph break).
- **Revisit when:** n/a — this is a fundamental LaTeX constraint.

---

## Quick error → cause map

| Error text | Cause | Entry |
|---|---|---|
| `Improper \halign inside $$'s` | algpseudocodex algorithm | C-ALGO |
| `Improper \halign inside $'s` | overlay around `&`/`\\` in `tabular`/`align*` | C-OVERLAY-ALIGN |
| `Misplaced alignment tab character &` | overlay around `&` in `tabular` | C-OVERLAY-ALIGN |
| `You can't use \halign in math mode` | multi-line `\State{…\\…}` (algpseudocodex) | C-ALGO |
| `Missing \endcsname` / `Extra \endcsname` at `\end{frame}` | `\begin{block}`+algorithmic | C-BLOCK-ALGO |
| `Missing \endcsname` / `Extra \endcsname` at `\end{frame}` | `\onslide{\State…}` in algorithmic | C-OVERLAY-ALGO |
| `There's no line here to end` | `\\` after display math | C-DISPMATH-NEWLINE |
| `tagpdf Error: … begin/end … differ` / `Sect can not be closed` | `\tableofcontents` | C-TOC |
| `Not allowed in LR mode` at `\maketitle` | `frame-title-arg` option set | C-MAKETITLE |
| frame title appears as body text | braced title, no `\frametitle` | C-FRAMETITLE |
| `not compatible with \DocumentMetadata` | class still `beamer` | switch class |
| `Paragraph ended before \lst@next…` | verbatim in normal frame | C-VERBATIM |
| `Undefined control sequence \setbeamer…` | Beamer styling command | C-NOBEAMER |
