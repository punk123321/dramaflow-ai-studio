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

## Not started

- Phase 5: speech-to-text, TTS, MP3, voice recording
- Phase 6: Studio editor, timeline
- Phase 7: Render Center, Gallery save, export history
- Phase 8: Copyright and Fair Use assistant, final QA
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
