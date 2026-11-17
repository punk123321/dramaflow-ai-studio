import 'segments.dart';

/// "Video recap": Gemini WATCHES the video (the user attaches it in the Gemini
/// app) and writes the narration part by part. Pure helpers, no Flutter.

/// Line that separates parts inside the saved narration script. The script
/// splitter never joins text across it, so one part stays one voice.
const partBreak = '---';

/// How many Burmese characters a part's narration should have. About 8 per
/// second of video; never less than 60 so a short part still gets a sentence.
int targetChars(int lengthMs) {
  final c = (lengthMs / 1000 * 8).round();
  return c < 60 ? 60 : c;
}

/// Prompt for the parts [from]..[to] (1-based, inclusive) of [parts].
String buildVideoRecapPrompt({
  required String dramaTitle,
  required int episode,
  required List<SegmentSpec> parts,
  required int from,
  required int to,
  String notes = '',
}) {
  final b = StringBuffer();
  b.writeln('You are writing narration for a drama recap video. The video of "$dramaTitle", episode $episode, is attached to this chat. Watch it and listen to it.');
  b.writeln('For each part listed below, write the narration for ONLY that time range, in natural spoken Burmese (Myanmar Unicode), as if a storyteller tells the story to a friend.');
  b.writeln();
  b.writeln('PARTS:');
  for (var i = from; i <= to && i <= parts.length; i++) {
    final p = parts[i - 1];
    b.writeln('Part $i: ${formatTime(p.startMs)} - ${formatTime(p.endMs)} (about ${targetChars(p.lengthMs)} Burmese characters)');
  }
  b.writeln();
  b.writeln('RULES:');
  b.writeln('1. Use only what really happens in the video in that time range. Do not invent events, characters or dialogue. If you cannot tell, say less instead of guessing.');
  b.writeln('2. Keep character names consistent.');
  b.writeln('3. Plain spoken text only: no headings inside a part, no bullet points, no emoji, no brackets, no timestamps. Short sentences ending with "။".');
  b.writeln('4. Start every part with exactly this line, with the part number: === PART n ===');
  b.writeln('5. Output only the parts. No introduction and no closing remark.');
  b.writeln('6. Put the whole result inside ONE code block so it can be copied in one tap.');
  if (notes.trim().isNotEmpty) {
    b.writeln();
    b.writeln('NAME AND TERM PREFERENCES (follow exactly):');
    b.writeln(notes.trim());
  }
  return b.toString();
}

final RegExp _partHead = RegExp(r'^[ \t]*[=\-#*\s]*PART\s*(\d+)[=\-#*\s:：]*$', caseSensitive: false, multiLine: true);

/// Reads Gemini's reply. Returns part number to text. Text before the first
/// "=== PART n ===" line is ignored; an empty part is skipped.
Map<int, String> parseVideoRecapReply(String reply) {
  final text = reply.replaceAll('\r\n', '\n').replaceAll('```', '');
  final heads = _partHead.allMatches(text).toList();
  final out = <int, String>{};
  for (var i = 0; i < heads.length; i++) {
    final n = int.tryParse(heads[i].group(1)!);
    if (n == null || n < 1) continue;
    final end = i + 1 < heads.length ? heads[i + 1].start : text.length;
    final body = text.substring(heads[i].end, end).trim();
    if (body.isNotEmpty) out[n] = body;
  }
  return out;
}

/// The narration script made of the parts that have text, in order, with
/// [partBreak] between them.
String scriptFromParts(Map<int, String> byPart) {
  final keys = byPart.keys.toList()..sort();
  return [for (final k in keys) byPart[k]!.trim()].join('\n$partBreak\n');
}
