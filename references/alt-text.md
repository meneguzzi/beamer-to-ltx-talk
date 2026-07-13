# Writing alt text for converted decks

Tagging a deck and leaving the figures unlabelled produces a PDF that *claims* to be
accessible and isn't. `tagpdf` warns once per bare `\includegraphics`
("Alternative text for graphic is missing … Using 'images/x.pdf' instead") — i.e. a
screen reader would read out **the filename**. Fixing that is the payoff of the whole
migration, and it is the one step that cannot be done by pattern-matching.

## The two inputs (you need both)

`scripts/alt_text_audit.py` collects them for every unlabelled image:

| Input | Gives you | Alone it produces |
|---|---|---|
| **The rendered image** (`preview_png`) | the *content*: node labels, axis labels, arrows, the actual data | "A diagram with boxes and arrows" |
| **The LaTeX context** (`frametitle`, surrounding prose) | the *role*: why the lecturer put it on this slide | "A search tree" |

**Always view the `preview_png` before writing.** Do not write alt text from the
filename, the frame title, or the surrounding bullets alone — that is how you end up
confidently describing a figure that shows something else. If a preview failed to
render, say so and leave the entry blank rather than guessing.

A worked example (from a real planning deck):

- *Context only* → "A search tree." — useless.
- *Image only* → "Tree from Start branching to Go To Pet Store, Go To School, … reaching
  Finish." — accurate but pointless; the student doesn't learn why it's there.
- *Both* → "Search tree illustrating why plain search fails on the shopping task: Start
  fans out into many unrelated actions — Go To Pet Store, Go To School, Go To
  Supermarket, Go To Sleep, Read A Book — each expanding further (Talk to Parrot, Buy a
  Dog, Buy Milk …). Only one long path eventually reaches Finish." ✅

## Rules

1. **Describe the function, not the appearance.** Answer "what is this figure *for* on
   this slide?", not "what shapes are in it?". The slide is making an argument; the
   figure is part of it.
2. **Transcribe the text inside the figure.** Node labels, axis labels, state names,
   equations-in-boxes. That is usually the exact information the sighted student is
   getting, and it is invisible to a screen reader.
3. **Don't repeat the frame title.** It is already in the tag tree and will be read out.
   Alt text that restates it wastes the listener's time.
4. **One or two sentences.** If a figure genuinely needs a paragraph (a complex plot, a
   worked derivation), that content belongs in the slide body or the speaker notes, where
   *everyone* benefits — not buried in alt text.
5. **Decorative images get `alt={}`, not a description.** Course logos, ornamental
   photos, the fight-club joke background. An empty alt marks it as an artifact and the
   screen reader skips it. Describing decoration is noise.
6. **Progressive figures: describe the delta.** For `\only<1>{a.pdf}\only<2>{b.pdf}` (the
   audit flags these as `overlay_variant`), each variant needs its own alt text saying
   *what changed* — "…, now with the explored region shaded" — not a fresh description of
   the whole picture.
7. **Plots: give the trend and the reading, not the pixels.** "Training error falls
   monotonically while validation error turns up after ~20 epochs (overfitting)" beats
   "a line chart with two curves".
8. **Never invent.** If you cannot read a label in the render, say the label is
   illegible; do not guess it.

## Author review is mandatory

This is the lecturer's teaching content and alt text is *pedagogy*, not metadata — it
decides what a blind student learns from the slide. Generated alt text is a **draft for
review**, never a silent commit. Present it to the author (image + proposed text) and get
sign-off. Flag anything you were unsure of.

## Workflow

```sh
# 1. collect: find unlabelled images, render previews, dump a worklist
python3 scripts/alt_text_audit.py week*/ai-lecture*.tex \
        --render-dir /tmp/alt-previews --json alt-worklist.json

# 2. for each entry: VIEW preview_png, read context, fill the "alt" field

# 3. inject (idempotent; skips entries whose "alt" is still empty)
python3 scripts/alt_text_apply.py alt-worklist.json --dry-run
python3 scripts/alt_text_apply.py alt-worklist.json

# 4. verify the warnings are gone
pdflatex deck.tex && grep -c 'Alternative text for graphic is missing' deck.log   # -> 0
```

Because both scripts are idempotent and skip empty entries, a large course can be done in
batches (say a lecture at a time) without losing your place.
