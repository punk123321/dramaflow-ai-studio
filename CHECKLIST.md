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

## Phone result (user, 2026-11-12)
- A render with TE operations (including Freeze Frame) now produces an MP4 on the phone (APK from claude/te-8-preflight). Earlier "Asset loader error" is gone in that build.
- Not yet confirmed one by one: Crop framing, Freeze look and timing, label/arrow, picture overlay, sound effect, Smart Cut timing, Burmese text shaping.
- Cause of the earlier error is not proven. The build that works has the JPEG type set on the freeze picture and an input-file check before rendering.

## TE-9: Brightness & Contrast (branch claude/te-9-brightness)
| Item | Automated | Phone-tested |
|---|---|---|
| Approved look ops set brightness/contrast on video pieces (and held frames) for a time range | yes | no |
| Native: Media3 Brightness and Contrast effects | compiles on CI | no |

Mirror/flip is NOT built: its purpose here would be to get past platform
copyright checks, and it also reverses any text in the video.

## TE-10: Split Screen, EXPERIMENTAL (branch claude/te-10-split-screen)
| Item | Automated | Phone-tested |
|---|---|---|
| Approved split ops become output-time windows (second picture = another moment of the SAME video) | yes (te_compile_test) | no |
| Render job carries the windows | yes | no |
| Native: second video sequence + Media3 VideoCompositorSettings (both pictures at half size) | compiles on CI | no |

Written from the Media3 documentation without a phone to test on. Unknown until
tested: which input index is which, whether the half-size pictures are
positioned as intended, whether a gap in the second sequence stays invisible.
Not built: a second video FILE, more than two panels. If a render fails or looks
wrong with a split operation, remove that operation; other tools are unaffected.

## TE-11: Ratio, fill modes, platform presets, sample render, upload text, thumbnail (branch claude/te-11-ratio-presets)
| Item | Automated | Phone-tested |
|---|---|---|
| Output size from ratio (original, 16:9, 9:16, 1:1, 4:5), always even numbers | yes (publish_text_test) | no |
| Platform presets (Shorts, TikTok/Reels, YouTube, Feed, 1:1) set ratio, size, fps, fill | yes | no |
| Fill: black bars and crop (Media3 Presentation layouts) | compiles on CI | no |
| Fill: blur background (second blurred copy of the same video under the real picture), EXPERIMENTAL | compiles on CI | no |
| Blur falls back to black bars when a freeze frame or split is in the edit | yes | no |
| Sample render: first 8 s, not saved to history, does not mark the Render stage done | yes (pieces, narration, windows) | no |
| Upload text by Gemini copy/paste: parse + checks + credit lines from the Fair Use record | yes | no |
| Thumbnail: one frame of the original + text, saved to Pictures/DramaFlow (Android 10+) | compiles on CI | no |
| Thumbnail from the user's own designed picture (optional text), saved to Pictures/DramaFlow; original file untouched | compiles on CI | no |

Blur background was written from the Media3 docs without a phone. Unknown until
tested: which compositor input is drawn on top, and whether the real picture is
sized as intended. If it looks wrong, use black bars or crop; they do not use the compositor.
Platform presets are common settings, not a check against any platform's current rules.
Not built, on purpose: covering other people's watermarks, flip/mirror, voice cloning, link downloading.

## Phone result (user, 2026-11-12, APK from claude/te-11-ratio-presets)
- Confirmed OK by the user: 8-second sample render, Split Screen, blur background, 9:16 with black bars, crop.
- Not tested yet: Brightness/Contrast, Thumbnail (frame, own picture, Gemini text).
- Problem found: with 9:16 (TikTok/Shorts/Reels) text ran outside the picture. Fix: subtitles, labels and corner text are now wrapped to the picture width in the renderer (native/RenderEngine.kt wrapText). Phone-tested: no.

## TE-12: polish (branch claude/te-12-polish)
| Item | Automated | Phone-tested |
|---|---|---|
| Subtitle presets (5 looks) in the Editor | yes (limits, matching) | no |
| Subtitle fade in/out (250 ms, 5 steps) | JSON + compiles on CI | no |
| Warning in Render when the original video can no longer be opened | compiles on CI | no |
| Warning when narration, music or logo files are gone | yes | no |
| Backup of all projects to one JSON file; restore adds them as NEW projects, nothing overwritten | yes (parse, round trip, damaged input) | no |

Backup does NOT contain videos, audio, pictures or finished MP4s.
Not built: audio-based silence detection (cannot be tested without a phone, so it was left out rather than guessed).

## TE-13: optional Gemini API narration (same branch)
| Item | Automated | Phone-tested |
|---|---|---|
| Key, model and voice saved locally; works with no key (phone TTS, Mic, files unchanged) | yes (settings round trip) | no |
| Request body for both model families, reply reading (base64 PCM/WAV), WAV header, error text without the key | yes (gemini_tts_test) | no |
| Network call (dart:io HttpClient), INTERNET permission added to the manifest patch | compiles on CI | no |
| Audio saved to the app's audio folder and used as a normal narration clip | compiles on CI | no |

NOT verified: the real Gemini reply. The request shape for the newer "interactions" endpoint
was taken from the public docs and could not be called from the build machine. If the first
call fails, the app shows Google's error text; send it and the request is adjusted.
The key is plain text in the app's private database and is not in backups. Chunk text is sent to Google.

## TE-14: Gemini draws the thumbnail (same branch)
| Item | Automated | Phone-tested |
|---|---|---|
| Request (picture + aspect ratio), reply reading, settings with a separate picture model | yes (gemini_tts_test) | no |
| Publish screen: prompt, shape, "Gemini နဲ့ ဆွဲမယ်"; the result goes through the same own-picture path (add text, save to Pictures/DramaFlow) | compiles on CI | no |

Not verified against the real API (same as TE-13). Default picture model is gemini-3.1-flash-image
(from Google's Firebase documentation; the REST shape is the standard generateContent one).
The prompt text is sent to Google. No copyright guarantee for generated pictures; the default
prompt asks for original characters, no real people, no logos, no text.

## TE-15: fast lane for people who already have a Burmese SRT (same branch)
| Item | Automated | Phone-tested |
|---|---|---|
| Home tile "အမြန်လမ်း": pick video, bring in SRT (file or clipboard), choose original sound on/off, then Render and Save on one screen | compiles on CI | no |
| Whole video becomes one piece (the user's own cuts are kept if they exist); subtitles are burned in | compiles on CI | no |
| "ဒီအဆင့် မလိုဘူး၊ ကျော်မယ်" on the Gemini, TTS and Editor stages in the guided workflow (marks the stage done) | compiles on CI | no |

The fast lane does not make the video index, narration or edit. A skipped stage is only marked done.

## TE-16: cut video and SRT into parts at subtitle lines (same branch)
| Item | Automated | Phone-tested |
|---|---|---|
| Parts built from break lines; each part ends exactly where the next starts, at a line start; no picture lost | yes (srt_split_test) | no |
| Auto split every N lines / every M minutes (never mid-line); manual ✂ per line | yes | no |
| SRT of each part counts from 0:00, text unchanged, a line crossing the cut is shortened; overlap warning | yes | no |
| Save each part's SRT (file dialog per part) | compiles on CI | no |
| One MP4 per part, rendered one after another, optionally saved to Gallery each time | compiles on CI | no |

Parts are made from the original video only: no narration, no TE operations. Style, logo and corner text come from the Editor settings.

## TE-17: output file size control (same branch)
| Item | Automated | Phone-tested |
|---|---|---|
| Quality menu (Auto, 1 to 8 Mbps) and 480p in Render and in the SRT split screen | yes (bitrate and estimate tests) | no |
| Auto sets the video bitrate close to the original file's (never above the normal value for the size) | yes | no |
| Real file size matches the estimate | no | no |

Reason: the fixed 4 or 8 Mbps made a 1 GB original into about 6 GB. The size shown before rendering is an estimate; the encoder can differ.

TE-16 addition: every part has its own "MP4" button (renders just that part, then saves it to Gallery if the switch is on) next to "SRT". Phone-tested: no.

Fix (user report 2026-11-13): wrapped subtitle lines were left-aligned inside their box, so the text did not look centred. Subtitles and Motion labels are now centred line by line; corner text is aligned to its own side. Phone-tested: no.

## TE-18 — Background render + pause (te-12)

| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Foreground service + progress notification keeps render alive with screen off | Yes (CI green, 4c5832e) | **No** |
| Notification permission asked on Android 13+ | Yes (CI green, 4c5832e) | **No** |
| SRT split: "ခဏရပ်/ဆက်လုပ်" before the next part (multi-part runs) | Yes (CI green, 4c5832e) | **No** |

Limit: Media3 Transformer cannot pause mid-file. Pause waits until the current part ends; a single file can only be cancelled. Some phones' battery savers can still stop background work.

## Phone result (user, 2026-11-13, te-12 APK)
- Works: items 1-5 (centering/9:16 wrap, Brightness, thumbnail, presets/fade, Backup file saved) and items 7-9 (fast lane, SRT/video parts with per-part MP4, Auto quality file size).
- Restore did not work: the file picker probably hid the .json file (MIME filter lacked application/json). Fix: picker now accepts all types, import limit raised to 50 MB. Not phone-tested yet.
- Item 6 (Gemini API): request reached Google and the reply was read (403: free tier not available, billing needed). Result of picture/voice drawing itself is NOT confirmed. Chat route (copy/paste) needs no key. Error text now explains billing.
- Phone-confirmed (user, 2026-11-13): Restore works after the picker fix; pause/resume between parts works; render keeps going with the screen off (TE-18).

## TE-19: fit video to narration (te-12)
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| "ဗီဒီယိုကို အသံအတိုင်း ညှိ": piece N gets the length of voice N, voice starts at its piece; undo button | Yes (CI green, 4c5832e) | **No** |
Rules: pairs by order; piece end moves in the original video (the file is never changed); video too short is reported; extra voices/pieces are reported. Preview still does not play narration with the video.

## TE-20: Video Recap, Gemini watches the video (te-12)
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Home tile "Video Recap": per-part prompt (5 parts per prompt), Gemini open/copy, reply split by "=== PART n ===", save as narration script (one part = one voice) | Yes (CI green, 4c5832e) | **No** |
Limits: the app does NOT send the video; the user attaches it in the Gemini app. Whether Gemini can watch the video (length/size limits) and how good the script is are NOT checked. Parts come from Video Index, or 1-minute parts if none (then saved as the Video Index).

## TE-21: News (RSS) reader inside DramaFlow (te-12)
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Home tile "သတင်း (RSS)": loads the user's RSS/Atom feeds, newest first, category chips, pull to refresh, cached for offline | Yes (CI green, 4c5832e) | **No** |
| Tap a story: new layer slides in (title, source, age, snippet, "မူရင်းမှာ ဖတ်" opens the browser) | Yes (CI green, 4c5832e) | **No** |
| Recap script from a story: Gemini prompt (headline + snippet + user-pasted text), reply paste, "Project ဖန်တီး + script သိမ်း" | Yes (CI green, 4c5832e) | **No** |
| Feed manager: add/switch off/delete, suggestions restore | Yes (CI green, 4c5832e) | **No** |
Rules: only headline, link, time and a ~220 character snippet are kept; no article copy, no pictures, no video from news sites. Feed links in the suggested list were NOT checked (the build session could not reach them): the user must try them on the phone. Parser is tested on sample RSS/Atom text only, not on live feeds. News data is app-wide and not part of Backup.

## TE-22: Scene Recap (scene finding + contact sheet for Gemini)
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Home tile "Scene Recap": scenes found from colour changes between sampled frames (range, step 1/2/4 s, max scenes), long still scenes split at 45 s, "ပေါင်း" removes a wrong cut | Yes (CI green, 4c5832e) | **No** |
| Contact sheet (one numbered tile per scene, 12 per sheet) saved to Pictures/DramaFlow and shared to Gemini with the prompt; prompt includes the SRT lines of each scene | Yes (CI green, 4c5832e) | **No** |
| Reply "=== PART n ===" read per scene, saved as the narration script (one scene = one voice) and the scenes saved as the Video Index | Yes (CI green, 4c5832e) | **No** |
Unproven: how fast scene finding is on a long video on the phone; how well colour differences find real cuts (fades, fast action); whether the Gemini app accepts the shared picture with text; token savings (the per-token figures are from memory, not checked). Gemini cannot hear the audio in this mode, so an SRT gives much better scripts. Speech-to-text (Whisper or similar) is NOT built.

## TE-23: UI refresh (indigo/violet theme, big gradient tiles)
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| New theme: deep indigo page gradient, violet accent, rounded buttons/chips/snackbars/bottom bar | Yes (CI green, 4c5832e) | **No** |
| Home: hero banner, six big gradient tiles (Recap Studio, Voice Studio, Subtitle Studio, Video Editor, Render Center, More Tools), "More Tools" sheet holds every other module | Yes (CI green, 4c5832e) | **No** |
Unproven: how it looks on a real phone (no screenshot was taken, there is no local Flutter), tile text fit with Burmese fonts, contrast on the other screens after the colour change. Only the home screen was redesigned; the other screens only pick up the new colours and button/chip shapes. No "Projects" tab, no Translation Studio / Voice Clone screens (voice cloning is deliberately not built).

## Signing key moved out of the repo (before making the repo public)
The old keystore and its password were committed in the repo. A new key is created outside the repo; the workflow reads it from the GitHub secrets `DF_KEYSTORE_BASE64` and `DF_KEY_PASSWORD` and stops with a clear error if they are missing. The old key is still in git history, so it must be treated as public and never used again. **APKs signed with the new key do not install over APKs signed with the old key: back up in the app, uninstall, install, restore.** Compiles on CI: yes (4c5832e; build with the new secrets worked, the APK signature itself was not inspected). Phone-tested: **No**.

## TE-24: UI refresh, all screens
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Every screen except Home sits on the same indigo gradient (shared `DfScaffold`), transparent app bar with bold title | Yes (CI green, run 44228633814) | **No** |
| Home: "Project အသစ်" is a wide gradient button under the tiles (the floating button covered the resume card); duplicate "ဆက်လုပ်ရန်" title removed | Yes (CI green, run 44228633814) | **No** |
| Settings tab is a real screen: optional Gemini key + model (save / remove), Backup / Restore link, short About | Yes (CI green, run 44228633814) | **No** |
Unproven: how each inner screen looks on the phone (only Home has been seen in a screenshot). The inner screens keep their old layouts; only the background, app bar, buttons and chips changed. No Language/Theme switch (nothing to switch yet). No Projects tab. Voice Clone is deliberately not built.

## TE-25: inner screens restyled (Render Center, Subtitle Studio, Workflow)
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Render Center: "ထုတ်ဖို့ အဆင်သင့်လား" checklist (video readable, pieces, voices, subtitles), progress ring with % and a time-left guess (elapsed ÷ percent, a guess only), gradient "MP4 ထုတ်မယ်" button | Yes (CI green, run 44260535793) | **No** |
| Subtitle Studio: rounded list cards, bigger preview, bottom bar "အချိန်ရွှေ့ / ပြင် / SRT သိမ်း" (the same actions as the menu) | Yes (CI green, run 44260535793) | **No** |
| Workflow: project header and step cards in the new card style | Yes (CI green, run 44260535793) | **No** |
Unproven: how they look on the phone. Not done yet: Voice Studio tabs, Video Editor tool row, "Projects" tab, Translation Studio screen. The progress steps in the mockup ("Preparing / Applying subtitles / Rendering") are NOT shown because the render engine does not report such steps; only the percent is real.

## TE-26: less clutter
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Long explanation paragraphs (Render, Video Recap, Scene Recap, Quick, SRT split) shrink to one "ℹ ရှင်းလင်းချက်" line, tap to read | Yes (CI green, run 44264606257) | **No** |
| Render: resolution / fps / quality moved into a collapsed "အဆင့်မြင့် setting" (its summary line shows the current values); "ဖုန်းမှာ ကျန်နေရာ" row removed (the low-space warning stays) | Yes (CI green, run 44264606257) | **No** |
| Subtitle Studio: only empty / bad-time / overlapping lines count as problems; "hard to read fast / long line" are only counted, not flagged on each line | Yes (CI green, run 44264606257) | **No** |
Unproven: how it looks on the phone. The rule thresholds (17 characters per second, 42 per line) did not change.

## TE-27: Video Editor + TE are one editor
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| One screen (Home "Video Editor" tile and Workflow Stage 4): preview, effect list, pieces, narration, subtitles; the separate "Transformative Editor" tile and its Mode selector are gone (the stored mode is kept) | Yes (CI green, run 44309080019) | **No** |
| Preview shows the first frame at once, scrubber with effect markers (green = approved, orange = proposed), play/pause | Yes (same run) | **No** |
| Effects drawn on the preview at the playhead: crop/zoom, brightness/contrast, text/arrow/picture; badges for cut, freeze, split, sound. Proposed (AI) effects are shown too, slightly faded, so a suggestion can be judged before approving. It is an **approximation**; the render makes the real result | Yes (same run) | **No** |
| Text/arrow/picture can be dragged on the preview (position saved on release) | Yes (same run) | **No** |
| Effect list: tap = jump to its start, approve / reject / edit (same dialog, pre-filled) / delete, "add at playhead", "approve all pending", find quiet stretches, Gemini copy-paste (collapsed) | Yes (same run) | **No** |
| TE plan saves at once on every change (no save button) | Yes (same run) | **No** |
| Pure helper `te_preview.dart` (which effects are active at a time, crop, look matrix, badges) | Yes, 9 tests (same run) | n/a |
Unproven: how the preview overlays line up with the render on a real video; the dragging gesture inside a scrolling page; the marker bar alignment with the slider (approximate). Smart cut is only dimmed in the preview, playback does not skip it. Split screen and Sound are shown as badges only. APK: artifact `dramaflow-apk-branch-119`. Not merged to main. APK artifact `dramaflow-apk-branch-191`.

## TE-28: edit effects directly on the preview
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Tap an effect (list, timeline block or overlay on the picture) to select it; its values are edited right under the preview with sliders (no dialog): zoom, brightness/contrast, freeze seconds, text, size, angle, colour; "start/end ← here" sets the time from the playhead | Yes (CI green, run 44311061814) | **No** |
| Crop/zoom by pinch (zoom) and drag (move) on the preview itself, only while the playhead is inside that effect | Yes (same run) | **No** |
| Unproven: pinch/drag inside a scrolling page may fight with the page scroll |  |  |

## TE-29: timeline-editor layout
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Transport row: undo / redo (effect list only, 50 steps), play/pause, time `mm:ss.t / total` | Yes (CI green, run 44431045192) | **No** |
| Bottom tool row: Text, Arrow, Zoom, Filter, Freeze, Cut add an effect at the playhead in one tap; Picture and Sound open the detail dialog | Yes (same run) | **No** |
| Multi-track timeline on the original video's time: ruler (tap/drag to move the playhead), Video track (kept pieces), subtitle track, one coloured block per effect (overlapping effects on separate rows), zoom in/out, follows the playhead while playing | Yes (same run) | **No** |
| `assignLanes` helper | Yes, 2 tests (same run) | n/a |
NOT built: Border (frame around the video), gradient text box with corner resize handles, Canvas (aspect ratio / background), AI Hook, Voice track in the timeline (narration lives on the edit time, not the original time), dragging block edges to trim, full-screen preview. Border and gradient text need changes in the render engine (native/RenderEngine.kt), which cannot be tested here. APK: `dramaflow-apk-branch-122`. Not merged to main. APK artifact `dramaflow-apk-branch-191`.

## TE-30: more effects (all under Motion Graphics)
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Box and Circle: an outline to point at something; drag to move, corner dot to resize (width and height) | Yes (CI green, run 44433026494; Kotlin compiled) | **No** |
| Spot: the whole picture is dimmed except one window (oval or rounded rectangle); centre button moves it, corner dot resizes | Yes (same run) | **No** |
| Border: a frame around the whole video, rainbow or one colour, thickness slider; added for the whole video by default | Yes (same run) | **No** |
| Label with a colourful (violet to pink, gold edge) background, as an option on the text effect | Yes (same run) | **No** |
| Filter presets (dark mood, bright, high contrast, soft) set brightness/contrast only | Yes (same run) | **No** |
| Tool row: Box, Circle, Spot, Border added; the detail dialog keeps the values of these effects (they are edited with the sliders under the preview) | Yes (same run) | **No** |
| Parameter checks (`motionFromParams`) for the new kinds | Yes, 5 tests (same run) | n/a |
Unproven: the render drawing (native/RenderEngine.kt) of all of these, how closely the preview matches it, and Burmese text on the colourful label background (drawn with StaticLayout). The AI (Gemini) prompt still only suggests label and arrow. NOT built: fade in/out, speed change (slow/fast), transitions between pieces, saturation / black-and-white / warm-cool filters (the render only has brightness and contrast), Canvas (aspect/background), blur or mosaic boxes (deliberately not built: they could be used to hide someone else's watermark). Not merged to main. APK artifact `dramaflow-apk-branch-191`.

## TE-31: more effects (Motion Graphics kinds)
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Fade in / Fade out / Flash (dip, white or colour), length slider | Yes (CI green, run 44441551934; Kotlin compiled) | **No** |
| Vignette (dark edges), Tint (warm / cool / sepia / red / green colour wash), Cinema bars, Shade (dark gradient from top or bottom edge for readable text) | Yes (same run) | **No** |
| Box / Circle can be filled like a marker | Yes (same run) | **No** |
| Sticker: tap an emoji, it is added as a big label without background | Yes (same run) | **No** |
| Tool row is longer (scrolls sideways): Text, Arrow, Box, Circle, Spot, Border, Sticker, Zoom, Filter, Freeze, Cut, Fade in/out, Flash, Tint, Vignette, Bars, Shade, Picture, Sound | Yes (same run) | **No** |
| Parameter checks + `fadeAlpha` | Yes, 2 more tests (same run) | n/a |
Unproven: the render drawing of all these (native/RenderEngine.kt: fade uses a changing alpha per frame, the others are full-size pictures, sharing one empty picture when hidden), memory use with many of them on a long 1080p video, emoji drawing in the render text, and the preview showing subtitles above a fade (the render covers them). Whole-video effects (Border, Vignette, Tint, Bars, Shade) are added for the whole video; trim with the start/end buttons. NOT built: black-and-white / saturation (the render has no saturation control), speed change, transitions between pieces, blur / mosaic (not built on purpose: it can hide someone else's watermark), mirror/flip, pitch change. Not merged to main. APK artifact: `dramaflow-apk-branch-126`.

## TE-32: Speed change
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Speed effect (0.25x to 4x, pitch kept) on a time range: tool row "Speed", presets 0.25 / 0.5 / 0.75 / 1.5 / 2 / 3 / 4, slider; detail dialog too | Yes (CI green, run 44476310269; Kotlin compiled after one fix: Media3 1.8 has no `setSpeed`, so `SpeedChangeEffect` + `SpeedChangingAudioProcessor` are used) | **No** |
| Compile: the range splits the pieces, the middle gets the speed; output length, overlay/sound/split times and subtitles follow the speed (`VideoPiece.speed`, never saved in the saved timeline) | Yes, 6 tests (same run) | n/a |
| Preview plays at that speed while the playhead is inside the range, badge shows the speed | Yes (same run) | **No** |
Unproven (all of it on a phone): the render result (picture and sound staying in sync at other speeds, the blurred background copy matching the length, very slow 0.25x on long ranges), the preview speed switching. Narration is placed on the OUTPUT time: after adding a Speed effect, re-check where the voices sit ("fit video to voices" is not redone automatically). Not merged to main. APK artifact `dramaflow-apk-branch-130`.

## TE-33: Subtitle Studio as a hub (Quick lane, SRT edit/check, SRT split)
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Subtitle Studio has three tabs along the bottom (icons): edit / check, Quick lane (SRT you already have to an MP4), split video + SRT into parts | Yes (CI green, run 44523463164; analyze, tests and Kotlin build passed) | **No** |
| Home: the separate "Quick lane" and "SRT split" tiles are removed; the Subtitle Studio tile opens the hub | Yes (CI green, run 44523463164; analyze, tests and Kotlin build passed) | **No** |
| Less text: icon buttons (video/SRT pick, undo, shift, save, per-part SRT/MP4), count + warning chip instead of sentences, short hints | Yes (CI green, run 44523463164; analyze, tests and Kotlin build passed) | **No** |
| Behaviour kept: all functions of the three old screens still exist; the editor reloads the SRT when you come back to its tab, the split tab reloads after the SRT was changed | Yes (CI green, run 44523463164; analyze, tests and Kotlin build passed) | **No** |
Unproven (phone): that all three tabs work inside one screen (render panel and long split runs keep running when switching tabs because the tabs stay alive), icons being understandable without text (tooltips on long-press), the editor reloading correctly after the quick lane brings in a new SRT. Not merged to main. APK artifact `dramaflow-apk-branch-191`.
Review fix for TE-33 (found when re-reading the code, not on a phone): undo in the editor tab did not tell the other tabs the SRT had changed, and the quick lane tab kept showing the old SRT count after edits in the editor tab. Now both tabs read the SRT again when opened after a change (without being rebuilt, so a running split export is not stopped), and undo steps are dropped when the quick lane replaced the SRT. Still **not** phone-tested.

## TE-34: Blur and Mirror / Flip (taken from PR #6 and rebuilt on the current editor)
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Blur (Gaussian, strength 0.5–50) and Mirror / Flip (left-right and/or top-bottom) as TE operations on a time range; tool row "Blur" and "Flip", presets and sliders under the preview, detail dialog, timeline blocks | Yes (CI green, run 44579032309; analyze, tests, Kotlin build passed) | **No** |
| Compile: only approved, valid operations set `blur` / `flipH` / `flipV` on the pieces; they combine with crop, speed and freeze frame (a freeze keeps them); never saved in the plain timeline | Yes (CI green, run 44579032309; analyze, tests, Kotlin build passed) | n/a |
| Preview: the video is blurred (strength scaled down, an estimate) and mirrored while the playhead is inside the effect; subtitles and labels are NOT mirrored | Yes (CI green, run 44579032309; analyze, tests, Kotlin build passed) | **No** |
| Render (native): `GaussianBlur` and `ScaleAndRotateTransformation` (scale -1) on video pieces and on freeze stills; overlays and subtitles are added afterwards so they stay readable | Yes (CI green, run 44579032309; analyze, tests, Kotlin build passed) | **No** |
Taken from PR #6: the compile/JSON design (keys `bl`, `fh`, `fv`), Kotlin effects and the parameter checks. NOT taken: the "global border template" (40 frames) in that PR: it had a Kotlin compile error (`sy` is not defined, so its CI failed) and the current Border effect already covers a frame; and its old Editing-stage UI, which this editor replaced. PR #6 stays open, nothing was merged from it by Git, so it can be closed.
Not offered to the AI (Gemini) proposals: the AI can only propose cut, crop, freeze, label and arrow. Both effects are described as creative tools only; Mirror / Flip must not be used to get around a platform's copyright check, and the app does not claim it helps with that. Unproven on a phone: the render result of both effects (blur strength in pixels versus the preview estimate, a flip together with crop/zoom, a flip on a blurred-background layout), memory use. Not merged to main. APK artifact `dramaflow-apk-branch-195`.

## TE-35: Blur box (rectangle blur, to censor part of the picture)
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| "Censor" in the tool row: a rectangle you drag and resize (corner dot) on the preview, strength slider under it; time range set like any effect; up to 3 at once | Yes (CI green, run 44650568363) | **No** |
| Preview: the rectangle really blurs what is behind it (strength scaled down, an estimate) | Yes (CI green, run 44650568363) | **No** |
| Render (native): a second picture of the same video is made with the SAME effects as the piece (speed, filter, zoom, flip), cut down to the rectangle (`Crop`), blurred (`GaussianBlur`), and drawn over its place only while the box is on (`CensorCompositor`, like the split screen). Works with cuts, speed changes and freeze frames | Yes (CI green, run 44650568363) | **No** |
| Fail-safe: if the box cannot be made (outside the picture, at the same time as Split Screen / blurred background, half of a slow-zoom piece) the render stops with an error and nothing is exported uncensored. Split Screen is dropped (with a note) when a box is used; the blurred background becomes black bars | Yes (CI green, run 44650568363) | n/a |
Meant for censoring sensitive parts of your own video; the editor says it must not be used to cover someone else's watermark or logo. Unproven on a phone (all of it): that the overlay lands exactly on the preview rectangle (scale / anchor meaning in Media3 1.8), blur strength in the render versus the preview estimate, three decoders at once on a long 1080p video (memory, time), freeze frames inside a box. CHECK THE EXPORT BY EYE before publishing anything. Not merged to main. APK artifact `dramaflow-apk-branch-197`.

## TE-36: Video Index: download all segments at once
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Under the segment list: one "download all" button makes an MP4 of every segment, one after another, and puts each in the Gallery (file name `<project>_segNN_<time>`); a download icon on each row does just that one; progress bar, pause (after the current segment) and stop | Yes (CI green, run 44651575811) | **No** |
| Options: original sound on/off, 480p / 720p / 1080p (quality follows the source file size) | Yes (CI green, run 44651575811) | **No** |
Picture and sound of the original only, no subtitles, original ratio. It re-encodes (the same render as the Render stage), so a 10-minute segment takes a while; the original file is never changed. Unproven on a phone: the whole run with many segments (time, heat, storage), keep-alive when the screen turns off, the Gallery save on each Android version, stopping in the middle. Not merged to main. APK artifact `dramaflow-apk-branch-198`.

## TE-37: ready-made Frame templates
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Tool row "Frame" opens a gallery with small pictures of 12 designs (Classic, Double, Gold, Neon, Film strip, Polaroid, Viewfinder, Cinema, Rounded, Dotted, Vintage, Rainbow glow) plus the old plain / rainbow border; tap one to put it on the whole video | Yes (CI green, run 44684055369) | **No** |
| Under the preview, a design strip switches the design of a selected frame; thickness slider; colour swatches for the designs that take a colour | Yes (CI green, run 44684055369) | **No** |
| One drawing list (short-side units) is made in Dart and drawn by BOTH the preview and the render (Kotlin canvas), so they look alike; the list is made for the real output size when the render job is built | Yes (CI green, run 44684055369) | **No** |
Unproven on a phone: how each design looks in the real render (glow blur, dotted line with round caps, the film-strip holes, gold / rainbow gradient), thin lines on a low-resolution output, and that the frame overlay does not hide subtitles badly (subtitles are drawn on top). The designs that cover the edges (Film, Polaroid, Cinema, Vintage) hide a strip of the picture; they do not shrink it. Frames are drawn by the app only; no pictures or fonts from other places are used. Not merged to main. APK artifact `dramaflow-apk-branch-199`.

## TE-38: "Aurora glass" look + Video Index download options
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| New theme: indigo base with soft violet / cyan / pink glows behind every page, glass cards (light veil + bright edge + shadow), themed dialogs, sheets, sliders, switches, menus | Yes (CI green, run 44685765147) | **No** |
| New bottom bar: the chosen tab grows into a violet pill with its name; press-shrink on buttons, tiles and chips; tiles fade in one after another | Yes (CI green, run 44685765147) | **No** |
| Home re-laid out: header with logo, "continue" glass card (or a start card), Studio tiles 01–05 with icon chips, Tools as chips (the old "More Tools" sheet is gone), glass project rows | Yes (CI green, run 44685765147) | **No** |
| Video Index segment download now also has output ratio and video quality (Mbps), like the SRT split screen | Yes (CI green, run 44685765147) | **No** |
Unproven on a phone: how the glows, glass blur and nav pill look and perform on a real device (the blurred hero card is the only heavy part), text contrast, and the animation smoothness. Only Home and the shared widgets were redesigned by hand; other screens get the new look through the theme and shared cards, so some may still look plain. Phone test found a bug in this APK (201): the bottom bar grew to the whole screen height and hid every page. Fixed (fixed bar height), CI green run 44723159162, APK `dramaflow-apk-branch-203`; the fix is not yet phone-tested. Not merged to main.

## TE-39: Studio pages opened straight from Home
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Video Index, Recap Studio, TTS / MP3 and Render Center now open as their own full page (like Subtitle Studio) instead of jumping to the Workflow tab; the page shows the same panel as the Workflow tab, the project header, and a "stage done" switch | Yes (CI green, run 44727168604) | **No** |
| Home Studio grid now has 6 tiles: Video Index, Recap Studio, Scene Studio, TTS / MP3, Subtitle Studio, Video Editor; Render Center is the wide tile; step numbers removed | Yes (CI green, run 44727168604) | **No** |
The Workflow tab still exists and shows all stages in order. Scene Studio is the old Scene Recap screen, only renamed and moved up to the grid. Unproven on a phone: that every panel behaves the same on its own page as inside the Workflow tab. Not merged to main. APK artifact `dramaflow-apk-branch-205`.

## TE-40: colour strength / B&W, drag the edges of an effect, fullscreen preview
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Filter effect has a colour-strength slider (−100% = black and white, +100% = twice as colourful) and chips "B&W", "အရောင်ထင်", "အရောင်မှိန်"; the preview shows it, and the render applies it with Media3's saturation adjustment | Yes (CI green, run 44730339071) | **No** |
| Timeline: the selected effect shows two white grips on its edges; drag to make it shorter or longer (min 0.2 s, stays inside the video); the change is saved when the finger lifts | Yes (CI green, run 44730339071) | **No** |
| A fullscreen button on the preview opens the video in landscape with play / pause, seek and the filter, crop, blur and flip applied (texts, overlays and subtitles are not drawn there) | Yes (CI green, run 44730339071) | **No** |
Old saved timelines load as before (the look was two numbers, it is now two or three). Unproven on a phone: that the saturation in the render matches the preview (the preview uses a colour matrix, the render uses Media3's saturation; they can differ a little), grip dragging next to the horizontal scroll of the timeline, and the fullscreen rotation coming back to normal. Not built on purpose: transitions, Canvas and a voice track in the timeline (changes the render path, better after the phone tests), Speech-to-Text (needs a paid service or a large model). Not merged to main; branch `claude/te-40-upgrades`. APK artifact `dramaflow-apk-branch-208`.

## TE-41: AI Hook, optional AssemblyAI speech-to-SRT, glass look on the other screens
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| New Gemini prompt "အစ ဆွဲဆောင်စာ (Hook)": 5 opening lines of 3 to 5 seconds, facts from the text only, no ending spoilers (copy/paste like the other prompts) | Yes (CI green, run 44768403494) | **No** |
| Settings: optional AssemblyAI key and language code (stored on the phone, not in backup). Subtitle Studio: new icon "အသံကနေ SRT ထုတ်" cuts the sound out of the video (Kotlin MediaExtractor + MediaMuxer to .m4a, no re-encode; copies the whole video if the sound is not AAC), uploads it, waits, downloads the SRT, and replaces the Studio text only after asking (undo brings the old text back) | Yes (CI green, run 44768403494) | **No** |
| Glass style on Workflow step cards, Library, drama pages, Settings, effect list, timeline, Fair Use, cards in the editor; Subtitle Studio bottom bar uses the same nav pill | Yes (CI green, run 44768403494) | **No** |
| Widget tests for the nav bar (it stays a bar at the bottom, the page keeps its space), tabs, buttons, Reveal / Glass / Pressable; tests for the AssemblyAI request and reply handling | Yes (CI green, run 44768403494) | n/a |
Unproven: everything that talks to AssemblyAI. The request was written from AssemblyAI's own docs (upload, create transcript with language_code, poll, /srt?chars_per_caption=28) but has never been run with a real key; the language code "zh" / "my" is not confirmed by the docs (the field in Settings can be edited; the error text from the service is shown); Mandarin accuracy on drama audio, Burmese accuracy (docs list it as "fair"), upload time and data use, whether the sound cut-out works for every phone video (AAC only; otherwise the whole video is copied to the cache and uploaded), and whether the free credit is still given. Not merged to main; branch `claude/te-40-upgrades`. APK artifact `dramaflow-apk-branch-211`.

## TE-42: News Video (own Colab backend) 
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| `tools/news_backend_colab.py` (backend v2): jobs with progress (POST /jobs, GET /jobs/<id>, download), access token, keys not stored, per-scene start/end seconds, ffmpeg errors reported, same encode settings for every clip, strict grounding really sent, real length measured. Only syntax-checked (py_compile); never run | n/a (Python, not built by CI) | **No** |
| Home > Tools > "News Video" screen: paste "URL#TOKEN" from Colab, Pexels key (optional), Gemini key from Settings, topic, 3 to 5 minutes, 9:16 / 16:9, voice, sources, strict grounding, 4 master prompts (editable); progress; result with scenes; save MP4 to Gallery, save SRT (made from scene timing), copy script | Yes (CI green, run 44847621657) | **No** |
| Tests for the connect line, settings, request limits, job reply, SRT from scenes | Yes (same run) | n/a |
Unproven: the backend has never run (not in Colab, not with real keys); Edge TTS Burmese voices, Gemini with Google Search grounding (may need billing or have a free quota; not checked), Pexels downloads, the Cloudflare tunnel, Colab terms for serving a tunnel, ffmpeg concat of the clips, and the app screen on a phone. The video has no burned-in subtitles, ticker or logo (the backend has no Burmese font); the SRT is for the app's own render. News content is made by AI: facts are not verified. APK artifact `dramaflow-apk-branch-213`.

## TE-43: Video Editor page like a phone video editor
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Video Editor page: preview (max about a third of the screen), play bar (undo, redo, previous / play / next, fullscreen) and the tool row stay on top; the timeline, effect editor, effect list and the rest scroll underneath. The workflow's Stage 4 still scrolls as one page | Yes (CI green, run 44848369562) | **No** |
| "Export Video" button on the editor's top bar opens the Render page | Yes (CI green, run 44848369562) | **No** |
| Previous / next jump to the previous / next effect start (or the ends of the video) | Yes (CI green, run 44848369562) | **No** |
Unproven on a phone: the proportions on small screens (the scrolling part may be short when an effect is selected), keyboard covering the editor fields, and portrait videos (preview is capped by height). Not merged to main. APK artifact `dramaflow-apk-branch-214`.

## TE-44: Automatic Video Recap / Scene Recap (own backend) + more stock sources for News Video
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| `tools/dramaflow_backend/` (FastAPI, for Altare / Colab / any Python host): POST /recap/jobs, GET /recap/jobs/<id>, GET .../audio/<n>.wav; asks Gemini per group, reads "=== PART n ===", Edge TTS Burmese voice per part (24 kHz mono WAV); token via APP_TOKEN; keys not stored and hidden in errors. The pure part (`recap_core.py`) has 8 unit tests that pass locally (`python3 -m unittest`); `main.py` is only py_compile-checked, never run with Gemini / Edge TTS / on Altare | n/a (Python, not built by CI) | **No** |
| Scene Recap > "Auto": makes the contact sheets, sends them with the prompts to the backend, saves the returned parts like pasted answers; "Script အဖြစ် သိမ်း" then "အသံကို project ထဲ သိမ်း" stores the WAVs as stage-3 audio (only when script chunks and parts match one-to-one) | Yes (CI green, run 44875365857) | **No** |
| Video Recap > "Auto": copies the video to the app cache (new native `copyVideo`), uploads it to the user's own Gemini Files API (resumable), backend asks Gemini for each 5-part batch with a start/end offset of the video | Yes (CI green, run 44875365857) | **No** |
| News Video: background source choice: Wikimedia Commons (no key), Pixabay (video), Unsplash (picture), Pexels; pictures get a slow zoom-in (Ken Burns, ffmpeg zoompan, command tested locally); falls back to Wikimedia when the chosen source finds nothing; older Pexels saves still load | Yes (CI green, run 44875365857) | **No** |
APK artifact `dramaflow-apk-branch-217`. Not merged to main.
Unproven: everything that talks to the network (Gemini video offsets via `video_metadata`, Files API upload of a big video from a phone, Edge TTS Burmese, Pixabay / Unsplash / Wikimedia answers, Altare free app staying on, its URL and body-size limits), the Kotlin `copyVideo` on a phone, matching of chunks to parts on a real script. Video upload uses a lot of data and Gemini free-tier quota; scene mode is far lighter. Wikimedia / Unsplash pictures may need credit.

## TE-45: News Video: about 20 pictures found at once and put in order
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Backend: Gemini gives 2 to 3 search phrases per scene; for each scene the backend finds as many different pictures as its voice length needs (about one per 12 s for 20 pictures in 4 minutes, at most 4 per scene, never the same picture twice), splits the scene time equally and joins them in story order with a slow zoom that alternates in / out. Sources: Wikimedia Commons (no key), Unsplash, Pixabay photos; nothing found: falls back to Wikimedia, then a plain colour. Video sources (Pixabay video, Pexels) still use one clip per scene. Helpers tested locally with ffmpeg (`python3 tools/test_news_helpers.py`: picture count rule; 3 pictures + voice become one 720x1280 scene of the right length; scenes of different kinds join without decode errors). The searches and downloads (Wikimedia, Unsplash, Pixabay) have never run | n/a (Python) | **No** |
| App: "Pixabay (ပုံ)" source; slider for the number of pictures (0 to 40, default 20, 0 = one per scene); the on-screen source, key and count are saved when a video is started; Pixabay pictures reuse the Pixabay key | Yes (CI green, run 44903753550) | **No** |
APK artifact `dramaflow-apk-branch-221`. Not merged to main.
Gemini model default changed to `gemini-3.8-flash` (the old `gemini-2.5-flash` answered 404 NOT_FOUND on the user's account, seen on the phone); the model name is editable in the News Video screen and the Recap Auto card.
Phone result seen: with Google Search on, Gemini answered 429 RESOURCE_EXHAUSTED on the user's free account; a "Google Search" switch (default on) was added to the News Video screen; when off the backend writes without search and warns that facts are unchecked.
Unproven: picture search quality (keywords may find unrelated pictures; the app does not show them before rendering), Wikimedia / Unsplash licences and credit, portrait crop of landscape pictures, Colab speed with many ffmpeg steps (each scene several encodes). Re-run Cell 2 of the notebook to get the new backend.

## TE-46: Stage 3 (Audio): Edge TTS through the user's backend
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Backends (`news_backend_colab.py` and `tools/dramaflow_backend/main.py`): new `POST /tts` (text, voice, rate) answers a 24 kHz mono WAV; token needed; text up to 6000 characters; only syntax-checked, never run (Edge TTS, ffmpeg) | n/a (Python) | **No** |
| Audio panel: "Edge TTS" card (paste the same URL#TOKEN as News Video, voice Thiha / Nilar), per-chunk "Edge TTS" button and "all missing" button; the speed slider is sent as a percentage; the clip is stored like the other TTS clips (label "Edge TTS") | Yes (CI green, run 44908315451) | **No** |
APK artifact `dramaflow-apk-branch-224`. Not merged to main.
Unproven: Edge TTS Burmese voices through the unofficial library (Microsoft may block or change it), Colab tunnel with the request, long chunks (up to 1500 characters per chunk). Text of the chunk goes to the user's backend and from there to Microsoft's voice service.

## TE-47: Video Editor tool tabs
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| The editor's tool row (24 tools in one long strip) is split into 4 tabs like a phone video editor: စာ / ပုံ (Text, Arrow, Box, Circle, Spot, Frame, Sticker), Edit (Zoom, Speed, Flip, Freeze, Cut), Effect (Filter, Blur, Censor, Fade in/out, Flash, Tint, Vignette, Bars, Shade), Layer / အသံ (Picture, Sound). The same tools and actions as before; only the grouping changed. No widget test (the editor needs a video player) | Yes (CI green, run 44980733356) | **No** |
APK artifact `dramaflow-apk-branch-227`. Not merged to main.
Unproven on a phone: the extra row (about 34 px) in the pinned top part on small screens. Not built: a "+" add button and Canvas / Audio tabs (there is no Canvas feature).

## TE-48: Hardening after the first phone results
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Video Recap upload: the video type is found from the file's first bytes (mp4, mov, 3gp, webm, avi, flv, wmv, mpeg) instead of always saying mp4; a refusal by Gemini now says which types work. Unit tests for the detection | Yes (CI green, run 45000512970) | **No** |
| Backends: Edge TTS tried 3 times (it sometimes drops a request); Gemini script call retried on 503 / overloaded (not on 429 quota). Not run (Python, only syntax-checked) | n/a (Python) | **No** |
Unproven: the retry waits in Colab, and MKV (the check cannot tell it from WebM; Gemini may refuse it and the message says so). APK artifact `dramaflow-apk-branch-230`. Branch `claude/te-48-hardening`, not merged.

## TE-49: AssemblyAI inside Video Recap / Scene Recap
| Feature | Compiles on CI | Phone-tested |
|---|---|---|
| Both recap screens: "အသံကနေ စာတန်းထုတ် (AssemblyAI)" button when the project has no subtitles (uses the existing AssemblyAI key and dialog; saved as the project's source subtitles) | not built yet (user asked for no APK for now) | **No** |
| Auto card: switch "စာတန်းမရှိရင် AssemblyAI နဲ့ ထုတ်" (on by default when a key exists): when the project has no subtitles, the video's sound is sent to AssemblyAI first, the SRT is saved and read, then the scenes/parts get their dialogue, then Gemini and Edge TTS run. The consent box names AssemblyAI when it will run | not built yet | **No** |
| Video Recap prompts (manual and Auto) now include each part's subtitle lines (cut to 600 characters) with a warning that speech-recognition text may be wrong; tests added | not built yet | **No** |
Unproven: everything (not even compiled: no Flutter here and no push so no CI). The AssemblyAI request itself has also never run with a real key. Branch `claude/te-48-hardening` plus local commit only.

## TE-50: Recap upgrades (backend + app) — also holds TE-49 (AssemblyAI in the recap screens)
| Feature | Tested here | Compiles on CI | Phone-tested |
|---|---|---|---|
| Backend: text cleaned before the voice (emoji, `*`/`#` marks and (stage directions) removed; whole numbers 0–99 spelled in Burmese; times, decimals, years left alone) | Python unit tests pass. Whether Edge TTS reads the result better is **unknown** | n/a (Python) | **No** |
| Backend: voice up to 15% too long for its video part is sped up (ffmpeg atempo, pitch kept); remaining mismatch is a warning. App sends each part's video length (`part_ms`) | Python tests with a stand-in voice and real ffmpeg | Dart part: see CI | **No** |
| Backend: each Gemini request after the first gets the last 300 characters of the story so far, to keep names/events consistent | Python test | n/a | **No**. Whether it makes scripts better is unproven |
| Backend: finished job is kept in a file, so the app can still fetch it after the web process restarted (not after a machine restart) | Python test | n/a | **No** |
| Backend `/selftest` + app **Self-test** button (ffmpeg, Edge TTS, Gemini key/model; Burmese hint for 404/429/key errors) | Python test with stand-ins; Dart parser test | see CI | **No** |
| App: "မရတဲ့ အပိုင်း ပြန်လုပ်" button: asks only the groups that miss parts, reuses the Gemini video upload, merges with parts already saved | Dart helper tests (`missingParts`, `groupsFor`) | see CI | **No** |
Not real: the backend was tested only with stand-ins for fastapi, edge-tts and Gemini (no network, no package installs here). Real FastAPI routing, real Edge TTS and real Gemini replies are untested. The Colab notebook `tools/dramaflow_recap_colab.ipynb` clones branch `claude/te-40-upgrades`, which does NOT contain these backend changes (they are on `claude/te-48-hardening`); until this is merged and the notebook points at the merged branch, Colab runs the old backend and the app's Self-test button will say the backend does not know it. Altare deploys from whichever branch is chosen.

CI (run 45003681194, commit 7a6dbc4, branch `claude/te-48-hardening`): `flutter analyze` 100 infos (same 100 as before: the deprecated `material.dart` import; no warnings or errors), `flutter test` 351 passed, release APK built (artifact `dramaflow-apk-branch-232`). So TE-49 and TE-50 **compile on CI and their tests pass**. Phone-tested: **No**. Not merged into main.

## TE-51: more recap upgrades
| Feature | Tested here | Compiles on CI | Phone-tested |
|---|---|---|---|
| Optional "အရန် model" field (Auto card): if the main Gemini model is gone (404) or over quota after 3 tries, the backend asks the second model; saved on the phone | Python tests with stand-in Gemini (404 -> fallback, 429 x3 -> fallback, no fallback -> error) | see CI | **No**. The right second model name is yours to type; I cannot check which names exist |
| Confirmation box says how many minutes of sound go to AssemblyAI (from the project's video length) | Dart helper test | see CI | **No** |
| "ဒီနေ့ ဒီဖုန်းက ပို့ခဲ့တာ (ခန့်မှန်း)" line: Gemini requests (one per group), AssemblyAI minutes, voice parts, stored on the phone, reset each day | Dart tests of the counter | see CI | **No**. It is the app's own estimate, not the service's real quota |
Already covered, not new work: an AssemblyAI result is saved as the project's subtitles and Auto does not run it again when subtitles exist, so a second Auto run does not spend credit twice; language auto-detect (empty code) already exists in Settings.

CI (run 45029307868, commit b9b0ff2): `flutter analyze` 101 infos (one more than before: a `prefer_const_declarations` hint in the new test, fixed afterwards; no warnings/errors), `flutter test` 356 passed, release APK built (artifact `dramaflow-apk-branch-234`). TE-51 compiles on CI and its tests pass. Phone-tested: **No**. Not merged into main.

## TE-52: pick a recap job up again
| Feature | Tested here | Compiles on CI | Phone-tested |
|---|---|---|---|
| The backend job id is kept per project; if the screen/app is closed while the backend works, "နောက်ဆုံး job ကို ပြန်ယူ" fetches the job (finished parts come in at once, a running job is waited for). A job the backend no longer has says so and the button goes away | Nothing automated for the network loop (it is the same polling loop as before, now shared); backend keeps finished jobs 2 h and in a file (tested in Python) | see CI | **No** |
Note: Auto Recap's "ဆက်သွယ်" loop was refactored (start and resume now share one polling function), so the normal Auto run is also affected: re-test it first.
Not done on purpose: a multi-episode queue (it needs each episode's video, subtitles and Gemini upload handled in the background; I cannot make that safe without the phone), and a new backup feature (Backup/Restore already exists; the keys and these usage counters are not in it).

## TE-53: Recap Queue + step bar
| Feature | Tested here | Compiles on CI | Phone-tested |
|---|---|---|---|
| `lib/core/recap_queue.dart`: queue bookkeeping (sequence, a failed episode is recorded with step + reason and the next goes on, cancel, retry unfinished, step done/skipped, copyable log) | 8 unit tests | see CI | **No** |
| `lib/platform/recap_episode_runner.dart`: one episode = subtitles (AssemblyAI only when none) → upload to the user's Gemini → backend job (Gemini + Edge TTS) → save parts (script only if the project has none) → voice into Audio (only for a script it wrote). Same pieces as the Auto card | Not testable here (network, phone channels) | see CI | **No** |
| `lib/ui/recap_queue_screen.dart` + Home > Tools "Recap Queue": pick episodes, settings, per-episode step bar, error with step, log, retry, stop | 3 widget tests for the step bar only | see CI | **No** |
| Auto card: step bar (same widget) and "Log ကူး" button | widget test of the bar | see CI | **No** |
Limits, on purpose: Video Recap only (Scene Recap needs contact sheets made on the phone); the app must stay open and the screen on (no background service); leaving the queue page stops the queue; the queue does not replace an existing script. The Auto card's code was refactored (steps are tracked in `_start/_applyJob/_saveAudio/_resume`), so re-test the normal Auto run first.

CI (run 45032250142, commit c4722ac): `flutter analyze` 104 infos (no warnings/errors; the new ones are lint hints), `flutter test` 367 passed, release APK built (artifact `dramaflow-apk-branch-237`). TE-53 compiles on CI and its tests pass. Phone-tested: **No**. Not merged into main.

## Phone test report from the user (2026-11-23)
The user reported, in one line and without screenshots or logs, that steps 1–6 of the list he was given all worked: (1) backup, (2) install the APK, (3) run the Colab backend and connect, (4) Self-test, (5) Scene Recap Auto on a short video with voice in Audio, (6) the rest of TESTPLAN 7b (AssemblyAI, Video Recap, News Video, retry missing parts, pick a job up again). This is the user's word only: which APK number was installed, what the Self-test showed, how the voice sounded and the time/data used were NOT reported. Treat TE-40…TE-52 as "phone-tested: yes, by the user's report" only for those flows, and still **No** for the Recap Queue (TE-53, APK built after that list) and anything not on that list.

## TE-54: fixes from the user's phone screenshots (2026-11-23)
What the screenshots showed: (1) Queue/Video Recap upload failed with "User location is not supported for the API use" (Gemini refuses the phone's IP; the old text wrongly blamed the video format); the user then turned on a VPN and reports everything works except News Video. (2) News Video said "Not Found" because News Video and Recap shared ONE backend address slot, so the Recap Colab URL was used for News. (3) Self-test showed Gemini 503 "high demand" with a useless "unknown error" hint. Also seen working on the phone: Queue runs, AssemblyAI subtitles (29 lines), per-step error + log + retry, the usage line, Self-test ffmpeg/Edge TTS green.
| Fix | Tested here | Compiles on CI | Phone-tested |
|---|---|---|---|
| Upload errors: a location refusal says "use a VPN" (not the format); a quick check before the upload stops at once for place/key problems | Dart tests of the hint functions | yes (run 45057201438) | **No** |
| Separate address slot for the Recap backend (also used by the voice in Audio and the queue); the old shared address is copied once. News Video keeps its own slot | Dart test for the service names; the repo is not unit-tested | yes | **No** |
| Connecting checks the backend's /health name and says "this is the News/Recap backend" when mixed up; 404 text mentions it | Python /health names checked; Dart test | yes | **No** |
| Self-test hint for 503 and for a location refusal on the backend | Python tests | n/a | **No** |
Still open: News Video itself was not tested working. It needs the NEWS Colab notebook (`dramaflow_news_backend`) running and its own URL#TOKEN pasted on the News Video page. The Colab recap notebook was regenerated (re-upload it to get the new hints). CI: run 45057201438, `flutter analyze` 104 infos (no warnings/errors), `flutter test` 372 passed, APK artifact `dramaflow-apk-branch-240`. Not merged into main.

## TE-55: video from a link (YouTube / TikTok / Red Note) + News AI pictures (2026-11-23)
Asked by the user: give a link instead of uploading a video file; News should make its pictures automatically. Branch `claude/te-55-link-ingest`, not merged into main.
| Change | Tested here | Compiles on CI | Phone-tested |
|---|---|---|---|
| Recap backend `/ingest/jobs`: link -> yt-dlp download (max 720p, size/length limits, private/local addresses refused) -> put into the user's Gemini account from the backend (so no VPN is needed for this upload) -> `file_uri`, mime, length | Python tests (`test_ingest_core`, `test_main_stubbed`) with stand-ins for yt-dlp and Gemini | yes (run 45118749572) | **No** |
| App: link card in Video Recap, link used by Auto and by the Queue (a project with a link and no local video can run); the answer is cached ~40 h so a retry does not download again; no subtitles for a link-only run (Gemini listens to the sound itself) | Dart tests (`source_link_test`) for link reading, cache and answer parsing | yes (run 45118749572) | **No** |
| News Video: AI picture sources (Gemini image, Pollinations) with fallback to Wikimedia stock search | Python + Dart tests of the helpers | yes (run 45118749572) | **No** |
Honest limits: yt-dlp against the real sites was NOT run here (no network). YouTube often blocks Colab's addresses ("sign in to confirm you're not a bot"); TikTok / Red Note short links may need updates of yt-dlp. The backend says so in Burmese when it happens. Downloading is for videos you have the right to use; the original is never changed (a temporary copy on the backend is deleted after the upload). Needs the NEW Recap notebook (`dramaflow_recap_colab_standalone.ipynb`, installs yt-dlp) and the News notebook re-uploaded.
CI: run 45118749572 success, `flutter analyze` 107 infos (no warnings/errors), APK artifact `dramaflow-apk-branch-246`. Not merged into main.

## TE-56: Scene Recap in the queue + the queue keeps going in the background (2026-11-23)
Asked by the user ("နှစ်ခုလုံးလုပ်ထား"). Branch `claude/te-56-queue-scenes` (built on TE-55; merging it brings TE-55 too). Not merged into main.
| Change | Tested here | Compiles on CI | Phone-tested |
|---|---|---|---|
| Queue: Video / Scene switch. Scene mode per episode: subtitles -> scene split + contact sheets on the phone -> pictures to the user's backend (Gemini + voice there; no VPN needed) -> save -> audio. A scene plan the user already made is reused; the script and Video Index are written only when the project has neither | Dart tests for scene-plan reading and the step lists / notice text; the runner itself needs a phone and a backend | yes (run 45120451549) | **No** |
| Link-only projects are not offered in Scene mode (frames need the video file) | by reading | yes | **No** |
| Contact sheets made by the queue are not saved to the phone gallery (a new `gallery:false` option in SceneTools.kt) | none (Kotlin) | yes | **No** |
| Background: the queue starts the existing foreground service (notification + wake lock) with its own title and "2/5 · episode · step" and a percent; it stops when the queue ends | notice text tested; the service needs a phone | yes | **No** |
Honest limits: this keeps the app alive, it does not guarantee it. Swiping the app away or a maker's battery saver can still stop it; "retry" then continues with what is left. Android 13+ asks once for the notification permission (without it the queue still runs, only the notification is hidden). CI: `flutter analyze` 107 infos (no warnings/errors), `flutter test` 397 passed, APK artifact `dramaflow-apk-branch-250`.

## TE-57: link — cookies.txt (YouTube bot check) + the link's own subtitles (2026-11-23)
Idea taken from the user's "All In One Download" notebook (only the downloader ideas; its Zoom/Flip/Colour/Pitch editor part was NOT used). Branch `claude/te-56-queue-scenes` (same branch as TE-56). Not merged into main.
| Change | Tested here | Compiles on CI | Phone-tested |
|---|---|---|---|
| Backend: an optional cookies.txt that YOU put on the backend machine (Colab: `/content/cookies.txt`, new notebook Cell 5b) is used by yt-dlp from a private copy that is deleted with the job. It never goes through the app. A broken file (JSON, empty, no tabs) stops with a Burmese reason; the bot-check hint says how to add cookies, or that they may be old | Python tests with a yt-dlp stand-in (`test_main_stubbed`, `test_ingest_core`) | n/a (Python) | **No** |
| Backend: the uploader's own subtitles (zh first, then en, my; not machine captions, not danmaku) are asked for as .srt and returned; a subtitle file is never mistaken for the video | same | n/a | **No** |
| App: those subtitles are saved as the project's source subtitles only when the project has none; used at once by Auto and the Queue (a log line says so) | Dart tests of the answer reading | yes (run 45159229875) | **No** |
Honest limits: the real YouTube / Bilibili / TikTok / Red Note were NOT contacted here. Cookies may expire or be refused; a cookie from your main Google account is a risk (use a spare account). Many videos have no uploader subtitles at all (then nothing changes). Needs the NEW Recap notebook.
CI: run 45159229875 success, `flutter analyze` 107 infos (no warnings/errors), `flutter test` 399 passed, APK artifact `dramaflow-apk-branch-252`.

## TE-59: downloads and jobs keep going when the screen turns off (2026-11-24)
Reported by the user: "ဖုန်းပိတ်ရင် download ဆွဲတယ် အခု မဆွဲ". Cause found by reading: only the Recap queue and the render screens started the foreground service; the link download, the Recap job (Auto / resume), the voice download and the News video job + MP4 download did not, so the phone stopped the app's network a few minutes after the screen went dark. Branch `claude/te-59-keepalive` (built on TE-57). Not merged into main.
| Change | Tested here | Compiles on CI | Phone-tested |
|---|---|---|---|
| New `BackgroundWork` (counted begin/update/end) around: link -> backend -> Gemini, Recap Auto run, Recap job resume, voice download, News video job, News MP4 download. Notification shows the stage and percent; it is switched off only when the last job ends | Dart test with a mocked channel (`background_work_test`) | see CI | **No** |
| `RenderService` also holds a Wi-Fi lock (released with the wake lock) so the Wi-Fi radio does not sleep with the screen off | none (Kotlin, needs a phone) | see CI | **No** |
Honest limits: this makes it much more likely, it does not guarantee it. Some phone makers (Xiaomi, Oppo, Huawei ...) still kill background apps unless battery saving is set to "No restrictions" for DramaFlow; swiping the app away stops it. Android 13+ asks once for the notification permission. If the phone loses Wi-Fi/mobile data, the job on the backend still goes on and can be resumed.
