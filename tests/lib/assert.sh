#!/usr/bin/env bash
# Helpers for a fixture's assert-before.sh / assert-after.sh.
#
# Sourced by tests/run_fixtures.sh with the cwd set to the build directory, so
# $PDF and $LOG are already built. Available environment:
#
#   FIXTURE_ID  the fixture directory name, e.g. C-FRAMESUBTITLE
#   VARIANT     before | after
#   ENGINE      the engine that built this PDF
#   PDF         path to the built PDF
#   LOG         path to the engine's .log
#
# Every helper exits non-zero with a message naming the observed value, so a CI
# log says what was measured and not merely that something failed.
set -uo pipefail

fail() { echo "    ASSERT FAIL [$FIXTURE_ID/$VARIANT/$ENGINE]: $*"; exit 1; }
note() { echo "    $*"; }

_text_cache=""
text() {
  if [ -z "$_text_cache" ]; then
    _text_cache=$(pdftotext -q "$PDF" - 2>/dev/null) || fail "pdftotext failed on $PDF"
  fi
  printf '%s' "$_text_cache"
}

# must_contain "Quiz" -- the string appears in the extracted text layer.
#
# Matched with bash's own [[ == *..* ]] rather than a pipe into grep -q. Under
# `set -o pipefail`, grep -q exits as soon as it matches, the writer upstream
# takes SIGPIPE, and the pipeline reports failure even though the match
# succeeded -- intermittently, depending on whether the text fits the pipe
# buffer. No pipeline, no flake.
must_contain() {
  local t; t=$(text)
  [[ "$t" == *"$1"* ]] || fail "expected text layer to contain '$1'; it does not"
}

must_not_contain() {
  local t; t=$(text)
  [[ "$t" != *"$1"* ]] || fail "expected text layer NOT to contain '$1'; it does"
}

pages() { pdfinfo "$PDF" 2>/dev/null | sed -n 's/^Pages: *//p'; }

must_have_pages() {
  local want="$1" got; got=$(pages)
  [ "$got" = "$want" ] || fail "expected $want page(s), got ${got:-none}"
}

must_be_tagged() {
  local info; info=$(pdfinfo "$PDF" 2>/dev/null)
  [[ "$info" == *"Tagged:"*"yes"* ]] || fail "PDF is not tagged"
}

# _count pattern file -- grep -c, but 0 instead of a non-zero exit and an
# empty line. grep -c exits 1 when the count is 0, so a naive
# `grep -c ... || echo 0` emits "0\n0" and every later -eq breaks on it.
_count() { grep -ac "$1" "$2" 2>/dev/null | head -1 || true; }

# log_count 'Missing character' -- occurrences in the engine log.
log_count() { local n; n=$(_count "$1" "$LOG"); echo "${n:-0}"; }

must_not_be_in_log() {
  local n; n=$(log_count "$1")
  [ "${n:-0}" -eq 0 ] || fail "log contains '$1' ($n time(s)); it must not"
}

# xmin_of "word" -- xMin of the first <word> whose text is exactly "word",
# from pdftotext -bbox. Empty if the word is absent.
xmin_of() {
  pdftotext -bbox -q "$PDF" - 2>/dev/null \
    | tr '>' '>\n' \
    | grep -F ">$1" \
    | head -1 \
    | sed -n 's/.*xMin="\([0-9.]*\)".*/\1/p'
}

# ymin_of "word" -- likewise for yMin.
ymin_of() {
  pdftotext -bbox -q "$PDF" - 2>/dev/null \
    | tr '>' '>\n' \
    | grep -F ">$1" \
    | head -1 \
    | sed -n 's/.*yMin="\([0-9.]*\)".*/\1/p'
}

# must_share_xmin tol word1 word2 [word3 ...] -- all named words start at the
# same x within tol points. This is how a lost list indent is detected: the
# items before and after the display no longer line up.
must_share_xmin() {
  local tol="$1"; shift
  local first="" w x
  for w in "$@"; do
    x=$(xmin_of "$w")
    [ -n "$x" ] || fail "word '$w' not found in the text layer"
    if [ -z "$first" ]; then first="$x"; continue; fi
    awk -v a="$first" -v b="$x" -v t="$tol" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<=t)}' \
      || fail "'$w' starts at xMin=$x, expected within $tol of $first"
    note "xMin $w=$x (ref $first)"
  done
}

# must_differ_xmin tol word_ref word_other -- the opposite: used in a
# before.tex assertion to show the defect really is present.
must_differ_xmin() {
  local tol="$1" a b xa xb
  a="$2"; b="$3"
  xa=$(xmin_of "$a"); xb=$(xmin_of "$b")
  [ -n "$xa" ] || fail "word '$a' not found"
  [ -n "$xb" ] || fail "word '$b' not found"
  awk -v a="$xa" -v b="$xb" -v t="$tol" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d>t)}' \
    || fail "'$a' (xMin=$xa) and '$b' (xMin=$xb) differ by <= $tol; the defect did not reproduce"
  note "xMin $a=$xa vs $b=$xb (differ, as the defect requires)"
}

# Vertical placement, for alignment fixtures.
#
# NB pdftotext -bbox measures y from the TOP of the page, not the bottom: a
# larger yMin is LOWER on the slide. (PDF user space itself is the other way up;
# do not carry that intuition into these helpers.)
#
# Prefer must_ymin_frac_* over the absolute forms. Page heights differ between
# classes -- beamer 16:9 is 272.126pt and ltx-talk 283.465pt -- so an absolute
# threshold that holds for after.tex will not hold for the beamer before.tex.
must_ymin_above() {
  local w="$1" lim="$2" y; y=$(ymin_of "$w")
  [ -n "$y" ] || fail "word '$w' not found"
  awk -v y="$y" -v l="$lim" 'BEGIN{exit !(y>l)}' \
    || fail "'$w' has yMin=$y, expected > $lim"
  note "yMin $w=$y (> $lim)"
}

must_ymin_below() {
  local w="$1" lim="$2" y; y=$(ymin_of "$w")
  [ -n "$y" ] || fail "word '$w' not found"
  awk -v y="$y" -v l="$lim" 'BEGIN{exit !(y<l)}' \
    || fail "'$w' has yMin=$y, expected < $lim"
  note "yMin $w=$y (< $lim)"
}

page_height() {
  pdfinfo "$PDF" 2>/dev/null | sed -n 's/^Page size: *[0-9.]* x \([0-9.]*\).*/\1/p'
}

# ymin_frac word -- yMin as a fraction of page height, 0.0 at the top edge and
# 1.0 at the bottom. Comparable across classes and paper sizes.
ymin_frac() {
  local y h; y=$(ymin_of "$1"); h=$(page_height)
  [ -n "$y" ] && [ -n "$h" ] || return 1
  awk -v y="$y" -v h="$h" 'BEGIN{printf "%.3f", y/h}'
}

# must_ymin_frac_between word lo hi -- e.g. 0.70 1.00 for bottom-aligned,
# 0.35 0.60 for centred.
must_ymin_frac_between() {
  local w="$1" lo="$2" hi="$3" f
  f=$(ymin_frac "$w") || fail "word '$w' not found, or no page size"
  awk -v f="$f" -v lo="$lo" -v hi="$hi" 'BEGIN{exit !(f>=lo && f<=hi)}' \
    || fail "'$w' sits at ${f} of page height, expected between $lo and $hi"
  note "yMin($w) = ${f} of page height (want $lo..$hi)"
}

# struct_count '/Figure' -- structure elements of a kind in the tag tree.
struct_count() {
  local q n; q=$(mktemp)
  if ! qpdf --qdf --object-streams=disable "$PDF" "$q" 2>/dev/null; then
    rm -f "$q"; echo 0; return
  fi
  n=$(_count "/S */$1" "$q")
  rm -f "$q"
  echo "${n:-0}"
}

# mathml_count -- MathML payloads in the PDF. Only non-zero once the build has
# converged, so a fixture asserting on this needs PASSES>1 (C-PDFTEX-MATH).
mathml_count() {
  local q n; q=$(mktemp)
  if ! qpdf --qdf --object-streams=disable "$PDF" "$q" 2>/dev/null; then
    rm -f "$q"; echo 0; return
  fi
  n=$(_count '<math' "$q")
  rm -f "$q"
  echo "${n:-0}"
}

must_have_mathml() {
  local n; n=$(mathml_count)
  [ "$n" -ge 1 ] || fail "no MathML payloads in the PDF; maths has no accessible representation under PDF/UA-2"
  note "MathML payloads = $n"
}

must_have_no_mathml() {
  local n; n=$(mathml_count)
  [ "$n" -eq 0 ] || fail "expected no MathML payloads, got $n"
  note "MathML payloads = $n (as the defect requires)"
}

must_have_struct_count() {
  local kind="$1" want="$2" got; got=$(struct_count "$kind")
  [ "$got" = "$want" ] || fail "expected $want /S /$kind element(s), got $got"
  note "/S /$kind = $got"
}
