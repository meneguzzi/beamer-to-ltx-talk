# Contributing to beamer-to-ltx-talk

Thanks for considering a contribution. This project is a small, tightly-scoped Claude Code skill,
so the bar for contributions is mostly "does this hold up against a real deck," not process.

## Ways to contribute

- **Report a new incompatibility.** If you hit a Beamer construct that breaks under ltx-talk and
  isn't in `references/compromises.md`, open an issue (or a PR) with the error signature, a minimal
  `.tex` snippet that reproduces it, and — if you have one — the fix you used.
- **Improve the catalogue.** Corrections, sharper detection heuristics for `--lint`, or narrower/
  broader regexes are welcome, especially if a current entry produced a false positive or false
  negative for you.
- **Extend the scripts.** `scripts/convert_deck.py` and friends are deliberately conservative — see
  "What this project won't automate" below before proposing a new auto-rewrite.

## Before you open a PR

1. **Reproduce against a real deck if you can.** Fixes validated only against a synthetic snippet
   are useful but weaker evidence than "this fixed an actual broken slide." Say which you have.
2. **Run the syntax/lint checks locally** (same as CI):
   ```sh
   for f in scripts/*.py; do
     python3 -W error::SyntaxWarning -c "import ast; ast.parse(open('$f').read())"
   done
   python3 scripts/convert_deck.py --help
   ```
3. **Update `references/compromises.md`** alongside any script change that adds or changes detection
   — the catalogue (symptom → cause → workaround → detect → revisit-when) is the actual source of
   truth; the code enforces it, not the other way round.
4. **Note the ltx-talk version** you tested against. The catalogue tracks this per-entry because
   ltx-talk is still experimental and behaviour shifts between releases.

## What this project won't automate

`convert_deck.py` deliberately does **not** auto-rewrite `\onslide<n>{…}` to `\uncover`/`\only`, even
though that's the single most common manual fix. An earlier automated attempt at this corrupted
groups that wrapped whole `tabular`/`align*`/`cases`/`matrix` environments — see **C-ONSLIDE-ARG** in
`references/compromises.md` for why, and `SKILL.md` Step 2 for the reasoning. PRs that reintroduce
this automation need to demonstrate they handle every environment in the test fixtures without
corrupting alignment — "worked on my deck" isn't sufficient evidence given the prior failure mode.

## AI-assisted contributions

Using AI tools (including Claude Code) to help write a contribution is fine — this project exists
*because* that workflow works, and most of it was built that way. What's not fine is submitting
AI output you haven't actually read and stand behind. By opening a PR, you're certifying that:

- **You read every line of the diff** and understand why each change is there.
- **It's meaningful** — it fixes a real, reproducible problem or adds something the catalogue/
  scripts genuinely lack, not a plausible-looking change generated to pad a contribution.
- **It's minimal** — scoped to the problem it claims to solve, not bundled with unrelated
  reformatting, renames, or "while I was in there" cleanup.
- **It's non-malicious** — no obfuscated behaviour, no supply-chain tricks, nothing that does
  something other than what the PR description says it does.

This can't be enforced by a linter — it's a statement about you, not the code. Maintainers will
close PRs that read as unreviewed AI output (sprawling diffs, invented catalogue entries with no
reproduction, changes that don't match their own description) without a detailed review, and repeat
offenses get the contributor blocked. If you're unsure whether a change is minimal enough, ask in
the issue before opening the PR rather than after.

## License and attribution

By contributing, you agree your contribution is licensed under the project's
[AGPLv3 (+ attribution addendum)](LICENSE), same as the rest of the codebase.

## Questions

Open an issue — there's no separate mailing list or chat for this project.
