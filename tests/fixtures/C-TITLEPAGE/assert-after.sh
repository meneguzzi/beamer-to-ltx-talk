#!/usr/bin/env bash
# The native title page, with the beamer title block kept. Three claims; naive.tex breaks the
# first two, which is what makes this fixture worth more than a compile.
#
#   1. The title is the document's H1. The title element's tag-begin is overridden so the
#      kernel's automatic per-paragraph tagger emits it (A-HEADINGS): exactly one /S /H1.
#      naive.tex has 0 -- plain text in a frame is tagged as nothing -- so its deck title is
#      not a heading at all. There is deliberately no /S /Title: the override replaces that
#      wrapper, and nothing requires one.
#   2. ONE SOURCE OF TRUTH, and the subtitle is split out of \title. dc:title is exactly the
#      main title. naive.tex leaves the beamer fold in place and its dc:title comes out as
#      "Constraint Satisfaction and SearchBacktracking and arc consistency" -- the \\ is
#      dropped and the two run together -- while its title page says something else again.
#   3. The attribution is still centred text after \maketitle, exactly as beamer wrote it,
#      and it lands clear below the institute. No workaround, no \date misuse.
#
# Measured, lualatex, two passes (page height 283.465pt): title yMin 45.05 (0.159 of the
# page), institute 157.04 (0.554), attribution 204.88 (0.723). The beamer original puts the
# attribution at 0.728 -- the construct survives the conversion.
. "$ASSERT_LIB"

must_have_pages 2
must_be_tagged
must_have_struct_count H1 1
must_have_struct_count Title 0
must_have_dc_title "Constraint Satisfaction"
must_contain "Material adapted from"
must_ymin_frac_between Constraint 0.10 0.30
must_ymin_frac_between University 0.45 0.65
must_ymin_frac_between Material   0.65 0.85
