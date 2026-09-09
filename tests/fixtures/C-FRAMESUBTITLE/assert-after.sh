# The \frametitlesub workaround folds the subtitle into the title, so the word
# survives the conversion. A failure here means the workaround stopped working.
. "$ASSERT_LIB"
must_contain "Quiz"
must_contain "Constraint Satisfaction"
must_be_tagged
