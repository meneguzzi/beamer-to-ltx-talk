# Fixtures

Minimal worked examples (MWEs) for the catalogue in `../references/compromises.md` and for
reported bugs. **Not shipped with the skill** — `tests/` is `export-ignore`d in
`.gitattributes`, so it's absent from `git archive` output (GitHub "Download ZIP", release
tarballs, and the zip `.github/workflows/release.yml` attaches to releases). It stays fully
tracked and browsable in the repo itself.

## Layout

```
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
- These are **not** run by CI (`ci.yml`'s syntax-check job has no TeX Live), and there is no
  test-runner script yet. For now they're a manual/local check: `cd` into a fixture's
  directory and build both files by hand when touching the matching catalogue entry or
  reviewing a PR that claims to fix it.
