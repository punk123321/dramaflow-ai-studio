# Project checklist

Legend: Code written = source exists. Verified = actually run. Nothing is Verified yet.

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
| Unit tests (progress logic, map round trip, date text) | yes | not run |

## Not started

- Phase 2: Drama Library, video import, video index, segments
- Phase 3: Gemini handoff, prompt templates, chunking, import of results
- Phase 4: Subtitle Studio, terminology dictionary, subtitle preview
- Phase 5: speech-to-text, TTS, MP3, voice recording
- Phase 6: Studio editor, timeline
- Phase 7: Render Center, Gallery save, export history
- Phase 8: Copyright and Fair Use assistant, final QA
- Backup and restore, project history
- Burmese UI language switch (the text is Burmese only for now)
- Guided/Free choice is not saved between app launches

## Known limits

- This code was written without a Flutter compiler. Expect a few compile errors on the first build.
- Dependency versions and licenses are not verified against pub.dev.
- Module tiles on Home only show a "later phase" message.
