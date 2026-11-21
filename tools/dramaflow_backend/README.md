# DramaFlow Recap Backend (Altare / Colab / any Python host)

App ထဲက **Video Recap** နဲ့ **Scene Recap** မှာ "Auto" ခလုတ်နှိပ်ရင် ဒီ backend က
Gemini ကို ခေါ်ပြီး script ရေး၊ Edge TTS နဲ့ မြန်မာအသံ (WAV) ထုတ်ပေးတယ်။
Key တွေ ဘယ်မှာမှ မသိမ်းဘူး (request နဲ့အတူ လာ၊ job ပြီးရင် မေ့)။

## Altare မှာ တင်ပုံ (Free plan)
1. Altare console → Apps → **Create app** → GitHub ချိတ် → repo `punk123321/dramaflow-ai-studio`,
   branch ကို ရွေး၊ **Root directory = `tools/dramaflow_backend`**
2. Python (3.13) ကို auto သိမယ်။ Start command: `Procfile` ထဲမှာ ပါပြီးသား
   (`uvicorn main:app --host 0.0.0.0 --port $PORT`)
3. **Environment variables** ထဲ `APP_TOKEN` = ကိုယ်ဖန်တီးတဲ့ စကားဝှက်ရှည် (အနည်းဆုံး ၂၀ လုံး) ထည့်။ Save ရင် redeploy ဖြစ်မယ်။
4. App ရဲ့ URL (`https://<နာမည်>.go.altare.global`) ကို ကူးပြီး နောက်ကနေ `#` နဲ့ APP_TOKEN ကို ဆက်ရေး:
   `https://<နာမည်>.go.altare.global#စကားဝှက်` → DramaFlow app ထဲ Backend ကွက်မှာ ထည့်

## Colab မှာ run ချင်ရင် (လွယ်ဆုံး: `tools/dramaflow_recap_colab.ipynb` ကို Colab မှာ ဖွင့်၊ Cell 1 နောက် Cell 2 run)
```
!pip -q install fastapi uvicorn edge-tts google-genai imageio-ffmpeg
```
ပြီး `tools/dramaflow_backend` ဖိုင်တွေ upload၊ `uvicorn main:app --port 8000` + cloudflared tunnel (News backend လိုပဲ)။

## စမ်းချက် (ဒီ code အတွက်)
`python3 -m unittest test_recap_core` — parse/ပြင်ဆင်ချက်/error ကိုင်ပုံ (package မလို)။
`main.py` (FastAPI + Gemini + Edge TTS) ကို အစစ်တကယ် မ run ရသေးဘူး — ပထမဆုံး deploy မှာ log ကြည့်ပါ။

## ကန့်သတ်ချက်
- တစ်ခါမှာ job တစ်ခုပဲ (409)။ Output ဖိုင်တွေ ၂ နာရီကြာရင် ဖျက်တယ်။
- Free plan က အမြဲ run ထားပေးမလား Altare စာမျက်နှာမှာ မပြောထားဘူး — ကိုယ်တိုင် စစ်ပါ။
