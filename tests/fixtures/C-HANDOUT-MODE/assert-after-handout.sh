#!/usr/bin/env bash
# The workaround's claim, and the only place the two decks differ: the handout shows the final
# step and nothing else. Matched handout:0 / handout:1 pairs, measured 1 page, "Step two".
#
# must_not_contain "Step one" is the assertion that bites. Marking only the overlays to DROP
# (handout:0 with no matching handout:1) produces a blank frame instead, which would fail the
# must_contain below -- silently worse than doing nothing, so both halves are asserted.
. "$ASSERT_LIB"

must_have_pages 1
must_contain "Step two"
must_not_contain "Step one"
