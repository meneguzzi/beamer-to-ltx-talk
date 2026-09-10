#!/usr/bin/env bash
# The defect: the box extracts as the digit 2, and the real character is nowhere.
. "$ASSERT_LIB"
must_contain "A 2 B"
must_not_contain "□"
# And the cheap log grep from C-GLYPH-MISSING is blind to this one, which is why the
# catalogue keeps the two entries apart. If this ever starts warning, say so.
must_not_be_in_log "Missing character"
