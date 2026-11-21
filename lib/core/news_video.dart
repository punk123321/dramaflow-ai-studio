import 'dart:convert';

import 'srt.dart';

/// News video made by the user's own backend (a Colab notebook, see
/// tools/news_backend_colab.py). The app only sends the request, shows the
/// progress and downloads the MP4. The parts here do not touch the network.

/// Where the backend is and the key for the stock-footage site, kept on the
/// phone only.
class NewsVideoSettings {
  const NewsVideoSettings({this.url = '', this.token = '', this.provider = 'wikimedia', this.keys = const {}, this.imageCount = 20});

  final String url;
  final String token;

  /// Where the background pictures/videos come from: see [stockProviders].
  final String provider;

  /// API key per provider (Wikimedia needs none).
  final Map<String, String> keys;

  /// Pictures for the whole video (picture sources only), 0 = one per scene.
  final int imageCount;

  bool get ready => url.isNotEmpty && token.isNotEmpty;

  String get stockKey => keyOf(provider);

  /// The key for [p]. Pixabay pictures use the same key as Pixabay videos.
  String keyOf(String p) => keys[p] ?? (p == 'pixabay_photo' ? keys['pixabay'] ?? '' : '');

  NewsVideoSettings copyWith({String? url, String? token, String? provider, Map<String, String>? keys, int? imageCount}) => NewsVideoSettings(
      url: url ?? this.url, token: token ?? this.token, provider: provider ?? this.provider, keys: keys ?? this.keys, imageCount: imageCount ?? this.imageCount);

  String encode() => jsonEncode({'url': url, 'token': token, 'provider': provider, 'keys': keys, 'images': imageCount});

  static NewsVideoSettings decode(String? s) {
    if (s == null || s.trim().isEmpty) return const NewsVideoSettings();
    try {
      final m = jsonDecode(s);
      if (m is! Map) return const NewsVideoSettings();
      String g(String k) => m[k] is String ? (m[k] as String).trim() : '';
      final keys = <String, String>{};
      final raw = m['keys'];
      if (raw is Map) {
        for (final e in raw.entries) {
          if (e.key is String && e.value is String && (e.value as String).trim().isNotEmpty) keys[e.key as String] = (e.value as String).trim();
        }
      }
      if (g('pexels').isNotEmpty) keys.putIfAbsent('pexels', () => g('pexels')); // older saves
      final prov = g('provider');
      final img = m['images'];
      return NewsVideoSettings(
        url: g('url'),
        token: g('token'),
        provider: stockProviders.containsKey(prov) ? prov : (keys.containsKey('pexels') ? 'pexels' : 'wikimedia'),
        keys: keys,
        imageCount: img is num ? img.toInt().clamp(0, maxNewsImages) : 20,
      );
    } catch (_) {
      return const NewsVideoSettings();
    }
  }
}

/// Where the background footage comes from. [needsKey] false = no account
/// needed; [images] true = pictures (slow zoom), many per video.
const stockProviders = <String, ({String title, String note, bool needsKey, bool images})>{
  'wikimedia': (title: 'Wikimedia Commons (ပုံ)', note: 'key မလို၊ ပုံ အများကြီး (Ken Burns zoom)၊ လိုင်စင်/credit စစ်ပါ', needsKey: false, images: true),
  'pixabay_photo': (title: 'Pixabay (ပုံ)', note: 'ပုံ အများကြီး၊ free API key လို (pixabay.com/api/docs)', needsKey: true, images: true),
  'unsplash': (title: 'Unsplash (ပုံ)', note: 'ပုံ အများကြီး (Ken Burns zoom)၊ Access Key လို', needsKey: true, images: true),
  'pixabay': (title: 'Pixabay (ဗီဒီယို)', note: 'scene တစ်ခုကို ဗီဒီယို ၁ ခု၊ free API key လို', needsKey: true, images: false),
  'pexels': (title: 'Pexels (ဗီဒီယို)', note: 'scene တစ်ခုကို ဗီဒီယို ၁ ခု၊ API key လို', needsKey: true, images: false),
};

const maxNewsImages = 40;

/// Reads what the backend prints: `https://xxxx.trycloudflare.com#TOKEN`.
/// Returns null when there is no usable web address.
({String url, String token})? parseConnect(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final hash = t.indexOf('#');
  var url = (hash >= 0 ? t.substring(0, hash) : t).trim();
  final token = hash >= 0 ? t.substring(hash + 1).trim() : '';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  final u = Uri.tryParse(url);
  if (u == null || !(u.scheme == 'https' || u.scheme == 'http') || u.host.isEmpty) return null;
  return (url: url, token: token);
}

const newsVoices = <String, String>{
  'my-MM-ThihaNeural': 'သီဟ (အမျိုးသား)',
  'my-MM-NilarNeural': 'နီလာ (အမျိုးသမီး)',
};

const newsSourceGroups = <String, List<String>>{
  'နိုင်ငံတကာ': ['Reuters', 'AP News', 'BBC News', 'Al Jazeera'],
  'နည်းပညာ': ['TechCrunch', 'The Verge', 'Wired'],
  'အားကစား': ['ESPN', 'UFC', 'ONE Championship'],
  'မြန်မာဘာသာ': ['BBC Burmese', 'VOA Burmese', 'Eleven Media', 'Mizzima'],
};

/// Master prompts. {{TOPIC}} {{SOURCES}} {{DURATION_MIN}} {{TARGET_WORDS}}
/// {{SCENE_COUNT}} are filled in by the backend.
const newsPrompts = <String, ({String title, String text})>{
  'anchor': (
    title: 'သတင်းကြေညာသူ',
    text: '''သင်သည် ကျွမ်းကျင်သော မြန်မာသတင်းကြေညာသူ (Senior News Anchor) တစ်ဦးဖြစ်သည်။
ခေါင်းစဉ်: {{TOPIC}}
အဓိက ကိုးကားရမည့် သတင်းရင်းမြစ်များ: {{SOURCES}}
ဗီဒီယိုကြာချိန်: {{DURATION_MIN}} မိနစ် (ခန့်မှန်း စာလုံးရေ {{TARGET_WORDS}} လုံး၊ စုစုပေါင်း {{SCENE_COUNT}} Scenes)။

စည်းမျဉ်းများ:
1. Hook (12%): ပထမ ၂၀ စက္ကန့်အတွင်း အဓိကသတင်းချက်ကို ဆွဲဆောင်မှုရှိရှိ စတင်ပါ။
2. Core & Sources (45%): ရင်းမြစ်အမည်ကို ထည့်သွင်းကိုးကားပြီး အချက်အလက်မှန်ကန်စွာ တင်ဆက်ပါ။
3. Analysis (30%): ဒီသတင်းက လူထု/နည်းပညာ/စီးပွားရေးအပေါ် ဘယ်လိုသက်ရောက်နိုင်မလဲ သုံးသပ်ပြပါ။
4. Outro (13%): အနှစ်ချုပ်ပြီး ကြည့်ရှုသူကို မေးခွန်းတစ်ခုမေးကာ ဖိတ်ခေါ်ပါ။
Scene တစ်ခုချင်းစီအတွက် narration နှင့် English visual search keyword ကို ခွဲထုတ်ပေးပါ။''',
  ),
  'viral': (
    title: 'အမြန် Viral',
    text: '''သင်သည် TikTok / Reels / Shorts အတွက် Fast-Paced News Creator ဖြစ်သည်။
ခေါင်းစဉ်: {{TOPIC}} | ရင်းမြစ်များ: {{SOURCES}}
ကြာချိန်: {{DURATION_MIN}} မိနစ် ({{TARGET_WORDS}} words, {{SCENE_COUNT}} scenes)။
- စကားပြောပုံစံကို သွက်လက်ပြီး နားထောင်ရလွယ်အောင် ရေးပါ။
- အံ့ဩစရာ အချက်အလက် (အမှန်တကယ်ရှိသည်ကိုသာ) နဲ့ စတင်ပါ။
- Scene တစ်ခုစီမှာ 10-15 စက္ကန့်စာ စာသားနဲ့ B-roll English Keyword ထည့်ပေးပါ။''',
  ),
  'deep': (
    title: 'အတွင်းကျကျ သုံးသပ်',
    text: '''သင်သည် Investigative News Analyst တစ်ဦးဖြစ်သည်။
ခေါင်းစဉ်: {{TOPIC}} | ကိုးကားရင်းမြစ်: {{SOURCES}}
ကြာချိန်: {{DURATION_MIN}} မိနစ် ({{TARGET_WORDS}} words, {{SCENE_COUNT}} scenes)။
- ဖြစ်ရပ်နောက်ခံ၊ ကိန်းဂဏန်းအချက်အလက်၊ ရှုထောင့်နှစ်ဖက်နှင့် အနာဂတ်ခန့်မှန်းချက်များကို စနစ်တကျ ခွဲခြမ်းစိတ်ဖြာ တင်ဆက်ပါ။''',
  ),
  'story': (
    title: 'ဇာတ်လမ်းပြောပုံ',
    text: '''သင်သည် Documentary Storyteller တစ်ဦးဖြစ်သည်။
ခေါင်းစဉ်: {{TOPIC}} | ရင်းမြစ်: {{SOURCES}}
ကြာချိန်: {{DURATION_MIN}} မိနစ် ({{TARGET_WORDS}} words, {{SCENE_COUNT}} scenes)။
- သတင်းကို ဇာတ်လမ်းတစ်ပုဒ်လို စီးမျောနားထောင်ချင်စရာ ဖြစ်အောင် ရေးပြီး Cinematic Visual Keywords များ ထည့်ပေးပါ။''',
  ),
};

const minNewsMinutes = 3.0;
const maxNewsMinutes = 5.0;

/// The body of "create job". The duration is kept between 3 and 5 minutes.
Map<String, Object?> newsRequestJson({
  required String topic,
  required String geminiKey,
  required String stockProvider,
  required String stockKey,
  int imageCount = 20,
  required String ratio,
  required double minutes,
  required String voice,
  required List<String> sources,
  required bool strict,
  required String prompt,
}) {
  final m = minutes.isNaN ? 4.0 : minutes.clamp(minNewsMinutes, maxNewsMinutes).toDouble();
  return {
    'topic': topic.trim(),
    'gemini_key': geminiKey.trim(),
    'stock_provider': stockProviders.containsKey(stockProvider) ? stockProvider : 'wikimedia',
    'stock_key': stockKey.trim(),
    'image_count': imageCount.clamp(0, maxNewsImages),
    if (stockProvider == 'pexels') 'pexels_key': stockKey.trim(),
    'aspect_ratio': ratio == '16:9' ? '16:9' : '9:16',
    'duration_min': m,
    'voice_model': voice,
    'news_sources': sources,
    'strict_grounding': strict,
    'master_prompt': prompt,
  };
}

class NewsScene {
  const NewsScene(this.narration, this.source, this.startMs, this.endMs);

  final String narration;
  final String source;
  final int startMs;
  final int endMs;
}

enum JobState { queued, running, done, error }

class NewsJob {
  const NewsJob({
    required this.state,
    this.stage = '',
    this.progress = 0,
    this.error = '',
    this.title = '',
    this.scenes = const [],
    this.seconds = 0,
    this.warnings = const [],
    this.downloadUrl = '',
  });

  final JobState state;
  final String stage;
  final int progress;
  final String error;
  final String title;
  final List<NewsScene> scenes;
  final double seconds;
  final List<String> warnings;
  final String downloadUrl;

  bool get finished => state == JobState.done || state == JobState.error;
}

/// Reads the reply of "job status". Anything unreadable is an error job.
NewsJob parseNewsJob(String body) {
  try {
    final m = jsonDecode(body);
    if (m is! Map) return const NewsJob(state: JobState.error, error: 'ပြန်ကြားချက် မှန်မှန် မဖတ်နိုင်ပါ');
    final st = switch (m['status']) {
      'queued' => JobState.queued,
      'running' => JobState.running,
      'done' => JobState.done,
      _ => JobState.error,
    };
    int ms(Object? v) => v is num && v.isFinite ? (v * 1000).round() : 0;
    final scenes = <NewsScene>[];
    final raw = m['scenes'];
    if (raw is List) {
      for (final s in raw) {
        if (s is! Map) continue;
        final n = s['narration'];
        if (n is! String || n.trim().isEmpty) continue;
        scenes.add(NewsScene(n.trim(), s['source'] is String ? s['source'] as String : '', ms(s['start']), ms(s['end'])));
      }
    }
    final p = m['progress'];
    final warn = m['warnings'];
    return NewsJob(
      state: st,
      stage: m['stage'] is String ? m['stage'] as String : '',
      progress: p is num ? p.clamp(0, 100).round() : 0,
      error: m['error'] is String ? m['error'] as String : (st == JobState.error ? 'ဘာကြောင့်မှန်း မသိ' : ''),
      title: m['title'] is String ? m['title'] as String : '',
      scenes: scenes,
      seconds: m['seconds'] is num ? (m['seconds'] as num).toDouble() : 0,
      warnings: warn is List ? [for (final w in warn) if (w is String) w] : const [],
      downloadUrl: m['download_url'] is String ? m['download_url'] as String : '',
    );
  } catch (_) {
    return const NewsJob(state: JobState.error, error: 'ပြန်ကြားချက် မှန်မှန် မဖတ်နိုင်ပါ');
  }
}

/// Subtitles from the scene timing: each scene is split at sentence ends
/// ("။" or ".") and the scene's time is shared by the length of each piece,
/// so a line stays up about as long as it takes to say.
List<SrtEntry> scenesToSrt(List<NewsScene> scenes) {
  final out = <SrtEntry>[];
  for (final sc in scenes) {
    final span = sc.endMs - sc.startMs;
    if (span <= 0) continue;
    final parts = sc.narration
        .split(RegExp(r'(?<=[။!?])\s*|(?<=\.)\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) continue;
    final total = parts.fold<int>(0, (a, b) => a + b.length);
    var cursor = sc.startMs;
    for (var i = 0; i < parts.length; i++) {
      final last = i == parts.length - 1;
      final len = last ? sc.endMs - cursor : (span * parts[i].length / total).round();
      final end = last ? sc.endMs : (cursor + len).clamp(cursor + 1, sc.endMs).toInt();
      out.add(SrtEntry(out.length + 1, cursor, end, parts[i]));
      cursor = end;
    }
  }
  return out;
}
