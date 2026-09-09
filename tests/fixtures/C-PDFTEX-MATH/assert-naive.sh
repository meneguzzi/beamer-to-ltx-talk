# The defect, asserted so the assertion on after.tex is not vacuous: under
# pdflatex ltx-talk falls back to sansmathfonts and the maths text layer is
# corrupt -- commas become semicolons, periods colons -- with no MathML at all.
#
# A failure means ltx-talk fixed the pdfTeX font path. Advisory, not a build
# failure: retire the entry.
. "$ASSERT_LIB"
must_contain ";"         # a, b, c -> a; b; c
must_contain "x:y"       # x.y -> x:y
must_have_no_mathml
