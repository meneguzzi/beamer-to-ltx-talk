#!/usr/bin/env bash
# C-DISPLAY-IN-CENTER: convert_deck.py must NOT rewrite $$ to \[ inside a center
# environment, because \[ there unbalances tagpdf's paragraph hooks while $$ does
# not. Runs without TeX, so it lives in the syntax-check CI job.
#
# The LaTeX side cannot carry this test: the defect exits 1 under the runner's
# -halt-on-error and emits no PDF, so it cannot be a naive.tex variant. This file
# is therefore the mutation-checkable guard -- see the MUTATION note at the end.
set -u
cd "$(dirname "$0")/.."
OK=0; FAIL=0
ok()   { OK=$((OK+1));   echo "  ok   -- $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL -- $1"; }
holds()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1', want '$2')"; fi; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/in.tex" <<'TEX'
$$ outside = 1 $$
\begin{center}
$$ inside = 2 $$
\end{center}
\begin{center}
\[ already = 3 \]
\end{center}
\begin{center}
\begin{center}
$$ nested = 4 $$
\end{center}
\end{center}
$$ after = 5 $$
\begin{verbatim}
\begin{center}
\end{verbatim}
$$ afterverbatim = 6 $$
\begin{center}
\includegraphics[width=2cm]{x.png}\\[1em]
\end{center}
TEX

out=$(python3 - "$tmp/in.tex" <<'PY'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("cd", "scripts/convert_deck.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
text = open(sys.argv[1]).read()
res = m.rewrite_display_dollar(text)
for i, l in enumerate(res.split('\n'), 1):
    print(f"{i}|{l.strip()}")
print("LINT|" + ",".join(str(f[0]) for f in m.display_in_center_findings(text)))
PY
)
line() { echo "$out" | sed -n "s/^$1|//p"; }

# Outside center: the C-DISPLAY-DOLLAR rewrite must still happen.
holds "$(line 1)"  '\[ outside = 1 \]'        'rewrites $$ outside center'
holds "$(line 13)" '\[ after = 5 \]'          'rewrites $$ after a closed center'
holds "$(line 17)" '\[ afterverbatim = 6 \]'  'a center inside verbatim opens no region'

# Inside center: $$ must survive untouched. This is the defect guard.
holds "$(line 3)"  '$$ inside = 2 $$'         'leaves $$ inside center alone'
holds "$(line 10)" '$$ nested = 4 $$'         'leaves $$ inside a NESTED center alone'

# A display already spelled \[ inside center is a finding, not a rewrite.
holds "$(line 6)"  '\[ already = 3 \]'        'does not touch an existing \[ inside center'
holds "$(line 'LINT')" '6'                    'lints the existing \[ inside center'
# \\[1em] is a line break with a spacing argument, NOT display math. It sits inside
# a center on line 19; the lint must not report it.
holds "$(echo "$out" | grep -c '^19|')" '1'   'fixture really contains the \\[1em] line'

echo
echo "OK=$OK FAIL=$FAIL"
# MUTATION: replace `if centred.get(i):` in rewrite_display_dollar with `if False:`
# and the two "leaves $$ ... alone" assertions must FAIL. Verified 2026-09-11.
[ "$FAIL" -eq 0 ]
