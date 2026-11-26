import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aistudio/core/studio.dart';

void main() {
  test('the library answer is read, a broken one gives an empty library', () {
    final lib = parseStudioLibrary(jsonEncode({
      'files': [
        {'name': 'a.mp4', 'size': 2048, 'kind': 'video', 'mtime': 5},
        {'name': 'a.srt', 'size': 10, 'kind': 'srt', 'mtime': 4},
        {'name': 'cover.png', 'size': 10, 'kind': 'image', 'mtime': 3},
        {'size': 1},
      ],
      'free_gb': 12.5,
      'aria2c': true,
      'youtube': {'secret': true, 'linked': false},
    }));
    expect(lib.files.length, 3);
    expect(lib.ofKind('video').single.name, 'a.mp4');
    expect(lib.files[1].isSrt, isTrue);
    expect(lib.freeGb, 12.5);
    expect(lib.aria2c, isTrue);
    expect(lib.ytSecret, isTrue);
    expect(lib.ytLinked, isFalse);
    expect(parseStudioLibrary('not json').files, isEmpty);
  });

  test('a running download shows speed, size and time left', () {
    final j = parseStudioJob(jsonEncode({
      'status': 'running',
      'op': 'download',
      'stage': 'ဆွဲနေတယ် (1/2) 45%',
      'progress': 22,
      'detail': {'downloaded_mb': 12.4, 'total_mb': 80.0, 'speed_mbs': 3.2, 'eta': 21, 'paused': false},
    }));
    expect(j.state, StudioState.running);
    expect(j.finished, isFalse);
    expect(j.progress, 22);
    expect(downloadLine(j), '12.4 / 80 MB · 3.2 MB/s · ကျန် 21 စက္ကန့်');
  });

  test('a paused download says so', () {
    final j = parseStudioJob(jsonEncode({'status': 'running', 'detail': {'paused': true}}));
    expect(j.paused, isTrue);
    expect(downloadLine(j), contains('ခဏရပ်ထားတယ်'));
  });

  test('a finished job gives files, YouTube links, notes and errors', () {
    final j = parseStudioJob(jsonEncode({
      'status': 'done',
      'progress': 100,
      'result': {
        'files': ['a.mp4'],
        'links': [
          {'title': 'T', 'watch': 'https://youtu.be/x', 'studio': 'https://studio.youtube.com/video/x/edit', 'note': 'thumbnail OK'},
          {'title': 'bad'},
        ],
        'notes': ['n'],
        'errors': ['e'],
      },
    }));
    expect(j.state, StudioState.done);
    expect(j.finished, isTrue);
    expect(j.files, ['a.mp4']);
    expect(j.links.single.watch, 'https://youtu.be/x');
    expect(j.notes, ['n']);
    expect(j.errors, ['e']);
  });

  test('states and progress are safe with odd answers', () {
    expect(parseStudioJob(jsonEncode({'status': 'error', 'error': 'x'})).state, StudioState.error);
    expect(parseStudioJob(jsonEncode({'status': 'canceled'})).finished, isTrue);
    expect(parseStudioJob(jsonEncode({'status': 'queued', 'progress': 400})).progress, 100);
    expect(parseStudioJob('oops').state, StudioState.queued);
  });

  test('sizes and times read well', () {
    expect(formatBytes(900), '900 B');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
    expect(etaText(45), '45 စက္ကန့်');
    expect(etaText(125), '2 မိနစ် 5 စက္ကန့်');
    expect(etaText(3720), '1 နာရီ 2 မိနစ်');
    expect(etaText(null), '');
  });

  test('requests carry the backend keys', () {
    final d = studioDownloadRequest(urls: 'https://a\nhttps://b', quality: '1080hevc', speed: 'fast8', playlist: true, playlistItems: ' 4-7 ', subLangs: 'zh', alsoSubtitles: true);
    expect(d['op'], 'download');
    expect(d['quality'], '1080hevc');
    expect(d['playlist_items'], '4-7');
    expect(d['sub_langs'], 'zh');
    expect(d['subtitles'], isTrue);
    final s = studioSplitRequest(file: 'a.mp4', byRanges: true, ranges: '0:00-1:00', srtFile: 'a.srt');
    expect(s['split_mode'], 'ranges');
    expect(studioSplitRequest(file: 'a.mp4')['split_mode'], 'count');
    expect(studioTranslateRequest(file: 'a.srt').containsKey('gemini_key'), isFalse, reason: 'the key is sent only for the Gemini engine');
    expect(studioTranslateRequest(file: 'a.srt', gemini: true, geminiKey: 'K')['gemini_key'], 'K');
    expect(studioSubtitleRequest(file: 'a.mp4', srtFile: 'a.srt', mode: 'both')['sub_mode'], 'both');
    expect(studioZipRequest(files: ['a'], name: 'p')['zip_name'], 'p');
  });

  test('the Whisper request names the op, the file, the language and the model', () {
    final r = studioTranscribeRequest(file: 'a.mp4', srcLang: 'zh', model: 'medium');
    expect(r['op'], 'transcribe');
    expect(r['file'], 'a.mp4');
    expect(r['src_lang'], 'zh');
    expect(r['whisper_model'], 'medium');
    expect(r['whisper_vad'], isTrue);
    expect(studioTranscribeRequest(file: 'a.mp4')['whisper_model'], 'small');
    expect(whisperModels.map((m) => m.$1), containsAll(['small', 'medium', 'large-v3']));
  });

  test('the YouTube request is private by default and always carries the rights answer', () {
    final y = studioYoutubeRequest(files: ['a.mp4'], confirmRights: true);
    expect(y['privacy'], 'private');
    expect(y['confirm_rights'], isTrue);
    expect(studioYoutubeRequest(files: ['a.mp4'], confirmRights: false)['confirm_rights'], isFalse);
  });

  test('every choice key is one the backend knows', () {
    expect(studioQualities.map((e) => e.$1), ['best', '1080', '1080hevc', '720', '480', 'mp3', 'srt']);
    expect(studioSpeeds.map((e) => e.$1), ['native', 'safe2', 'safe4', 'fast8', 'turbo16']);
    expect(studioPrivacy.first.$1, 'private');
    expect(labelOf(studioQualities, '720'), contains('720'));
    expect(labelOf(studioQualities, 'zzz'), 'zzz');
  });

  test('links in a pasted text are counted', () {
    expect(countLinks('https://a.com/x\nhttp://b.com'), 2);
    expect(countLinks('no link'), 0);
  });

  test('no picture or sound changing option exists in the requests', () {
    final all = [
      studioDownloadRequest(urls: 'https://a'),
      studioSplitRequest(file: 'a.mp4'),
      studioSubtitleRequest(file: 'a.mp4', srtFile: 'a.srt'),
      studioYoutubeRequest(files: ['a.mp4'], confirmRights: true),
    ].map((m) => m.keys.join(',')).join(',');
    for (final bad in ['zoom', 'flip', 'color', 'colour', 'pitch', 'speed_up']) {
      expect(all.contains(bad), isFalse, reason: bad);
    }
  });
}
