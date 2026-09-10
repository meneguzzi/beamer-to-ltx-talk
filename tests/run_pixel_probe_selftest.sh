#!/usr/bin/env bash
# Proves the pixel probe (tests/lib/pixelprobe.py plus the render/measure
# helpers in tests/lib/assert.sh) measures what it claims, and FAILS when the
# claim is false.
#
# This exists because of #18. The fixture assertions added there were written,
# passed, and were trusted -- and some of them could not have failed. An
# assertion that cannot fail is worse than no assertion: it reports a defect as
# fixed. So before any fixture depends on the probe, the probe is shown to bite:
# every positive check below is paired with the inverted claim, which must be
# REJECTED.
#
# Two arms:
#
#   parser    synthetic Netpbm rasters with known contents. No LaTeX, no
#             poppler; exact expected values, so a wrong answer is visible as a
#             wrong number rather than as a tolerance judgement.
#   rendered  end to end: lualatex -> pdftoppm -> the assert.sh helpers, on a
#             two-page deck whose page 1 is painted edge to edge and whose page
#             2 is blank. Skipped where lualatex or pdftoppm is absent, which is
#             why the parser arm does not depend on them.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
probe="$here/lib/pixelprobe.py"
status=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass() { echo "OK: $*"; }
bad()  { echo "FAIL: $*"; status=1; }

# --- arm 1: the parser and the measurements ----------------------------------

# Three rasters, each with contents chosen so every measurement below has one
# exact right answer:
#   halves.ppm  P6, left half black / right half white
#   topbot.ppm  P6, top half black / bottom half white -- pins y-from-the-top
#   ramp.pgm    P5 grey, one column per value 248..251 -- pins the white cutoff
python3 - "$work" <<'PY'
import sys
d = sys.argv[1]
W, H = 100, 50
with open(f"{d}/halves.ppm", "wb") as f:
    f.write(b"P6\n%d %d\n255\n" % (W, H))
    f.write(bytes([0, 0, 0] * (W // 2) + [255, 255, 255] * (W // 2)) * H)
with open(f"{d}/topbot.ppm", "wb") as f:
    f.write(b"P6\n# a comment, legal anywhere in the header\n%d %d\n255\n" % (W, H))
    f.write(bytes([0, 0, 0] * W) * (H // 2) + bytes([255, 255, 255] * W) * (H // 2))
with open(f"{d}/ramp.pgm", "wb") as f:
    f.write(b"P5\n4 1\n255\n")
    f.write(bytes([248, 249, 250, 251]))
PY

check() {  # check <label> <expected> <args...>
  local label="$1" want="$2"; shift 2
  local got; got=$(python3 "$probe" "$@" 2>&1)
  if [ "$got" = "$want" ]; then pass "$label = $got"
  else bad "$label: expected '$want', got '$got'"; fi
}

check "black pixel"            "0 0 0"           "$work/halves.ppm" pixel 0.1 0.5
check "white pixel"            "255 255 255"     "$work/halves.ppm" pixel 0.9 0.5
check "mean of half and half"  "127.5 127.5 127.5" "$work/halves.ppm" mean 0 0 1 1
check "non-white, whole page"  "0.5000"          "$work/halves.ppm" nonwhite 0 0 1 1
check "non-white, black half"  "1.0000"          "$work/halves.ppm" nonwhite 0 0 0.5 1
check "non-white, white half"  "0.0000"          "$work/halves.ppm" nonwhite 0.5 0 1 1
# y from the TOP: the black band is the top half, as pdftotext -bbox reports it.
check "top band is ink"        "1.0000"          "$work/topbot.ppm" nonwhite 0 0 1 0.5
check "bottom band is paper"   "0.0000"          "$work/topbot.ppm" nonwhite 0 0.5 1 1
check "P5 grey is read"        "249.5 249.5 249.5" "$work/ramp.pgm" mean 0 0 1 1
# The cutoff: 248 and 249 are ink, 250 and 251 are paper, so exactly half.
check "white cutoff at 250"    "0.5000"          "$work/ramp.pgm" nonwhite 0 0 1 1

# A zero-height region must still measure one row rather than divide by zero:
# a fixture asking about a hairline is a bug in the fixture, not a crash here.
check "degenerate region"      "0.0000"          "$work/halves.ppm" nonwhite 0.6 0.5 0.6 0.5

# And the parser must refuse what it cannot handle rather than answer wrongly.
refuse() {  # refuse <label> <args...>
  local label="$1"; shift
  if python3 "$probe" "$@" >/dev/null 2>&1; then
    bad "$label: pixelprobe.py accepted input it cannot measure"
  else pass "$label rejected"; fi
}
printf 'not a raster at all' > "$work/bogus.ppm"
refuse "a non-Netpbm file"   "$work/bogus.ppm" nonwhite 0 0 1 1
refuse "an out-of-range region" "$work/halves.ppm" nonwhite 0 0 1.5 1
refuse "a reversed region"      "$work/halves.ppm" nonwhite 0.8 0 0.2 1
refuse "an unknown operation"   "$work/halves.ppm" hue 0 0 1 1

# --- arm 2: render a real PDF and check the helpers bite ----------------------

if ! command -v lualatex >/dev/null 2>&1 || ! command -v pdftoppm >/dev/null 2>&1; then
  echo "NOTE: skipping the rendered arm (needs lualatex and pdftoppm); the parser arm ran."
  exit $status
fi

# Page 1 is painted edge to edge, page 2 is not painted at all. The background
# hook and the \put offset are the C-BACKGROUND recipe verbatim, so this also
# checks the probe against the very construct the first fixture will use it on.
cat > "$work/probe.tex" <<'TEX'
% \DocumentMetadata is not optional: ltx-talk \NeedsDocumentMetadata and stops
% with "This file needs \DocumentMetadata" without it.
\DocumentMetadata{lang=en, pdfversion=2.0, pdfstandard={a-4,ua-2}, tagging=on}
\documentclass{ltx-talk}
\begin{document}
\AddToHookNext{shipout/background}{\put(0cm,-\paperheight){\rule{\paperwidth}{\paperheight}}}
\begin{frame}
\end{frame}
\begin{frame}
\end{frame}
\end{document}
TEX
if ! (cd "$work" && lualatex -interaction=nonstopmode -halt-on-error probe.tex > probe.build.log 2>&1); then
  bad "the self-test deck did not compile"
  tail -n 40 "$work/probe.build.log"
  exit 1
fi

export ASSERT_LIB="$here/lib/assert.sh"
# holds/rejects run each assertion in a subshell: the helpers exit non-zero on
# failure, and a rejection is the expected outcome for half of these.
run_assert() {
  local claim="$1"
  ( cd "$work" \
    && FIXTURE_ID="PIXEL-PROBE-SELFTEST" VARIANT="probe" ENGINE="lualatex" \
       PDF="$work/probe.pdf" LOG="$work/probe.log" \
       bash -c "source '$ASSERT_LIB'; $claim" )
}
holds()   { if run_assert "$1"; then pass "held: $1"; else bad "should have held: $1"; fi; }
rejects() {
  if run_assert "$1" >/dev/null 2>&1; then
    bad "VACUOUS: '$1' passed on a page where it is false -- the probe does not bite"
  else pass "rejected, as it must: $1"; fi
}

holds   "must_be_painted 1 0.00 0.00 1.00 1.00"
rejects "must_be_blank   1 0.00 0.00 1.00 1.00"
# Page 2 measures 0.0000 non-white across the WHOLE page on ltx-talk 0.6.2: an
# empty frame draws no header or footer furniture. Blankness is still claimed
# for the body region only, so the check keeps its meaning if the class starts
# drawing a footer; the whole-page fraction is reported below either way.
holds   "must_be_blank   2 0.10 0.30 0.90 0.70"
rejects "must_be_painted 2 0.10 0.30 0.90 0.70"
# Region arithmetic: the bottom-left quarter of the painted page is painted too.
holds   "must_be_painted 1 0.00 0.50 0.50 1.00"
# A page that does not exist must fail loudly rather than measure nothing.
rejects "must_be_blank   9 0.10 0.30 0.90 0.70"
# The measurement itself, reported so a change in ltx-talk's furniture is
# visible in the CI log rather than only in a tolerance failure.
echo "    page 2 body non-white fraction: $(run_assert 'frac_nonwhite 2 0.10 0.30 0.90 0.70')"
echo "    page 2 whole-page non-white fraction: $(run_assert 'frac_nonwhite 2 0 0 1 1')"

exit $status
