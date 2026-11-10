"""Adds what Phase 5 needs to the generated AndroidManifest.xml:
RECORD_AUDIO (microphone recording) and a <queries> entry so the app can see
the phone's text-to-speech engine. Safe to run twice."""
import sys

path = sys.argv[1]
s = open(path, encoding="utf-8").read()

perm = '<uses-permission android:name="android.permission.RECORD_AUDIO"/>'
queries = (
    '<queries><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries>'
)

changed = False
i = s.index("<manifest")
j = s.index(">", i) + 1
add = ""
if "android.permission.RECORD_AUDIO" not in s:
    add += "\n    " + perm
if "android.intent.action.TTS_SERVICE" not in s:
    add += "\n    " + queries
if add:
    s = s[:j] + add + s[j:]
    changed = True
open(path, "w", encoding="utf-8").write(s)
print("manifest patched" if changed else "manifest already patched")
