# Beamer builds this construct without complaint -- it has no tag tree to unbalance.
# Records that the defect is introduced by the conversion, not present in the source.
. "$ASSERT_LIB"
must_not_be_in_log 'para hooks differ'
must_have_pages 1
