# beamer-to-ltx-talk

An [Agent Skill](https://agentskills.io) that converts existing LaTeX **Beamer** slide decks to the **ltx-talk** class, producing tagged, accessible PDF (PDF/UA, PDF/A). Built and tested with [Claude Code](https://claude.ai/code), but the `SKILL.md` format is an open, cross-tool standard. The [client list](https://agentskills.io/clients) includes Cursor, GitHub Copilot, Gemini CLI, Codex, and dozens of others. Point any compliant agent at this repo, or just ask any coding agent with file-read and shell access to follow `SKILL.md`.

The guiding principle is **faithful, minimal, scripted change**: keep body content and slide order identical, rewrite only what the class change forces, and report every compromise made.

---

## Why ltx-talk?

Beamer is [incompatible with `\DocumentMetadata`](https://github.com/josephwright/beamer/issues/808), the LaTeX kernel's tagging activation hook. ltx-talk is a purpose-built replacement that supports:

- Tagged PDF output (PDF/UA-2, PDF/A-4) via the LaTeX tagging kernel
- Native handout mode without per-deck edits
- Clean `\EditInstance`-based theming instead of `\setbeamer*` commands

The trade-off is that ltx-talk is still experimental and has known incompatibilities, most of which only surface under tagging. This skill encodes the fixes discovered converting two real courses: an 11-deck course and a 20-deck course.

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

When you give a compatible agent a Beamer `.tex` file and ask to convert it, the skill:

1. **Checks** the toolchain and surveys the deck for constructs that need attention.
2. **Generates** an ltx-talk shared preamble from `assets/preamble-template.tex`. Fill in the Identity block (author/institute) and ThemeAccent colour to match your original theme.
3. **Runs** `scripts/convert_deck.py` to handle the mechanical rewrites:
   - Switches `\documentclass{beamer}` → `\documentclass{ltx-talk}`
   - Converts braced frame titles to `\frametitle{…}`
   - Rewrites `\center{X}` → `\begin{center}X\end{center}` (a declaration, not a command, fatal under tagging)
   - Strips `\AtBeginSection` outline frames (the preamble's redefined `\section` emits a tagging-safe divider instead, so `\section{X}` lines stay untouched)
   - Rewrites title pages and verbatim frames
4. **Lints** with `convert_deck.py --lint` *before* compiling. See below.
5. **Compiles** and triages errors against the known-incompatibilities catalogue.
6. **Delivers** a conversion report listing the ltx-talk version targeted, page-count comparison, every compromise made, and outstanding manual follow-ups (especially missing alt text on images).

### Lint before you build

The two costliest bugs in a real 20-deck migration were **invisible to the compiler**: a braced frame title renders as body text with no error at all, and `\center{…}` corrupts the PDF tag tree with an error reported nowhere near the offending line. Both are pure source greps needing no build:

```sh
python3 scripts/convert_deck.py deck.tex --lint    # exit 1 if anything is flagged
```

---

## Repository layout

```
assets/
  preamble-template.tex   # Deployable ltx-talk preamble, copy to your project
  Makefile                # latexmk-based build for slide and handout targets

references/
  compromises.md          # Catalogue of Beamer→ltx-talk incompatibilities
                          # (symptom → cause → workaround → revisit when)

scripts/
  convert_deck.py         # Idempotent source transformer; also `--lint` (pre-build check)
  fix_frame_titles.py     # Second pass: brace-matched titles convert_deck.py can't see
  alt_text_audit.py       # Lists \includegraphics missing alt= text
  alt_text_apply.py       # Writes alt= text back into the source
  table_audit.py          # Classifies every tabular: data table (needs TH) vs
                          # layout grid (needs table/tagging=div), see A-TABLE-TH

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

⚠️ The template carries `columns`/`column`/`block` **stubs inside an `\iffalse` block; leave them disabled**. ltx-talk provides all of them *natively*; enabling the stubs clashes (`Command \columns already defined`). They exist only for a plain kernel-class setting. See **C-NATIVE-ENVS**.

---

## Known incompatibilities (summary)

Full details, including error signatures and workarounds, are in [`references/compromises.md`](references/compromises.md).

**The worst failures produce no error at the offending line.** `--lint` catches the greppable ones (all but the first):

| ID | Silent failure | Fix |
|---|---|---|
| **C-ONSLIDE-ARG** | `\onslide<n>{…}` takes **no argument** in ltx-talk → the declaration leaks and blanks **everything after it to the end of the frame** on early overlays; 139 occurrences in one 11-deck course, invisible in every "builds clean" report | `\uncover<n>{…}` (reserves space) or `\only<n>{…}` (doesn't) |
| **C-FRAMETITLE-NESTED** | Nested-brace title left unconverted → frame has **no title**, text lands in the body | Run `fix_frame_titles.py` |
| **C-CENTER-ARG** | `\center{…}` used as a command → tag tree corrupts, error lands **far away** | `\begin{center}…\end{center}` |
| **C-OVERLAY-ALGO** | `\State<2>` used as an overlay spec → **literal `<2>` printed on the slide**, overlay never fires | `\State \uncover<2>{…}` (not `\onslide`, see C-ONSLIDE-ARG) |
| **C-NO-DOCMETA** | `\DocumentMetadata` shipped commented out → ltx-talk **half-loads**, cascading `Undefined control sequence` naming none of the real cause | Uncomment/add `\DocumentMetadata{…}` before `\documentclass` |
| *(alt text)* | `\includegraphics` without `alt=` → screen reader reads out **the filename** | `alt_text_audit.py` |

⚠ Verify overlays by **rendering pages** (`pdftoppm -f N -l N -png`), never with `pdftotext`. Hidden overlay content stays in the PDF text layer, so text extraction reports content that isn't visible on the slide. This is how C-ONSLIDE-ARG and C-OVERLAY-ALGO were actually caught.

Failures that survive **all** of the above (clean compile, `Tagged: yes`, 0 tagpdf errors,
every image described) and are found only by running a real PDF/UA checker (**Step 6b**):

| ID | Silent failure | Fix |
|---|---|---|
| **A-HEADINGS** | ltx-talk roles `frametitle` to `H4` and nothing is an `H1` → "headings do not begin at level one" | `role/new-tag = frametitle / H2`, tag the deck title `H1` |
| **A-MATHALT** | `Formula` elements carry no `/Alt` → maths reported as undescribed images | `\tagpdfsetup{math/alt/use}` |
| **A-TABLE-TH** | Every `tabular` is a `Table` with no `TH`, layout grids included, and the settings **leak** between tables | State all three keys per table (`table/tagging=…,header-rows=…,header-columns=…`), or `table/tagging=div`; `table_audit.py` |
| **A-CONTRAST** | Saturated emphasis colours are <4.5:1 on white | Darken the palette **and** the raw `\color{red}` sites |

The first two are one-line preamble fixes, already in `preamble-template.tex`.

Errors the compiler *does* report:

| ID | Issue | Workaround |
|---|---|---|
| **C-ALGO** ⚠️ | `algpseudocodex` cannot be typeset under tagging at all | Switch to classic `algorithmicx`/`algpseudocode[noend]` |
| **C-FRAMESTAR-TAG** ⚠️ | `frame*` + `listings` corrupts the tag tree | `\tag_stop:`/`\tag_start:` hooks around the whole `frame*` |
| **C-BLOCK-ALGO** ⚠️ | `\begin{block}` conflicts with `algorithmicx` | Define theorem-like envs with `tcolorbox` |
| **C-TOC** | `\tableofcontents` corrupts the tag tree | Redefine `\section` to emit a divider frame (decks unchanged) |
| **C-VERBATIM** | `containsverbatim`/`lstlisting` fail in `frame` | Use `frame*`: necessary but **not sufficient**, see C-FRAMESTAR-TAG |
| **C-CALL-NEST** | Nested `\Call` breaks classic `algpseudocode` | `\algrenewcommand\Call[2]{\textproc{#1}(#2)}` |
| **C-ALGO-FLOAT** | The `algorithm` float isn't registered for tagging | Drop the float; keep bare `algorithmic` |
| **C-THEOREM** | No `definition`/`theorem`/… environments | Build them with `tcolorbox` |
| **C-NATIVE-ENVS** | `columns`/`block` stubs clash with ltx-talk's native ones | Use the native envs; keep the template's stubs disabled |
| **C-FRAMETITLE** | Braced frame titles render as body text | Use `\frametitle{…}` explicitly |
| **C-MAKETITLE** | `frame-title-arg` breaks `\maketitle` | Don't use `frame-title-arg` |
| **C-TITLEPAGE** | `\maketitle` fills frame; trailing text overlaps | Use `\coursetitlepage{}{}{}` |
| **C-NOBEAMER** | All `\usetheme`/`\setbeamer*` are undefined | Rebuild styling with `\EditInstance` |
| **C-BACKGROUND** | No `\usebackgroundtemplate` | Overlay tikz node (never a no-op stub) |
| **C-AND-TITLE** ⚠️ | `\and` typeset outside `\author` (e.g. in a custom title page) → **101 errors**, none near the fault (`Misplaced \crcr`) | `\renewcommand{\and}{\qquad}` for the duration of the title frame; already in `preamble-template.tex` |
| **C-IMMATURE** | `block`/theorem envs are undocumented/incomplete (issues #205, #219); `media9` untested under tagging | Use sparingly; build theorems with `tcolorbox` (C-THEOREM) |
| **C-OLDFONT** | `\sc`/`\it`/`\bf` undefined, and may sit inside maths | `\ifmmode`-guarded `\providecommand` stubs |
| **C-EDITINSTANCE-EXPAND** | Template colour keys won't expand `\ThemeAccent` | Write the colour name out literally |
| **C-OVERLAY-ALIGN** | Overlay tokens around `&`/`\\` break alignment | Wrap only the cell content |
| **C-DISPMATH-NEWLINE** | `\\` after display math errors | Replace with `\vspace{…}` or a blank line |
| **C-FONTS** | Maths is sans-serif by default | Re-point the four maths symbol fonts to Latin Modern |

The catalogue is verified across **ltx-talk 0.5.0-0.5.2** (each entry in `compromises.md` notes the specific version it was checked against). Before converting, check the [ltx-talk changelog](https://github.com/josephwright/ltx-talk/blob/main/CHANGELOG.md) and [open issues](https://github.com/josephwright/ltx-talk/issues); some workarounds may no longer be needed.

---

## Accessibility notes

The whole point of this conversion is tagged, accessible PDF. Things to check after conversion:

- **Alt text**: `tagpdf` warns for every `\includegraphics` without `alt={…}`. Surface the list and fill it; this is the main accessibility payload.
- **Reading order in columns**: content is tagged in source order (left column first, then right). Write columns so left-first is the correct reading order. For paired-row content, use `tabular` instead.
- **Block titles**: the `title=` argument of `block`/`alertblock`/`exampleblock` is tagged as plain text, not as a heading. For semantically important labels, use `\subsubsection*{}` inside the box body.
- **Verify tagging**: `pdfinfo deck.pdf | grep Tagged` should return `yes`; `grep 'tagpdf Error' deck.log` should return 0 matches.

---

## License

Licensed under the [GNU Affero General Public License v3.0](LICENSE) (or later), with an additional attribution term under §7(b): any redistributed or modified version (including one run as a network service) must keep a visible credit back to this project. See [`LICENSE`](LICENSE) for the exact wording.
