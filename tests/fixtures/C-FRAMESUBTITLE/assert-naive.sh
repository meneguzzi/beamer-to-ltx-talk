# The defect: ltx-talk accepts \framesubtitle and never typesets it.
# Asserting the ABSENCE is what makes the other two assertions meaningful.
# A failure means ltx-talk now typesets subtitles -- good news, reported as
# advisory. Retire the entry and delete this fixture variant.
. "$ASSERT_LIB"
must_contain "Constraint Satisfaction"   # the title still works
must_not_contain "Quiz"                  # the subtitle does not
