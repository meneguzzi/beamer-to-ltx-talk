# Fixtures

Minimal worked examples (MWEs) for the catalogue in `../references/compromises.md` and for
reported bugs. **Not shipped with the skill** — `tests/` is `export-ignore`d in
`.gitattributes`, so it's absent from `git archive` output (GitHub "Download ZIP", release
tarballs, and the zip `.github/workflows/release.yml` attaches to releases). It stays fully
tracked and browsable in the repo itself.

## Layout

```text
tests/fixtures/<ID>/
  before.tex   # minimal Beamer source that hits the problem
  after.tex    # the same content converted, workaround applied
```

`<ID>` is the catalogue ID from `compromises.md` (`C-ALGO`, `A-TIKZ-ALT`, …) or, for a bug
with no catalogue entry yet, the GitHub issue number (`ISSUE-2`).

## Conventions

- **`before.tex`** is standalone Beamer (`\documentclass{beamer}`, no `\DocumentMetadata`)
  reduced to the smallest source that reproduces the symptom described in the matching
  catalogue entry — one frame, placeholder content, no unrelated packages.
- **`after.tex`** is the same frame converted to `ltx-talk` with the entry's documented
  workaround applied. It should compile clean and tagged
  (`pdflatex` exits 0, `pdfinfo` reports `Tagged: yes`) against the ltx-talk version noted in
  the catalogue entry.
- Neither file needs a full preamble/theme — borrow the minimum from
  `../assets/preamble-template.tex`, not the whole thing.
- **Head comments carry the diagnosis.** Each file opens with a comment saying what the
  symptom is and, in `after.tex`, why the workaround is the one it is — including the things
  that were tried and don't work. The fixture is documentation as much as it is a test; a
  reader who lands here from a failing build should not have to go and find the catalogue
  entry to understand what they are looking at.

## What the suite can and cannot assert

`run_fixtures.sh` checks that both files compile and that `after.tex` is tagged. That catches
the compile-time compromises, but **most of this catalogue fails silently** — the whole reason
it exists — so for those the green tick means only "the fixed version still builds", not "the
bug is caught". Verify the negative side by hand when adding a fixture, and record the result
in the head comment. Measured for the current set:

| fixture | unfixed version fails how? | caught by the suite? |
|---|---|---|
| `C-FRAMESTAR-TAG` | exit 1, 2 tagpdf errors | **yes** — a genuine regression test |
| `C-ALERTBLOCK` | literal `[` renders as the box title | no — visual |
| `C-ONSLIDE-ARG` | overlay 1 renders **blank**; page count correct | no — visual |
| `C-FRAMESUBTITLE` | subtitle text absent from the PDF | no — needs a `pdftotext` grep |
| `C-HANDOUT-MODE` | handout stacks all overlays on one page | no — handout build only |
| `C-FRAMETITLE`, `C-FRAMETITLE-NESTED` | title renders as body text, header bar empty | no — visual |
| `C-TITLEPAGE` | attribution overprints the title | no — visual |

⚠ **`pdftotext` cannot verify overlays.** ltx-talk typesets every overlay branch once and
toggles visibility with PDF OCG layers, so hidden content is still present in the extracted
text. Extracting text from the `C-ONSLIDE-ARG` fixture gives *byte-identical* output for the
broken and fixed versions while one of them renders an entirely blank page. Render to an
image (`pdftoppm -r 50 -png`) and look at it.

There is currently **no convention for a fixture that must fail** — the runner asserts every
`.tex` it finds compiles. Where the interesting artifact is a broken conversion (the naive
`\[` inside `columns > column > center`, say), it lives in the catalogue entry rather than
here.

## Running them

`.github/workflows/ci.yml`'s `latex-fixtures` job runs `run_fixtures.sh` on every push/PR,
inside the `texlive/texlive:latest` container (Ubuntu's own `texlive` packages are too old to
have `ltx-talk`). It compiles every `before.tex`/`after.tex`, and additionally checks
`after.tex`'s PDF reports `Tagged: yes`.

Locally, with a TeX Live that has `ltx-talk` installed:

```sh
bash tests/run_fixtures.sh
```
