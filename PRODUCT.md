# Product

## Platform
android

## Stack
Flutter (Dart), Material 3 theming with a custom design kit in `lib/design/`. Coach server: Deno
(`supabase/functions/coach/`). Offline speech: `packages/prepsuite_speech` (sherpa-onnx). Robot
characters rendered in Blender (`tools/blender/models/assistant.py`) and drawn live in
`lib/design/assistant_avatar.dart`.

## Users
Students and first-time job candidates preparing for entry-level interviews. Many have school,
volunteering or project experience but struggle to say it out loud. English first.

## Product Purpose
Practice one answer, improve one thing, hear your progress. Short spoken sessions (3 questions, or
1 for a quick drill) with honest, evidence-quoting feedback, plus quick tap-the-answer skill drills.

## Positioning
A compact, approachable practice routine with a recognizable robot coach. Not a general chat
assistant and not a voice-analytics dashboard.

## Operating Context
Phone in hand, often in a quiet room before an interview, sometimes where speaking aloud is not
possible (typing is always available). Sessions last minutes.

## Capabilities and Constraints
Questions and feedback come from the coach server (Ollama or Anthropic). Speech is transcribed on
the phone; only text and measured delivery numbers are sent. Typed answers get content feedback
only. Local-first: no account needed to start.

## Brand Commitments
- The 3D robot coaches (Tide, Ember, Echo, Sprout) are the brand and the hero of hub screens.
- Dark metallic look from the owner's references: near-black base, satin metal cards, one warm
  accent per theme, big numbers, round controls, floating pill tab bar.
- Very few words on every screen.
- Banned (owner's list): purple-to-blue gradients, gradient hero text, emoji in headings, Inter
  everywhere, colored left-border cards, glassmorphism cards, low-contrast dark mode, three icon
  boxes in a row, badges above headlines, Lucide icons everywhere, untouched shadcn, fade-in on
  scroll, cursor beams, buttons that fade on hover, inconsistent spacing, em dashes, generic
  buzzword copy, serif italic accents, Space Grotesk plus Instrument Serif, grain over gradients.

## Evidence on Hand
Owner-supplied reference images (dark smart-home and drone apps). PRD:
`docs/PREPSUITE-PRD-2026-10-02.md`.

## Product Principles
- One obvious next action per screen.
- No fabricated facts, scores, confidence ratings or employability judgments.
- Encouragement tied to effort; no streaks, XP or leaderboards.
- Honest voice observations only from real measurements.

## Accessibility & Inclusion
TalkBack labels on every control, 48 dp targets, no color-only meaning, large text (1.3x+)
without loss of actions, reduced motion respected, contrast AA or better in every theme.
