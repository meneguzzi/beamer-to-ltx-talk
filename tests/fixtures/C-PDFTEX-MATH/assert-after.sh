# Under lualatex the maths text layer is intact and MathML is present.
#
# NB the letters are Unicode mathematical italic here (U+1D44E etc), not ASCII,
# so this asserts on the PUNCTUATION, which is what pdfTeX corrupts. The
# catalogue's own detection grep is the same idea: pdftotext | grep '[a-z]; [a-z]'.
. "$ASSERT_LIB"
must_not_contain ";"     # pdfTeX turns every maths comma into a semicolon
must_not_contain "x:y"   # and every period into a colon
must_be_tagged
[ "$(struct_count 'Formula')" -ge 1 ] || fail "expected at least one /S /Formula"
must_have_mathml         # LuaTeX-only, and only after the build converges
