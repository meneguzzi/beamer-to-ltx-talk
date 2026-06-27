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
- **Cause:** the `algpseudocodex` package's algorithmic body uses an alignment that the
  tagging/output path turns into an improper display `\halign`. Independent of columns,
  `[c]`, tagging *phase*, and box-wrapping (minipage/parbox/varwidth do **not** help, nor
  does `\SuspendTagging` for function blocks).
- **Workaround:** switch the engine to the **classic `algorithmicx`/`algpseudocode`**:
  ```latex
  \usepackage{algorithmicx}
  \usepackage[noend]{algpseudocode}   % [noend] mimics algpseudocodex's noEnd look
  ```
  Syntax is ~identical (`\State`, `\Function`, `\Comment`, `\Call`, `\If`, `\While`,
  `\Statex`). The exact same algorithm source then compiles tagged and clean. Drop the
  `algpseudocodex` options `noEnd,indLines=false` (not valid here). Cosmetic differences:
  classic prints "end function" unless `[noend]`; no indent guide lines.
- **Revisit when:** either package addresses tagging. No upstream issue is filed (this looks
  like an `algpseudocodex` × tagpdf interaction, not strictly an ltx-talk bug) — consider
  filing one. **This blocks most algorithm-bearing decks, so check it first.**

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
- **Theorems:** `\newtheorem*` is incomplete (issue #219). Avoid for now.
- **Media:** `media9 \includemedia`, `\movie`, `\animategraphics` are untested under tagging —
  verify case-by-case or fall back to a static image + hyperlink.
- **Revisit when:** the cited issues close.

---

## Quick error → cause map

| Error text | Cause | Entry |
|---|---|---|
| `Improper \halign inside $$'s` | algpseudocodex algorithm | C-ALGO |
| `You can't use \halign in math mode` | multi-line `\State{…\\…}` (algpseudocodex) | C-ALGO |
| `tagpdf Error: … begin/end … differ` / `Sect can not be closed` | `\tableofcontents` | C-TOC |
| `Not allowed in LR mode` at `\maketitle` | `frame-title-arg` option set | C-MAKETITLE |
| frame title appears as body text | braced title, no `\frametitle` | C-FRAMETITLE |
| `not compatible with \DocumentMetadata` | class still `beamer` | switch class |
| `Paragraph ended before \lst@next…` | verbatim in normal frame | C-VERBATIM |
| `Undefined control sequence \setbeamer…` | Beamer styling command | C-NOBEAMER |
