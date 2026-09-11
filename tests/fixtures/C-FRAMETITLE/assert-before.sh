#!/usr/bin/env bash
# Both titles sit in the header band. Measured: 0.041 (Beamer), 0.023 (ltx-talk with
# \frametitle). A title that has fallen into the body starts at 0.475 -- see assert-naive.sh.
# One word from each of the two frames, since both forms must convert.
. "$ASSERT_LIB"
must_ymin_frac_between Objectives 0.00 0.06
must_ymin_frac_between Overlay    0.00 0.06
