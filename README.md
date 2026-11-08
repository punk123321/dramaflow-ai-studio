# DramaFlow AI Studio (Phase 1)

Personal Android app for drama recap production. Flutter UI, local SQLite, no API keys, no account.
Package name: `com.dramaflow.aistudio`.

## Status

Phase 1 source code is written. **It has not been compiled or run yet.** See `CHECKLIST.md`.

## What Phase 1 contains

- Dark cinematic design system (`lib/core/theme.dart`, one color per workflow stage).
- Home dashboard: resume card, module grid, project list.
- Projects stored in local SQLite: create, rename, duplicate, delete, resume after restart.
- Workflow screen with the six stages, Guided and Free modes. Stages can be marked done (saved).
- Module tiles and the Library and Settings tabs say plainly that they come in a later phase.

Not in Phase 1: video import, index, Gemini handoff, subtitles, TTS, editor, render.

## Build without a PC (GitHub Actions)

1. Create a free GitHub repository and upload this whole folder (the `.github` folder too).
2. Open the repository, go to Actions, choose "Build APK", press Run workflow.
3. When it finishes, open the run and download the `dramaflow-apk` artifact. Unzip it and install `app-release.apk`.
4. If the run fails, send me the error text or a screenshot of the failed step.

## Build on a computer

```
flutter create --org com.dramaflow --project-name aistudio --platforms=android _gen
cp -r _gen/android ./android && rm -rf _gen
flutter pub get
flutter test
flutter build apk --release
```

The APK is at `build/app/outputs/flutter-apk/app-release.apk`. It is signed with the debug key, which is fine for personal installs.

## Burmese font

The app uses the phone's own Myanmar font by default. To bundle one, put the .ttf files in `assets/fonts/` and uncomment the `fonts:` block in `pubspec.yaml`.

## Dependencies and licenses

| Package | Use | License |
| --- | --- | --- |
| flutter | UI | BSD-3-Clause |
| sqflite | local SQLite | BSD-2-Clause |
| path, path_provider | file paths | BSD-3-Clause |
| provider | state | MIT |
| characters | first letter of Burmese titles | BSD-3-Clause |

Licenses are listed from memory and versions are not checked against pub.dev yet. Verify them before relying on this table.
