#!/usr/bin/env bash
# scripts/stamp_conversion.py writes the provenance record a converted course carries
# (#51, first half of #12). It is the only thing that will ever say which ltx-talk and
# which converter a repo was built against, so it has to be right on the day and honest
# when it cannot tell.
#
# Pure source-level: no LaTeX, no PDF. Runs in the syntax-check CI job.
#
# Every positive claim is paired with an inverted one. A test that only checks the happy
# path would pass just as well against a script that wrote a fixed string.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
stamp="$repo/scripts/stamp_conversion.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()   { echo "OK: $*"; pass=$((pass + 1)); }
bad()  { echo "FAIL: $*"; fail=$((fail + 1)); }

holds()   { if eval "$1"; then ok "$2"; else bad "$2"; fi; }
rejects() { if eval "$1"; then bad "$2 -- the inverted claim held, so the check proves nothing"; else ok "$2"; fi; }

# key_in FILE SECTION KEY -- the value of KEY inside [SECTION], empty if absent.
# Needed because several keys share a name across sections: `version` appears under
# both [ltx_talk] and [skill], and a bare `grep '^version ='` matched the wrong one,
# which made the TeX-free branch of this suite pass for the wrong reason.
key_in() {
  awk -v sect="[$2]" -v key="$3" '
    $0 == sect { in_s = 1; next }
    /^\[/     { in_s = 0 }
    in_s && $0 ~ "^" key " = " { sub("^" key " = ", ""); gsub(/^"|"$/, ""); print; exit }
  ' "$1"
}

# --- a course whose \DocumentMetadata is in a shared file, with a commented-out variant
# --- carrying an UNBALANCED brace. That shape is not invented: it is what a real course
# --- ships, because the pre-tagging block is kept around commented out.
course="$tmp/course"
mkdir -p "$course/day01"
cat > "$course/tag-commands.tex" <<'EOF'
\DocumentMetadata{
	lang=en-GB,
	pdfstandard={a-4,ua-2},
%	An older setting, kept for reference. Note the unbalanced brace: testphase={
%	lang=en,
	tagging=on,
}
% A commented-out variant BELOW the live one, so a finder that takes the last
% match rather than the first would pick the wrong block up.
% \DocumentMetadata{ lang=en-XX }
EOF
cat > "$course/day01/deck.tex" <<'EOF'
\input{../tag-commands.tex}
\documentclass{ltx-talk}
\begin{document}\begin{frame}x\end{frame}\end{document}
EOF

out="$tmp/out.toml"
python3 "$stamp" "$course" >"$tmp/stamp.err" 2>&1
st="$course/ltx-talk-conversion.toml"

holds   "[ -f '$st' ]"                              "writes ltx-talk-conversion.toml at the course root"
rejects "[ -f '$course/.ltx-talk-conversion.toml' ]" "does not write a HIDDEN file -- discoverability is the point"
rejects "grep -rq 'ltx-talk-conversion' '$course/day01/deck.tex'" "does not touch the deck sources"

# The brace matcher must stop at the real closing brace, not run on to the end of file.
holds   "grep -q 'tagging=on' '$st'"                "records the \\DocumentMetadata actually in force"
rejects "grep -q 'lang=en,' '$st'"                  "does not pick up the COMMENTED-OUT metadata block"
rejects "grep -qi 'testphase' '$st'"                "an unbalanced brace INSIDE a comment in the block does not run the matcher off the end"
rejects "grep -q 'en-XX' '$st'"                    "a commented-out block below the live one is not picked up"
holds   "grep -q 'documentmetadata_source = \"tag-commands.tex\"' '$st'" \
        "names the file the metadata came from, not the deck"

# Provenance proper. This suite runs in the syntax-check CI job, which has NO TeX at
# all, so the happy path and the degradation path are both real and both get asserted --
# whichever applies here. A test that silently skipped when TeX was missing would make
# the syntax-check run of this file prove nothing.
if kpsewhich ltx-talk.cls >/dev/null 2>&1; then
  holds   "key_in '$st' ltx_talk version | grep -qE '^[0-9]+\\.[0-9]+'" \
          "records an ltx-talk version when the class is installed"
  rejects "grep -q 'ltx_talk.version' '$st'"        "and does not also list it as undeterminable"
else
  echo "  (no ltx-talk.cls on this runner -- asserting the degradation path instead)"
  holds   "grep -q 'ltx_talk.version' '$st'"        "names ltx-talk.version in [unknown] when the class is not installed"
  rejects "[ -n \"\$(key_in '$st' ltx_talk version)\" ]" "and does not invent a version"
fi
holds   "[ -n \"\$(key_in '$st' skill version)\" ]" "always records which converter ran -- the one fact nothing else can supply"
rejects "grep -qi 'cat-version' '$st'"              "does not record tlmgr's cat-version, which lags the installed class"
holds   "grep -q 'schema = 1' '$st'"                "declares a schema version, so a reader can tell what it is looking at"
holds   "grep -q '\\[unknown\\]' '$st'"             "always emits an [unknown] table, even when empty"

# ⚠ A committed file must not carry the converting machine's layout.
rejects "grep -qE '/(usr|home|Users|private|tmp)/' '$st'" \
        "records no absolute filesystem paths"

# --- honest degradation: a course with no \DocumentMetadata at all
bare="$tmp/bare"; mkdir -p "$bare"
echo '\documentclass{ltx-talk}' > "$bare/deck.tex"
python3 "$stamp" "$bare" >/dev/null 2>&1
bst="$bare/ltx-talk-conversion.toml"
holds   "grep -q 'conversion.documentmetadata' '$bst'" \
        "an undeterminable value is NAMED in [unknown], not silently omitted"
rejects "grep -qE '^documentmetadata = ' '$bst'" \
        "and is not invented as a default"

# --- re-running is safe and reports what moved
before=$(grep -c 'superseded' "$st" || true)
python3 "$stamp" "$course" >/dev/null 2>&1
holds   "[ \$(grep -c '^schema = ' '$st') -eq 1 ]"  "re-stamping updates in place rather than appending a second document"
holds   "grep -q 'superseded' '$st'"                "re-stamping keeps the previous stamp"
rejects "[ '$before' != '0' ]"                      "the first stamp had no superseded block"

# --- dry run writes nothing
dry="$tmp/dry"; mkdir -p "$dry"; echo '\documentclass{ltx-talk}' > "$dry/d.tex"
python3 "$stamp" "$dry" --dry-run >"$tmp/dry.out" 2>/dev/null
rejects "[ -f '$dry/ltx-talk-conversion.toml' ]"    "--dry-run writes no file"
holds   "grep -q 'schema = 1' '$tmp/dry.out'"       "--dry-run prints the stamp to stdout"

echo
echo "=== stamp_conversion self-test: $pass OK, $fail FAIL ==="
[ "$fail" -eq 0 ]
