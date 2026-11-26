# Phone test plan (APK from branch claude/te-40-upgrades)

Tick each line on the phone. Anything that fails: send a screenshot and the line number.

## 0. Install
1. In the old app: Settings > Backup, save the backup file.
2. Uninstall the old app, install the new APK, Restore.
3. Open the app: Home shows the header, a "continue" card (or start card), Studio tiles, Tools chips.

## 1. Look and navigation
4. Bottom bar: 4 tabs, the chosen one is a violet pill with its name; the page above is NOT hidden.
5. Tap Workflow, Library, Settings, Home: each page shows, no blank page.
6. Text is readable on the glass cards (contrast).
7. Scrolling Home is smooth (no stutter from the blurred card).

## 2. Studio pages (open from Home)
8. Video Index opens as its own page: split segments, the panel works.
9. Recap Studio opens its own page: copy a prompt (try the new "Hook" prompt), paste a reply.
10. Scene Studio opens its own page.
11. TTS / MP3 opens its own page: make or record audio.
12. Render Center opens its own page: start a render.
13. "ဒီအဆင့် ပြီးပြီ" switch on a stage page shows in the Workflow tab.

## 3. Subtitle Studio
14. Three tabs at the bottom (edit, quick, split); changing text in one is seen in the others.
15. Undo works after an edit.
16. Mic-wave icon (SRT from sound): see section 7.

## 4. Video Index download
17. Download one segment: MP4 appears in the Gallery.
18. Download all: runs one after another; pause and stop work.
19. Ratio, resolution, quality (Mbps) and sound on/off change the result.

## 5. Video Editor effects (check the preview AND the rendered MP4)
20. Blur on a time range; strength slider.
21. Mirror / Flip (horizontal, vertical).
22. Censor box (rectangle blur): the box in the MP4 is where it was in the preview; it moves/resizes; up to 3.
23. Frame templates (12): look of each in the MP4; thin lines on 480p.
24. Filter: brightness, contrast, colour strength; chips B&W, colourful, faded. Compare the preview with the MP4.
25. Timeline: select an effect, drag its two white grips; the time changes and stays after lifting the finger; the timeline still scrolls sideways.
26. Fullscreen button on the preview: landscape, play / pause / seek, back returns to normal portrait.
27. Speed change, crop, freeze, smart cut, split screen, sounds (older features, quick check that nothing broke).

## 6. Render
28. Render with a Censor box + Frame + Blur together (the heaviest case): time, heat, finished MP4 plays.
29. Original video is unchanged (open it in the Gallery).

## 7. AssemblyAI (only if you want it)
30. Settings: paste the key, language "zh", save.
31. Subtitle Studio > mic-wave icon > Start: stages shown (cut sound, upload, wait, SRT).
32. Result has timed lines in Chinese; accept it (asks before replacing; Undo brings the old text back).
33. Wrong key shows "Key မမှန်ဘူး"; stop button works.
34. Note how long it took and how much data it used.

## 7b. Auto Recap with your own backend (Colab/Altare) — Video Recap and Scene Recap
a. Backend is running (Colab cell 2 or Altare). In the Auto card, paste `URL#TOKEN`, tap "သိမ်း + စမ်းချိတ်": "ချိတ်မိပြီ ✓".
b. Tap **Self-test**: ffmpeg, Edge TTS, Gemini should be green. A red line shows what to fix; send me a screenshot of it.
c. Project WITHOUT subtitles + AssemblyAI key: "Auto လုပ်မယ်" asks about AssemblyAI in the box; stages show the sound being cut, AssemblyAI waiting, then Gemini. Note the minutes used.
d. Project WITH subtitles: AssemblyAI does NOT run (box does not mention it).
e. Result: parts saved; "Script အဖြစ် သိမ်း", then "အသံကို project ထဲ သိမ်း": Audio stage 3 shows the voices.
f. Warnings: a part whose voice is much longer/shorter than its video part is listed ("အသံက ရှည်နေတယ်"). Voices up to 15% too long are sped up by the backend.
g. Switch the Gemini model field to a wrong name (e.g. `x`), run Auto: error is readable. Put the right one back, tap "မရတဲ့ အပိုင်း … ပြန်လုပ်": only the missing parts run and the video is NOT uploaded again.
h. Listen: numbers under 100 and emoji in the script are read sensibly (the backend spells small numbers in Burmese and removes emoji and * marks).
i. Note: time per part, data used, anything that sounds wrong.
j. Start Auto, then close the screen (or kill the app) while the stage says Gemini/voice. Reopen the same project's Recap page: "နောက်ဆုံး job ကို ပြန်ယူ" appears; tap it: the finished parts come in. (If Colab was restarted meanwhile it says the job is gone: that is expected.)

## 7c. Recap Queue (Home > Tools > Recap Queue) — only after 7b works for ONE episode
a. Open it: Backend ✓, Gemini key ✓ shown (else it says what is missing).
b. Pick 2 short episodes (1–2 min videos, one with subtitles, one without), tap "Queue စမယ်": the box warns about Wi-Fi/data.
c. Each episode shows a row of steps: စာတန်း → Upload → Gemini + အသံ → သိမ်း → အသံ သိမ်း. The running step has a spinner, finished ✓, skipped –.
d. The episode with subtitles shows "စာတန်း … ရှိပြီးသား" (skipped); the other one runs AssemblyAI.
e. When done: open each project's Video Recap page: the parts are there. A project that had NO script got a new script and its voice in Audio (stage 3); one that already had a script keeps it (the log says so).
f. Make one fail on purpose (turn off the Colab cell, or a wrong Gemini model): that episode shows ✗ with the step and the reason, the next one still runs. Tap "မအောင်တာ/ကျန်တာ ပြန်လုပ်" after fixing.
g. "Log အကုန် ကူး" copies the whole log: paste it to me with any error.
h. The Auto card (Video/Scene Recap) now also shows the step row and a "Log ကူး" button.

## 7d. Video from a link (needs the NEW Recap notebook)
1. Run the new Recap Colab notebook, connect it in Video Recap (Self-test green).
2. Video Recap > link card: paste a public YouTube link (or a TikTok / Red Note share text). Press the link button; it should show progress (download, then Gemini) and then the length. Note: no VPN should be needed for this upload.
3. Run Auto with the link. Try a Red Note / TikTok link too; if one fails, copy the log and send it.
4. Recap Queue: a project with a link and no video file should run.
5. News Video: pick the AI picture source and make a video; pictures should appear without stock search.

## 8. Data safety
35. Backup > Restore on a fresh install keeps projects.
36. Keys (Gemini, AssemblyAI) are NOT in the backup file.
