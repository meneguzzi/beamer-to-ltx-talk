#!/usr/bin/env bash
# Same claim on the converted deck: tcolorbox with a plain mandatory brace argument.
#
# must_not_contain "[" is the whole assertion, and it is enough because nothing in this
# fixture's content contains a bracket -- so a bracket in the text layer can only be the
# literal one tcolorbox prints when a braced title is fed to its key=value argument.
# "Key result]" is checked separately: it is the other half of the same defect, the title text
# left behind in the box body with the wrapper's closing bracket welded to it.
. "$ASSERT_LIB"

must_contain "Key result"
must_contain "Worked example"
must_not_contain "["
must_not_contain "Key result]"
