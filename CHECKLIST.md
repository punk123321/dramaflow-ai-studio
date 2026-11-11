# Project checklist

Legend: Code written = source exists. Verified = actually run.

CI result (GitHub Actions run 42444881217, 2026-11-08): `flutter pub get`, `flutter analyze` (no errors), `flutter test` (5 unit tests) and `flutter build apk --release` all passed. The APK has NOT been installed or run on a phone yet, so every on-device item below is still unverified.

## Phase 1 - setup, design, home, navigation, database, projects

| Item | Code written | Verified |
| --- | --- | --- |
| Project setup, package name | yes | no |
| Design system and theme | yes | no |
| Home dashboard | yes | no |
| Bottom navigation | yes | no |
| Local SQLite database | yes | no |
| Create project | yes | no |
| Rename project | yes | no |
| Duplicate project | yes | no |
| Delete project (never deletes video files) | yes | no |
| Resume unfinished project after restart | yes | no |
| Workflow stages, Guided and Free mode | yes | no |
| Unit tests (progress logic, map round trip, date text) | yes | yes, passed in CI |
| Compiles and builds a release APK | yes | yes, passed in CI |

## Phase 2 - Drama Library, video import, video index

CI result (run 42557490319, 2026-11-09): analyze has no errors, 29 unit and database tests passed, release APK built (51.6 MB). The native Kotlin picker compiled. None of it has been run on a phone yet.

| Item | Code written | Verified |
| --- | --- | --- |
| Database upgrade 1 to 2 keeps old projects | yes | yes, test passed in CI |
| Segment maths (split, time parse, validation, overlap) | yes | yes, tests passed in CI |
| Segment index saved in one transaction, removed with the project | yes | yes, tests passed in CI |
| Drama and episode storage, delete unlinks projects | yes | yes, tests passed in CI |
| Drama Library screen: add, edit, delete, search, status filter | yes | no |
| Episodes: add, mark completed, delete, duplicate number blocked | yes | no |
| Pick a video from Gallery or File Manager (no copy, no permission) | yes | no, needs a phone |
| Duration, resolution, file size, thumbnail | yes | no, needs a phone |
| Segment presets 5, 10, 15, 20 min and custom length | yes | no |
| Edit, add, delete a segment with custom start and end | yes | no |
| Index survives closing the app | yes | database part tested; full app restart not tested |
| Home tiles Video Index and Drama Library open the real screens | yes | no |
| New project can link to a drama | yes | no |

Known limits of Phase 2:

- Video formats depend on the phone. MP4 is expected to work. MOV and MKV work only if Android can read them; if not, the app shows an error instead of guessing.
- Drama poster picture is not built. The card shows the first letter of the title.
- Episodes are marked completed by hand. They do not follow a project automatically.
- Video Index lives inside workflow step 1. There is no separate Video Index screen yet.
- The picked video is kept as a link. If the file is moved or deleted, a later phase must show a clear "file missing" message (not built yet).

## Phase 3 - Gemini handoff (written, awaiting CI and phone test)

| Item | Automated test | Phone test |
|---|---|---|
| SRT parse/write, BOM, CRLF, dot ms, missing numbers | yes (CI) | - |
| Chunking never loses or splits an entry | yes (CI) | - |
| Merge keeps source numbers and timestamps even if Gemini changes them | yes (CI) | - |
| Reply cleanup (code fences, chatter) and chunk report | yes (CI) | - |
| 10 prompt templates | content tested | quality with real Gemini: not tested |
| DB v3 tables, v2 to v3 upgrade, delete/copy with project | yes (CI) | - |
| Share to Gemini app (package com.google.android.apps.bard), chooser fallback | no | needs phone |
| Import SRT file, save final SRT file | no | needs phone |
| Burmese text round trip through Gemini | text round trip tested | needs phone |

Known limits: results are checked by number and time, not by translation quality. Share is refused above 200,000 characters.

## Phase 4 - Subtitle Studio (written, awaiting CI and phone test)

Scope: edit line by line, split, merge, delete, shift time, fix overlaps, problem finder, terminology list, preview, undo, export. VTT/TXT import and a video-synced preview are NOT built yet.

| Item | Automated test | Phone test |
|---|---|---|
| merge / split / delete / shift / overlap fix keep numbering and valid times | yes (CI) | - |
| time field parsing | yes (CI) | - |
| problem finder (fast, short, empty, overlap, long line) | yes (CI) | - |
| terminology list apply | yes (CI) | - |
| Studio screen, edit sheet, preview, undo, persistence after restart | no | needs phone |
| Burmese text in list and preview | no | needs phone |

## Phase 5 - Audio: TTS, microphone, audio import (written, awaiting CI and phone test)

Honest scope:
- TTS uses the phone's own Android text-to-speech engine. Whether it has a Burmese voice depends on the phone; the app checks and says so. No internet, no API.
- Microphone recording and importing an audio file (from any other app) are the other two ways to get narration audio.
- Output is WAV (TTS) and M4A/AAC (microphone). MP3 encoding is NOT built.
- Speech-to-text (audio to subtitles) is NOT built: Android has no offline file transcription without an extra model or an API.
- The script is split into chunks at sentence ends so long scripts work.

| Item | Automated test | Phone test |
|---|---|---|
| Script splitting (no lost text, limits, Burmese sentence ends) | yes (CI) | - |
| audio_clips table, ordering, delete with project, v3 to v4 | yes (CI) | - |
| Burmese voice present on the phone | no | needs phone |
| TTS to WAV, playback, long script | no | needs phone |
| Microphone record, permission prompt, playback | no | needs phone |
| Import audio, export saved file | no | needs phone |

## Phase 6 - Studio Editor (written, awaiting CI and phone test)

What it is: an edit DESCRIPTION saved in the database (video pieces, narration, music, subtitle options). It never changes the original video. The new MP4 is made in Phase 7.

Built: pieces from Video Index, add/trim/split/move/delete, narration from Stage 3 in sequence with volume and start time, background music with volume and loop, subtitle remap to the edit timeline with offset, original-sound volume, checks (errors and warnings), preview of a piece or all pieces with subtitle overlay.

Not built (honest): preview does NOT play narration or music together with the video, only the video and subtitles; no drag-on-timeline UI, only lists and time fields; no sound waveform; no transitions or effects.

| Item | Automated test | Phone test |
|---|---|---|
| trim/split/move/remove, positions, subtitle remap across cuts, save/load, checks | yes (CI) | - |
| Editor screen, lists, dialogs, sliders | no | needs phone |
| Video preview from the picked file, subtitle overlay, play all | no | needs phone |
| Music import, voice from Stage 3 | no | needs phone |

## Added after Phase 6: Recap narration inside the TTS stage

Stage 3 (TTS) now has "Gemini ကို Recap narration ရေးခိုင်း": a TTS-friendly narration prompt (spoken Burmese, no symbols, numbers in words), a target length in minutes split across chunks by dialogue time, copy/share to the Gemini app, paste the reply back, then "Recap ရလဒ်ကယူ" fills the script. Prompt text is tested; how well Gemini follows the length target needs the phone.

## Phase 7 - Render Center, MP4 export, Gallery, export history (written, awaiting CI and phone test)

Library choice: AndroidX Media3 Transformer 1.8.0 (maintained by Google, Android native, Apache 2.0). No FFmpeg, so no extra licence questions. It is added to the generated Android project by native/patch_gradle.py in CI.

Built: pieces cut from the original and joined, narration (with gaps and overlap lanes) and background music mixed with volumes, optional original sound, subtitles burned in (remapped to the edit timeline), 720p or 1080p, 24/25/30 fps, progress, safe cancel, free-space check, size estimate, writes NAME.part.mp4 and renames only when finished (an interrupted render leaves no fake video), keeps the screen on while rendering, export history, save to Gallery (Movies/DramaFlow, Android 10+) or as a file (any Android), delete.

Honest limits:
- Nothing here has been run on a phone. Media3 compiles in CI but real rendering, audio mixing, gaps and Burmese subtitle shaping are NOT verified.
- The render needs the app open. There is no background service yet, so if Android kills the app the render stops (the unfinished file is removed on the next start).
- The output is as long as the video pieces; narration or music longer than the video is cut.
- Subtitle look is fixed (white text on a dark band at the bottom). Font and style options are not built.
- Speed depends on the phone. A long video can take longer than its own length.

| Item | Automated test | Phone test |
|---|---|---|
| Size estimate, voice lanes, job JSON, blockers, file name | yes (CI) | - |
| exports table, history order, delete with project | yes (CI) | - |
| Media3 build, render of a 30 second test, audio mixing, subtitles, cancel, low storage | no | needs phone |
| Save to Gallery, save as file | no | needs phone |

## Next: Phase 7b - look options (asked by the user)

- Subtitle style: font size, text color, background on/off, top or bottom position.
- Logo image: pick a picture, choose corner, size, opacity.
- Text badges in the corners, for example "translate by Brutal Knockout": text, corner, size, color.
- Shown in the editor preview and burned into the render.

## Added after Phase 7: subtitle style, own logo, corner text, zoom

Built: subtitle size, colour, dark band on/off, top or bottom; your own logo picture in any corner (size, opacity); your own corner texts (any text, 4 corners, colour, size); slow zoom in or out per video piece (100% to 115%). All saved in the edit description and sent to the renderer.

Decided NOT to build (by design, and in the original spec): removing or covering other people's watermarks or logos, and tricks meant to avoid copyright detection (Content ID). Zoom here is for framing only and does not protect against copyright claims. Phase 8 adds a Fair Use assistant instead.

Needs phone testing: how the corner texts, logo and zoom look in a real render, and whether Burmese corner text shapes correctly. Zoom timing assumes the effect clock starts at zero for each piece; if a later piece zooms from the wrong point, report it.

## Not started

- Phase 5 leftovers: speech-to-text, MP3 encoding
- (done) Phase 8 Fair Use assistant; final phone QA still needed
- Backup and restore, project history
- Burmese UI language switch (the text is Burmese only for now)
- Guided/Free choice is not saved between app launches

## Known limits

- The first CI build found one real error (enum value `index` clashed with Dart's built-in `index`). It was renamed to `videoIndex` and the second build passed.
- Dependency versions and licenses are not verified against pub.dev.
- Module tiles on Home only show a "later phase" message.

## Ideas for later (from the user, not scheduled yet)

- Thumbnail Studio (idea from aifunmyanmar/Audiobook-Studio, no code copied; that repo has no license): title, episode, 6 layouts, frame from the video as background, drawn on a Flutter canvas. Fits next to Phase 7.
- Gemini cover-art prompt through the same share flow as Phase 3.
- Not planned: YouTube audio download (yt-dlp).

## Phase 8 — Copyright & Fair Use assistant

| Item | Automated | Phone-tested |
|---|---|---|
| Measures reuse share, narration share, longest bare stretch (`fair_use.dart`) | yes (fair_use_test) | no |
| Source / rights holder / permission record saved per project | yes (JSON round-trip) | no |
| Self-declared checklist + findings + risk label | yes | no |
| Description text (credits, facts the maker entered only) | yes | no |
| Home tiles FU and RN open their screens | no | no |

Rules of thumb only, not legal advice. No feature hides material from platform
copyright checks, and none will be added.

## Re-check after Phase 8
- Fixed in code: when no subtitle was showing, the renderer drew a small dark box (background colour on a blank space). Now blank = no styling. Needs a phone check.
- Unverified assumption: zoom uses the effect clock modulo the piece length, so it works whether the clock starts at 0 per piece or runs on; a phone test must confirm it zooms smoothly in each piece.

## TE review fixes (branch claude/te-review-fixes)

| Item | Automated | Phone-tested |
|---|---|---|
| Plan v2: real version handling, v1 files load, newer files keep unknown fields/tools/ops | yes | no |
| Operations list with proposed/approved/rejected; only approved+valid ops are runnable | yes | no |
| Per-project storage and project copy include the TE plan | yes (db test) | no |
| Tool status badges (planned vs works in Studio Editor) | yes (model) | no |
| Unsaved-changes prompt on leaving the TE screen | no | no |
| Branch CI artifact name differs from main | CI only | n/a |

TE itself still renders nothing: operations are records. No AI is connected.

## TE-2: Crop & Reframe (branch claude/te-2-crop-reframe)

| Item | Automated | Phone-tested |
|---|---|---|
| Approved Crop & Reframe operations compile into video pieces (split, fold tiny leftovers, later wins) | yes (te_compile_test) | no |
| Render job carries the crop; saved timeline is not changed | yes | no |
| Native crop (Media3 MatrixTransformation, kept area centred on cx,cy) | compiles on CI | no |
| Render screen lists TE operations that are applied or left out, with the reason | no | no |

Other TE tools are still records only. Crop is a still frame crop; picture
quality drops at high zoom because the video is enlarged, not re-shot.

## TE-3: Freeze Frame (branch claude/te-3-freeze-frame)

| Item | Automated | Phone-tested |
|---|---|---|
| Approved Freeze Frame ops insert a held still at render time (split, edge handling, hold 0.5-30 s) | yes (te_compile_test) | no |
| Held frames keep the piece's crop; stored timeline is not changed | yes | no |
| Original subtitles pause during a hold; later ones shift by the hold | yes | no |
| Render screen shows where each hold lands on the edit time | no | no |
| Native: frame taken with MediaMetadataRetriever, held as an image item (Media3) | compiles on CI | no |

Known limits: narration is NOT shifted by a hold (the user adjusts it), the
frame is taken on the main thread (a few frames are fine, many may stall), and
how Media3 mixes an image item into a sequence that has original audio is
unverified on a phone.

## TE-4: Motion Graphics, text label and arrow (branch claude/te-4-motion-graphics)

| Item | Automated | Phone-tested |
|---|---|---|
| Approved label/arrow ops become timed overlays on the OUTPUT time (follows cuts, reorder, held frames) | yes (te_compile_test) | no |
| Bad text/position/size are reported, not silently dropped | yes | no |
| Render job carries overlays; stored timeline unchanged | yes | no |
| Native: timed text and arrow overlays (Media3 TextOverlay / BitmapOverlay) | compiles on CI | no |

Not built: shapes other than an arrow, animation (fade/move), infographics.
The arrow is drawn around its centre, not its tip. A label spans one line.

## TE-5: Sound Design, one sound effect at a moment (branch claude/te-5-sound-design)

| Item | Automated | Phone-tested |
|---|---|---|
| Approved sound ops become effects on the OUTPUT time (follows cuts and held frames) | yes (te_compile_test) | no |
| Effects join the existing narration lanes in the render job (no new native code) | yes | no |
| Bad file/volume, time outside the video, past the end: reported | yes | no |
| Pick a file, volume slider in the TE dialog | no | no |

Not built: ducking (lowering music under narration), fades, trimming a long
effect, an effects library. Only use sounds you may use; the app cannot check.

## TE-6: Gemini suggestions by copy/paste (branch claude/te-6-ai-proposals)

| Item | Automated | Phone-tested |
|---|---|---|
| Prompt built from subtitles, duration, enabled tools and the user's instructions | yes (te_ai_test) | no |
| Reply read from a code fence or bare JSON; every suggestion checked | yes | no |
| Suggestions always enter as proposed/AI; compile only after the user approves | yes | no |
| Bad suggestions listed with a reason; at most 30 taken | yes | no |
| Copy prompt / paste reply buttons in the TE screen | no | no |

No API key and no network call. Gemini's own quality is not tested here.

## TE-7: Smart Cut and picture overlay (branch claude/te-7-smart-cut-pip)

| Item | Automated | Phone-tested |
|---|---|---|
| Approved Smart Cut ops remove source ranges from the render (other ops follow the cut) | yes (te_compile_test) | no |
| "Find gaps" suggests cuts from subtitle gaps (rule-based, proposed only) | yes (te_suggest_test) | no |
| Gemini prompt/reply understands smartCut | yes (te_ai_test) | no |
| Picture-in-Picture: a PICTURE as a timed overlay (position, width) | yes (model) | no |
| Native image overlay (Media3 BitmapOverlay) | compiles on CI | no |

NOT built: second-video picture-in-picture, Split Screen (needs multi-input
compositing in Media3, unverified), audio-based silence detection. A subtitle
gap is only a guess that nothing is said there, so cuts stay proposals.

## TE-8: Pre-render file check (branch claude/te-8-preflight)
The Render screen now refuses to start when a picture or sound file used by an approved TE operation is gone (app files only; `content://` links cannot be checked in advance). Automated: yes. Phone-tested: no.

## Still not built (TE)
Split Screen and second-video picture-in-picture need Media3 multi-input compositing. Without a phone to test on, writing them blind would only add code that may not work, so they wait for the phone results of the existing tools.
