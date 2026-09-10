#!/usr/bin/env bash
# The symbol reaches the text layer as itself, not as some other character.
. "$ASSERT_LIB"
must_contain "⇝"
must_not_contain "A ; B"
must_not_fail_ua2 8.4.5.8-1
