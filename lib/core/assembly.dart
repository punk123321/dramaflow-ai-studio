import 'dart:convert';

/// AssemblyAI speech-to-text (optional, needs the user's own key). These are the
/// parts that do not touch the network, so they can be tested.
const assemblyBase = 'https://api.assemblyai.com';

/// The language codes offered in the app. The code is also typed by hand
/// (Settings), because the list of codes AssemblyAI accepts can change.
const assemblyLanguages = <String, String>{
  'zh': 'တရုတ် (Mandarin)',
  'en': 'အင်္ဂလိပ်',
  'my': 'မြန်မာ (တိကျမှု နိမ့်)',
  '': 'အလိုအလျောက် သိ',
};

/// Key and language, kept on the phone only.
class AssemblySettings {
  const AssemblySettings({this.apiKey = '', this.language = 'zh'});

  final String apiKey;
  final String language;

  bool get hasKey => apiKey.trim().isNotEmpty;

  AssemblySettings copyWith({String? apiKey, String? language}) =>
      AssemblySettings(apiKey: apiKey ?? this.apiKey, language: language ?? this.language);

  String encode() => jsonEncode({'key': apiKey, 'lang': language});

  static AssemblySettings decode(String? s) {
    if (s == null || s.trim().isEmpty) return const AssemblySettings();
    try {
      final m = jsonDecode(s);
      if (m is! Map) return const AssemblySettings();
      final k = m['key'];
      final l = m['lang'];
      return AssemblySettings(apiKey: k is String ? k.trim() : '', language: l is String ? l.trim() : 'zh');
    } catch (_) {
      return const AssemblySettings();
    }
  }
}

/// Body of "create transcript". An empty [language] means: let AssemblyAI
/// detect the language. The speech model is left out on purpose, so the
/// service picks its own (and falls back for a language its newest model lacks).
String transcriptBody(String audioUrl, String language) {
  final lang = language.trim();
  return jsonEncode({
    'audio_url': audioUrl,
    if (lang.isEmpty) 'language_detection': true else 'language_code': lang,
  });
}

/// `upload_url` from the upload reply, or null.
String? uploadUrlFrom(String body) {
  try {
    final m = jsonDecode(body);
    final u = m is Map ? m['upload_url'] : null;
    return u is String && u.isNotEmpty ? u : null;
  } catch (_) {
    return null;
  }
}

/// `id` from the create-transcript reply, or null.
String? transcriptIdFrom(String body) {
  try {
    final m = jsonDecode(body);
    final u = m is Map ? m['id'] : null;
    return u is String && u.isNotEmpty ? u : null;
  } catch (_) {
    return null;
  }
}

enum AsrState { waiting, done, failed }

class AsrStatus {
  const AsrStatus(this.state, [this.error = '']);
  final AsrState state;
  final String error;
}

/// Reads the polling reply. Anything that is not completed or error means keep waiting.
AsrStatus parseAsrStatus(String body) {
  try {
    final m = jsonDecode(body);
    if (m is! Map) return const AsrStatus(AsrState.failed, 'ပြန်ကြားချက် မှန်မှန် မဖတ်နိုင်ပါ');
    final st = m['status'];
    if (st == 'completed') return const AsrStatus(AsrState.done);
    if (st == 'error') {
      final e = m['error'];
      return AsrStatus(AsrState.failed, e is String && e.isNotEmpty ? e : 'AssemblyAI က error ပြန်ပါတယ်');
    }
    return const AsrStatus(AsrState.waiting);
  } catch (_) {
    return const AsrStatus(AsrState.failed, 'ပြန်ကြားချက် မှန်မှန် မဖတ်နိုင်ပါ');
  }
}

/// A short Burmese reason for an HTTP error, with the service's own message when it sends one.
String assemblyHttpError(int code, String body) {
  String? detail;
  try {
    final m = jsonDecode(body);
    if (m is Map && m['error'] is String) detail = m['error'] as String;
  } catch (_) {}
  final why = switch (code) {
    401 || 403 => 'Key မမှန်ဘူး၊ ဒါမှမဟုတ် ခွင့်မရှိဘူး',
    402 => 'Credit ကုန်နေပြီ',
    429 => 'တောင်းဆိုမှု များလွန်းတယ်၊ ခဏနေပြီး ထပ်စမ်းပါ',
    _ => 'HTTP $code',
  };
  return detail == null ? why : '$why ($detail)';
}
