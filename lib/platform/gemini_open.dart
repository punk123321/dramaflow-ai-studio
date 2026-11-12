import 'package:flutter/services.dart';

import 'handoff_channel.dart';

/// Copies [prompt] to the clipboard (as a backup) and hands it to the Gemini
/// app through the normal Android share mechanism. No API, no key. Returns a
/// short Burmese message for the user.
Future<String> openInGemini(String prompt) async {
  await Clipboard.setData(ClipboardData(text: prompt));
  try {
    switch (await HandoffChannel.share(prompt)) {
      case ShareResult.gemini:
        return 'Gemini ကို ပွင့်ပြီး prompt ပို့ပြီးပါပြီ။ ဖြေပြီးရင် ဖြေချက်ကို copy လုပ်ပြီး ပြန်လာပါ။';
      case ShareResult.chooser:
        return 'Gemini app မတွေ့လို့ share စာရင် ဖွင့်ထားတယ်။ Gemini ကို ရွေးပါ။ (Prompt ကို Copy လည်း လုပ်ထားပြီး)';
      case ShareResult.tooLarge:
        return 'စာသား ရှည်လွန်းလို့ မပို့နိုင်ပါ။ Copy လုပ်ထားပြီး၊ Gemini ထဲ ကိုယ်တိုင် paste လုပ်ပါ။';
    }
  } catch (_) {
    return 'Gemini မဖွင့်နိုင်ပါ။ Prompt ကို Copy လုပ်ထားပြီး၊ Gemini ထဲ ကိုယ်တိုင် paste လုပ်ပါ။';
  }
}
