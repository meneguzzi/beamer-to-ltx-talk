#!/usr/bin/env bash
# The defect: with \usebackgroundtemplate stubbed out, the two pages that should carry the
# background are blank, under white text that is now invisible.
#
# The first three lines are the point of the entry, not padding: they assert that every cheap
# check a build normally offers reports the deck as fine. Page count unchanged, PDF tagged,
# every word still in the text layer -- and the slide renders white on white.
. "$ASSERT_LIB"

must_have_pages 3
must_be_tagged
must_contain "White text over the image"
must_contain "Second overlay, still white"

# 0.0025 and 0.0026 measured: the white text's antialiasing, not content.
must_be_blank 1 0.00 0.00 1.00 1.00
must_be_blank 2 0.00 0.00 1.00 1.00
