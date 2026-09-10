#!/usr/bin/env bash
# The defect: \leadsto extracts as ";" and the real character is nowhere.
. "$ASSERT_LIB"
must_contain "A ; B"
must_not_contain "⇝"
# The cheap log grep from C-GLYPH-MISSING is blind to this one, which is why the catalogue
# keeps the two entries apart. If this ever starts warning, say so.
must_not_be_in_log "Missing character"
must_fail_ua2 8.4.5.8-1
