# The whole point of this fixture: keeping $$ inside the center environment must
# leave the paragraph-hook balance intact. If this fails, convert_deck.py has
# started rewriting $$ inside center again (C-DISPLAY-IN-CENTER), or the kernel
# changed and the entry can be retired.
. "$ASSERT_LIB"
must_not_be_in_log 'para hooks differ'
must_be_tagged
must_have_pages 1
