# The defect: a bare [b] is discarded and the frame renders CENTRED. Asserting
# the centring is what keeps the two assertions above from being vacuous.
#
# A failure means ltx-talk now parses bare option words (or rejects them loudly).
# Advisory, not a build failure: retire the entry.
. "$ASSERT_LIB"
must_ymin_frac_between paragraph 0.35 0.60
