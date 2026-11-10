"""Adds AndroidX Media3 (Transformer) to the generated app module. Safe to run twice."""
import os
import sys

app = sys.argv[1]
V = "1.5.1"
mods = ["media3-transformer", "media3-effect", "media3-common"]

for name, kts in (("build.gradle.kts", True), ("build.gradle", False)):
    path = os.path.join(app, name)
    if os.path.exists(path):
        break
else:
    sys.exit("no app build.gradle found in " + app)

s = open(path, encoding="utf-8").read()
if "media3-transformer" in s:
    print("gradle already patched")
    sys.exit(0)

lines = []
for m in mods:
    lines.append('    implementation("androidx.media3:%s:%s")' % (m, V) if kts
                 else "    implementation 'androidx.media3:%s:%s'" % (m, V))
s += "\ndependencies {\n" + "\n".join(lines) + "\n}\n"
open(path, "w", encoding="utf-8").write(s)
print("gradle patched:", path)
