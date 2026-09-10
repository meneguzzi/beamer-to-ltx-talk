#!/usr/bin/env bash
# The check mark is in the text layer, and nothing was dropped.
. "$ASSERT_LIB"
must_contain "✓"
must_not_be_in_log "Missing character"
