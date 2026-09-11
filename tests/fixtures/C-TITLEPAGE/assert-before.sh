#!/usr/bin/env bash
# The beamer original, and the property the conversion has to preserve: the title at the top,
# the institute below it, and the attribution clear below that -- a title frame whose trailing
# centred block does NOT collide with \maketitle.
#
# This is also what retired the original C-TITLEPAGE symptom. The same construct, converted
# with nothing worked around (after.tex), behaves the same way on ltx-talk 0.6.2.
#
# Measured, pdflatex, two passes (page height 272.126pt, beamer 16:9): title yMin 72.26
# (0.266 of the page), institute 164.40 (0.604), attribution 198.02 (0.728). Fractions, not
# points -- before.tex is beamer at 272.126pt and after.tex is ltx-talk at 283.465pt.
. "$ASSERT_LIB"

must_have_pages 1
must_ymin_frac_between Constraint 0.15 0.35
must_ymin_frac_between University 0.50 0.65
must_ymin_frac_between Material   0.65 0.85
