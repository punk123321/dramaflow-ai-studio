import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aistudio/core/news_video.dart' show JobState;
import 'package:aistudio/core/recap_auto.dart';
import 'package:aistudio/core/scenes.dart';
import 'package:aistudio/core/segments.dart';

void main() {
  test('video groups: 5 parts per request, each with its own time range', () {
    final parts = buildSegments(14 * 60000, 60000); // 14 parts
    final g = videoRecapGroups(dramaTitle: 'D', episode: 2, parts: parts, notes: 'n');
    expect(g.map((e) => (e.first, e.last)).toList(), [(1, 5), (6, 10), (11, 14)]);
    expect(g[0].startMs, 0);
    expect(g[0].endMs, 5 * 60000);
    expect(g[2].endMs, 14 * 60000);
    expect(g[0].prompt, contains('PART'));
    expect(g[0].toJson()['end_ms'], 300000);
    expect(g[0].toJson().containsKey('jpeg_b64'), isFalse);
  });

  test('scene groups carry the sheet picture of their group', () {
    final scenes = [for (var i = 0; i < 30; i++) SceneSpan(i * 5000, i * 5000 + 5000)];
    final g = sceneRecapGroups(
      dramaTitle: 'D',
      episode: 1,
      scenes: scenes,
      dialogue: List.filled(30, ''),
      notes: '',
      sheets: {1: 'AAA', 13: 'BBB'},
    );
    expect(g.length, 3);
    expect(g[0].jpegBase64, 'AAA');
    expect(g[1].jpegBase64, 'BBB');
    expect(g[2].jpegBase64, '');
    expect(g[0].toJson().containsKey('end_ms'), isFalse);
  });

  test('request json', () {
    final j = recapRequestJson(
      mode: 'weird',
      geminiKey: ' k ',
      model: ' ',
      voice: '',
      groups: const [RecapGroup(first: 1, last: 2, prompt: 'p')],
    );
    expect(j['mode'], 'scenes');
    expect(j['gemini_key'], 'k');
    expect(j.containsKey('gemini_model'), isFalse);
    expect((j['groups'] as List).length, 1);
    expect(recapRequestJson(mode: 'video', geminiKey: 'k', model: 'm', voice: 'v', groups: const [])['mode'], 'video');
  });

  test('job parse: parts sorted, empty text dropped, broken body is an error', () {
    final j = parseRecapJob(jsonEncode({
      'status': 'done',
      'progress': 100,
      'warnings': ['w'],
      'parts': [
        {'n': 2, 'text': 'b', 'audio_ms': 1500, 'audio_url': '/x/2.wav'},
        {'n': 1, 'text': 'a'},
        {'n': 3, 'text': '  '},
      ],
    }));
    expect(j.state, JobState.done);
    expect(j.parts.map((p) => p.n).toList(), [1, 2]);
    expect(j.parts[1].audioMs, 1500);
    expect(j.parts[0].audioUrl, '');
    expect(j.warnings, ['w']);
    expect(parseRecapJob('nope').state, JobState.error);
    expect(parseRecapJob(jsonEncode({'status': 'error', 'error': 'x'})).error, 'x');
    expect(parseRecapJob(jsonEncode({'status': 'running', 'progress': 400})).progress, 100);
  });

  test('chunk to part matching is strict', () {
    final texts = {2: 'ဒုတိယ အပိုင်း စာသား ရှည်ရှည်', 5: 'ပဉ္စမ အပိုင်း စာသား ရှည်ရှည်'};
    expect(matchChunksToParts(['ဒုတိယ အပိုင်း စာသား ရှည်ရှည်', 'ပဉ္စမ အပိုင်း စာသား ရှည်ရှည်'], texts), [2, 5]);
    expect(matchChunksToParts(['ဒုတိယ အပိုင်း စာသား ရှည်ရှည်'], texts), isNull); // fewer chunks
    expect(matchChunksToParts(['ပဉ္စမ အပိုင်း စာသား ရှည်ရှည်', 'ဒုတိယ အပိုင်း စာသား ရှည်ရှည်'], texts), isNull); // wrong order
  });

  test('video groups put each part\'s dialogue into the prompt', () {
    final parts = buildSegments(6 * 60000, 60000);
    final g = videoRecapGroups(dramaTitle: 'D', episode: 1, parts: parts, notes: '', dialogue: ['a1', 'a2', 'a3', 'a4', 'a5', 'a6']);
    expect(g[0].prompt, contains('Dialogue (subtitles): a1'));
    expect(g[0].prompt, contains('Dialogue (subtitles): a5'));
    expect(g[0].prompt, isNot(contains('a6')));
    expect(g[1].prompt, contains('Dialogue (subtitles): a6'));
  });

  test('groups tell the backend how long each part is', () {
    final parts = buildSegments(7 * 60000, 60000); // 7 parts
    final g = videoRecapGroups(dramaTitle: 'D', episode: 1, parts: parts, notes: '');
    expect(g[0].partMs, [60000, 60000, 60000, 60000, 60000]);
    expect(g[0].toJson()['part_ms'], [60000, 60000, 60000, 60000, 60000]);
    expect(g[1].toJson()['part_ms'], [60000, 60000]);
    final scenes = [for (var i = 0; i < 14; i++) SceneSpan(i * 4000, i * 4000 + 4000 + i * 100)];
    final s = sceneRecapGroups(dramaTitle: 'D', episode: 1, scenes: scenes, dialogue: List.filled(14, ''), notes: '', sheets: const {});
    expect(s[0].partMs.length, s[0].last - s[0].first + 1);
    expect(s[0].partMs.first, 4000);
    expect(s[1].partMs.last, scenes.last.lengthMs);
    // a wrong-length list is never sent
    const bad = RecapGroup(first: 1, last: 3, prompt: 'p', partMs: [1000]);
    expect(bad.toJson().containsKey('part_ms'), isFalse);
  });

  test('job parse reads the video length of a part', () {
    final j = parseRecapJob(jsonEncode({
      'status': 'done',
      'parts': [
        {'n': 1, 'text': 'a', 'audio_ms': 4000, 'target_ms': 5000},
        {'n': 2, 'text': 'b'},
      ],
    }));
    expect(j.parts[0].targetMs, 5000);
    expect(j.parts[1].targetMs, 0);
  });

  test('missing parts and the groups to ask again', () {
    const groups = [
      RecapGroup(first: 1, last: 3, prompt: 'a'),
      RecapGroup(first: 4, last: 6, prompt: 'b'),
      RecapGroup(first: 7, last: 7, prompt: 'c'),
    ];
    expect(missingParts(groups, [1, 2, 3, 4, 5, 6, 7]), isEmpty);
    expect(missingParts(groups, [1, 3, 4, 5, 6]), [2, 7]);
    expect(missingParts(groups, const []), [1, 2, 3, 4, 5, 6, 7]);
    expect(groupsFor(groups, [2, 7]).map((g) => g.first).toList(), [1, 7]);
    expect(groupsFor(groups, [5]).map((g) => g.first).toList(), [4]);
    expect(groupsFor(groups, const []), isEmpty);
  });

  test('self-test reply is read, anything else is no checks', () {
    final c = parseSelfTest(jsonEncode({
      'checks': [
        {'id': 'ffmpeg', 'ok': true, 'note': 'ok'},
        {'id': 'gemini', 'ok': false, 'note': 'quota'},
        {'id': 5, 'ok': true},
      ],
    }));
    expect(c.length, 2);
    expect(c[0].ok, isTrue);
    expect(c[1].ok, isFalse);
    expect(c[1].note, 'quota');
    expect(c[0].label, contains('ffmpeg'));
    expect(parseSelfTest('nope'), isEmpty);
    expect(parseSelfTest('{"x":1}'), isEmpty);
  });

  test('request json carries the optional fallback model only when given', () {
    const g = [RecapGroup(first: 1, last: 1, prompt: 'p')];
    final a = recapRequestJson(mode: 'scenes', geminiKey: 'k', model: 'm', voice: '', groups: g);
    expect(a.containsKey('gemini_fallback'), isFalse);
    final b = recapRequestJson(mode: 'scenes', geminiKey: 'k', model: 'm', voice: '', groups: g, fallbackModel: ' f2 ');
    expect(b['gemini_fallback'], 'f2');
  });
}
