#!/usr/bin/env bash
# The property the conversion has to preserve: overlay 1 shows the prose. In Beamer
# \onslide<2>{...} takes its argument, hides that argument on overlay 1, and leaves everything
# else alone.
#
# Measured, pdflatex, 70dpi, prose band (0.05,0.35)-(0.75,0.62): overlay 1 = 0.0463,
# overlay 2 = 0.0767 (the revealed line adds to it). The band is generous because Beamer's page
# is 362.8x272.1pt against ltx-talk's 503.9x283.5, so one band has to hold both geometries.
. "$ASSERT_LIB"

must_have_pages 2
must_frac_nonwhite_between 1 0.05 0.35 0.75 0.62 0.02 0.15
must_frac_nonwhite_between 2 0.05 0.35 0.75 0.62 0.02 0.15
