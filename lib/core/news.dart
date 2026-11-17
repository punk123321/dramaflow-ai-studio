import 'dart:convert';

/// News reading (RSS/Atom). The app keeps only the headline, the link, the time
/// and a short snippet of each story. It never copies full articles, pictures
/// or videos: the reader opens the original site, and the user writes the
/// recap script themselves (or with Gemini). Pure Dart, no Flutter imports.

class NewsFeed {
  const NewsFeed({required this.id, required this.name, required this.url, this.enabled = true, this.category = ''});

  final String id;
  final String name;
  final String url;
  final bool enabled;
  final String category;

  NewsFeed copyWith({String? name, String? url, bool? enabled, String? category}) =>
      NewsFeed(id: id, name: name ?? this.name, url: url ?? this.url, enabled: enabled ?? this.enabled, category: category ?? this.category);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'url': url, 'on': enabled, 'cat': category};

  static NewsFeed? fromJson(Object? m) {
    if (m is! Map) return null;
    final id = m['id'], name = m['name'], url = m['url'];
    if (id is! String || name is! String || url is! String) return null;
    if (!isHttpUrl(url)) return null;
    return NewsFeed(id: id, name: name, url: url, enabled: m['on'] is bool ? m['on'] as bool : true, category: m['cat'] is String ? m['cat'] as String : '');
  }
}

class NewsItem {
  const NewsItem({required this.feedId, required this.feedName, required this.title, required this.link, required this.publishedMs, required this.snippet});

  final String feedId;
  final String feedName;
  final String title;
  final String link;

  /// Milliseconds since epoch, 0 when the feed gave no usable date.
  final int publishedMs;
  final String snippet;

  Map<String, Object?> toJson() => {'f': feedId, 'fn': feedName, 't': title, 'l': link, 'p': publishedMs, 's': snippet};

  static NewsItem? fromJson(Object? m) {
    if (m is! Map) return null;
    final f = m['f'], fn = m['fn'], t = m['t'], l = m['l'];
    if (f is! String || fn is! String || t is! String || l is! String) return null;
    return NewsItem(feedId: f, feedName: fn, title: t, link: l, publishedMs: m['p'] is int ? m['p'] as int : 0, snippet: m['s'] is String ? m['s'] as String : '');
  }
}

bool isHttpUrl(String s) {
  final u = Uri.tryParse(s.trim());
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.contains('.');
}

/// Feeds offered as a starting point. They have NOT been checked: a feed
/// address can change or stop working. The user can edit or remove any of them.
const suggestedFeeds = <NewsFeed>[
  NewsFeed(id: 's-bbc-my', name: 'BBC မြန်မာ', url: 'https://feeds.bbci.co.uk/burmese/rss.xml', category: 'နိုင်ငံတကာ'),
  NewsFeed(id: 's-bbc-world', name: 'BBC World', url: 'https://feeds.bbci.co.uk/news/world/rss.xml', category: 'နိုင်ငံတကာ'),
  NewsFeed(id: 's-aj', name: 'Al Jazeera', url: 'https://www.aljazeera.com/xml/rss/all.xml', category: 'နိုင်ငံတကာ'),
  NewsFeed(id: 's-nasa', name: 'NASA', url: 'https://www.nasa.gov/news-release/feed/', category: 'သိပ္ပံ'),
];

// ---- parsing ----

final RegExp _tag = RegExp(r'<[^>]*>');

String decodeEntities(String s) {
  var out = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => _cp(int.parse(m.group(1)!, radix: 16), m.group(0)!));
  out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) => _cp(int.parse(m.group(1)!), m.group(0)!));
  return out
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}

String _cp(int v, String orig) => (v > 0 && v <= 0x10FFFF && !(v >= 0xD800 && v <= 0xDFFF)) ? String.fromCharCode(v) : orig;

/// Text of an element value: CDATA unwrapped, tags removed, entities decoded,
/// white space collapsed.
String cleanText(String raw) {
  var s = raw.trim();
  final cdata = RegExp(r'^<!\[CDATA\[([\s\S]*?)\]\]>$');
  final m = cdata.firstMatch(s);
  if (m != null) {
    s = m.group(1)!;
  } else {
    s = decodeEntities(s);
  }
  // A description is often escaped HTML; decode once more before stripping.
  if (s.contains('&lt;') || s.contains('&gt;')) s = decodeEntities(s);
  s = s.replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), ' ');
  s = s.replaceAll(_tag, ' ');
  s = decodeEntities(s);
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? _inner(String block, String name) {
  final r = RegExp('<$name(?:\\s[^>]*)?>([\\s\\S]*?)</$name>', caseSensitive: false);
  return r.firstMatch(block)?.group(1);
}

String? _atomLink(String block) {
  // <link rel="alternate" href="..."/> is preferred, then any <link href>.
  final links = RegExp(r'<link\s[^>]*>', caseSensitive: false).allMatches(block).map((m) => m.group(0)!).toList();
  String? any;
  for (final l in links) {
    final href = RegExp('href\\s*=\\s*["\']([^"\']+)["\']', caseSensitive: false).firstMatch(l)?.group(1);
    if (href == null) continue;
    final rel = RegExp('rel\\s*=\\s*["\']([^"\']+)["\']', caseSensitive: false).firstMatch(l)?.group(1);
    if (rel == null || rel == 'alternate') return decodeEntities(href);
    any ??= decodeEntities(href);
  }
  return any;
}

const _months = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};

/// RFC 822 ("Mon, 16 Nov 2026 10:00:00 +0630") or ISO 8601. 0 when unreadable.
int parseFeedDate(String? raw) {
  if (raw == null) return 0;
  final s = cleanText(raw);
  if (s.isEmpty) return 0;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso.toUtc().millisecondsSinceEpoch;
  final m = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]{1,4})?').firstMatch(s);
  if (m == null) return 0;
  final month = _months[m.group(2)!.toLowerCase()];
  if (month == null) return 0;
  var ms = DateTime.utc(int.parse(m.group(3)!), month, int.parse(m.group(1)!), int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6) ?? '0')).millisecondsSinceEpoch;
  final z = m.group(7);
  if (z != null && RegExp(r'^[+-]\d{4}$').hasMatch(z)) {
    final sign = z.startsWith('-') ? -1 : 1;
    final off = int.parse(z.substring(1, 3)) * 60 + int.parse(z.substring(3, 5));
    ms -= sign * off * 60000;
  }
  return ms;
}

String _snippet(String s, int max) {
  final runes = s.runes.toList();
  if (runes.length <= max) return s;
  return '${String.fromCharCodes(runes.take(max)).trimRight()}…';
}

/// Reads RSS 2.0 and Atom. A broken item is skipped; the rest still load.
/// Returns an empty list when [xml] is not a feed at all.
List<NewsItem> parseFeed(String xml, {required String feedId, required String feedName, int maxItems = 40, int snippetChars = 220}) {
  final out = <NewsItem>[];
  final isAtom = RegExp(r'<feed[\s>]', caseSensitive: false).hasMatch(xml) && !RegExp(r'<rss[\s>]', caseSensitive: false).hasMatch(xml);
  final blockTag = isAtom ? 'entry' : 'item';
  final blocks = RegExp('<$blockTag(?:\\s[^>]*)?>([\\s\\S]*?)</$blockTag>', caseSensitive: false).allMatches(xml);
  for (final b in blocks) {
    final block = b.group(1)!;
    final titleRaw = _inner(block, 'title');
    if (titleRaw == null) continue;
    final title = cleanText(titleRaw);
    if (title.isEmpty) continue;
    String? link;
    if (isAtom) {
      link = _atomLink(block);
    } else {
      final l = _inner(block, 'link');
      link = l == null ? null : cleanText(l);
      link ??= _atomLink(block);
    }
    if (link == null || !isHttpUrl(link)) continue;
    final desc = _inner(block, 'description') ?? _inner(block, 'summary') ?? _inner(block, 'content:encoded') ?? _inner(block, 'content') ?? '';
    final date = parseFeedDate(_inner(block, 'pubDate') ?? _inner(block, 'published') ?? _inner(block, 'updated') ?? _inner(block, 'dc:date'));
    out.add(NewsItem(feedId: feedId, feedName: feedName, title: title, link: link.trim(), publishedMs: date, snippet: _snippet(cleanText(desc), snippetChars)));
    if (out.length >= maxItems) break;
  }
  return out;
}

/// Newest first; items without a date go last in feed order. Duplicate links
/// (the same story in two feeds) are kept once.
List<NewsItem> mergeItems(List<List<NewsItem>> perFeed) {
  final seen = <String>{};
  final all = <NewsItem>[];
  for (final list in perFeed) {
    for (final it in list) {
      if (seen.add(it.link)) all.add(it);
    }
  }
  final indexed = [for (var i = 0; i < all.length; i++) (i, all[i])];
  indexed.sort((a, b) {
    final c = b.$2.publishedMs.compareTo(a.$2.publishedMs);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

String encodeItems(List<NewsItem> items, int savedMs) => jsonEncode({'v': 1, 'saved': savedMs, 'items': [for (final i in items) i.toJson()]});

({List<NewsItem> items, int savedMs}) decodeItems(String? raw) {
  if (raw == null || raw.trim().isEmpty) return (items: const <NewsItem>[], savedMs: 0);
  try {
    final m = jsonDecode(raw);
    if (m is! Map) return (items: const <NewsItem>[], savedMs: 0);
    final list = m['items'];
    final items = <NewsItem>[];
    if (list is List) {
      for (final e in list) {
        final x = NewsItem.fromJson(e);
        if (x != null) items.add(x);
      }
    }
    return (items: items, savedMs: m['saved'] is int ? m['saved'] as int : 0);
  } catch (_) {
    return (items: const <NewsItem>[], savedMs: 0);
  }
}

String encodeFeeds(List<NewsFeed> f) => jsonEncode({'v': 1, 'feeds': [for (final x in f) x.toJson()]});

/// Null when nothing was saved yet (the caller then offers the suggestions).
List<NewsFeed>? decodeFeeds(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final m = jsonDecode(raw);
    if (m is! Map || m['feeds'] is! List) return null;
    return [
      for (final e in (m['feeds'] as List))
        if (NewsFeed.fromJson(e) != null) NewsFeed.fromJson(e)!,
    ];
  } catch (_) {
    return null;
  }
}

/// "5 မိနစ်က", "2 နာရီက", "3 ရက်က". Empty when the date is unknown.
String ageText(int publishedMs, int nowMs) {
  if (publishedMs <= 0) return '';
  final d = nowMs - publishedMs;
  if (d < 0) return 'ယခု';
  final min = d ~/ 60000;
  if (min < 1) return 'ယခု';
  if (min < 60) return '$min မိနစ်က';
  final h = min ~/ 60;
  if (h < 24) return '$h နာရီက';
  return '${h ~/ 24} ရက်က';
}

/// Prompt for Gemini to write a recap script from one story. Only the headline,
/// the snippet and what the user pasted are given; Gemini is told not to add
/// facts. [articleText] is text the user pasted from the original page.
String buildNewsScriptPrompt({required NewsItem item, String articleText = '', String notes = '', int seconds = 45}) {
  final b = StringBuffer();
  b.writeln('You are writing a short news video script. Write natural spoken Burmese (Myanmar Unicode), about $seconds seconds when read aloud, in your own words.');
  b.writeln();
  b.writeln('RULES:');
  b.writeln('1. Use only the facts given below. Do not invent facts, names, numbers or quotes. If something is not given, leave it out.');
  b.writeln('2. Do not copy sentences from the source; retell them in your own words.');
  b.writeln('3. Short sentences ending with "။". No headings, emoji, brackets or timestamps.');
  b.writeln('4. Put the whole result inside ONE code block so it can be copied in one tap.');
  if (notes.trim().isNotEmpty) {
    b.writeln();
    b.writeln('NAME AND TERM PREFERENCES (follow exactly):');
    b.writeln(notes.trim());
  }
  b.writeln();
  b.writeln('SOURCE: ${item.feedName}');
  b.writeln('HEADLINE: ${item.title}');
  if (item.snippet.isNotEmpty) b.writeln('SUMMARY FROM THE FEED: ${item.snippet}');
  if (articleText.trim().isNotEmpty) {
    b.writeln();
    b.writeln('ARTICLE TEXT (pasted by the user):');
    final t = articleText.trim();
    b.writeln(t.length > 6000 ? t.substring(0, 6000) : t);
  }
  return b.toString();
}
