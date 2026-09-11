#!/usr/bin/env bash
# The property the conversion has to preserve: each box's title is its title. Beamer's native
# alertblock/exampleblock print it in the title bar and nowhere else, so no bracket appears
# anywhere on the slide.
. "$ASSERT_LIB"

must_contain "Key result"
must_contain "Worked example"
must_not_contain "["
