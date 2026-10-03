# PrepSuite: rules for every session

## Design (always)
- Before any UI work, use the impeccable skill (`.claude/skills/impeccable/`): run
  `.claude/skills/impeccable/scripts/impeccable context`, then read `reference/craft-floor.md` and
  `reference/android.md`. Product truth: `PRODUCT.md`. Visual system: `DESIGN.md` (when present).
- Never ship any of these (owner's list): purple-to-blue gradients, gradient hero text, emoji in
  headings, Inter everywhere, colored left-border cards, glassmorphism cards, low-contrast dark
  mode, three icon boxes in a row, a badge above the headline, Lucide icons everywhere, untouched
  shadcn, sections fading in on scroll, cursor beams, buttons that fade on hover, inconsistent
  spacing, em dashes, generic buzzword copy, serif italic accents, Space Grotesk plus Instrument
  Serif, grain over a gradient.
- Words budget: hub cards ≤ 1 title + 1 short meta; no paragraphs on hub screens; buttons 1–2
  words; feedback cards ≤ 14 words. Numbers over sentences. US English, no em dashes.
- The robot is the hero: large on Home and in sessions, never a tiny icon.

## Workflow
- Work in this folder only: no git worktrees. Finish with a full `flutter run` so the device runs
  the committed code.
- Never run `dart format` on the whole repo (it rewrites ~50 hand-formatted files).
- `flutter analyze` clean and `flutter test` green before every commit.
- Update `HANDOFF-Claude.md` (never `HANDOFF-GPT.md`).
