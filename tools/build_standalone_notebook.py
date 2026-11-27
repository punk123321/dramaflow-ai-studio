"""Rebuilds tools/dramaflow_recap_colab_standalone.ipynb from the backend source files, so the notebook can never
drift from the code. Run from the repo root:  python3 tools/build_standalone_notebook.py   (add --check to only compare)."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKEND = ROOT / "tools" / "dramaflow_backend"
NB = ROOT / "tools" / "dramaflow_recap_colab_standalone.ipynb"
FILES = ["main.py", "recap_core.py", "tts_text.py", "ingest_core.py", "studio_core.py", "render_core.py", "studio_ops.py"]

INTRO = """# DramaFlow Backend (Colab) — Recap + Link ဆွဲ + Creator Studio
GitHub branch မလိုဘူး၊ backend ကုဒ်အားလုံး ဒီ notebook ထဲမှာ ပါပြီးသား။ (Video Recap / Scene Recap "Auto" + Edge TTS + Self-test + **ဗီဒီယို link (YouTube/TikTok/Red Note/Bilibili) ဆွဲပေးတာ** + **Creator Studio** — download၊ ဖြတ်၊ စာတန်း ဘာသာပြန်၊ CC/Hardsub၊ ZIP၊ YouTube တင်)

**သုံးပုံ**
1. Colab (colab.research.google.com) > File > Upload notebook > ဒီဖိုင်ကို ရွေး
2. Cell တွေကို အစီအစဉ်အတိုင်း **တစ်ခုချင်း run** (Cell 1 → ၂ → … → နောက်ဆုံး server Cell)
3. နောက်ဆုံး Cell ကထုတ်ပေးတဲ့ `https://….trycloudflare.com#TOKEN` တစ်ကြောင်းလုံးကို DramaFlow ရဲ့ Backend ကွက်မှာ ထည့်၊ "သိမ်း + စမ်းချိတ်" နှိပ်
4. Colab ရပ်ရင်/ပိတ်ရင် URL ပြောင်းမယ် — နောက်ဆုံး Cell ကို ပြန် run ပြီး အသစ်ယူ။ runtime ပြန်စထားရင် Cell တွေ အကုန်ပြန် run။ **Studio ထဲက ဖိုင်တွေက Colab runtime နဲ့အတူ ပျောက်မယ်** — လိုတာကို ဖုန်းထဲ အရင်ဆွဲယူထားပါ။

**ဗီဒီယို link:** ဗီဒီယိုနဲ့အတူ စာတန်း (.srt) ပါရင် အလိုလို ယူပေးတယ်။ YouTube က Colab ကို တားရင် **Cell 5b** မှာ cookies.txt တင်ပါ။
**Creator Studio:** ကိုယ်ပိုင် / တင်ခွင့်ရှိတဲ့ ဗီဒီယိုအတွက်ပဲ။ YouTube တင်ချင်ရင် **Cell 5c** မှာ `client_secret.json` တင်ပါ (Google Cloud > YouTube Data API v3 > OAuth client "Desktop app")။ GPU runtime ရွေးရင် Hardsub ပိုမြန်တယ်။
"""

INSTALL = """# Cell 1: package တွေ + cloudflared + aria2 + မြန်မာဖောင့် တပ်ဆင် (တစ်ကြိမ်၊ ၂ မိနစ်လောက်)
!pip -q install fastapi uvicorn edge-tts google-genai imageio-ffmpeg yt-dlp deep-translator google-api-python-client google-auth-oauthlib google-auth-httplib2 faster-whisper
!apt-get -qq install -y aria2 fonts-sil-padauk > /dev/null 2>&1 || echo "aria2/ဖောင့် မတပ်နိုင်ဘူး — download က 1 လိုင်းနဲ့ပဲ၊ Hardsub က မူရင်းဖောင့်နဲ့ ထွက်မယ်"
!wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared
!mkdir -p /content/dramaflow_backend
print("ok")"""

COOKIES = '''# Cell 5b (ရွေးချယ်ခွင့် — YouTube က "robot မဟုတ်ကြောင်း အတည်ပြုပါ" လို့ တားမှသာ run ပါ)
# 1) Chrome မှာ YouTube ကို login ဝင်ထား၊ "Get cookies.txt LOCALLY" လို extension နဲ့ Netscape format cookies.txt ထုတ်ပါ။
# 2) ဒီ cell run ပြီး ထုတ်ထားတဲ့ ဖိုင်ကို ရွေးတင်ပါ။ ဖိုင်က သင့် Colab ထဲမှာပဲ နေမယ် (DramaFlow app ကို မဖြတ်ဘူး)။
# 3) ဒီ cookie က account login အတွက်ဖြစ်လို့ တခြားသူကို မပေးပါနဲ့၊ အဓိက account မဟုတ်တဲ့ အပိုတစ်ခုနဲ့ ထုတ်တာ ပိုစိတ်ချရတယ်။
# Server ပြေးနေပြီးသားဆိုရင်လည်း ဒီ cell ကို နောက်မှ run လို့ရတယ် — link တစ်ခုချင်းစီမှာ ဖိုင်ကို ပြန်ဖတ်တယ်။
from google.colab import files
import shutil
up = files.upload()
if up:
    shutil.move(next(iter(up)), "/content/cookies.txt")
    print("cookies.txt သိမ်းပြီး (/content/cookies.txt)")
else:
    print("ဘာမှ မတင်ဘူး — ကျော်လိုက်တယ်")'''

SECRET = '''# Cell 5c (ရွေးချယ်ခွင့် — Studio ကနေ YouTube ကို တင်ချင်မှသာ run ပါ)
# 1) console.cloud.google.com > project တစ်ခုဆောက် > "YouTube Data API v3" ကို Enable
# 2) OAuth consent screen (External) ဖြည့်၊ Test users ထဲ ကိုယ့် Gmail ထည့်
# 3) Credentials > Create credentials > OAuth client ID > Application type = "Desktop app" > JSON ဒေါင်းလုဒ်
# 4) ဒီ cell run ပြီး အဲဒီ JSON ကို ရွေးတင်ပါ။ ဖိုင်က သင့် Colab ထဲမှာပဲ နေမယ် (app ကို မဖြတ်ဘူး)။
# 5) App > Studio > YouTube မှာ "Login ဝင်" နှိပ်ပြီး ညွှန်ပြတဲ့အတိုင်း လုပ်ပါ။
# မှတ်ချက်: တစ်ရက်မှာ ၆ ပုဒ်လောက်ပဲ quota ရှိတယ်။ audit မလုပ်ရသေးတဲ့ API project က Public ပေးတာကို private ပဲ ထားတတ်တယ်။
from google.colab import files
import os, shutil
up = files.upload()
if up:
    shutil.move(next(iter(up)), "/content/client_secret.json")
    os.chmod("/content/client_secret.json", 0o600)
    print("client_secret.json သိမ်းပြီး (/content/client_secret.json)")
else:
    print("ဘာမှ မတင်ဘူး — ကျော်လိုက်တယ်")'''

DRIVE = '''# Cell 5d (ရွေးချယ်ခွင့် — Studio ဖိုင်တွေ Colab ပိတ်ရင်လည်း မပျောက်ချင်မှသာ run ပါ — Server cell မတိုင်ခင်)
# Google Drive ထဲက "DramaFlow_Studio" folder ကို Studio library အဖြစ် သုံးမယ်။ ဗီဒီယိုကို ဒီ folder ထဲ တစ်ခါထည့်ထားရင်
# နောက်တစ်ခါ Colab စတိုင်း ပြန်မတင်ရတော့ဘူး၊ App > Render > "Colab မှာ ထုတ်မယ်" က ဒီဖိုင်ကို တိုက်ရိုက်သုံးမယ်။
from google.colab import drive
import os
drive.mount("/content/drive")
os.makedirs("/content/drive/MyDrive/DramaFlow_Studio", exist_ok=True)
os.environ["DF_STUDIO_DIR"] = "/content/drive/MyDrive/DramaFlow_Studio"
print("Studio library =", os.environ["DF_STUDIO_DIR"])'''

SERVER_FALLBACK = None


def src(text):
    lines = text.split("\n")
    return [l + "\n" for l in lines[:-1]] + [lines[-1]]


def build():
    old = json.loads(NB.read_text(encoding="utf-8"))
    server = next(c for c in old["cells"] if "Cell 6" in "".join(c["source"])[:40])
    cells = [("markdown", INTRO.rstrip("\n")), ("code", INSTALL)]
    for f in FILES:
        cells.append(("code", f"%%writefile /content/dramaflow_backend/{f}\n" + (BACKEND / f).read_text(encoding="utf-8").rstrip("\n")))
    cells += [("code", COOKIES), ("code", SECRET), ("code", DRIVE), ("code", "".join(server["source"]))]
    out = []
    for kind, text in cells:
        c = {"cell_type": kind, "metadata": {}, "source": src(text)}
        if kind == "code":
            c.update(execution_count=None, outputs=[])
        out.append(c)
    old["cells"] = out
    return old


def check():
    nb = json.loads(NB.read_text(encoding="utf-8"))
    bad = []
    for f in FILES:
        want = f"%%writefile /content/dramaflow_backend/{f}\n" + (BACKEND / f).read_text(encoding="utf-8").rstrip("\n")
        got = next(("".join(c["source"]) for c in nb["cells"] if "".join(c["source"]).startswith(f"%%writefile /content/dramaflow_backend/{f}\n")), None)
        if got != want:
            bad.append(f)
    return bad


if __name__ == "__main__":
    if "--check" in sys.argv:
        bad = check()
        print("same" if not bad else "DIFFERENT: " + ", ".join(bad))
        sys.exit(1 if bad else 0)
    NB.write_text(json.dumps(build(), ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("written;", "same" if not check() else "DIFFERENT: " + ", ".join(check()))
