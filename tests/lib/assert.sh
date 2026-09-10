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

# _word_line "word" -- the pdftotext -bbox <word> element whose text is EXACTLY
# "word" (first occurrence). pdftotext emits one <word ...>text</word> per line,
# so this is a line match. The closing tag is part of the pattern on purpose:
# matching ">word" alone is a prefix match, and `xmin_of a` would silently
# return the position of "agent".
_word_line() {
  pdftotext -bbox -q "$PDF" - 2>/dev/null | grep -F -m1 -- ">$1</word>"
}

# xmin_of "word" -- xMin of that word. Empty if the word is absent.
xmin_of() { _word_line "$1" | sed -n 's/.*xMin="\([0-9.]*\)".*/\1/p'; }

# ymin_of "word" -- likewise for yMin.
ymin_of() { _word_line "$1" | sed -n 's/.*yMin="\([0-9.]*\)".*/\1/p'; }

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

# --- PDF/UA-2 validation (veraPDF) -------------------------------------------
#
# Two of the font-level defects in the catalogue have NO cheap signal:
# C-SYMBOL-FONT-TOUNICODE compiles clean, is tagged, logs nothing, and is only
# visible to a real validator. So these helpers call verapdf.
#
# They assert on a NAMED CLAUSE, never on overall PASS/FAIL. The fixtures are
# minimal decks with no \title, so every one of them fails 8.11.1-1 (the XMP
# metadata clause) on its own account. Asserting "passes ua2" would therefore be
# false for all of them, and asserting "fails ua2" would be true for the wrong
# reason. A clause is the only claim that isolates the defect.
#
# If verapdf is not installed the helpers NOTE and pass, so a contributor
# without it still gets a green suite. CI must not rely on that: the workflow
# installs verapdf and checks it is on PATH, so a broken install fails loudly
# there rather than silently skipping these assertions.

# ua2_clauses -- failing clause ids for $PDF, space separated, e.g. "8.11.1-1".
#
# NB: verapdf exits 1 for a NON-COMPLIANT file, which is the normal case here and
# not an error. Only a missing or unparseable report means the run failed. An
# earlier version of this treated exit 1 as "could not run" and returned no
# clauses at all, which made must_not_fail_ua2 pass vacuously for every fixture.
ua2_clauses() {
  local x; x=$(mktemp)
  verapdf -f ua2 --format xml "$PDF" > "$x" 2>/dev/null
  if [ ! -s "$x" ] || ! grep -q '<report' "$x"; then
    rm -f "$x"; echo "VERAPDF-DID-NOT-RUN"; return
  fi
  python3 - "$x" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8', errors='replace').read()
out = []
for m in re.finditer(r'<rule\b[^>]*>', s):
    tag = m.group(0)
    cl = re.search(r'clause="([^"]+)"', tag)
    tn = re.search(r'testNumber="(\d+)"', tag)
    fc = re.search(r'failedChecks="(\d+)"', tag)
    st = re.search(r'status="([A-Z]+)"', tag)
    if cl and tn and ((fc and fc.group(1) != '0') or (st and st.group(1) == 'FAILED')):
        out.append(f"{cl.group(1)}-{tn.group(1)}")
print(' '.join(sorted(set(out))))
PY
  rm -f "$x"
}

_ua2_skip() {
  command -v verapdf >/dev/null 2>&1 && return 1
  note "verapdf not installed; skipping the PDF/UA-2 clause check"
  return 0
}

# must_fail_ua2 8.4.5.8-1 -- the defect must be visible to a real validator.
must_fail_ua2() {
  _ua2_skip && return 0
  local want="$1" got; got=$(ua2_clauses)
  [ "$got" = "VERAPDF-DID-NOT-RUN" ] && fail "verapdf produced no report for $PDF"
  case " $got " in
    *" $want "*) note "veraPDF ua2 fails $want, as the defect requires (all: ${got:-none})" ;;
    *) fail "expected veraPDF -f ua2 to fail clause $want; failing clauses were: ${got:-none}" ;;
  esac
}

# must_not_fail_ua2 8.4.5.8-1 -- the workaround must clear that clause. Says
# nothing about any other clause, deliberately: see the note above.
must_not_fail_ua2() {
  _ua2_skip && return 0
  local want="$1" got; got=$(ua2_clauses)
  [ "$got" = "VERAPDF-DID-NOT-RUN" ] && fail "verapdf produced no report for $PDF"
  case " $got " in
    *" $want "*) fail "veraPDF -f ua2 still fails clause $want; failing clauses: $got" ;;
    *) note "veraPDF ua2 does not fail $want (other clauses: ${got:-none})" ;;
  esac
}

# --- Rendered pixels (pdftoppm) ----------------------------------------------
#
# The text layer, the log and the structure tree can all be correct while the
# page renders wrong. C-BACKGROUND is the case that forced this: stub out
# \usebackgroundtemplate and the frame compiles, is tagged, has the right page
# count and extracts the right words -- as white text on a white page. These
# helpers render the page with pdftoppm and measure it.
#
# pdftoppm is not a new dependency and needs no new CI install step: it is part
# of poppler-utils, which the suite already requires for pdfinfo and pdftotext,
# and SKILL.md Step 4 already tells a human to eyeball a page with it. There are
# deliberately NO stored reference images -- a committed PNG rots on the first
# ltx-talk font or spacing change and tells nobody why. Every claim here is a
# measurement with a stated tolerance instead.
#
# Regions are FRACTIONS of page width/height, y from the TOP, as in
# pdftotext -bbox and hence must_ymin_frac_between.
#
# Resolution is deliberately low (PIXEL_DPI, default 70, as in SKILL.md Step 4).
# These assertions measure whether a region is painted at all, not typography,
# and pixelprobe.py sums in pure Python: a full page at 70dpi is ~0.5M pixels
# and about a second, at 300dpi it is twenty times that.

PIXEL_DPI="${PIXEL_DPI:-70}"

# render_page N -- path to page N as a PPM, rendered once per (page, dpi).
render_page() {
  local page="$1" out=".probe-p$1-$PIXEL_DPI"
  if [ ! -s "$out.ppm" ]; then
    pdftoppm -f "$page" -l "$page" -r "$PIXEL_DPI" -singlefile "$PDF" "$out" \
      2>/dev/null || fail "pdftoppm failed to render page $page of $PDF"
    [ -s "$out.ppm" ] || fail "pdftoppm produced no raster for page $page of $PDF (does it exist?)"
  fi
  echo "$out.ppm"
}

_probe() {
  local ppm; ppm=$(render_page "$1"); shift
  python3 "$(dirname "$ASSERT_LIB")/pixelprobe.py" "$ppm" "$@" \
    || fail "pixelprobe.py $* failed on $ppm"
}

# pixel_at PAGE X Y -- "R G B" at that point.
pixel_at() { _probe "$1" pixel "$2" "$3"; }

# region_mean PAGE X0 Y0 X1 Y1 -- "R G B" mean over the region.
region_mean() { _probe "$1" mean "$2" "$3" "$4" "$5"; }

# frac_nonwhite PAGE X0 Y0 X1 Y1 -- fraction of the region's pixels that are
# not near-white, 0.0000 to 1.0000.
frac_nonwhite() { _probe "$1" nonwhite "$2" "$3" "$4" "$5"; }

# must_frac_nonwhite_between PAGE X0 Y0 X1 Y1 LO HI -- the primitive. Both
# bounds are inclusive; the measured value is always reported.
must_frac_nonwhite_between() {
  local page="$1" got lo="$6" hi="$7"
  got=$(frac_nonwhite "$1" "$2" "$3" "$4" "$5")
  python3 -c "import sys; sys.exit(0 if $lo <= $got <= $hi else 1)" \
    || fail "page $page region ($2,$3)-($4,$5) is $got non-white, expected $lo..$hi"
  note "page $page region ($2,$3)-($4,$5): $got non-white (wanted $lo..$hi)"
}

# must_be_blank PAGE X0 Y0 X1 Y1 -- nothing is drawn there. The 2% allowance is
# for antialiased ink bleeding in from just outside the region, not for content.
must_be_blank() { must_frac_nonwhite_between "$1" "$2" "$3" "$4" "$5" 0.00 0.02; }

# must_be_painted PAGE X0 Y0 X1 Y1 -- the region is essentially all ink, which
# is what a full-bleed background or a filled block looks like. NOT for text:
# a region of prose is mostly white paper, so measure that with
# must_frac_nonwhite_between and a band you have actually observed.
must_be_painted() { must_frac_nonwhite_between "$1" "$2" "$3" "$4" "$5" 0.90 1.00; }
