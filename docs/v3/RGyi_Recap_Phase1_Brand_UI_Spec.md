# RGyi Recap — Phase 1 Brand & UI/UX Specification

**Status:** Design specification / implementation plan  
**Branch:** feature/rgyi-recap-phase1-brand-ui  
**Base:** main  
**Product direction:** Premium AI-assisted movie recap, subtitle, narration and video-production studio.

## 1. Product identity
- Product name: **RGyi Recap**
- Descriptor: **AI Movie Production Studio**
- Brand promise: **Create · Translate · Narrate · Produce**
- Keep the existing Flutter package name and Android application ID unchanged in this phase. A visible product rename must not break upgrades, local data, Android installs or existing project files.

## 2. Visual direction
Create a cinematic, professional studio interface. Avoid a generic admin dashboard look.

### Core palette
| Token | Value | Use |
|---|---|---|
| Background | #080B14 | Main canvas |
| Surface | #111827 | Panels and cards |
| Elevated | #192238 | Hover/raised surfaces |
| Primary | #8B5CF6 | Main actions and brand |
| Secondary | #22D3EE | AI / active accents |
| Pink accent | #EC4899 | Creative highlights |
| Text | #F8FAFC | Primary text |
| Muted | #94A3B8 | Supporting text |
| Border | #263247 | Dividers and outlines |
| Success | #34D399 | Completed states |
| Warning | #FBBF24 | Warnings |

Use gradients sparingly: violet → indigo for the brand; cyan only for selected AI states. Maintain contrast and readable Burmese typography.

### Logo and app icon concept
- A cinematic play triangle.
- A subtle film-frame / reel motif.
- A small AI sparkle or waveform detail.
- Provide square launcher icon, compact symbol, horizontal wordmark and monochrome variant. Keep it legible at Android launcher and Windows taskbar sizes. Do not use emoji as the final brand mark.

## 3. UI principles
1. Cinematic visual hierarchy, premium cards, restrained glow and layered surfaces.
2. Consistent 8-point spacing scale, rounded corners and clear typography hierarchy.
3. Use real icons (Material Symbols / Lucide-equivalent icon assets), not letter abbreviations such as VI, GM, ST as primary module icons.
4. Every interactive control must perform its stated action; do not present disabled or future-phase modules as working.
5. Use loading, empty, error, success and confirmation states consistently.
6. Burmese text must wrap correctly and remain readable; do not clip Myanmar glyphs.
7. Respect reduced motion and avoid animations that delay core workflows.
8. Maintain keyboard, mouse, touch and screen-reader usability.

## 4. Responsive layout
### Android / compact width
- Touch-first layout with compact top app bar.
- Bottom navigation for Home, Workflow, Library and Settings.
- Two-column module grid where space permits; one column on narrow screens.
- Full-screen editing tools and bottom sheets for short actions.
- Keep primary actions reachable and avoid horizontal overflow.

### Windows / wide width
- Persistent left navigation rail/sidebar.
- Top command bar with project selector, status and settings.
- Wider dashboard content with responsive cards and recent projects.
- Editor surfaces may use multi-panel layouts; preserve the same features and data model as Android.
- Support keyboard shortcuts where relevant and visible tooltips for icon-only controls.

Use LayoutBuilder / width breakpoints based on available space, not platform-name checks alone. Do not fork the product into two separate implementations.

## 5. Dashboard information architecture
1. Brand header: RGyi Recap and a compact product descriptor.
2. Welcome / quick-start area with Create Project and Resume Project.
3. Recent projects with poster thumbnail, progress and last-edited time.
4. Studio modules grouped by workflow: Media & Library; Script & Recap; Subtitle Studio; Voice & Audio; Video Editor; Render & Export; Copyright / Fair Use; Utilities and Backup.
5. Clear availability labels. Existing working features remain accessible; unfinished features are marked honestly.

## 6. Feature icon language
Use a consistent 24px outline icon family with a selected/active filled state:
- Library: clapperboard / folder-video
- Video index: film / list-video
- Recap script: file-pen
- Subtitles: captions
- Translation: languages
- TTS / narration: audio-lines / mic
- Audio editor: waveform
- Timeline editor: panels-top-left / timeline
- Render: film / wand-sparkles
- Fair use: shield-check
- Backup: archive / cloud-download

Each icon needs a consistent container, accent color and accessible label. Avoid using color alone to communicate status.

## 7. Motion and interaction
- Short page transitions (150–220ms) and subtle card press feedback.
- Animated progress only when actual work is running.
- Audio waveform animation only during playback or recording.
- Skeleton placeholders for loading; no fake progress.
- Respect system reduced-motion preferences.

## 8. Architecture and safety constraints
- Preserve all existing feature screens, repositories, SQLite schema, project data, navigation actions and tests.
- Keep the established Flutter + Provider + local SQLite architecture unless a verified technical reason requires a change.
- Maintain the local-first / offline-capable core. AI is an optional assistant layer; manual workflows must remain usable without AI or internet.
- Do not add mandatory accounts, cloud storage or paid API dependencies as part of the visual redesign.
- Never change package/application IDs or database schema as a side effect of branding.
- Make changes incrementally and review diffs before each commit.
- No claim that a build or test passed unless CI actually reports success.

## 9. Phase 1 implementation checklist
- [ ] Add RGyi Recap brand tokens and theme components.
- [ ] Create vector logo and launcher icon assets in light/dark-safe variants.
- [ ] Update visible app title and dashboard brand header.
- [ ] Redesign dashboard hierarchy and module cards without removing actions.
- [ ] Replace text-code tiles with consistent feature icons.
- [ ] Add responsive Android / Windows navigation and dashboard behavior.
- [ ] Add widget tests for navigation, module actions and responsive layouts.
- [ ] Run formatter, analyzer and all tests.
- [ ] Run Android build and Windows build where runners/toolchains are available.
- [ ] Inspect screenshots at compact phone, tablet and desktop widths.
- [ ] Update README and release notes only after implementation is verified.

## 10. Acceptance criteria
Phase 1 is complete only when:
- the RGyi Recap brand is consistently visible in the app and launcher;
- the dashboard looks coherent at phone and desktop widths;
- all pre-existing working module actions still navigate to their original screens;
- existing projects remain intact after upgrade;
- Burmese labels render without clipping;
- automated checks pass, and any unavailable platform build is explicitly reported as unverified.