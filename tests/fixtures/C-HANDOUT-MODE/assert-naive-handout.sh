#!/usr/bin/env bash
# The defect: with no handout: qualifier, both overlays print on the one handout page. Measured
# 1 page, text layer "Step one Step two". In a real deck each \only holds an \includegraphics,
# so this is four images on top of one another rather than two short strings.
#
# The page count is right and the build is clean, which is why a handout has to be looked at
# rather than counted.
. "$ASSERT_LIB"

must_have_pages 1
must_contain "Step one"
must_contain "Step two"
