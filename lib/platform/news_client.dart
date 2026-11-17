import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/news.dart';

/// Result of loading every enabled feed. A feed that fails is listed in
/// [errors] (name and reason) and does not stop the others.
class NewsLoad {
  const NewsLoad(this.items, this.errors);
  final List<NewsItem> items;
  final Map<String, String> errors;
}

const _maxBytes = 2 * 1024 * 1024;

Future<String> _get(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    var uri = Uri.parse(url);
    for (var hop = 0; hop < 5; hop++) {
      final req = await client.getUrl(uri);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, 'DramaFlow-NewsReader/1.0');
      req.headers.set(HttpHeaders.acceptHeader, 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*');
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.isRedirect) {
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (loc == null) throw const HttpException('redirect without location');
        uri = uri.resolve(loc);
        if (uri.scheme != 'http' && uri.scheme != 'https') throw const HttpException('bad redirect');
        continue;
      }
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw HttpException('HTTP ${resp.statusCode}');
      }
      final bytes = <int>[];
      await for (final c in resp.timeout(const Duration(seconds: 20))) {
        bytes.addAll(c);
        if (bytes.length > _maxBytes) throw const HttpException('ဖိုင်ကြီးလွန်း');
      }
      return utf8.decode(bytes, allowMalformed: true);
    }
    throw const HttpException('redirect များလွန်း');
  } finally {
    client.close(force: true);
  }
}

String _why(Object e) {
  if (e is SocketException) return 'Internet ချိတ်မရ';
  if (e is TimeoutException) return 'အချိန်ကြာလွန်း';
  if (e is HandshakeException) return 'လုံခြုံရေး ချိတ်ဆက်မှု မအောင်';
  if (e is HttpException) return e.message;
  return 'ဖတ်မရ';
}

Future<NewsLoad> loadNews(List<NewsFeed> feeds) async {
  final on = feeds.where((f) => f.enabled).toList();
  final errors = <String, String>{};
  final lists = await Future.wait(on.map((f) async {
    try {
      final xml = await _get(f.url);
      final items = parseFeed(xml, feedId: f.id, feedName: f.name);
      if (items.isEmpty) errors[f.name] = 'RSS/Atom feed မဟုတ် ဒါမှမဟုတ် သတင်းမရှိ';
      return items;
    } catch (e) {
      errors[f.name] = _why(e);
      return <NewsItem>[];
    }
  }));
  return NewsLoad(mergeItems(lists), errors);
}
