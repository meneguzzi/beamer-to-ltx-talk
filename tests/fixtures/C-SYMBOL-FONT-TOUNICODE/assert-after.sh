#!/usr/bin/env bash
# The symbol reaches the text layer as itself, not as some other character.
. "$ASSERT_LIB"
must_contain "□"
must_not_contain "A 2 B"
