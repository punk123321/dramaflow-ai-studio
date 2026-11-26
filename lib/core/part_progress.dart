import 'dart:convert';

/// Remembers which parts (segments) of a long video were already made as MP4,
/// so "make all" after a stop or a crash only makes the ones that are left.
///
/// A part is identified by its time range plus a short [tag] for the settings
/// that change the file (sound on/off ...), not by its number, so adding a cut
/// elsewhere does not make the finished parts look unfinished.
String partKey(int startMs, int endMs, {String tag = ''}) => '$startMs-$endMs${tag.isEmpty ? '' : '|$tag'}';

/// Positions (0-based) of the parts that still have to be made.
List<int> pendingParts(int total, Set<int> finished) => [for (var i = 0; i < total; i++) if (!finished.contains(i)) i];

Set<String> decodeDone(String? raw) {
  if (raw == null || raw.trim().isEmpty) return {};
  try {
    final v = jsonDecode(raw);
    if (v is List) return {for (final e in v) if (e is String) e};
  } catch (_) {}
  return {};
}

String encodeDone(Set<String> keys) => jsonEncode(keys.toList()..sort());
