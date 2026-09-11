#!/usr/bin/env bash
# Same claim as assert-before.sh on the converted deck: \uncover<2>{...} hides its argument on
# overlay 1 and nothing else. Measured, lualatex, 70dpi, same band: 0.0387 and 0.0595.
#
# Page count is asserted because it is the invariant of this rewrite -- \uncover reserves the
# space it hides, so the swap must not add or remove a page. It is also the check that sees
# nothing wrong with the defect: naive.tex is 2 pages as well.
. "$ASSERT_LIB"

must_have_pages 2
must_frac_nonwhite_between 1 0.05 0.35 0.75 0.62 0.02 0.15
must_frac_nonwhite_between 2 0.05 0.35 0.75 0.62 0.02 0.15
