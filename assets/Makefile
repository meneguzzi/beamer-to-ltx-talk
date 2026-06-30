# Makefile for ltx-talk lecture decks.
# <<ADAPT>> the SRCS glob below to match your directory layout and file-naming
# convention. The default pattern assumes decks live in dayNN/ subdirectories
# and are named *-slides-*.tex; adjust as needed.
#
#   make            build every deck as on-screen slides (tagged PDF)
#   make slides     same as `make'
#   make handout    build every deck as a handout (overlays flattened)
#   make day01      build just one day's decks (slides)
#   make <file>.pdf build a single deck, e.g. day01/lecture01-slides-intro.pdf
#   make clean      remove LaTeX aux files (keeps PDFs)
#   make distclean  remove aux files and all generated PDFs
#
# Decks are compiled with latexmk inside their own dayNN directory so that
# shared inputs and images/ paths resolve. Handouts are produced by passing
# the ltx-talk `handout' option on the command line (no per-deck edits), which
# collapses every overlay frame to a single page.

LATEXMK := latexmk
LATEXMKFLAGS := -pdf -interaction=nonstopmode -halt-on-error

# <<ADAPT>> glob to match your source layout, e.g.:
#   SRCS := $(wildcard *.tex)
#   SRCS := $(wildcard lectures/*-slides.tex)
SRCS := $(wildcard day*/*-slides-*.tex)
PDFS := $(SRCS:.tex=.pdf)
HANDOUTS := $(SRCS:.tex=-handout.pdf)
DAYS := $(sort $(dir $(SRCS)))

.PHONY: all slides handout clean distclean $(patsubst %/,%,$(DAYS))

all: slides
slides: $(PDFS)
handout: $(HANDOUTS)

# Slides: one PDF per deck, built in its own directory.
%.pdf: %.tex
	cd $(dir $<) && $(LATEXMK) $(LATEXMKFLAGS) $(notdir $<)

# Handout: same source, ltx-talk `handout' option injected before the class is
# loaded. Uses a separate jobname so the slide PDF is not overwritten.
%-handout.pdf: %.tex
	cd $(dir $<) && $(LATEXMK) $(LATEXMKFLAGS) \
	    -jobname=$(notdir $*)-handout \
	    -usepretex='\PassOptionsToClass{handout}{ltx-talk}' \
	    $(notdir $<)

# Per-day convenience targets: `make day01' builds that day's slides.
define DAY_template
$(patsubst %/,%,$(1)): $(filter $(1)%,$(PDFS))
endef
$(foreach d,$(DAYS),$(eval $(call DAY_template,$(d))))

clean:
	for d in $(DAYS); do (cd $$d && $(LATEXMK) -c); done

distclean:
	for d in $(DAYS); do (cd $$d && $(LATEXMK) -C); done
	rm -f $(HANDOUTS)
