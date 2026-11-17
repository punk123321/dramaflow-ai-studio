/// Splits a narration script into pieces a text-to-speech engine can read in
/// one go. No Flutter imports.

/// One sentence including its closing mark. Burmese "။", Latin ". ! ?" and
/// CJK "。！？" end a sentence; the Burmese comma "၊" does not.
final RegExp _sentence = RegExp(r'[^။.!?。！？]+[။.!?。！？]*|[။.!?。！？]+');

/// Splits [text] into chunks of at most [maxChars]. Chunks follow line and
/// sentence boundaries, so no sentence is cut in the middle unless one
/// sentence alone is longer than the limit. All text is kept, in order.
List<String> splitScript(String text, {int maxChars = 1500}) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (normalized.isEmpty) return [];
  final pieces = <String?>[]; // null = hard break between parts
  for (final line in normalized.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    if (t == '---') {
      if (pieces.isNotEmpty && pieces.last != null) pieces.add(null);
      continue;
    }
    for (final m in _sentence.allMatches(t)) {
      final u = m.group(0)!.trim();
      if (u.isEmpty) continue;
      if (u.length <= maxChars) {
        pieces.add(u);
      } else {
        for (var i = 0; i < u.length; i += maxChars) {
          pieces.add(u.substring(i, i + maxChars > u.length ? u.length : i + maxChars));
        }
      }
    }
  }
  final chunks = <String>[];
  final cur = StringBuffer();
  for (final p in pieces) {
    if (p == null) {
      if (cur.isNotEmpty) {
        chunks.add(cur.toString());
        cur.clear();
      }
      continue;
    }
    if (cur.isNotEmpty && cur.length + 1 + p.length > maxChars) {
      chunks.add(cur.toString());
      cur.clear();
    }
    if (cur.isNotEmpty) cur.write(' ');
    cur.write(p);
  }
  if (cur.isNotEmpty) chunks.add(cur.toString());
  return chunks;
}

/// Rough speaking time. Used only to show an estimate before audio exists.
Duration estimateSpeech(String text, {double charsPerSecond = 9}) =>
    Duration(milliseconds: (text.runes.length / charsPerSecond * 1000).round());
