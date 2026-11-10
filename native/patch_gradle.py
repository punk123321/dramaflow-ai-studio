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

# ---- fixed signing key, so a new APK installs over the old one ----
# native/dramaflow.jks is copied to android/app/dramaflow.jks by the workflow.
s = open(path, encoding="utf-8").read()
if "dramaflow.jks" not in s:
    if kts:
        block = (
            '    signingConfigs {\n'
            '        create("dramaflow") {\n'
            '            storeFile = file("dramaflow.jks")\n'
            '            storePassword = "dramaflow"\n'
            '            keyAlias = "dramaflow"\n'
            '            keyPassword = "dramaflow"\n'
            '        }\n'
            '    }\n\n'
        )
        s = s.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("dramaflow")')
    else:
        block = (
            '    signingConfigs {\n'
            '        dramaflow {\n'
            '            storeFile file("dramaflow.jks")\n'
            '            storePassword "dramaflow"\n'
            '            keyAlias "dramaflow"\n'
            '            keyPassword "dramaflow"\n'
            '        }\n'
            '    }\n\n'
        )
        s = s.replace("signingConfigs.debug", "signingConfigs.dramaflow")
    marker = "    buildTypes {"
    if marker not in s:
        sys.exit("buildTypes block not found; cannot set the signing key")
    s = s.replace(marker, block + marker, 1)
    open(path, "w", encoding="utf-8").write(s)
    print("signing key configured")
