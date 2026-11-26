import 'srt.dart';

/// "m:ss" or "h:mm:ss" for a chapter-style time.
String clockText(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

/// A short, even picture of the whole story taken from the subtitles: lines
/// spread over the full length, each with its time, within [maxChars]. A long
/// drama has thousands of lines; sending them all would be too long to paste.
String sampleStory(List<SrtEntry> subs, {int maxChars = 9000}) {
  final lines = <SrtEntry>[
    for (final e in subs)
      if (e.text.replaceAll(RegExp(r'\s+'), ' ').trim().length >= 2) e
  ];
  if (lines.isEmpty || maxChars <= 0) return '';
  String fmt(SrtEntry e) => '[${clockText(e.startMs)}] ${e.text.replaceAll(RegExp(r'\s+'), ' ').trim()}';
  final all = [for (final e in lines) fmt(e)];
  final total = all.fold<int>(0, (a, l) => a + l.length + 1);
  if (total <= maxChars) return all.join('\n');
  // Keep every k-th line so the whole length is covered.
  final avg = total / all.length;
  final keep = (maxChars / avg).floor().clamp(1, all.length);
  final out = <String>[];
  var used = 0;
  for (var i = 0; i < keep; i++) {
    final idx = (i * all.length / keep).floor();
    final l = all[idx];
    if (used + l.length + 1 > maxChars) break;
    out.add(l);
    used += l.length + 1;
  }
  return out.join('\n');
}

/// The prompt that is handed to Gemini. Everything the model may use is in the
/// prompt; it is told not to invent anything that is not there.
String buildDescriptionPrompt({
  required String title,
  String part = '',
  String channel = '',
  String notes = '',
  String script = '',
  String subtitleSample = '',
}) {
  String line(String label, String v) => v.trim().isEmpty ? '' : '$label: ${v.trim()}\n';
  final story = StringBuffer();
  if (script.trim().isNotEmpty) {
    final s = script.trim();
    story.writeln('--- Recap စာသား (ကျွန်တော့် narration) ---');
    story.writeln(s.length > 6000 ? s.substring(0, 6000) : s);
  }
  if (subtitleSample.trim().isNotEmpty) {
    story.writeln('--- စာတန်း (အချိန်နဲ့ ရွေးထုတ်ထားတာ) ---');
    story.writeln(subtitleSample.trim());
  }
  final hasStory = story.isNotEmpty;
  return '''သင်ဟာ YouTube Chinese drama recap video များအတွက် description ရေးတဲ့ ကျွမ်းကျင်သူ တစ်ယောက်ပါ။
အောက်ပါအချက်အလက်ကိုပဲ အခြေခံပြီး မြန်မာဘာသာ description ကို ရေးပေးပါ။

${line('ဇာတ်လမ်းအမည်', title)}${line('အပိုင်း', part)}${line('Channel အမည်', channel)}${line('ထပ်ဆောင်းမှတ်ချက်', notes)}
စည်းမျဉ်းများ:
1. ပထမ ၂ ကြောင်းက ကြည့်သူကို စိတ်ဝင်စားစေမယ့် hook ဖြစ်ရမယ်။ ဇာတ်လမ်းအဆုံးသတ်ကို မဖော်ပါနဲ့။
2. ဇာတ်လမ်းအကျဉ်းကို ၃–၄ ကြောင်းနဲ့ ရေးပါ။ အောက်က စာသားထဲမှာ ပါတာကိုပဲ သုံးပါ။ မပါတဲ့ နာမည်၊ အဖြစ်အပျက်ကို ကိုယ်တိုင် မဖန်တီးပါနဲ့။ မသေချာရင် ချန်ထားပါ။
3. "ဒီ video က မူရင်း drama ကို ကိုယ်တိုင် ပြန်ပြောပြထားတဲ့ recap / commentary ဖြစ်ပါတယ်။ မူရင်းဖန်တီးသူများကို ကျေးဇူးတင်ပါတယ်" ဆိုတဲ့ စာကို ထည့်ပါ။
4. အချိန် ([m:ss]) ပါတဲ့ စာတန်းရှိရင် အဓိက အချိန် ၃–၆ ခုကို chapter အဖြစ် `0:00 အမည်` ပုံစံနဲ့ စာရင်းချပါ။ အချိန်မရှိရင် မထည့်ပါနဲ့။
5. အောက်ဆုံးမှာ hashtag ၃–၅ ခု (ဇာတ်လမ်းအမည်၊ Chinese drama recap အပါအဝင်)။
6. Subscribe / Like ကို တစ်ကြောင်းတည်း ယဉ်ကျေးစွာ ပြောပါ။
7. စုစုပေါင်း စာလုံး ၁၅၀–၂၅၀ ကြား။ Emoji ကို အနည်းငယ်သာ သုံးပါ။

ထုတ်ပေးမယ့် ပုံစံ:
- Description (ကူးသုံးလို့ရတဲ့ စာသား)
- Title ရွေးချယ်စရာ ၃ ခု

${hasStory ? story.toString() : '(ဇာတ်လမ်းစာသား မပါပါ။ အပေါ်က အချက်အလက်ပဲ သုံးပြီး ရေးပါ၊ ဇာတ်လမ်းအကျဉ်းကို မဖန်တီးပါနဲ့။)'}''';
}
