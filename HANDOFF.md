# DramaFlow AI Studio - handoff

Use this file to continue the work in another Claude account or session (for example the one connected to GitHub).

## Goal

Build **DramaFlow AI Studio**, a personal Android app for Chinese drama recap video production. The full requirements are in `reference/DramaFlow_spec.txt`. The workflow comes from the screenshots in `reference/` (Easy Recap / Zippy Cut): Video index, Save and copy, TTS / mp3, Studio editor, Render, Save.

Key rules from the spec: Flutter + Kotlin, local SQLite, no Gemini or OpenAI API, no account, Gemini only through the Android app with copy and share, no claims of "done" without real testing, no Content ID bypass.

## Decisions made

- Package name `com.dramaflow.aistudio`, Flutter project name `aistudio`.
- UI first. The design was approved from `artifacts_html/dramaflow-ui.html` (dark cinematic, one color per stage).
- State: `provider`. Database: `sqflite`. No Firebase, no cloud.
- Build without a PC: GitHub Actions workflow in `dramaflow_ai_studio/.github/workflows/build-apk.yml` (it generates the `android/` folder, then builds the APK).
- Work in phases 1 to 8 as in the spec. Honest status in `dramaflow_ai_studio/CHECKLIST.md`.

## What exists

| Item | Where | Status |
| --- | --- | --- |
| Phase 1 Flutter source (theme, home, projects in SQLite, workflow screen, tests) | `dramaflow_ai_studio/` | Written. Never compiled, never run. |
| UI design preview | `artifacts_html/dramaflow-ui.html` | Works in a browser. Preview only. |
| Recap Maker (summarize text, short / medium / long) | `artifacts_html/recap-maker.html` | Artifact page. Uses Claude through the artifact `sample` capability, no API key. Not opened in a browser yet. |
| Recap Studio (frame index, script, TTS preview, subtitle export) | `artifacts_html/recap-studio.html` | Same as above. Not opened in a browser yet. |

The three HTML pages were published as private artifacts in the previous account. They do not move between accounts. To use them again, publish these files as new artifacts. They need the `sample` capability (Recap Studio also needs `{images: true}` and `downloads`).

## Not done

Phase 2 onward: Drama Library, video import and index, Gemini handoff and prompt templates, subtitle studio, speech-to-text, TTS and audio, editor, render, copyright assistant, backup and restore. See the checklist.

## Known limits

- The previous environment had no Flutter, Dart or Android SDK, and package installs were blocked. Nothing was compiled or tested. Expect first-build errors.
- Dependency versions and licenses are from memory, not checked on pub.dev.
- Guided / Free mode is not saved between launches.
- Android cannot read Gemini's reply automatically. The user copies and pastes it back. This is by design.

## Next steps

1. Create an empty private GitHub repo, connect it to Claude, push `dramaflow_ai_studio/` (keep the `.github` folder).
2. Run the "Build APK" workflow. Fix every compile or analyze error from the log.
3. Install the APK on the Redmi Note 12 Pro+ and check: create a project, close and reopen the app, Burmese text rendering.
4. Start Phase 2: Drama Library, video import (Storage Access Framework), video index and segments. Never modify the original video.

## Prompt to paste in the new session

```
I am continuing a project from another session. Read HANDOFF.md, CHECKLIST.md and reference/DramaFlow_spec.txt first.
Repo: <owner>/<repo>  (already connected).
Tasks: 1) push the code if the repo is empty, 2) run the Build APK workflow and fix all errors, 3) then start Phase 2.
Be honest: say "written" for untested code and "verified" only after it actually ran. Reply to me in Burmese.
```
