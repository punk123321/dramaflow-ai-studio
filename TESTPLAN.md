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

## 8. Data safety
35. Backup > Restore on a fresh install keeps projects.
36. Keys (Gemini, AssemblyAI) are NOT in the backup file.
