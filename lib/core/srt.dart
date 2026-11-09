/// SRT engine: parse, write, validate, split into chunks and merge results.
/// Pure Dart, no Flutter imports.
///
/// The golden rule: subtitle numbers and timestamps of the SOURCE file are
/// never lost. Merging always takes them from the source, and only the text
/// comes from the translated chunks.

class SrtEntry {
  const SrtEntry(this.index, this.startMs, this.endMs, this.text);

  final int index;
  final int startMs;
  final int endMs;
  final String text;

  SrtEntry withText(String t) => SrtEntry(index, startMs, endMs, t);

  @override
  bool operator ==(Object other) =>
      other is SrtEntry &&
      other.index == index &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      other.text == text;

  @override
  int get hashCode => Object.hash(index, startMs, endMs, text);

  @override
  String toString() => 'SrtEntry($index, $startMs-$endMs, $text)';
}

class SrtParseResult {
  const SrtParseResult(this.entries, this.badBlocks, this.missingIndexBlocks);

  final List<SrtEntry> entries;

  /// Blocks that could not be read as a subtitle (no timestamp line).
  final int badBlocks;

  /// Blocks that had a timestamp but no number. They were numbered
  /// automatically.
  final int missingIndexBlocks;
}

final RegExp _timeLine = RegExp(
  r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})',
);

int _ms(String h, String m, String s, String frac) {
  final f = int.parse(frac.padRight(3, '0'));
  return ((int.parse(h) * 60 + int.parse(m)) * 60 + int.parse(s)) * 1000 + f;
}

String _two(int n) => n < 10 ? '0$n' : '$n';

/// 3723456 -> "01:02:03,456".
String formatSrtTime(int ms) {
  final v = ms < 0 ? 0 : ms;
  final h = v ~/ 3600000;
  final m = (v % 3600000) ~/ 60000;
  final s = (v % 60000) ~/ 1000;
  final f = v % 1000;
  return '${_two(h)}:${_two(m)}:${_two(s)},${f.toString().padLeft(3, '0')}';
}

String _normalize(String raw) {
  var t = raw;
  if (t.isNotEmpty && t.codeUnitAt(0) == 0xFEFF) t = t.substring(1);
  return t.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

/// Reads SRT text. Accepts "," or "." before the milliseconds, Windows line
/// endings and a leading BOM. Blocks without a timestamp are counted in
/// [SrtParseResult.badBlocks] and left out.
SrtParseResult parseSrt(String raw) {
  final text = _normalize(raw).trim();
  if (text.isEmpty) return const SrtParseResult([], 0, 0);
  final blocks = text.split(RegExp(r'\n[ \t]*\n+'));
  final out = <SrtEntry>[];
  var bad = 0;
  var noIndex = 0;
  var last = 0;
  for (final block in blocks) {
    final lines = block.split('\n');
    var i = 0;
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
    if (i >= lines.length) continue;
    int? index;
    var timeAt = i;
    final first = lines[i].trim();
    final asInt = int.tryParse(first);
    if (asInt != null && i + 1 < lines.length) {
      index = asInt;
      timeAt = i + 1;
    }
    final m = _timeLine.firstMatch(lines[timeAt]);
    if (m == null) {
      bad++;
      continue;
    }
    if (index == null) {
      noIndex++;
      index = last + 1;
    }
    last = index;
    final body = lines.sublist(timeAt + 1).join('\n').trimRight();
    out.add(SrtEntry(
      index,
      _ms(m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!),
      _ms(m.group(5)!, m.group(6)!, m.group(7)!, m.group(8)!),
      body,
    ));
  }
  return SrtParseResult(out, bad, noIndex);
}

/// Writes entries back as SRT, keeping the numbers they carry.
String serializeSrt(List<SrtEntry> entries) {
  final b = StringBuffer();
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    b.write('${e.index}\n${formatSrtTime(e.startMs)} --> ${formatSrtTime(e.endMs)}\n${e.text}\n');
    if (i < entries.length - 1) b.write('\n');
  }
  return b.toString();
}

/// True when the text parses as at least one subtitle and most blocks are valid.
bool looksLikeSrt(String raw) {
  final r = parseSrt(raw);
  if (r.entries.isEmpty) return false;
  return r.badBlocks <= r.entries.length ~/ 2;
}

class SrtIssue {
  const SrtIssue(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Finds problems in a subtitle list: duplicate or missing numbers, an end
/// before its start, overlaps, and empty text.
List<SrtIssue> validateSrt(List<SrtEntry> entries) {
  final issues = <SrtIssue>[];
  final seen = <int>{};
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (!seen.add(e.index)) issues.add(SrtIssue('နံပါတ် ${e.index} ထပ်နေပါတယ်။'));
    if (e.endMs <= e.startMs) issues.add(SrtIssue('#${e.index} ဆုံးချိန်က စတင်ချိန်ထက် နောက်မကျပါဘူး။'));
    if (e.text.trim().isEmpty) issues.add(SrtIssue('#${e.index} စာသား မရှိပါဘူး။'));
    if (i > 0) {
      final prev = entries[i - 1];
      if (e.index != prev.index + 1 && e.index > prev.index) {
        issues.add(SrtIssue('နံပါတ် ${prev.index + 1} မှ ${e.index - 1} အထိ ပျောက်နေပါတယ်။'));
      }
      if (e.startMs < prev.endMs) {
        issues.add(SrtIssue('#${prev.index} နဲ့ #${e.index} အချိန် ထပ်နေပါတယ်။'));
      }
    }
  }
  return issues;
}

/// Splits subtitles into chunks of at most [maxChars] characters. An entry is
/// never cut in half, and every chunk has at least one entry.
List<List<SrtEntry>> chunkEntries(List<SrtEntry> entries, {int maxChars = 6000}) {
  final chunks = <List<SrtEntry>>[];
  var current = <SrtEntry>[];
  var size = 0;
  for (final e in entries) {
    final cost = e.text.length + 40;
    if (current.isNotEmpty && size + cost > maxChars) {
      chunks.add(current);
      current = <SrtEntry>[];
      size = 0;
    }
    current.add(e);
    size += cost;
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

/// Splits plain text by lines into chunks of at most [maxChars]. A single
/// line longer than the limit stays whole.
List<String> chunkText(String raw, {int maxChars = 6000}) {
  final lines = _normalize(raw).split('\n');
  final chunks = <String>[];
  final cur = StringBuffer();
  var size = 0;
  for (final line in lines) {
    final cost = line.length + 1;
    if (size > 0 && size + cost > maxChars) {
      chunks.add(cur.toString().trim());
      cur.clear();
      size = 0;
    }
    cur.writeln(line);
    size += cost;
  }
  final tail = cur.toString().trim();
  if (tail.isNotEmpty) chunks.add(tail);
  return chunks.where((c) => c.isNotEmpty).toList();
}

/// Dialogue lines only, without numbers and timestamps. Used for recap tasks.
String entriesToPlain(List<SrtEntry> entries) =>
    entries.map((e) => e.text.replaceAll('\n', ' ').trim()).where((t) => t.isNotEmpty).join('\n');

/// Cleans a reply pasted from an AI app: removes code fences and any chatter
/// before the first subtitle. Text after the last subtitle that is separated
/// by a blank line is dropped by the parser as a bad block.
String cleanModelReply(String raw) {
  var t = _normalize(raw).trim();
  final fence = RegExp(r'```[a-zA-Z0-9_-]*\n([\s\S]*?)```');
  final matches = fence.allMatches(t).toList();
  if (matches.isNotEmpty) {
    final withTime = matches.where((m) => m.group(1)!.contains('-->')).toList();
    if (withTime.isNotEmpty) {
      t = withTime.map((m) => m.group(1)!.trim()).join('\n\n');
    } else {
      t = t.replaceAll(RegExp(r'```[a-zA-Z0-9_-]*'), '').trim();
    }
  }
  final lines = t.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (_timeLine.hasMatch(lines[i])) {
      var start = i;
      if (i > 0 && int.tryParse(lines[i - 1].trim()) != null) start = i - 1;
      return lines.sublist(start).join('\n').trim();
    }
  }
  return t;
}

class ChunkReport {
  const ChunkReport({
    required this.missing,
    required this.extra,
    required this.changedTimes,
    required this.parsed,
    required this.badBlocks,
  });

  /// Source numbers that are not in the reply.
  final List<int> missing;

  /// Reply numbers that are not in the source.
  final List<int> extra;

  /// Numbers whose timestamps differ from the source.
  final List<int> changedTimes;
  final int parsed;
  final int badBlocks;

  bool get clean => missing.isEmpty && extra.isEmpty && changedTimes.isEmpty && badBlocks == 0 && parsed > 0;
}

/// Compares a reply with the source chunk it came from.
ChunkReport compareChunk(List<SrtEntry> source, SrtParseResult reply) {
  final byIndex = <int, SrtEntry>{for (final e in reply.entries) e.index: e};
  final srcIdx = source.map((e) => e.index).toSet();
  final missing = <int>[];
  final changed = <int>[];
  for (final s in source) {
    final r = byIndex[s.index];
    if (r == null) {
      missing.add(s.index);
    } else if (r.startMs != s.startMs || r.endMs != s.endMs) {
      changed.add(s.index);
    }
  }
  final extra = reply.entries.map((e) => e.index).where((i) => !srcIdx.contains(i)).toList();
  return ChunkReport(
    missing: missing,
    extra: extra,
    changedTimes: changed,
    parsed: reply.entries.length,
    badBlocks: reply.badBlocks,
  );
}

class MergeResult {
  const MergeResult(this.entries, this.missing, this.changedTimes);

  /// Complete subtitle list, same numbers and timestamps as the source.
  final List<SrtEntry> entries;

  /// Numbers with no translated text. The source text was kept for them.
  final List<int> missing;

  /// Numbers whose timestamps in the reply differed. The source ones were used.
  final List<int> changedTimes;
}

/// Builds the final subtitle list. Numbers and timestamps always come from
/// [source]; only the text is taken from the replies. An entry that no reply
/// covers keeps its source text and is listed in [MergeResult.missing].
MergeResult mergeTranslated(List<SrtEntry> source, Iterable<SrtParseResult> replies) {
  final byIndex = <int, SrtEntry>{};
  for (final r in replies) {
    for (final e in r.entries) {
      byIndex[e.index] = e;
    }
  }
  final out = <SrtEntry>[];
  final missing = <int>[];
  final changed = <int>[];
  for (final s in source) {
    final r = byIndex[s.index];
    if (r == null || r.text.trim().isEmpty) {
      missing.add(s.index);
      out.add(s);
    } else {
      if (r.startMs != s.startMs || r.endMs != s.endMs) changed.add(s.index);
      out.add(s.withText(r.text));
    }
  }
  return MergeResult(out, missing, changed);
}
