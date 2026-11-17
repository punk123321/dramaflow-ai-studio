# RGyi Recap — Feature Integration & Upgrade Roadmap

**Status:** Engineering plan based on source audit  
**Branch:** feature/rgyi-recap-phase1-brand-ui  
**Scope:** Reuse DramaFlow AI foundations and upgrade the competitor-video feature set without removing existing workflows.

## 1. Product decision

RGyi Recap will combine:
- proven DramaFlow AI project, subtitle, audio, timeline, render and Transformative Editor foundations;
- the demonstrated KG Recap-style workflows: AI text-to-speech, recap/full translation, aspect-ratio outputs, blur masks, Whisper subtitle generation and multiple narrator voices;
- a guided end-to-end movie recap pipeline with manual overrides at every stage.

This is an integration roadmap, not a claim that every feature is already implemented. Each feature must pass the acceptance checks below before it is labelled ready.

## 2. Existing DramaFlow AI foundations confirmed in source

| Area | Existing source | Current capability / reuse decision |
|---|---|---|
| Project & local data | `lib/data/project.dart`, `app_db.dart`, `project_repo.dart`, `project_store.dart` | Keep existing project identity, SQLite data and repositories. No schema reset or package ID change. |
| SRT parsing & editing | `lib/core/srt.dart`, `subtitle_ops.dart`, `lib/ui/subtitle_studio_screen.dart` | Reuse parser, validator, split/merge, time shift, undo and separate studio copy. |
| Narration generation | `lib/core/video_recap.dart`, `lib/ui/video_recap_screen.dart` | Existing Gemini-assisted, part-by-part recap prompt and manual response handoff. Upgrade toward integrated provider adapters later. |
| TTS & audio | `lib/ui/audio_panel.dart`, `lib/core/gemini_tts.dart`, `lib/platform/gemini_tts_client.dart`, `audio_channel.dart` | Existing device TTS, microphone recording, imported audio and optional Gemini API TTS. Preserve offline/manual paths. |
| Timeline & edit decision list | `lib/core/timeline.dart`, `lib/ui/editor_panel.dart` | Reuse non-destructive video pieces, crop/zoom, freeze frames, look adjustments, narration/music placement and subtitle remapping. |
| Output format & rendering | `lib/core/render_plan.dart`, `lib/ui/render_panel.dart`, `render_channel.dart` | Existing 16:9, 9:16, 1:1, 4:5, bars/crop/blur-fill, quality/FPS settings and native MP4 rendering. |
| Transformative Editor | `transformative_plan.dart`, `te_compile.dart`, `te_ai.dart`, `transformative_editor_screen.dart` | Reuse plan/compile architecture and keep operations non-destructive until render. |
| Video import | `lib/platform/video_import.dart`, `video_info.dart` | Reuse existing import and metadata path. |

## 3. Feature parity audit against the supplied reference video

### A. Text-to-Speech / Voice Studio
**Already present:** device TTS where Burmese voice is installed, microphone recording, imported audio, chunked narration, optional Gemini API TTS and voice selection.

**Upgrade:**
- unified voice catalogue with provider, language, gender/style description where supplied by provider, availability and offline/online labels;
- audition/preview before generating all chunks;
- per-chunk voice, speed, pitch (only where provider supports it), volume and retry;
- batch generation with progress, cancellation and resume;
- normalize loudness and optionally trim silence; keep original generated audio;
- clearly show API/network/cost requirements before cloud synthesis.

**Acceptance:** one chunk can be regenerated without overwriting other chunks; offline/manual audio still works with no API key; provider failures are recoverable.

### B. Recap translation and full translation
**Already present:** Gemini-assisted tasks and Burmese recap/narration workflow exist; subtitle text can be edited and imported as SRT.

**Upgrade:**
- two distinct modes: (1) Recap Translation — translate/adapt narration while preserving storytelling tone; (2) Full Translation — translate every subtitle cue while preserving cue order and timestamps;
- glossary and character-name memory per project;
- chunked translation with stable cue IDs, retry and progress;
- side-by-side source/target editor and terminology consistency checks;
- never silently rewrite source SRT; save translated output as a separate document.

**Acceptance:** source cue count, cue IDs and timestamps remain unchanged unless the user explicitly requests timing edits; partial retries do not duplicate or drop cues.

### C. Whisper subtitle generation
**Status:** no native Whisper transcription integration was confirmed in the source files inspected. Existing SRT parsing/editing is reusable, but it is not speech recognition.

**Upgrade path:**
- provider interface for local Whisper and optional remote transcription;
- audio extraction from imported video through the native media layer;
- language selection / auto-detect, timestamps, chunked long-video handling;
- import generated SRT into existing Subtitle Studio for correction;
- model download size, storage, device requirements and online/offline state shown before use.

**Acceptance:** generated SRT passes the existing parser/validator; timestamps are monotonic and editable; transcription can be cancelled/resumed; no claim of offline support until an actual on-device model runs successfully on target devices.

### D. Aspect ratio, background blur and blur masks
**Already present:** output ratios 16:9, 9:16, 1:1 and 4:5; bars, crop and experimental blurred-background fill; timeline crop/zoom/look controls.

**Important distinction:** blurred background fill is not the same as a user-positioned blur mask that obscures a region in the video.

**Upgrade:**
- promote ratio presets for YouTube, Shorts, TikTok/Reels and Facebook;
- interactive safe-area/crop preview with draggable focal point;
- blur-mask layer with rectangle/ellipse, position, size, feather, strength and time range;
- keyframes or tracked masks as a later advanced capability;
- render preview and clear performance warnings on mobile.

**Acceptance:** masks affect only selected time ranges and positions; original media remains untouched; render output matches preview within supported renderer limits. Keep background blur and privacy blur as separate controls.

### E. Narrator voices and voice count
**Already present:** the Gemini TTS voice list and device voice availability are configurable; imported/recorded audio is supported.

**Upgrade:** provider-neutral voice catalogue. Do not promise “10 AI voices” until ten selectable, tested voices are actually available through configured providers. Show provider and network/cost requirements for each voice.

### F. End-to-end production
Add a guided production board that links existing stages:
1. Import video and inspect metadata.
2. Generate / import transcript (Whisper or external SRT).
3. Translate subtitles or create recap narration.
4. Review and edit script.
5. Generate / record narrator audio.
6. Arrange clips, narration, music and subtitles on the existing timeline.
7. Apply ratio, crop and blur masks.
8. Run quality checks and render MP4.
9. Review output and export.

Every stage must remain manually accessible in Free Mode. Guided Mode can recommend the next step but must not lock user data.

## 4. Delivery phases

### Phase 1 — Brand/UI stabilization
- Finish responsive RGyi Recap shell, dashboard and launcher branding.
- Verify Android release build, tests and existing project compatibility.
- Do not merge while required checks are failing or unresolved.

### Phase 2 — Reuse and integration foundation
- Map all existing screens to the new studio navigation.
- Add capability/status metadata so unavailable integrations are not shown as working.
- Add provider interfaces for transcription, translation and TTS without replacing current implementations.
- Add regression tests before changing shared data flows.

### Phase 3 — Voice Studio upgrade
- Voice catalogue, preview, per-chunk settings, batch queue, retry/resume and audio quality controls.
- Preserve device TTS, microphone and import options.

### Phase 4 — Translation Studio
- Recap Translation and Full Translation modes.
- Glossary, side-by-side review, stable cue IDs and separate source/target documents.

### Phase 5 — Whisper Transcription
- Local model feasibility and Android/Windows device benchmarks first.
- Then implement audio extraction, transcription queue and SRT handoff.
- Remote transcription remains optional.

### Phase 6 — Advanced Video Editor
- Upgrade ratio preview and safe areas.
- Implement real time-bounded blur masks distinct from blurred background fill.
- Add keyframes/tracking only after the base renderer is stable.

### Phase 7 — Production automation & QA
- Connect all stages into a resumable project pipeline.
- Add quality checks for missing audio, subtitle overflow, timing gaps, aspect ratio and render readiness.
- Test on Android and Windows; document platform-specific limitations.

## 5. Non-negotiable engineering safeguards
- Preserve package name, Android application ID, existing project IDs and SQLite schema unless a separately reviewed migration is essential.
- Do not remove or silently replace any current screen, route, workflow or manual feature.
- Local-first: importing, editing, SRT correction, timeline planning and existing manual audio paths remain usable without AI.
- Keep source video and source SRT immutable; derived assets are separate.
- Never expose API keys in logs, URLs, screenshots or committed files.
- Do not claim a provider, voice, Whisper model, blur mask or platform build is supported until it is tested.
- Run formatter, analyzer, full tests and Android build after each meaningful integration; Windows build is required before declaring desktop parity.

## 6. Immediate next engineering actions
1. Complete the current Android release CI and resolve any build errors.
2. Inspect current routes and module entry points; connect existing working screens to the RGyi Recap studio navigation without duplicating engines.
3. Add regression tests for existing SRT, audio, timeline and render behavior.
4. Start Phase 2 with provider interfaces and a feature-capability registry; no large engine rewrite.
