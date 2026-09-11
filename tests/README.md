# Fixtures

Minimal worked examples (MWEs) for the catalogue in `../references/compromises.md` and for
reported bugs. **Not shipped with the skill** — `tests/` is `export-ignore`d in
`.gitattributes`, so it's absent from `git archive` output (GitHub "Download ZIP", release
tarballs, and the zip `.github/workflows/release.yml` attaches to releases). It stays fully
tracked and browsable in the repo itself.

## Layout

```text
tests/fixtures/<ID>/
  before.tex        # minimal Beamer source that hits the problem
  after.tex         # the same content converted, workaround applied
  naive.tex         # OPTIONAL: converted WITHOUT the workaround, i.e. the defect
  assert-before.sh  # OPTIONAL: the property this conversion must preserve
  assert-after.sh   # OPTIONAL: the same property, still there
  assert-naive.sh   # OPTIONAL: the defect is present
  assert-<variant>-<output>.sh   # OPTIONAL: the claim for an extra output
  fixture.conf      # OPTIONAL: engine, pass-count and extra-output overrides
```

Alongside the LaTeX fixtures there is a source-level corpus, which no build touches:

```text
tests/converter/*.tex        # inputs for tests/run_converter_idempotence.sh
```

`<ID>` is the catalogue ID from `compromises.md` (`C-ALGO`, `A-TIKZ-ALT`, …) or, for a bug
with no catalogue entry yet, the GitHub issue number (`ISSUE-2`).

## Conventions

- **`before.tex`** is standalone Beamer (`\documentclass{beamer}`, no `\DocumentMetadata`)
  reduced to the smallest source that reproduces the symptom described in the matching
  catalogue entry — one frame, placeholder content, no unrelated packages.
- **`after.tex`** is the same frame converted to `ltx-talk` with the entry's documented
  workaround applied. It should compile clean and tagged (exit 0, `pdfinfo` reports
  `Tagged: yes`) against the ltx-talk version noted in the catalogue entry.
- **`naive.tex`** is the conversion done *without* the workaround — the defect itself. It is
  what stops a fixture asserting something vacuous: without it, an assertion that passes shows
  only that the property holds, not that it could ever have been lost. Add one wherever the
  defect can be expressed in source.
- Neither file needs a full preamble/theme — borrow the minimum from
  `../assets/preamble-template.tex`, not the whole thing.
- **Head comments carry the diagnosis.** Each file opens with a comment saying what the
  symptom is and, in `after.tex`, why the workaround is the one it is — including the things
  that were tried and don't work. The fixture is documentation as much as it is a test; a
  reader who lands here from a failing build should not have to go and find the catalogue
  entry to understand what they are looking at.

## Source-level tests: is the converter idempotent?

`run_fixtures.sh` builds PDFs. `run_converter_idempotence.sh` never invokes LaTeX: it runs
`convert_deck.py` over a corpus and checks two halves of one promise the script has always
made in its docstring, and `SKILL.md` Step 2 with it.

| check | property | corpus |
|---|---|---|
| fixed point | `convert(x) == x` on a deck that is already converted | `tests/converter/*.tex`, every fixture `after.tex` |
| idempotence | `convert(convert(x)) == convert(x)` | all of the above plus every `before.tex` and `naive.tex` |

Nothing checked either half until #26, where a second run starred the closing `\end` of the
first ordinary frame after every `frame*` and stopped real decks compiling. Both halves are
needed: on already-converted input that bug struck the *first* run, so the two runs agreed
with each other and only the fixed-point check catches it.

`naive.tex` is exempt from the fixed-point check. That variant is the conversion done without
a workaround, so the converter still has legitimate work to do on it.

The suite ends with a vacuity guard: the corpus must still contain both shapes that broke —
an `\end{frame*}` with a later ordinary `\end{frame}`, and a `containsverbatim` frame with an
ordinary frame after it. Delete the last file with either and the suite fails rather than
quietly stops testing the regression it exists for.

Add a case to `tests/converter/` when a bug is about what the converter *writes*; add a
fixture to `tests/fixtures/` when it is about what LaTeX then *does* with it.

## Assertions

`run_fixtures.sh` always checks that every variant compiles and that `after.tex` is tagged.
Those two checks are, deliberately, the exact pair this project exists to call insufficient:
every silent-failure entry in the catalogue compiles clean and reports `Tagged: yes` while
broken. So a fixture may carry assertions that look at what is actually in the PDF.

A fixture's `assert-<variant>.sh` runs with the cwd set to the build directory and
`tests/lib/assert.sh` available to source. It gets `FIXTURE_ID`, `VARIANT`, `ENGINE`, `PDF`
and `LOG` in the environment. The library provides `must_contain` / `must_not_contain`,
`must_share_xmin` / `must_differ_xmin` / `must_ymin_above` / `must_ymin_below` (via
`pdftotext -bbox`), `must_have_pages`, `must_be_tagged`, `struct_count`,
`must_have_mathml` / `must_have_no_mathml`, `log_count`, and the pixel helpers below. Each
failure message names the value observed, so a CI log says what was measured rather than only
that something failed.

### PDF/UA-2 clauses (veraPDF)

Two font-level entries have no cheap signal — `C-SYMBOL-FONT-TOUNICODE` compiles clean, is
tagged, logs nothing, and only a real validator sees it. So `assert.sh` provides
`must_fail_ua2` and `must_not_fail_ua2`, both taking a **clause id**:

```sh
must_fail_ua2 8.4.5.8-1        # the defect is visible to a validator
must_not_fail_ua2 8.4.5.8-1    # the workaround clears that clause
```

**Always a named clause, never overall PASS/FAIL.** These fixtures are minimal decks with no
`\title`, so every one of them fails `8.11.1-1` and `8.2.2-1` on its own account. "Passes ua2"
would be false for all of them and "fails ua2" would be true for the wrong reason. A clause is
the only claim that isolates the defect, and `must_not_fail_ua2` deliberately says nothing
about any other clause.

If `verapdf` is not on `PATH` the helpers print a note and pass, so a contributor without it
still gets a green suite. CI does not rely on that: the workflow installs veraPDF and then runs
`verapdf --version`, so a broken install fails the job instead of quietly disabling these
assertions. Cost measured: 45-60s once per job for the JRE and installer, then ~0.9s per
validation, of which the suite does four.

⚠ veraPDF exits **1 for a non-compliant file**, which is the normal case here. Treating that as
"could not run" is a real trap — an early version of `ua2_clauses` did, and returned no clauses
at all, which made `must_not_fail_ua2` pass vacuously for every fixture. Only a missing or
unparseable report means the run failed.

### Rendered pixels (pdftoppm)

Several entries fail in a way that leaves the text layer, the log, the page count and the
structure tree all correct while the page renders wrong. `C-BACKGROUND` is the worked case:
stub `\usebackgroundtemplate` out and the deck still compiles to 4 pages, still reports
`Tagged: yes`, and renders white text on a white page. So `assert.sh` renders the page with
`pdftoppm` and measures it:

```sh
must_be_painted 1 0.00 0.00 1.00 1.00     # page 1 is ink edge to edge
must_be_blank   3 0.10 0.30 0.90 0.70     # nothing drawn in page 3's body
must_frac_nonwhite_between 1 0 0 1 0.2 0.30 0.60   # the primitive, with bounds you measured
pixel_at 1 0.5 0.5                        # "R G B"
region_mean 1 0 0 1 1                     # "R G B", mean over the region
frac_nonwhite 1 0 0 1 1                   # 0.0000 to 1.0000
```

Regions are **fractions** of page width and height with y from the **top**, the same
convention as `pdftotext -bbox` and `must_ymin_frac_between`. A pixel counts as non-white when
any channel is below `PIXEL_WHITE_MIN` (default 250 of 255); antialiasing a glyph edge against
white lands in the 230s, so a cutoff at 255 would score the blank margin of any page as
painted. `must_be_blank` allows 2% for ink bleeding in from just outside the region, and
`must_be_painted` requires 90%. Neither is for text: a region of prose is mostly white paper,
so measure that with `must_frac_nonwhite_between` and a band you have observed.

Rendering is `pdftoppm -r $PIXEL_DPI -singlefile` (default 70, as in SKILL.md Step 4), cached
per page. `tests/lib/pixelprobe.py` parses the Netpbm raster directly — no Pillow, no new
dependency, and `pdftoppm` is already part of the `poppler-utils` the suite requires, so this
adds no CI install step.

**There are deliberately no stored reference images.** A committed PNG rots on the first
ltx-talk font or spacing change and tells nobody why it differed. Every claim here is a
measurement with a stated tolerance instead.

`tests/run_pixel_probe_selftest.sh` is how the probe is trusted at all. Its parser arm checks
exact values against synthetic rasters (no LaTeX, no poppler); its rendered arm builds a
two-page deck, painted then blank, and pairs **every** positive check with the inverted claim,
which must be rejected. A probe that measured the wrong thing would make several fixtures agree
with each other and be wrong together — which is #18 repeated. It runs in both CI jobs.

**A failure means different things per variant, and that asymmetry is the point:**

| variant | assertion says | on failure |
|---|---|---|
| `before.tex` | the property exists in the Beamer original | **hard** — the fixture itself is invalid |
| `after.tex` | the workaround preserves it | **hard** — a regression, CI fails |
| `naive.tex` | the defect is present | **advisory** — ltx-talk fixed it upstream; CI stays green and the run prints a retirement candidate |

CI must break when one of our fixes stops working, and must *not* break when ltx-talk fixes
something underneath us. The advisory results are how "which entries still reproduce on the
installed ltx-talk?" becomes an answer the suite gives rather than prose someone maintains by
hand (see #10).

**The mutation check.** Where a fixture has both `naive.tex` and `assert-after.sh`, the runner
also runs the *after* assertion against the *naive* build and requires it to **fail**. If it
passes, that assertion cannot detect the defect its fixture exists for, and the fixture is
reported as `VACUOUS ASSERTION` — a hard failure. This is the harness checking itself against
its own original sin: an assertion of "compiles and `Tagged: yes`" passes every naive.tex in
this directory, and would be caught here.

`fixture.conf` overrides the build — `ENGINES` (default `lualatex`), `PASSES` (default 1) and
`EXTRA_OUTPUTS` (default none):

```sh
ENGINES="lualatex pdflatex"   # build and assert under each
ENGINES_before="pdflatex"     # or per variant
ENGINES_after="lualatex"
ENGINES_naive="pdflatex"
PASSES=3
EXTRA_OUTPUTS="handout"           # build each variant again with class options
CLASS_OPTIONS_handout="handout"   # ...these ones
```

The default engine is `lualatex` because that is what SKILL.md Step 3 requires; running the
fixtures under `pdflatex` would validate them under an engine the skill tells users not to use.
Per-variant engines exist because for some entries **the defect is the engine, not the source**
— `C-PDFTEX-MATH` is one deck built three ways. `PASSES` exists because some properties only
appear once the build converges: MathML payloads are absent on pass 1 under every engine, so a
single-pass harness would "prove" LuaLaTeX no better than pdfTeX.

`EXTRA_OUTPUTS` exists because for one entry the defect is invisible in the only output the
suite used to build. `C-HANDOUT-MODE` is that entry: the **slides** build of the fixed and the
broken deck are the same 2 pages with the same text layer, and they differ only in the
**handout** build, where the broken one stacks every overlay of a frame onto one page. Each
extra output is built with `\PassOptionsToClass{<opts>}{<class>}` ahead of the file, taking
`<class>` from the source's own `\documentclass` — so one key covers a beamer `before.tex` and
an ltx-talk `after.tex` without the fixture naming either. Measured: that injection is
equivalent to writing the option into `\documentclass[...]`, under both classes.

An extra output asserts through its own `assert-<variant>-<output>.sh`, with the same
per-variant meaning and the same mutation check as the default output. `C-HANDOUT-MODE` has
**no** `assert-after.sh` for the default output on purpose: any assertion true of the fixed
slides build is equally true of the broken one, so the mutation check would report it as
vacuous — correctly. That the slides build cannot tell them apart is the entry.

## What the suite can and cannot assert

Fixtures without assertions are still compile smoke-tests only, and **most of this catalogue
fails silently** — so for those the green tick means "the fixed version still builds", not "the
bug is caught". Verify the negative side by hand when adding a fixture, and record the result
in the head comment. Measured for the current set:

| fixture | unfixed version fails how? | caught by the suite? |
|---|---|---|
| `C-FRAMESTAR-TAG` | exit 1, 2 tagpdf errors | **yes** — a genuine regression test |
| `C-ALERTBLOCK` | literal `[` renders as the box title | **yes** — `assert-*.sh`, text layer: `[` and `Key result]` |
| `C-ONSLIDE-ARG` | overlay 1 renders **blank**; page count correct | **yes** — `assert-*.sh`, pixel probe, prose band 0.0387 vs 0.0000 |
| `C-FRAMESUBTITLE` | subtitle text absent from the PDF | **yes** — `assert-*.sh`, `pdftotext` grep |
| `C-HANDOUT-MODE` | handout stacks all overlays on one page | **yes** — `assert-*-handout.sh`, via `EXTRA_OUTPUTS`; the slides build cannot see it |
| `C-DISPLAY-DOLLAR` | items after the display outdent to the frame margin | **yes** — `assert-*.sh`, `xMin` 50.165 vs 28.346 |
| `C-FRAME-OPT` | `[b]` frame renders centred instead of bottom-aligned | no — needs `pdftotext -bbox` (`yMin` 135.76 vs 247.96) |
| `C-FRAMETITLE` | title renders as body text, header bar empty | **yes** — `assert-*.sh`, `yMin` 0.475 vs 0.023 of page height |
| `C-FRAMETITLE-NESTED` | nested-brace title renders as body text, also behind an overlay spec | yes |
| `C-TITLEPAGE` | **retired** — the overlap does not reproduce on 0.5.3 or 0.6.2, four variants measured | n/a — deliberately no `naive.tex`, see the fixture's head comment |
| `C-BACKGROUND` | stubbed out, the background page is 99% white under white text; unscoped, it leaks onto page 3 | **yes** — `assert-*.sh`, pixel probe, page-1 ink 1.0000 vs 0.0025; also pins `/S /Figure` = 0 |
| `C-PDFTEX-MATH` | maths punctuation corrupt in the text layer, no MathML | **yes** — `assert-*.sh`, three engines, 4 vs 0 MathML payloads |
| `C-GLYPH-MISSING` | the character is absent from the slide | **yes** — `assert-*.sh`, `Missing character` in the log, U+FFFD in the text layer, veraPDF `8.4.5.9-1` |
| `C-SYMBOL-FONT-TOUNICODE` | text layer returns `;` where `⇝` was rendered | **yes** — `assert-*.sh`, `pdftotext` plus veraPDF `8.4.5.8-1`; no `before.tex`, the Beamer original has the same defect |

⚠ **`pdftotext` cannot verify overlays.** ltx-talk typesets every overlay branch once and
toggles visibility with PDF OCG layers, so hidden content is still present in the extracted
text. Extracting text from the `C-ONSLIDE-ARG` fixture gives *byte-identical* output for the
broken and fixed versions while one of them renders an entirely blank page — checked with
`diff`. That fixture now measures the pixels instead: overlay 1's prose band is 0.0387
non-white with `\uncover` and 0.0000 with `\onslide`. For anything similar, look at the
pixels — by hand with `pdftoppm -r 50 -png`, or in an assertion with the helpers above.

A fixture that must *fail* is spelled `naive.tex` plus an `assert-naive.sh` asserting the
defect. Note it still has to **compile** — the runner requires that of every variant, and for
a silent failure it is true by definition. A defect that cannot compile belongs in `before.tex`
with the compile itself as the test (`C-FRAMESTAR-TAG`).

## Running them

`.github/workflows/ci.yml`'s `latex-fixtures` job runs `run_fixtures.sh` on every push/PR,
inside the `texlive/texlive:latest` container (Ubuntu's own `texlive` packages are too old to
have `ltx-talk`). It builds every variant, checks `after.tex` reports `Tagged: yes`, and runs
whatever assertions the fixtures carry. It needs `poppler-utils` (`pdfinfo`, `pdftotext`) and
`qpdf`, which the container does not ship.

Locally, with a TeX Live that has `ltx-talk` installed:

```sh
bash tests/run_fixtures.sh
```
