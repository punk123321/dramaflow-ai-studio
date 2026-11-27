/// Plain-text answers from Gemini (generateContent). The key goes in a header
/// (see the client), never in the address.
Uri textEndpoint(String model) => Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/${model.trim()}:generateContent');

Map<String, Object?> textBody(String prompt) => {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {'temperature': 0.7},
    };

/// All the text parts of the first candidate, or null when there are none.
String? extractText(Object? json) {
  if (json is! Map) return null;
  final cands = json['candidates'];
  if (cands is! List || cands.isEmpty) return null;
  final first = cands.first;
  if (first is! Map) return null;
  final content = first['content'];
  if (content is! Map) return null;
  final parts = content['parts'];
  if (parts is! List) return null;
  final b = StringBuffer();
  for (final p in parts) {
    if (p is Map && p['text'] is String) b.write(p['text']);
  }
  final t = b.toString().trim();
  return t.isEmpty ? null : t;
}

/// Why Gemini refused to answer, when it did (for example a safety block).
String? blockReason(Object? json) {
  if (json is! Map) return null;
  final fb = json['promptFeedback'];
  if (fb is Map && fb['blockReason'] is String) return fb['blockReason'] as String;
  final cands = json['candidates'];
  if (cands is List && cands.isNotEmpty && cands.first is Map) {
    final r = (cands.first as Map)['finishReason'];
    if (r is String && r != 'STOP' && r != 'MAX_TOKENS') return r;
  }
  return null;
}
