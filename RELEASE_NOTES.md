# DramaFlow AI Studio 1.1.0 (build 9)

Personal Android app for Chinese-drama recap videos. Updates install over the
old app (fixed signing key); no uninstall needed.

## Works (automated tests pass; most also confirmed on the phone)
- Projects, drama library, video index (video is never copied or changed)
- Gemini handoff with lossless SRT timestamps
- Subtitle Studio, narration script, TTS / mic / imported audio
- Editor: cut, split, order, zoom framing, voice, music, subtitle style, own logo, corner texts
- Render to MP4 (Media3) and save to Gallery
- Copyright & Fair Use assistant (rules of thumb, not legal advice)

## Added since 1.0.0
Confirmed on the phone by the user: Transformative Editor render, 8-second sample render,
Split Screen, blur background, 9:16 with black bars, crop.
Not phone-tested yet (see CHECKLIST.md): Brightness/Contrast, thumbnail (frame, own picture,
Gemini picture), text wrapping in 9:16, subtitle presets and fade, missing-file warnings,
Backup/Restore, optional Gemini API narration and picture, fast lane for an existing
Burmese SRT, cutting video and SRT into parts at subtitle lines (per part SRT and MP4),
output quality menu (Auto close to the original bitrate) and 480p.

## Needs the internet (optional, only when tapped)
Gemini API narration and Gemini picture, with the user's own key. Everything else works offline.
The key is stored as plain text in the app's private storage and is not in backups.

## Not confirmed on a phone yet
Subtitle style, logo, corner text (Burmese shaping), per-piece zoom, Fair Use screen.

## Known limits
- Device TTS has no Burmese voice; use mic or import audio
- Render stops if Android kills the app (no background service)
- No MP3 encoding, no speech-to-text

## Never built, on purpose
Removing or covering others' watermarks/logos, and any way to avoid platform
copyright checks (flip, pitch change, zoom-to-evade).
