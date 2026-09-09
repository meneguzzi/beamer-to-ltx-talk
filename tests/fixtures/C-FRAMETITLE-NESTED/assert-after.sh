#!/usr/bin/env bash
# A word from the single and the overlay title must sit in the header band, not the
# body. The double title is not probed: its small-caps half extracts as INFERENCE and,
# in the naive build, fuses with the word before it.
. "$ASSERT_LIB"
must_ymin_frac_between Example   0.00 0.15
must_ymin_frac_between Planning  0.00 0.15
