import 'dart:convert';

/// Upload text (titles, description, hashtags) written by Gemini through
/// copy/paste. Pure Dart, no network, no API key. The reply is only a draft:
/// the user reads and edits it before using it anywhere.

const maxTitles = 5;
const maxHashtags = 15;
const maxThumbTexts = 6;
const maxThumbChars = 40;
const maxTitleChars = 100;
const maxDescriptionChars = 2000;
const maxScriptCharsInPrompt = 6000;

class PublishText {
  const PublishText({this.titles = const [], this.description = '', this.hashtags = const [], this.thumbTexts = const []});

  final List<String> titles;

  /// Short lines for the picture itself.
  final List<String> thumbTexts;
  final String description;
  final List<String> hashtags;

  bool get isEmpty => titles.isEmpty && thumbTexts.isEmpty && description.trim().isEmpty && hashtags.isEmpty;

  String encode() => jsonEncode({'titles': titles, 'description': description, 'hashtags': hashtags, 'thumb': thumbTexts});

  static PublishText decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const PublishText();
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const PublishText();
      return PublishText(
        titles: [for (final t in (m['titles'] as List? ?? const [])) if (t is String) t],
        description: (m['description'] as String?) ?? '',
        hashtags: [for (final t in (m['hashtags'] as List? ?? const [])) if (t is String) t],
        thumbTexts: [for (final t in (m['thumb'] as List? ?? const [])) if (t is String) t],
      );
    } catch (_) {
      return const PublishText();
    }
  }
}

String buildPublishPrompt({required String dramaTitle, required int episode, required String script}) {
  final cut = script.length > maxScriptCharsInPrompt ? script.substring(0, maxScriptCharsInPrompt) : script;
  final b = StringBuffer()
    ..writeln('I made a recap / commentary video about the drama "$dramaTitle", episode $episode.')
    ..writeln('Write upload text in Burmese for it. Reply with ONE JSON object only, in a code block:')
    ..writeln('{"titles":["...","...","..."],"description":"...","hashtags":["#...","#..."],"thumbnailTexts":["...","..."]}')
    ..writeln('Rules:')
    ..writeln('- 3 different titles, each under $maxTitleChars characters.')
    ..writeln('- description: 2 to 4 sentences about what the video explains. Do not add the source or copyright line, I add that myself.')
    ..writeln('- 5 to 10 hashtags.')
    ..writeln('- thumbnailTexts: 5 very short, eye-catching lines (at most 6 words each) to print on the thumbnail picture. Catchy and curious is fine, but they must match what the video really shows.')
    ..writeln('- Be honest: do not promise anything the video does not show, do not claim it is official, and do not pretend to be the original creator.')
    ..writeln('- Do not suggest ways to avoid copyright or platform checks.')
    ..writeln()
    ..writeln('My narration script:')
    ..writeln(cut.trim().isEmpty ? '(no script yet - use only the drama title)' : cut.trim());
  return b.toString();
}

/// Reads Gemini's reply. Everything is checked and shortened; null when
/// nothing usable was found.
PublishText? parsePublishReply(String reply) {
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(reply);
  var body = fence != null ? fence.group(1)! : reply;
  final a = body.indexOf('{');
  final z = body.lastIndexOf('}');
  if (a < 0 || z <= a) return null;
  body = body.substring(a, z + 1);
  Object? m;
  try {
    m = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (m is! Map) return null;

  final titles = <String>[];
  for (final t in (m['titles'] as List? ?? const [])) {
    if (t is! String) continue;
    final s = t.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty) continue;
    titles.add(s.length > maxTitleChars ? s.substring(0, maxTitleChars) : s);
    if (titles.length >= maxTitles) break;
  }
  var desc = m['description'] is String ? (m['description'] as String).trim() : '';
  if (desc.length > maxDescriptionChars) desc = desc.substring(0, maxDescriptionChars);

  final tags = <String>[];
  for (final t in (m['hashtags'] as List? ?? const [])) {
    if (t is! String) continue;
    final s = t.trim().replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'^#+'), '');
    if (s.isEmpty || s.length > 40) continue;
    final tag = '#$s';
    if (!tags.contains(tag)) tags.add(tag);
    if (tags.length >= maxHashtags) break;
  }
  final thumbs = <String>[];
  for (final t in (m['thumbnailTexts'] as List? ?? const [])) {
    if (t is! String) continue;
    final x = t.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (x.isEmpty || thumbs.contains(x)) continue;
    thumbs.add(x.length > maxThumbChars ? x.substring(0, maxThumbChars) : x);
    if (thumbs.length >= maxThumbTexts) break;
  }
  final out = PublishText(titles: titles, description: desc, hashtags: tags, thumbTexts: thumbs);
  return out.isEmpty ? null : out;
}

/// The description to paste: Gemini's text, then the source and credit lines
/// the maker confirmed (see fair_use.dart), then the hashtags.
String finalDescription(PublishText t, String creditNote) {
  final b = StringBuffer();
  if (t.description.trim().isNotEmpty) b.writeln(t.description.trim());
  if (creditNote.trim().isNotEmpty) {
    if (b.isNotEmpty) b.writeln();
    b.writeln(creditNote.trim());
  }
  if (t.hashtags.isNotEmpty) {
    if (b.isNotEmpty) b.writeln();
    b.writeln(t.hashtags.join(' '));
  }
  return b.toString().trim();
}
