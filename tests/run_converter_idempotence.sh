#!/usr/bin/env bash
# convert_deck.py says it is idempotent, in its own docstring and in SKILL.md Step 2.
# Nothing checked that until #26, where a second run starred the closer of the first
# ordinary frame after every frame* and stopped real decks compiling. Re-running the
# converter is a natural thing to do, and #12 (upgrade already-converted decks with
# newer skill fixes) is exactly that operation, so the invariant is load-bearing.
#
# Two checks, because the claim has two halves and only one of them catches #26 on
# already-converted input:
#
#   FIXED POINT   convert(x) == x for a deck that is ALREADY converted. This is the
#                 issue's own reproduction, and the property SKILL.md Step 2 promises.
#   IDEMPOTENCE   convert(convert(x)) == convert(x) for every corpus source. This is
#                 the half that catches the same bug coming from Beamer input.
#
# The fixed-point check deliberately skips naive.tex: that variant is the conversion
# done WITHOUT a workaround, so the converter still has legitimate work to do on it and
# is expected to change it. after.tex and tests/converter/*.tex are finished decks.
#
# Pure source-level -- no LaTeX, no PDF -- so it runs in the syntax-check CI job on
# every push rather than only where a TeX Live container is available.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
cv="$repo/scripts/convert_deck.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

status=0
n=0

corpus=("$here"/converter/*.tex "$here"/fixtures/*/*.tex)

for src in "${corpus[@]}"; do
  [ -f "$src" ] || continue
  rel="${src#$repo/}"
  n=$((n + 1))

  if ! python3 "$cv" "$src" > "$tmp/r1.tex" 2>"$tmp/r1.err"; then
    echo "FAIL: $rel -- convert_deck.py exited non-zero"
    tail -n 5 "$tmp/r1.err"
    status=1
    continue
  fi
  # An empty output would make both comparisons below pass for the wrong reason.
  if [ ! -s "$tmp/r1.tex" ]; then
    echo "FAIL: $rel -- the converter produced nothing, so these checks would be vacuous"
    status=1
    continue
  fi

  # FIXED POINT, for finished decks only.
  case "$rel" in
    */naive.tex) ;;
    *)
      if grep -q 'documentclass{ltx-talk}' "$src"; then
        if ! cmp -s "$tmp/r1.tex" "$src"; then
          echo "FAIL: $rel is already converted, but the converter changed it."
          diff "$src" "$tmp/r1.tex" | head -n 20
          status=1
        fi
      fi
      ;;
  esac

  # IDEMPOTENCE.
  python3 "$cv" "$tmp/r1.tex" > "$tmp/r2.tex" 2>/dev/null
  if ! cmp -s "$tmp/r1.tex" "$tmp/r2.tex"; then
    echo "FAIL: $rel -- a second run is not a no-op. convert_deck.py is not idempotent."
    diff "$tmp/r1.tex" "$tmp/r2.tex" | head -n 20
    status=1
  fi
done

# Vacuity guard, in the spirit of #18: the corpus must still contain the two shapes
# that broke. If the last one is deleted or edited flat, these runs stop covering the
# regression they exist for, and must say so rather than pass.
#
# In Python, not awk: the shapes are literal backslash-brace strings, and getting them
# through an awk ERE portably is more trouble than it is worth -- an earlier version of
# this guard matched where it should not have and reported a deleted shape as present.
if ! python3 - "${corpus[@]}" <<'PYGUARD'
import sys

def lines(path):
    try:
        return open(path, encoding='utf-8').read().split('\n')
    except OSError:
        return []

def converted_shape(ls):
    """An \\end{frame*} with a later ordinary \\end{frame} -- what #26 corrupted."""
    seen = False
    for l in ls:
        if l.lstrip().startswith('%'):
            continue
        if '\\end{frame*}' in l:
            seen = True
        elif seen and '\\end{frame}' in l:
            return True
    return False

def beamer_shape(ls):
    """A containsverbatim frame with a later ordinary \\begin{frame}."""
    seen = False
    for l in ls:
        if l.lstrip().startswith('%'):
            continue
        if 'containsverbatim' in l and '\\begin{frame}' in l:
            seen = True
        elif seen and l.lstrip().startswith('\\begin{frame}') and '{frame*}' not in l:
            return True
    return False

corpus = [lines(p) for p in sys.argv[1:]]
missing = []
if not any(converted_shape(f) for f in corpus):
    missing.append('an \\end{frame*} followed by a later \\end{frame}'
                   ' -- see tests/converter/issue-26-framestar-converted.tex')
if not any(beamer_shape(f) for f in corpus):
    missing.append('a containsverbatim frame followed by an ordinary \\begin{frame}'
                   ' -- see tests/converter/issue-26-framestar-beamer.tex')
for m in missing:
    print('FAIL: no corpus deck has ' + m)
sys.exit(1 if missing else 0)
PYGUARD
then
  status=1
fi

if [ "$status" = 0 ]; then
  echo "OK: $n source(s) -- convert(x) == x on finished decks, and a second run is a no-op."
fi
exit $status
