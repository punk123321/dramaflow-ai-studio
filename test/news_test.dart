import 'package:aistudio/core/news.dart';
import 'package:flutter_test/flutter_test.dart';

const rss = '''<?xml version="1.0"?>
<rss version="2.0"><channel><title>X</title>
<item><title><![CDATA[First &amp; story]]></title><link>https://example.com/a</link>
<description>&lt;p&gt;Hello &lt;b&gt;world&lt;/b&gt; &amp;amp; more&lt;/p&gt;</description>
<pubDate>Mon, 16 Nov 2026 10:00:00 GMT</pubDate></item>
<item><title>Second</title><link>https://example.com/b</link><pubDate>Mon, 16 Nov 2026 12:00:00 +0630</pubDate></item>
<item><title>No link</title></item>
<item><title>Bad link</title><link>javascript:alert(1)</link></item>
</channel></rss>''';

const atom = '''<feed xmlns="http://www.w3.org/2005/Atom"><title>A</title>
<entry><title>Atom one</title><link rel="alternate" href="https://example.org/1"/><link rel="self" href="https://example.org/self"/>
<updated>2026-11-16T05:30:00Z</updated><summary>Short &amp; sweet</summary></entry></feed>''';

void main() {
  test('rss items: cdata, entities, html stripped; bad items skipped', () {
    final r = parseFeed(rss, feedId: 'f', feedName: 'F');
    expect(r.length, 2);
    expect(r[0].title, 'First & story');
    expect(r[0].snippet, 'Hello world & more');
    expect(r[0].publishedMs, DateTime.utc(2026, 11, 16, 10).millisecondsSinceEpoch);
  });

  test('rfc822 offset is applied', () {
    final r = parseFeed(rss, feedId: 'f', feedName: 'F');
    expect(r[1].publishedMs, DateTime.utc(2026, 11, 16, 5, 30).millisecondsSinceEpoch);
  });

  test('atom: alternate link and iso date', () {
    final r = parseFeed(atom, feedId: 'f', feedName: 'F');
    expect(r.single.link, 'https://example.org/1');
    expect(r.single.publishedMs, DateTime.utc(2026, 11, 16, 5, 30).millisecondsSinceEpoch);
    expect(r.single.snippet, 'Short & sweet');
  });

  test('not a feed gives nothing', () {
    expect(parseFeed('<html><body>hi</body></html>', feedId: 'f', feedName: 'F'), isEmpty);
    expect(parseFeed('', feedId: 'f', feedName: 'F'), isEmpty);
  });

  test('burmese text survives', () {
    final x = '<rss><channel><item><title>မြန်မာသတင်း</title><link>https://a.com/x</link><description>စာသား။</description></item></channel></rss>';
    final r = parseFeed(x, feedId: 'f', feedName: 'F');
    expect(r.single.title, 'မြန်မာသတင်း');
  });

  test('merge: newest first, duplicate links once, undated last', () {
    const a = NewsItem(feedId: 'a', feedName: 'A', title: 'old', link: 'https://x/1', publishedMs: 100, snippet: '');
    const b = NewsItem(feedId: 'b', feedName: 'B', title: 'new', link: 'https://x/2', publishedMs: 200, snippet: '');
    const dup = NewsItem(feedId: 'b', feedName: 'B', title: 'dup', link: 'https://x/1', publishedMs: 100, snippet: '');
    const none = NewsItem(feedId: 'b', feedName: 'B', title: 'none', link: 'https://x/3', publishedMs: 0, snippet: '');
    final m = mergeItems([[a, none], [b, dup]]);
    expect(m.map((e) => e.title), ['new', 'old', 'none']);
  });

  test('items and feeds round trip; damaged data gives empty', () {
    const i = NewsItem(feedId: 'a', feedName: 'A', title: 't', link: 'https://x/1', publishedMs: 5, snippet: 's');
    final d = decodeItems(encodeItems([i], 9));
    expect(d.items.single.title, 't');
    expect(d.savedMs, 9);
    expect(decodeItems('{oops').items, isEmpty);
    final f = decodeFeeds(encodeFeeds(const [NewsFeed(id: '1', name: 'n', url: 'https://a.com/rss')]));
    expect(f!.single.url, 'https://a.com/rss');
    expect(decodeFeeds(null), isNull);
    expect(decodeFeeds(encodeFeeds(const [])), isEmpty);
  });

  test('only http(s) addresses are accepted', () {
    expect(isHttpUrl('https://a.com/x'), true);
    expect(isHttpUrl('ftp://a.com'), false);
    expect(isHttpUrl('javascript:alert(1)'), false);
    expect(isHttpUrl('abc'), false);
    expect(NewsFeed.fromJson({'id': '1', 'name': 'n', 'url': 'file:///etc/passwd'}), isNull);
  });

  test('age text', () {
    expect(ageText(0, 1000), '');
    expect(ageText(1000, 1000 + 5 * 60000), '5 မိနစ်က');
    expect(ageText(1000, 1000 + 3 * 3600000), '3 နာရီက');
    expect(ageText(1000, 1000 + 2 * 86400000), '2 ရက်က');
  });

  test('script prompt has the facts and the no-invention rule, and cuts long text', () {
    const it = NewsItem(feedId: 'a', feedName: 'Src', title: 'Head', link: 'https://x/1', publishedMs: 0, snippet: 'Snip');
    final p = buildNewsScriptPrompt(item: it, articleText: 'z' * 7000, notes: 'A=က');
    expect(p, contains('HEADLINE: Head'));
    expect(p, contains('SUMMARY FROM THE FEED: Snip'));
    expect(p, contains('Do not invent facts'));
    expect(p, contains('A=က'));
    expect('z'.allMatches(p).length, lessThan(6100));
  });
}
