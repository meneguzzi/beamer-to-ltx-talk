# vertical-alignment=bottom puts it back where beamer had it. A failure means the
# frame-option rewrite stopped taking effect -- the exact silent regression this
# entry is about, since the page count and extracted text are identical either way.
. "$ASSERT_LIB"
must_ymin_frac_between paragraph 0.70 1.00
must_be_tagged
