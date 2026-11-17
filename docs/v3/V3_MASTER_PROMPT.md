DRAMAFLOW AI STUDIO V3 — MASTER IMPLEMENTATION PROMPT

PROJECT

Repository: "punk123321/dramaflow-ai-studio"

Product: DramaFlow AI Studio V3

Platforms:

- Android
- Windows Desktop

Framework: Flutter / Dart
Native Android: Kotlin + Media3
Database: SQLite
State Management: Provider (preserve unless a documented technical reason requires change)

Design Direction: HYBRID CINEMATIC + PROFESSIONAL STUDIO

---

ROLE

Act as a Senior Flutter Architect, Professional Video Editor UI/UX Designer, Desktop Application Engineer, Android Native Engineer, and QA Automation Engineer.

Your task is to upgrade the existing DramaFlow AI Studio into a premium, professional, multi-platform video production studio.

This is an evolution of the existing application, NOT a rewrite.

You must inspect the actual repository before making changes.

Do not assume a feature exists merely because it is described in documentation.

Distinguish:

- Implemented
- Implemented but not tested
- Tested in CI
- Tested on Android device
- Tested on Windows desktop

Never claim something is complete without evidence.

1. NON-NEGOTIABLE PRESERVATION RULES

The existing application contains important functionality.

Preserve all existing modules and workflows:

- Home Dashboard
- Project Management
- Drama Library
- Video Import
- Video Index and Segments
- Gemini Recap Workflow
- SRT / Subtitle Studio
- TTS and Audio Recording
- Studio Editor (ED)
- Render Center (RN)
- Transformative Editor (TE)
- Copyright & Fair Use (FU)
- Upload & Thumbnail (UP)
- SQLite Database
- Export History
- Project Persistence
- Native Android Media3 Rendering

STRICT RULES:

1. Never delete existing working functionality.
2. Never replace the existing application with a demo UI.
3. Never delete existing project data.
4. Never reset the SQLite database.
5. Never break existing database migrations.
6. Never modify original source videos.
7. Never remove existing tests.
8. Never silently change existing project formats.
9. Preserve TransformativePlan V2 compatibility and unknown data.
10. Never automatically execute AI-proposed operations.
11. Never bypass existing Fair Use or copyright safety features.
12. Never claim an unsupported tool is rendered.
13. Never merge into main.
14. Never commit directly to main.

Before modifying any file, understand its existing responsibilities and dependencies.

2. DESIGN SYSTEM — V3

Build a premium hybrid design system combining:

A. Cinematic Glassmorphism

- Translucent glass panels
- Layered floating cards
- Soft neon outlines
- Purple and cyan gradients
- Controlled background blur
- Subtle shadows
- Depth and elevation
- Smooth transitions

B. Professional Video Editing Interface

- Multi-panel workspace
- Professional timeline
- Layer management
- Inspector panels
- Preview canvas
- Tool properties
- Render controls

C. Mobile-First Interaction

- Touch-friendly controls
- Bottom sheets
- Floating tool panels
- Expandable sections
- Responsive navigation
- Full-screen preview

DESIGN COLORS:

Main background: #080D1B
Panel background: #151D35
Elevated surface: #202945
Primary purple: #7138F5
Secondary cyan: #08BFEA
Success: #36D399
Warning: #FBBF24
Error: #FB7185
Primary text: #F5F5FF
Secondary text: #A8B1CC

Design requirements:

- Consistent spacing system
- Consistent typography
- Burmese text support
- English text support
- Accessible contrast
- Consistent iconography
- Responsive animations
- Loading, empty, error and success states

Do not use excessive blur or animations that damage performance.

3. RESPONSIVE MULTI-PLATFORM ARCHITECTURE

Build one shared Flutter application with adaptive layouts.

ANDROID:

- Mobile dashboard
- Bottom navigation
- Touch-based controls
- Full-screen video preview
- Expandable inspector
- Bottom-sheet properties
- Floating editing toolbar
- Timeline with horizontal scrolling
- Mobile-friendly layer manager

WINDOWS:

- Desktop navigation sidebar
- Resizable panels
- Central preview canvas
- Left layer/media panel
- Right properties inspector
- Bottom multi-track timeline
- Keyboard shortcuts
- Mouse interactions
- Drag-and-drop where supported
- Context menus
- Desktop dialogs

Use LayoutBuilder and platform-aware widgets.

Define documented layout breakpoints.

Do not merely stretch the mobile layout to fit desktop.

Desktop and mobile should feel like two native experiences belonging to the same product.

4. V3 STUDIO SHELL

Create a new responsive Studio Shell.

Main navigation:

1. Home
2. Projects
3. Video Studio
4. AI Studio
5. Asset Library
6. Render Center
7. Settings

Do not remove existing navigation destinations.

All existing modules must remain accessible.

Create reusable components:

- StudioSidebar
- StudioTopBar
- StudioBottomNavigation
- GlassPanel
- LayerCard
- InspectorPanel
- PreviewCanvas
- TimelinePanel
- ToolButton
- ProjectCard
- FloatingToolPanel
- StatusIndicator
- RenderProgressCard

Avoid duplicating components across platforms.

5. PROFESSIONAL PROJECT DASHBOARD

Create a premium dashboard containing:

- Welcome section
- Create New Project
- Continue Editing
- Recent Projects
- Project thumbnails
- Project progress
- Last modified date
- Project search
- Project filters
- Quick Actions
- Recent Exports
- AI Tools shortcuts

Project operations:

- Create
- Rename
- Duplicate
- Delete
- Open
- Resume
- Archive (only if safely implemented)

Project deletion must never accidentally delete source videos.

Display autosave and recovery status.

6. PROFESSIONAL MULTI-LAYER EDITOR

Build a dedicated Layer Manager and Timeline UI.

Layer types:

1. Background
2. Main Video
3. Secondary Video
4. Image Overlay
5. Text / Title
6. Subtitle
7. Narration / Voice
8. Music / Sound Effects
9. Effects
10. Adjustment

Layer controls:

- Add
- Remove
- Duplicate
- Rename
- Hide / Show
- Lock / Unlock
- Reorder
- Group / Ungroup
- Select
- Copy / Paste
- Opacity
- Position X/Y
- Scale
- Rotation
- Start / End time
- Keyframes

TIMELINE:

- Multiple tracks
- Time ruler
- Playhead
- Track selection
- Clip selection
- Clip trimming
- Split
- Move
- Delete
- Zoom in/out
- Horizontal scrolling
- Track visibility
- Track locking
- Audio waveform when supported

Use efficient rendering for long timelines.

Do not rebuild the entire timeline on every playhead update.

PREVIEW:

- Video playback
- Layer overlays
- Transform handles
- Selection boundaries
- Safe area guides
- Aspect-ratio guides
- Accurate preview time
- Preview/render consistency

Do not pretend that UI-only layers are renderable.

Every layer type must have a documented rendering capability.

7. TRANSFORMATIVE EDITOR V3

Preserve the existing TE architecture.

Modes:

- Manual
- AI Assisted
- Hybrid

Preserve:

- Versioned TransformativePlan
- V1 to V2 migration
- Unknown field preservation
- Unknown operation preservation
- Per-project storage
- Proposed / Approved / Rejected statuses
- Approval workflow
- Render compilation
- Unsupported tool reporting

Tools:

- Smart Cut
- Crop & Reframe
- Picture-in-Picture
- Commentary / Voice-over
- Freeze Frame
- Scene Reordering
- Motion Graphics
- Sound Design
- Split Screen
- Critical Commentary
- Brightness / Contrast

Implement:

- Visual crop controls
- Transform inspector
- Keyframe interface
- Operation review panel
- Operation history
- Preview of proposed changes
- Clear tool capability labels

Only approved and valid operations may be compiled.

Rejected and proposed operations must never execute.

Never mutate the saved timeline when creating a render job.

Keep experimental features visibly marked as experimental.

8. AI COMMAND CENTER

Create a dedicated AI workspace.

Sections:

- AI Director
- Script Assistant
- Scene Analysis
- Subtitle Assistant
- Narration Assistant
- Thumbnail Assistant
- Transformative Suggestions

AI suggestions must be reviewable.

Every generated editing operation must require user approval.

Preserve the existing Gemini copy/share/paste workflow and current API configuration.

Do not introduce mandatory API keys, paid cloud services, Firebase, or new external services without explicit approval.

Never expose private API tokens in the UI or source code.

Clearly report unavailable AI capabilities.

9. RENDER STUDIO

Preserve the current Android Media3 rendering engine.

Build a professional Render Studio interface:

- Resolution
- FPS
- Bitrate
- Format
- Output filename
- File size estimate
- Available storage
- Render progress
- Cancel render
- Render queue
- Export history
- Save to Gallery
- Save to File

Preserve the existing safe temporary-file and completed-file behavior.

PLATFORM BACKENDS:

Create an abstraction such as:

RenderBackend

- capabilities
- startRender
- cancelRender
- renderProgress
- renderResult

Android:
Continue using the existing Kotlin Media3 implementation.

Windows:
Investigate and implement a genuine compatible Windows rendering backend.

Do not call Android Media3 from Windows.

Do not claim Windows rendering works until a real Windows export has been tested.

If a backend is not implemented, display a clear unsupported status.

Do not silently substitute a fake renderer.

10. DATABASE AND PERSISTENCE

Preserve existing SQLite schema and migration history.

Inspect:

- app_db.dart
- project_repo.dart
- project_store.dart
- transformative_plan.dart
- render_store.dart

Add migrations only when necessary.

All new project data must be saved and restored correctly.

Test:

- Existing project reopening
- Project duplication
- Project deletion
- Timeline persistence
- Layer persistence
- TransformativePlan persistence
- Export history
- Autosave
- Recovery after interrupted sessions

Never overwrite unknown future-version data.

11. IMPLEMENTATION PHASES

Work incrementally.

V3.1 — Design System and Responsive Shell
V3.2 — Dashboard and Project Workspace
V3.3 — Layer Manager and Timeline UI
V3.4 — Transformative Editor Integration
V3.5 — AI Command Center
V3.6 — Render Studio and Windows Backend
V3.7 — Final QA and Performance Optimization

Each phase must have:

- Code changes
- Unit tests
- Widget tests
- Integration tests where appropriate
- Flutter Analyze
- Regression tests
- Build verification
- Documentation updates

Do not start the next major phase while the current phase has unresolved critical regressions.

12. PERFORMANCE REQUIREMENTS

Android:

- Avoid excessive widget rebuilds.
- Avoid unnecessary memory copies of video files.
- Dispose controllers and subscriptions correctly.
- Handle app lifecycle changes.
- Handle low-storage situations.
- Keep timeline scrolling responsive.

Windows:

- Support resizable application windows.
- Handle large screens.
- Avoid unnecessary rendering and widget rebuilds.
- Handle large project lists and timelines.
- Support mouse and keyboard interaction.

Both:

- No memory leaks.
- No lost project data.
- No unhandled platform exceptions.
- No fake progress indicators.

13. TESTING AND REGRESSION

Preserve all existing tests.

Add tests for:

- Responsive breakpoints
- Navigation
- Project management
- Existing database migrations
- Layer CRUD
- Layer ordering
- Timeline editing
- Undo / Redo
- TransformativePlan migration
- Unknown data preservation
- Operation approval safety
- Render job integration
- Unsupported tool reporting
- Project persistence
- Autosave and recovery

CI must verify:

1. Dependency resolution
2. Flutter Analyze
3. All Flutter tests
4. Android Release APK Build
5. APK Artifact Upload
6. Windows Release Build
7. Windows Artifact Upload

Each required workflow must be associated with its exact branch and commit SHA.

A successful CI build does not prove on-device or desktop behavior.

Maintain a device/desktop testing checklist.

14. GITHUB WORKFLOW

Never modify main directly.

Create a dedicated feature branch:

claude/v3-hybrid-studio

If that branch already exists, inspect it and continue safely or select a unique V3 branch.

Create small, reviewable commits.

Open a Pull Request targeting main.

Never merge the PR.

Do not disable CI checks.

Do not delete existing branches or artifacts.

Do not modify repository protection settings.

The PR must include:

- Summary
- Changed files
- New features
- Preserved existing features
- Database impact
- Platform support
- CI results
- Known limitations
- Phone testing requirements
- Windows testing requirements

15. FINAL REPORT

At the end of each phase, provide a Burmese report:

1. What was implemented
2. What existing functionality was preserved
3. Files changed
4. New UI components
5. Android compatibility
6. Windows compatibility
7. Flutter Analyze result
8. Test results
9. Android build result
10. Windows build result
11. APK artifact link
12. Windows artifact link
13. Exact branch name
14. Exact commit SHA
15. PR link
16. Remaining issues
17. Features requiring real-device testing

Never report untested features as verified.

FINAL INSTRUCTION

Start by auditing the complete existing repository.

Read:

- README.md
- HANDOFF.md
- CHECKLIST.md
- RELEASE_NOTES.md
- pubspec.yaml
- Existing architecture
- Existing tests
- Native Android implementation
- GitHub Actions workflows

Produce a concise architecture audit and implementation plan first.

Then begin V3.1.

Do not stop after producing a visual mockup. Implement real, reusable Flutter components.

Do not rewrite working modules unnecessarily.

Do not remove or replace existing functionality.

The final product must look premium, behave professionally, preserve existing data, and work honestly across Android and Windows.

DramaFlow AI Studio V3 — One Studio. Multiple Platforms. Professional Creation.