#!/usr/bin/env bash
# The slides build of the broken deck is indistinguishable from the fixed one: same page count,
# same text layer, clean compile, Tagged: yes. That is what this file asserts, and it is why the
# fixture needs a second output at all -- everything the suite could check here says "fine".
#
# It is also why there is no assert-after.sh for this output: it would be this same assertion,
# and the mutation check would rightly call it vacuous.
. "$ASSERT_LIB"

must_have_pages 2
must_be_tagged
must_contain "Step one"
must_contain "Step two"
