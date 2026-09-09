#!/usr/bin/env bash
# The defect: the braced titles render as body text, nowhere near the header.
. "$ASSERT_LIB"
must_ymin_frac_between Example   0.30 0.70
must_ymin_frac_between Planning  0.30 0.70
