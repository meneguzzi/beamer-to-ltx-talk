#!/usr/bin/env bash
# The property the conversion has to preserve: the background image covers the whole of the
# frame it is scoped to, and does not touch the page after the group. Beamer's { ... } group
# is what ends the template, and the conversion has to end it too.
#
# Measured, pdflatex, two passes, 70dpi: pages 1-2 are 1.0000 non-white edge to edge; page 3
# is 0.0124 over the whole page (its own two lines of text) and 0.0000 in the bottom-left
# corner. A leaked background would put page 3 at ~1.0 and the corner at ~1.0.
. "$ASSERT_LIB"

must_have_pages 3
must_be_painted 1 0.00 0.00 1.00 1.00
must_be_painted 2 0.00 0.00 1.00 1.00
# The scope. The corner is the crisp claim -- no text ever reaches it -- and the whole-page
# band catches a background that is painted but somehow clipped away from the corner.
must_be_blank 3 0.02 0.80 0.20 0.98
must_frac_nonwhite_between 3 0.00 0.00 1.00 1.00 0.00 0.10
