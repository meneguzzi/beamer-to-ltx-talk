#!/usr/bin/env bash
# Compiles every tests/fixtures/<ID>/{before,after}.tex and checks:
#   - before.tex (plain Beamer) and after.tex (ltx-talk) both compile clean
#   - after.tex's PDF is tagged (pdfinfo reports "Tagged: yes")
# Needs a real TeX Live with ltx-talk (see .github/workflows/ci.yml, job
# latex-fixtures, which runs this inside the texlive/texlive container) and
# poppler-utils for pdfinfo. Not shipped with the skill -- see tests/README.md.
set -uo pipefail

cd "$(dirname "$0")/fixtures"
status=0

for dir in */; do
  id="${dir%/}"
  for variant in before after; do
    src="$dir$variant.tex"
    [ -f "$src" ] || continue

    workdir=$(mktemp -d)
    cp "$src" "$workdir/$variant.tex"

    echo "::group::$id/$variant.tex"
    if ! (cd "$workdir" && pdflatex -interaction=nonstopmode -halt-on-error "$variant.tex" >build.log 2>&1); then
      echo "FAIL: $id/$variant.tex did not compile"
      tail -n 60 "$workdir/build.log"
      status=1
    elif [ "$variant" = "after" ] && ! pdfinfo "$workdir/$variant.pdf" 2>/dev/null | grep -q "^Tagged: *yes"; then
      echo "FAIL: $id/after.tex compiled but is not tagged"
      status=1
    else
      echo "OK: $id/$variant.tex"
    fi
    echo "::endgroup::"
    rm -rf "$workdir"
  done
done

exit $status
