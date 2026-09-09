# The reference: pdfTeX extracts this maths correctly under beamer, commas and
# all. So naive.tex's corruption arrives with the ltx-talk class, not with the
# engine alone -- without this variant the fixture would look like a pdfTeX bug.
. "$ASSERT_LIB"
must_contain "a, b, c"
must_not_contain "a; b; c"
