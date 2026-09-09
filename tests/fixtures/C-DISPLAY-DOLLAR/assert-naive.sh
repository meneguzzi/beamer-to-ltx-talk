# The defect: items after a $$...$$ display lose the itemize indent and render
# flush with the frame margin. Item 1 (before the display) keeps its indent, so
# the list visibly splits in two.
#
# A failure means ltx-talk no longer outdents after $$ -- retire the entry.
. "$ASSERT_LIB"
must_differ_xmin 10.0 A The          # item 1 vs item 2: the split
must_differ_xmin 10.0 A Preferences  # and item 3 stays out too
