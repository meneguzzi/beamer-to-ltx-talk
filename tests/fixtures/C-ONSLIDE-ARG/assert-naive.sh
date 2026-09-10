#!/usr/bin/env bash
# The defect: the \onslide<2> declaration blanks the rest of the frame, so overlay 1 is empty
# and the prose that must always be visible is gone with it.
#
# The first three lines assert that every cheap check reports the deck as fine: page count
# unchanged, and both lines of text still in the text layer -- including the one that renders
# nowhere. The text layer of this file and of after.tex are byte-identical.
. "$ASSERT_LIB"

must_have_pages 2
must_contain "Prose that must stay visible on every overlay"
must_contain "Revealed on the second overlay"

# 0.0000 measured: overlay 1 is not merely dimmed, it is empty.
must_be_blank 1 0.05 0.35 0.75 0.62
# Overlay 2 is exactly what the fixed version renders -- 0.0595 in both. Only the first
# overlay is lost, which is what makes this survive a glance at the deck.
must_frac_nonwhite_between 2 0.05 0.35 0.75 0.62 0.02 0.15
