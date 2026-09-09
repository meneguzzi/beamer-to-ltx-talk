#!/usr/bin/env bash
# Builds every tests/fixtures/<ID>/{before,after}.tex and checks:
#
#   - both variants compile clean
#   - after.tex's PDF is tagged (pdfinfo reports "Tagged: yes")
#   - the fixture's own assertions hold, if it has any
#
# The first two are smoke tests. They are also, deliberately, the exact pair of
# checks this project exists to say are insufficient: every silent-failure entry
# in references/compromises.md compiles clean and reports Tagged: yes while
# broken. So a fixture may carry assertions that look at what is actually in the
# PDF.
#
# There are three fixture variants, and the assertions mean different things:
#
#   before.tex   the Beamer original. Its assertion states the property the
#                conversion has to preserve -- it is the reference, not a broken
#                deck. HARD: a failure means the fixture itself is invalid.
#   after.tex    the converted deck with the workaround. Same assertion, and a
#                failure is a REGRESSION: exit 1.
#   naive.tex    OPTIONAL. The conversion done WITHOUT the workaround, i.e. the
#                defect. Its assertion states that the defect is present. A
#                failure here is NOT an error: it means ltx-talk fixed the bug
#                underneath us, which is good news during a version bump.
#                Reported as advisory, exit code unaffected.
#
# That asymmetry is the point. CI must break when a fix stops working, and must
# not break when ltx-talk fixes something. The advisory results are how "which
# entries still reproduce on the installed ltx-talk?" becomes an answer the
# suite gives rather than prose someone maintains by hand.
#
# naive.tex is also what stops a fixture asserting something vacuous. Without
# it, an assertion that passes proves only that the property holds -- not that
# it would ever have failed.
#
# So where a fixture has both naive.tex and assert-after.sh, the runner performs
# a MUTATION CHECK: it runs after.tex's assertion against the naive build and
# requires it to FAIL. If the after assertion passes on the defective PDF, that
# assertion cannot detect the defect it exists for, and the fixture is reported
# as VACUOUS -- which is this harness's original sin (#18) and a hard failure.
#
# Per-fixture overrides go in tests/fixtures/<ID>/fixture.conf:
#
#   ENGINES="lualatex pdflatex"   # default "lualatex"; each is built and asserted
#   ENGINES_before="pdflatex"     # per-variant override of ENGINES
#   ENGINES_after="lualatex"
#   ENGINES_naive="pdflatex"
#   PASSES=3                      # default 1; some properties need a converged
#                                 # build (MathML payloads appear on pass 3)
#
# Per-variant engines exist because for some entries the defect IS the engine,
# not a source change. C-PDFTEX-MATH is the case: the same ltx-talk source is
# correct under lualatex and corrupts the maths text layer under pdflatex, and
# the Beamer original is correct under pdflatex. Three variants, three engines,
# one entry.
#
# The default engine is lualatex because that is what SKILL.md Step 3 requires:
# under pdfTeX ltx-talk falls back to sansmathfonts and corrupts the maths text
# layer (C-PDFTEX-MATH). A fixture that is specifically about engine differences
# names both.
#
# Needs a real TeX Live with ltx-talk plus poppler-utils (pdfinfo, pdftotext)
# and qpdf. See .github/workflows/ci.yml, job latex-fixtures.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
export ASSERT_LIB="$here/lib/assert.sh"
cd "$here/fixtures"

status=0
advisory=()

for dir in */; do
  id="${dir%/}"
  fixture_dir="$(cd "$dir" && pwd)"

  ENGINES="lualatex"
  ENGINES_before=""; ENGINES_after=""; ENGINES_naive=""
  PASSES=1
  # shellcheck disable=SC1090
  [ -f "$dir/fixture.conf" ] && . "$dir/fixture.conf"

  for variant in before after naive; do
    src="$dir$variant.tex"
    [ -f "$src" ] || continue

    # Per-variant engine list, falling back to the fixture-wide one.
    eval "variant_engines=\${ENGINES_$variant}"
    [ -n "$variant_engines" ] || variant_engines="$ENGINES"

    for engine in $variant_engines; do
      label="$id/$variant.tex"
      [ "$(printf '%s\n' $variant_engines | wc -w | tr -d ' ')" -gt 1 ] && label="$label ($engine)"
      [ -n "${ENGINES_before}${ENGINES_after}${ENGINES_naive}" ] && label="$id/$variant.tex ($engine)"

      workdir=$(mktemp -d)
      cp "$src" "$workdir/$variant.tex"

      echo "::group::$label"
      ok=1
      pass=1
      while [ "$pass" -le "$PASSES" ]; do
        if ! (cd "$workdir" && "$engine" -interaction=nonstopmode -halt-on-error "$variant.tex" >>build.log 2>&1); then
          echo "FAIL: $label did not compile (pass $pass of $PASSES, $engine)"
          tail -n 60 "$workdir/build.log"
          status=1; ok=0
          break
        fi
        pass=$((pass + 1))
      done

      if [ "$ok" = 1 ] && [ "$variant" = "after" ] \
         && ! pdfinfo "$workdir/$variant.pdf" 2>/dev/null | grep -q "^Tagged: *yes"; then
        echo "FAIL: $label compiled but is not tagged"
        status=1; ok=0
      fi

      # The fixture's own assertion, if it has one.
      assertion="$fixture_dir/assert-$variant.sh"
      if [ "$ok" = 1 ] && [ -f "$assertion" ]; then
        if (cd "$workdir" \
              && FIXTURE_ID="$id" VARIANT="$variant" ENGINE="$engine" \
                 PDF="$workdir/$variant.pdf" LOG="$workdir/$variant.log" \
                 bash "$assertion"); then
          echo "OK: $label (assertion held)"
        elif [ "$variant" = "naive" ]; then
          echo "ADVISORY: $label -- the defect no longer reproduces under $engine."
          echo "          If ltx-talk fixed it, retire the catalogue entry (CLAUDE.md says"
          echo "          how) and delete this fixture. Not a build failure."
          advisory+=("$id ($engine): defect no longer reproduces")
          ok=0   # already reported; skip the plain OK line below
        else
          echo "FAIL: $label -- the assertion for this fixture no longer holds"
          status=1; ok=0
        fi
      elif [ "$ok" = 1 ]; then
        echo "OK: $label"
      fi

      # Mutation check: after.tex's assertion must FAIL on the defective build.
      # Otherwise it does not test the defect and the fixture is vacuous.
      if [ "$variant" = "naive" ] && [ "$ok" = 1 ] && [ -f "$fixture_dir/assert-after.sh" ]; then
        if (cd "$workdir" \
              && FIXTURE_ID="$id" VARIANT="$variant" ENGINE="$engine" \
                 PDF="$workdir/$variant.pdf" LOG="$workdir/$variant.log" \
                 bash "$fixture_dir/assert-after.sh" >/dev/null 2>&1); then
          echo "FAIL: $id -- VACUOUS ASSERTION. assert-after.sh passes on naive.tex,"
          echo "      so it cannot detect the defect this fixture exists for."
          status=1
        else
          echo "OK: $id mutation check (assert-after.sh correctly rejects naive.tex)"
        fi
      fi

      echo "::endgroup::"
      rm -rf "$workdir"
    done
  done
done

if [ "${#advisory[@]}" -gt 0 ]; then
  echo
  echo "=== Advisory: ${#advisory[@]} fixture(s) whose defect no longer reproduces ==="
  for a in "${advisory[@]}"; do echo "  - $a"; done
  echo "These are candidates for retirement from references/compromises.md."
fi

exit $status
