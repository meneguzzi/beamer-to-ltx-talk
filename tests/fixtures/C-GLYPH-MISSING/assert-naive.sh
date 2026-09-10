#!/usr/bin/env bash
# The defect: the glyph is gone. The log says so, and the text layer has U+FFFD instead.
. "$ASSERT_LIB"
must_not_contain "✓"
[ "$(log_count 'Missing character')" -ge 1 ] \
  || fail "expected at least one 'Missing character' in the log; found none"
