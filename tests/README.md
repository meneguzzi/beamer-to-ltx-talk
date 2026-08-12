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

## Running them

`.github/workflows/ci.yml`'s `latex-fixtures` job runs `run_fixtures.sh` on every push/PR,
inside the `texlive/texlive:latest` container (Ubuntu's own `texlive` packages are too old to
have `ltx-talk`). It compiles every `before.tex`/`after.tex`, and additionally checks
`after.tex`'s PDF reports `Tagged: yes`.

Locally, with a TeX Live that has `ltx-talk` installed:

```sh
bash tests/run_fixtures.sh
```
