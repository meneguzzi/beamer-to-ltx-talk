#!/usr/bin/env bash
# The defect: the braced group is not a title, so its text renders as body text and the
# header bar is empty. Measured at 0.475 of page height -- the very line "Body text." is on.
#
# Same assertion shape as C-FRAMETITLE-NESTED, deliberately: that entry is about
# convert_deck.py's regex missing nested braces, this one is about what ltx-talk does with a
# braced group at all. Different causes, same observable.
. "$ASSERT_LIB"
must_ymin_frac_between Objectives 0.30 0.70
must_ymin_frac_between Overlay    0.30 0.70
