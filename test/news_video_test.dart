import 'package:aistudio/core/news_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseConnect: URL#TOKEN, trailing slash, no token, bad text', () {
    final a = parseConnect(' https://abc.trycloudflare.com/#tok123 ');
    expect(a?.url, 'https://abc.trycloudflare.com');
    expect(a?.token, 'tok123');
    expect(parseConnect('https://x.y')?.token, '');
    expect(parseConnect('not a url'), isNull);
    expect(parseConnect(''), isNull);
    expect(parseConnect('ftp://x.y#t'), isNull);
  });

  test('settings round trip and broken text', () {
    const s = NewsVideoSettings(url: 'https://a.b', token: 't', provider: 'pixabay', keys: {'pixabay': 'k'});
    final back = NewsVideoSettings.decode(s.encode());
    expect([back.url, back.token, back.provider, back.stockKey], ['https://a.b', 't', 'pixabay', 'k']);
    expect(back.ready, isTrue);
    expect(NewsVideoSettings.decode('x').ready, isFalse);
    expect(NewsVideoSettings.decode(null).ready, isFalse);
  });

  test('stock provider: older save with a Pexels key still works, unknown provider falls back', () {
    final old = NewsVideoSettings.decode('{"url":"https://a.b","token":"t","pexels":"pk"}');
    expect(old.provider, 'pexels');
    expect(old.stockKey, 'pk');
    final odd = NewsVideoSettings.decode('{"url":"https://a.b","token":"t","provider":"nope"}');
    expect(odd.provider, 'wikimedia');
    expect(odd.stockKey, '');
    final j = newsRequestJson(
        topic: 't', geminiKey: 'g', stockProvider: 'unsplash', stockKey: ' u ', ratio: '9:16', minutes: 4, voice: 'v', sources: ['a'], strict: true, prompt: 'p');
    expect(j['stock_provider'], 'unsplash');
    expect(j['stock_key'], 'u');
    expect(j.containsKey('pexels_key'), isFalse);
    final px = newsRequestJson(
        topic: 't', geminiKey: 'g', stockProvider: 'pexels', stockKey: 'p', ratio: '9:16', minutes: 4, voice: 'v', sources: ['a'], strict: true, prompt: 'p');
    expect(px['pexels_key'], 'p');
    final bad = newsRequestJson(
        topic: 't', geminiKey: 'g', stockProvider: 'zzz', stockKey: '', ratio: '9:16', minutes: 4, voice: 'v', sources: ['a'], strict: true, prompt: 'p');
    expect(bad['stock_provider'], 'wikimedia');
  });

  test('picture count: default 20, kept between 0 and 40, sent with the request, alias key for Pixabay pictures', () {
    expect(const NewsVideoSettings().imageCount, 20);
    expect(NewsVideoSettings.decode('{"url":"https://a.b","token":"t","images":99}').imageCount, maxNewsImages);
    expect(NewsVideoSettings.decode('{"url":"https://a.b","token":"t","images":-5}').imageCount, 0);
    final back = NewsVideoSettings.decode(const NewsVideoSettings(url: 'https://a.b', token: 't', imageCount: 12).encode());
    expect(back.imageCount, 12);
    const s = NewsVideoSettings(provider: 'pixabay_photo', keys: {'pixabay': 'pk'});
    expect(s.stockKey, 'pk');
    const own = NewsVideoSettings(provider: 'pixabay_photo', keys: {'pixabay': 'pk', 'pixabay_photo': 'x'});
    expect(own.stockKey, 'x');
    final j = newsRequestJson(
        topic: 't', geminiKey: 'g', stockProvider: 'wikimedia', stockKey: '', imageCount: 99, ratio: '9:16', minutes: 4, voice: 'v', sources: ['a'], strict: true, prompt: 'p');
    expect(j['image_count'], maxNewsImages);
    expect(stockProviders['wikimedia']!.images, isTrue);
    expect(stockProviders['pexels']!.images, isFalse);
  });

  test('Gemini model: default, saved, sent, empty falls back', () {
    expect(const NewsVideoSettings().model, defaultTextModel);
    final back = NewsVideoSettings.decode(const NewsVideoSettings(url: 'https://a.b', token: 't', model: 'gemini-x').encode());
    expect(back.model, 'gemini-x');
    expect(NewsVideoSettings.decode('{"url":"https://a.b","token":"t","model":" "}').model, defaultTextModel);
    final j = newsRequestJson(
        topic: 't', geminiKey: 'g', stockProvider: 'wikimedia', stockKey: '', model: ' m ', ratio: '9:16', minutes: 4, voice: 'v', sources: ['a'], strict: true, prompt: 'p');
    expect(j['gemini_model'], 'm');
  });

  test('Google Search switch: on by default, saved, sent', () {
    expect(const NewsVideoSettings().search, isTrue);
    expect(NewsVideoSettings.decode('{"url":"https://a.b","token":"t"}').search, isTrue);
    final off = NewsVideoSettings.decode(const NewsVideoSettings(url: 'https://a.b', token: 't', search: false).encode());
    expect(off.search, isFalse);
    final j = newsRequestJson(
        topic: 't', geminiKey: 'g', stockProvider: 'wikimedia', stockKey: '', search: false, ratio: '9:16', minutes: 4, voice: 'v', sources: ['a'], strict: true, prompt: 'p');
    expect(j['use_search'], isFalse);
  });

  test('request: duration kept between 3 and 5, ratio only 9:16 or 16:9', () {
    Map<String, Object?> r(double m, String ratio) => newsRequestJson(
          topic: ' t ', geminiKey: ' g ', stockProvider: 'wikimedia', stockKey: '', ratio: ratio, minutes: m, voice: 'v', sources: ['a'], strict: true, prompt: 'p');
    expect(r(1, '9:16')['duration_min'], 3.0);
    expect(r(9, '9:16')['duration_min'], 5.0);
    expect(r(double.nan, '9:16')['duration_min'], 4.0);
    expect(r(4, 'weird')['aspect_ratio'], '9:16');
    expect(r(4, '16:9')['aspect_ratio'], '16:9');
    expect(r(4, '16:9')['topic'], 't');
    expect(r(4, '16:9')['gemini_key'], 'g');
  });

  test('parseNewsJob: running, done with scenes, error, garbage', () {
    final run = parseNewsJob('{"status":"running","stage":"x","progress":42}');
    expect(run.state, JobState.running);
    expect(run.progress, 42);
    final done = parseNewsJob(
        '{"status":"done","title":"T","seconds":200.5,"download_url":"/download/a.mp4","warnings":["w"],"scenes":[{"narration":" hi ","source":"S","start":0,"end":2.5},{"narration":"","start":1,"end":2}]}');
    expect(done.state, JobState.done);
    expect(done.scenes.length, 1);
    expect(done.scenes.first.endMs, 2500);
    expect(done.downloadUrl, '/download/a.mp4');
    expect(done.warnings, ['w']);
    final err = parseNewsJob('{"status":"error","error":"bad"}');
    expect(err.state, JobState.error);
    expect(err.error, 'bad');
    expect(parseNewsJob('nope').state, JobState.error);
    expect(parseNewsJob('{"status":"running","progress":999}').progress, 100);
  });

  test('scenesToSrt: split at sentence ends, times add up and stay inside the scene', () {
    const sc = NewsScene('ပထမ စာကြောင်း။ ဒုတိယ စာကြောင်း ပိုရှည်တယ်။ တတိယ။', 'S', 1000, 7000);
    final e = scenesToSrt([sc]);
    expect(e.length, 3);
    expect(e.first.startMs, 1000);
    expect(e.last.endMs, 7000);
    for (var i = 1; i < e.length; i++) {
      expect(e[i].startMs, e[i - 1].endMs);
    }
    expect(e.every((x) => x.endMs > x.startMs), isTrue);
    expect([for (final x in e) x.index], [1, 2, 3]);
    expect(scenesToSrt([const NewsScene('abc', '', 5, 5)]), isEmpty);
    expect(scenesToSrt([const NewsScene('One. Two.', '', 0, 2000)]).length, 2);
  });

  test('every prompt preset has the topic and sources variables', () {
    for (final e in newsPrompts.values) {
      expect(e.text, contains('{{TOPIC}}'));
      expect(e.text, contains('{{SOURCES}}'));
    }
  });

  test('AI picture sources: listed as picture sources without a key, model sent only for Gemini', () {
    for (final p in ['ai_gemini', 'ai_pollinations']) {
      expect(stockProviders[p]!.images, isTrue, reason: p);
      expect(stockProviders[p]!.needsKey, isFalse, reason: p);
      expect(isAiProvider(p), isTrue);
    }
    expect(isAiProvider('wikimedia'), isFalse);
    final g = newsRequestJson(
        topic: 't', geminiKey: 'g', stockProvider: 'ai_gemini', stockKey: '', imageModel: ' my-image-model ', ratio: '9:16', minutes: 4, voice: 'v', sources: ['a'], strict: true, prompt: 'p');
    expect(g['stock_provider'], 'ai_gemini');
    expect(g['image_model'], 'my-image-model');
    final empty = newsRequestJson(
        topic: 't', geminiKey: 'g', stockProvider: 'ai_gemini', stockKey: '', ratio: '9:16', minutes: 4, voice: 'v', sources: ['a'], strict: true, prompt: 'p');
    expect(empty.containsKey('image_model'), isFalse);
    final other = newsRequestJson(
        topic: 't', geminiKey: 'g', stockProvider: 'ai_pollinations', stockKey: '', imageModel: 'x', ratio: '9:16', minutes: 4, voice: 'v', sources: ['a'], strict: true, prompt: 'p');
    expect(other.containsKey('image_model'), isFalse);
    final back = NewsVideoSettings.decode(const NewsVideoSettings(url: 'https://a.b', token: 't', provider: 'ai_gemini', imageModel: 'm1').encode());
    expect(back.provider, 'ai_gemini');
    expect(back.imageModel, 'm1');
    expect(NewsVideoSettings.decode('{"url":"https://a.b","token":"t"}').imageModel, '');
  });
}
