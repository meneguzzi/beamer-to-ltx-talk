#!/usr/bin/env bash
# The Beamer baseline for the slides build: two overlays, two pages, both steps in the text
# layer. This is the reference the conversion must not change.
. "$ASSERT_LIB"

must_have_pages 2
must_contain "Step one"
must_contain "Step two"
