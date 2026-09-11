#!/usr/bin/env bash
# Same claim as assert-before.sh, on the converted deck: the shipout/background hook covers
# the frame's pages, and \aftergroup\ltxtalkbgoff ends the scope the way beamer's { ... } did.
# Measured, lualatex, two passes, 70dpi: 1.0000 / 1.0000 / 0.0095, corner 0.0000.
#
# The last line is a second, independent claim from this entry: with \ltxtalkbgartifact the
# background stays out of the structure tree. Re-measured on 0.6.2 by deleting that one macro
# from the shim -- 2 /Figure and 2 /Alt, one per shipped page, /Alt being the FILENAME -- so
# this assertion catches a regression that removes it. naive.tex cannot express that defect
# (it has no background at all), which is why the number is pinned here.
. "$ASSERT_LIB"

must_have_pages 3
must_be_painted 1 0.00 0.00 1.00 1.00
must_be_painted 2 0.00 0.00 1.00 1.00
must_be_blank 3 0.02 0.80 0.20 0.98
must_frac_nonwhite_between 3 0.00 0.00 1.00 1.00 0.00 0.10
must_have_struct_count Figure 0
