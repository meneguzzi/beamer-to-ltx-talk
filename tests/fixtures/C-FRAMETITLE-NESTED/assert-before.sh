#!/usr/bin/env bash
# A word from the single and the overlay title must sit in the header band (measured
# 0.017 Beamer, 0.023 ltx-talk; a title fallen into a top-aligned body starts at 0.11), not the
# body. The double title is not probed: its small-caps half extracts as INFERENCE and,
# in the naive build, fuses with the word before it.
. "$ASSERT_LIB"
must_ymin_frac_between Example   0.00 0.06
must_ymin_frac_between Planning  0.00 0.06
