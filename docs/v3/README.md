# DramaFlow AI Studio V3 — notes only (NOT started)

Status: planning notes. No V3 code exists. The current work stays on version 1.x.

Files here
- `V3_DESIGN_DIRECTION.md` — the owner's design idea (layers, 5 workspaces, colours, phases V3.1 to V3.6). Kept as written.
- `V3_MASTER_PROMPT.md` — the owner's implementation prompt for a later session. Kept as written.
- this file — honest notes from the assistant, written 2026-11-13.

## Order of work agreed with the owner
1. Finish and test v1.x on a phone (see CHECKLIST.md).
2. v2 candidates: render in the background, silence-based Smart Cut.
3. V3 only after that. Not before v1 is tested.

## Things to decide before V3 starts
- Device scope: Android first, Windows as a separate later project (recommended).
- UI direction: Hybrid; keep blur and glass effects light because video editing already heats a phone.
- Merge rule: the master prompt says "never merge, PR only". The owner once asked for a merge in v1.
  Unless told otherwise the V3 session follows the prompt: PR only, the owner merges.

## Honest risks
- Many layers, keyframes, blend modes and masking go beyond what the current Media3 render path does.
  Each layer type needs its own render support, written and tested on a phone. A layer that is
  only drawn in the preview must be labelled as such (preview is not render).
- Windows needs a different render backend (Media3 is Android only). That is a project of its own
  (for example FFmpeg, with licence and packaging questions) and can only be proven on a real Windows PC.
- Preview and render can differ. Earlier examples: split screen and blur background needed phone testing.
- Undo/redo, autosave, groups and nested compositions change data formats. Existing projects and
  TransformativePlan V2 (including unknown fields) must keep opening; migrations must not overwrite
  data from a newer version.
- Size: this is months of work, not one session. Phases should be small and each one tested on the phone before the next.

## Must stay true in V3
All existing modules keep working (workflow, library, Subtitle Studio, TTS, Editor, Render, Transformative Editor,
Fair Use, Upload & Thumbnail, Backup, fast lane, SRT split). AI suggestions are only proposals until approved.
No mandatory API key. No original video is modified. No features whose purpose is to get past copyright
or platform checks (flip/mirror, covering others' watermarks, voice cloning, link downloading).
