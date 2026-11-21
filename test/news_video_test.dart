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
    const s = NewsVideoSettings(url: 'https://a.b', token: 't', pexelsKey: 'k');
    final back = NewsVideoSettings.decode(s.encode());
    expect([back.url, back.token, back.pexelsKey], ['https://a.b', 't', 'k']);
    expect(back.ready, isTrue);
    expect(NewsVideoSettings.decode('x').ready, isFalse);
    expect(NewsVideoSettings.decode(null).ready, isFalse);
  });

  test('request: duration kept between 3 and 5, ratio only 9:16 or 16:9', () {
    Map<String, Object?> r(double m, String ratio) => newsRequestJson(
          topic: ' t ', geminiKey: ' g ', pexelsKey: '', ratio: ratio, minutes: m, voice: 'v', sources: ['a'], strict: true, prompt: 'p');
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
}
