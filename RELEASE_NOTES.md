# DramaFlow AI Studio 1.0.0 (build 8)

Personal Android app for Chinese-drama recap videos. Updates install over the
old app (fixed signing key); no uninstall needed.

## Works (automated tests pass; most also confirmed on the phone)
- Projects, drama library, video index (video is never copied or changed)
- Gemini handoff with lossless SRT timestamps
- Subtitle Studio, narration script, TTS / mic / imported audio
- Editor: cut, split, order, zoom framing, voice, music, subtitle style, own logo, corner texts
- Render to MP4 (Media3) and save to Gallery
- Copyright & Fair Use assistant (rules of thumb, not legal advice)

## Not confirmed on a phone yet
Subtitle style, logo, corner text (Burmese shaping), per-piece zoom, Fair Use screen.

## Known limits
- Device TTS has no Burmese voice; use mic or import audio
- Render stops if Android kills the app (no background service)
- No MP3 encoding, no speech-to-text

## Never built, on purpose
Removing or covering others' watermarks/logos, and any way to avoid platform
copyright checks (flip, pitch change, zoom-to-evade).
