#!/usr/bin/env bash
# Beamer's own handout of this source ALSO stacks both steps onto one page -- measured, 1 page,
# "Step one Step two". So for an unqualified \only pair the stacking is inherited from Beamer
# and is not introduced by the conversion.
#
# The matched handout:0 / handout:1 pair that after.tex uses is PORTABLE: measured under beamer
# on this same source shape, it gives 2 pages with both steps as slides and 1 page with "Step
# two" as a handout -- identical to ltx-talk's after.tex. So the workaround is not an ltx-talk
# dialect, and a deck that keeps beamer as an export target can carry one source for both.
#
# What ltx-talk lacks is beamer's frame-level \begin{frame}<handout:N> form, which it parses and
# then only half implements: the frame is kept and every \only in it is suppressed, leaving the
# non-overlay text alone. That is the form a deck has to be moved off, not the \only pair.
. "$ASSERT_LIB"

must_have_pages 1
must_contain "Step one"
must_contain "Step two"
