#!/usr/bin/env bash
# The check mark is in the text layer, and nothing was dropped.
. "$ASSERT_LIB"
must_contain "✓"
must_not_be_in_log "Missing character"
must_not_fail_ua2 8.4.5.9-1
