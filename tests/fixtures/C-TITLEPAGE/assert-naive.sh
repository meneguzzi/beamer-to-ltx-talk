#!/usr/bin/env bash
# THE DEFECT: the hand-rolled title frame, with the beamer folded subtitle left in \title.
# It compiles clean, is Tagged: yes, has the right page count and looks right on screen.
# Nothing about the build says otherwise -- which is why this fixture exists.
#
# Measured, lualatex, two passes:
#   * /S /H1 = 0, and /S /Title = 0 too. Nothing tags plain text in a frame, so the deck has
#     no title heading. A-HEADINGS had to hand-write one back for exactly this shape.
#   * dc:title = "Constraint Satisfaction and SearchBacktracking and arc consistency". Two
#     defects in one string: the \title text has drifted from the title page's own text
#     (nothing renders \title, so nothing compares them), and the folded subtitle is
#     concatenated into it with the \\ dropped.
. "$ASSERT_LIB"

must_have_pages 2
must_be_tagged
must_have_struct_count H1 0
must_have_struct_count Title 0
must_have_dc_title "Constraint Satisfaction and SearchBacktracking and arc consistency"
must_contain "Material adapted from"
