import 'dart:convert';
import 'dart:typed_data';

/// Optional spoken narration from the Gemini API. Used ONLY when the user has
/// saved their own API key and taps the button. Without a key the app works
/// exactly as before (phone TTS, microphone, imported audio).
///
/// Pure Dart: request building and reply reading. The network call itself is
/// in lib/platform/gemini_tts_client.dart.
///
/// Written from the public documentation without a way to call the API from
/// here, so the first real call decides whether the request shape is right.

/// The model that lists Burmese as supported (the cheaper Flash-Lite one does not).
const defaultTtsModel = 'gemini-3.8-flash-tts';
const defaultTtsVoice = 'Kore';

/// Picture model ("Nano Banana 2" in Google's naming). Editable in settings.
const defaultImageModel = 'gemini-3.1-flash-image';

const imageAspects = ['16:9', '9:16', '1:1', '4:5'];

const ttsVoices = [
  'Zephyr', 'Puck', 'Charon', 'Kore', 'Fenrir', 'Leda', 'Orus', 'Aoede', 'Callirrhoe', 'Autonoe',
  'Enceladus', 'Iapetus', 'Umbriel', 'Algieba', 'Despina', 'Erinome', 'Algenib', 'Rasalgethi',
  'Laomedeia', 'Achernar', 'Alnilam', 'Schedar', 'Gacrux', 'Pulcherrima', 'Achird',
  'Zubenelgenubi', 'Vindemiatrix', 'Sadachbia', 'Sadaltager', 'Sulafat',
];

class GeminiTtsSettings {
  const GeminiTtsSettings({this.apiKey = '', this.model = defaultTtsModel, this.voice = defaultTtsVoice, this.imageModel = defaultImageModel});

  final String apiKey;
  final String model;
  final String voice;
  final String imageModel;

  bool get ready => apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  GeminiTtsSettings copyWith({String? apiKey, String? model, String? voice, String? imageModel}) => GeminiTtsSettings(
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        voice: voice ?? this.voice,
        imageModel: imageModel ?? this.imageModel,
      );

  String encode() => jsonEncode({'key': apiKey, 'model': model, 'voice': voice, 'imgModel': imageModel});

  static GeminiTtsSettings decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const GeminiTtsSettings();
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const GeminiTtsSettings();
      final model = (m['model'] as String?)?.trim() ?? '';
      final voice = (m['voice'] as String?) ?? '';
      return GeminiTtsSettings(
        apiKey: (m['key'] as String?)?.trim() ?? '',
        model: model.isEmpty ? defaultTtsModel : model,
        voice: ttsVoices.contains(voice) ? voice : defaultTtsVoice,
        imageModel: ((m['imgModel'] as String?)?.trim().isEmpty ?? true) ? defaultImageModel : (m['imgModel'] as String).trim(),
      );
    } catch (_) {
      return const GeminiTtsSettings();
    }
  }
}

/// Older "gemini-2.x ... -tts" models use generateContent; newer ones use the
/// interactions endpoint.
bool usesGenerateContent(String model) => model.trim().startsWith('gemini-2');

Uri ttsEndpoint(String model) {
  final m = model.trim();
  return usesGenerateContent(m)
      ? Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent')
      : Uri.parse('https://generativelanguage.googleapis.com/v1beta/interactions');
}

Map<String, Object?> ttsBody(String model, String text, String voice) {
  if (usesGenerateContent(model)) {
    return {
      'contents': [
        {
          'parts': [
            {'text': text}
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {'voiceName': voice}
          }
        },
      },
    };
  }
  return {
    'model': model.trim(),
    'input': [
      {
        'type': 'user_input',
        'content': [
          {'type': 'text', 'text': text}
        ]
      }
    ],
    'response_format': {'type': 'audio'},
    'generation_config': {
      'speech_config': [
        {'voice': voice}
      ]
    },
  };
}

class TtsAudio {
  const TtsAudio(this.bytes, this.sampleRate);

  final Uint8List bytes;
  final int sampleRate;
}

/// Finds the base64 audio anywhere in the reply (both reply shapes), decodes
/// it, and returns a playable WAV. Null when the reply holds no audio.
TtsAudio? extractAudio(Object? json) {
  TtsAudio? found;
  void walk(Object? n) {
    if (found != null) return;
    if (n is Map) {
      final data = n['data'];
      final mime = '${n['mimeType'] ?? n['mime_type'] ?? ''}';
      if (data is String && data.length > 100 && (n['type'] == 'audio' || mime.startsWith('audio'))) {
        try {
          final raw = base64Decode(data);
          final rate = int.tryParse(RegExp(r'rate=(\d+)').firstMatch(mime)?.group(1) ?? '') ?? 24000;
          found = TtsAudio(ensureWav(raw, sampleRate: rate), rate);
          return;
        } catch (_) {}
      }
      for (final v in n.values) {
        walk(v);
      }
    } else if (n is List) {
      for (final v in n) {
        walk(v);
      }
    }
  }

  walk(json);
  return found;
}

/// Raw 16-bit mono PCM gets a WAV header. A reply that already is a WAV is left alone.
Uint8List ensureWav(Uint8List b, {int sampleRate = 24000}) {
  if (b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46) return b;
  final out = BytesBuilder();
  void w32(int v) => out.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  void w16(int v) => out.add([v & 255, (v >> 8) & 255]);
  out.add(ascii.encode('RIFF'));
  w32(36 + b.length);
  out.add(ascii.encode('WAVEfmt '));
  w32(16);
  w16(1); // PCM
  w16(1); // mono
  w32(sampleRate);
  w32(sampleRate * 2);
  w16(2);
  w16(16);
  out.add(ascii.encode('data'));
  w32(b.length);
  out.add(b);
  return out.toBytes();
}

/// A short Burmese explanation for a failed call. The key is never shown.
String explainTtsHttp(int status, String body, String apiKey) {
  var detail = body.trim();
  if (apiKey.isNotEmpty) detail = detail.replaceAll(apiKey, '***');
  if (detail.length > 300) detail = detail.substring(0, 300);
  final lower = body.toLowerCase();
  final billing = (status == 403 || status == 429) && (lower.contains('billing') || lower.contains('free tier'));
  final why = billing
      ? 'ဒီ Google project မှာ free tier မရတော့ဘူး၊ billing ဖွင့်မှ API သုံးလို့ရမယ်။ ပိုက်ဆံမကုန်ချင်ရင် "Gemini ဖွင့်မယ်" (chat) နည်းကို သုံးပါ။'
      : switch (status) {
    400 => 'တောင်းဆိုမှု ပုံစံ ဒါမှမဟုတ် model နာမည် မှားနိုင်တယ်။',
    401 || 403 => 'API key မမှန်ဘူး ဒါမှမဟုတ် ဒီ model ကို သုံးခွင့်မရှိဘူး။',
    404 => 'Model နာမည် မတွေ့ဘူး။ Model နာမည်ကို စစ်ပါ။',
    429 => 'သုံးခွင့်ပမာဏ (quota) ပြည့်သွားတယ်။ ခဏစောင့်ပါ ဒါမှမဟုတ် Google AI Studio မှာ စစ်ပါ။',
    >= 500 => 'Gemini ဘက်က ပြဿနာ။ ခဏနေ ပြန်စမ်းပါ။',
    _ => 'မအောင်မြင်ပါ။',
  };
  return 'Gemini API ($status): $why${detail.isEmpty ? '' : '\n$detail'}';
}

// ---- pictures (thumbnail) ----

Uri imageEndpoint(String model) => Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/${model.trim()}:generateContent');

Map<String, Object?> imageBody(String prompt, String aspect) => {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['IMAGE'],
        'imageConfig': {'aspectRatio': imageAspects.contains(aspect) ? aspect : '16:9'},
      },
    };

class GeneratedImage {
  const GeneratedImage(this.bytes, this.extension);

  final Uint8List bytes;
  final String extension;
}

/// The first picture in the reply (base64 in an `inlineData` part). Null when none.
GeneratedImage? extractImage(Object? json) {
  GeneratedImage? found;
  void walk(Object? n) {
    if (found != null) return;
    if (n is Map) {
      final data = n['data'];
      final mime = '${n['mimeType'] ?? n['mime_type'] ?? ''}';
      if (data is String && data.length > 100 && mime.startsWith('image/')) {
        try {
          final ext = mime.contains('jpeg') || mime.contains('jpg') ? 'jpg' : (mime.contains('webp') ? 'webp' : 'png');
          found = GeneratedImage(base64Decode(data), ext);
          return;
        } catch (_) {}
      }
      for (final v in n.values) {
        walk(v);
      }
    } else if (n is List) {
      for (final v in n) {
        walk(v);
      }
    }
  }

  walk(json);
  return found;
}

/// The starting prompt for a thumbnail. Original scene, no real faces, no
/// logos, no lettering (the app adds text itself).
String defaultImagePrompt(String dramaTitle) =>
    'Eye-catching video thumbnail for a recap of a Chinese drama called "$dramaTitle". '
    'Dramatic, emotional mood, cinematic lighting, bold colours. Original invented characters, '
    'no real people, no existing characters, no logos, no text or lettering in the picture.';
