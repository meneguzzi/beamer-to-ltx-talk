#!/usr/bin/env bash
# The defect: title={[} on both boxes, with the real title text left in the body.
#
# The first two lines are the point of the entry: the page count is right, the PDF is tagged,
# and both title strings are still in the text layer -- so a grep for the title finds it and
# reports the slide as fine. Only where the title sits has changed.
. "$ASSERT_LIB"

must_have_pages 1
must_be_tagged
must_contain "["
must_contain "Key result]"
must_contain "Worked example]"
