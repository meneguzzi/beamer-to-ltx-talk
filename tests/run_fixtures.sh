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
#   EXTRA_OUTPUTS="handout"       # build each variant AGAIN with class options
#   CLASS_OPTIONS_handout="handout"
#
# EXTRA_OUTPUTS exists because for one entry the defect is invisible in the only
# output the suite used to build. C-HANDOUT-MODE is that entry: the slides build
# of the fixed and the broken deck are indistinguishable -- same pages, same text
# -- and the two differ only in the HANDOUT build, where the broken one stacks
# every overlay of a frame onto one page. A suite that builds one output per
# source can only ever report that entry as green.
#
# Each extra output is built with \PassOptionsToClass{<opts>}{<class>} ahead of
# the file, where <class> is read from the source's own \documentclass -- so the
# same key works for a beamer before.tex and an ltx-talk after.tex without the
# fixture naming either. Measured: that injection is byte-for-byte equivalent to
# writing the option into \documentclass[...], under both classes.
#
# Its assertion is a SEPARATE file, assert-<variant>-<output>.sh, and it carries
# the same per-variant meaning and the same mutation check as the default output.
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
  # CLASS_OPTIONS_<name> is named after the output, so the names in scope depend
  # on the previous fixture's conf. Unset them before reading the next one, or a
  # fixture inherits another's options silently.
  for stale in ${EXTRA_OUTPUTS:-}; do unset "CLASS_OPTIONS_$stale"; done
  EXTRA_OUTPUTS=""
  # shellcheck disable=SC1090
  [ -f "$dir/fixture.conf" ] && . "$dir/fixture.conf"

  for variant in before after naive; do
    src="$dir$variant.tex"
    [ -f "$src" ] || continue

    # Per-variant engine list, falling back to the fixture-wide one.
    eval "variant_engines=\${ENGINES_$variant}"
    [ -n "$variant_engines" ] || variant_engines="$ENGINES"

    # One job per (engine, output) pair, so adding extra outputs costs no nesting
    # here. "-" is the default output; an extra output is a name whose class
    # options are CLASS_OPTIONS_<name>.
    jobs=()
    for e in $variant_engines; do
      for o in - $EXTRA_OUTPUTS; do jobs+=("$e $o"); done
    done

    for job in "${jobs[@]}"; do
      read -r engine output <<< "$job"
      class_options=""
      if [ "$output" != - ]; then
        eval "class_options=\${CLASS_OPTIONS_$output:-}"
        if [ -z "$class_options" ]; then
          echo "FAIL: $id declares EXTRA_OUTPUTS=$output with no CLASS_OPTIONS_$output"
          status=1
          continue
        fi
      fi
      # Name the engine whenever the fixture configures engines at all, so a
      # multi-engine fixture's lines are distinguishable in the CI log.
      label="$id/$variant.tex"
      if [ -f "$dir/fixture.conf" ]; then label="$label ($engine)"; fi
      if [ "$output" != - ]; then label="$label [$output]"; fi

      workdir=$(mktemp -d)
      cp "$src" "$workdir/$variant.tex"

      # The class to pass options to is the one the source itself names, so one
      # key covers a beamer before.tex and an ltx-talk after.tex.
      jobarg="$variant.tex"
      if [ -n "$class_options" ]; then
        cls=$(sed -n 's/.*\\documentclass\(\[[^]]*\]\)\{0,1\}{\([^}]*\)}.*/\2/p' "$src" | head -1)
        if [ -z "$cls" ]; then
          echo "FAIL: $label -- cannot find \\documentclass in $src, so [$output] cannot be built"
          status=1
          rm -rf "$workdir"
          continue
        fi
        jobarg="\\PassOptionsToClass{$class_options}{$cls}\\input{$variant.tex}"
      fi

      echo "::group::$label"
      ok=1
      pass=1
      while [ "$pass" -le "$PASSES" ]; do
        if ! (cd "$workdir" && "$engine" -interaction=nonstopmode -halt-on-error "$jobarg" >>build.log 2>&1); then
          echo "FAIL: $label did not compile (pass $pass of $PASSES, $engine)"
          tail -n 60 "$workdir/build.log"
          status=1; ok=0
          break
        fi
        pass=$((pass + 1))
      done

      if [ "$ok" = 1 ] && [ "$variant" = "after" ]; then
        info=$(pdfinfo "$workdir/$variant.pdf" 2>/dev/null)
        if [[ "$info" != *"Tagged:"*"yes"* ]]; then
          echo "FAIL: $label compiled but is not tagged"
          status=1; ok=0
        fi
      fi

      # The fixture's own assertion, if it has one. Each output asserts through
      # its own file: the whole reason an extra output exists is that its claim
      # differs from the default one's.
      suffix=""; [ "$output" = - ] || suffix="-$output"
      assertion="$fixture_dir/assert-$variant$suffix.sh"
      if [ "$ok" = 1 ] && [ -f "$assertion" ]; then
        if (cd "$workdir" \
              && FIXTURE_ID="$id" VARIANT="$variant" ENGINE="$engine" \
                 PDF="$workdir/$variant.pdf" LOG="$workdir/$variant.log" \
                 bash "$assertion"); then
          echo "OK: $label (assertion held)"
        elif [ "$variant" = "naive" ]; then
          echo "ADVISORY: $label -- the defect no longer reproduces under $engine."
          echo "          If ltx-talk fixed it, retire the catalogue entry and delete this"
          echo "          fixture variant (see tests/README.md). Not a build failure."
          advisory+=("$id ($engine)${suffix:+ $output}: defect no longer reproduces")
          # 2. Not a real failure, but the plain OK line below must not print, and
          # the mutation check below must NOT run: with the defect gone,
          # assert-after.sh would pass on naive.tex and be misreported as vacuous.
          ok=0
        else
          echo "FAIL: $label -- the assertion for this fixture no longer holds"
          status=1; ok=0
        fi
      elif [ "$ok" = 1 ]; then
        echo "OK: $label"
      fi

      # Mutation check: after.tex's assertion must FAIL on the defective build.
      # Otherwise it does not test the defect and the fixture is vacuous. Per
      # output, against that output's own after-assertion.
      after_assertion="$fixture_dir/assert-after$suffix.sh"
      if [ "$variant" = "naive" ] && [ "$ok" = 1 ] && [ -f "$after_assertion" ]; then
        if (cd "$workdir" \
              && FIXTURE_ID="$id" VARIANT="$variant" ENGINE="$engine" \
                 PDF="$workdir/$variant.pdf" LOG="$workdir/$variant.log" \
                 bash "$after_assertion" >/dev/null 2>&1); then
          echo "FAIL: $id -- VACUOUS ASSERTION. assert-after$suffix.sh passes on naive.tex,"
          echo "      so it cannot detect the defect this fixture exists for."
          status=1
        else
          echo "OK: $id mutation check${suffix:+ [$output]} (assert-after$suffix.sh correctly rejects naive.tex)"
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
